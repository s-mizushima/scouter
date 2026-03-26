# Scouter

海外スタートアップの最新プロダクト情報を自動取得・日本語翻訳して表示するiOSアプリ。
RSSフィードをバックグラウンドで定期取得し、タイトル・要約はDeepL APIで事前翻訳、記事本文はApple Translation（オンデバイス）でリアルタイム翻訳する。

---

## 目次

1. [アプリの全体像](#アプリの全体像)
2. [技術スタック](#技術スタック)
3. [システムアーキテクチャ](#システムアーキテクチャ)
4. [データフロー](#データフロー)
5. [Supabase バックエンド詳細](#supabase-バックエンド詳細)
   - [データベース設計](#データベース設計)
   - [Row Level Security (RLS)](#row-level-security-rls)
   - [Edge Function: fetch-and-translate](#edge-function-fetch-and-translate)
   - [pg_cron 定期実行](#pg_cron-定期実行)
6. [iOS アプリ詳細](#ios-アプリ詳細)
   - [プロジェクト構成](#プロジェクト構成)
   - [MVVM アーキテクチャ](#mvvm-アーキテクチャ)
   - [Supabase Swift SDK の使い方](#supabase-swift-sdk-の使い方)
   - [WKWebView 翻訳ブリッジ](#wkwebview-翻訳ブリッジ)
   - [スワイプアニメーション](#スワイプアニメーション)
   - [画像表示（AsyncImage）](#画像表示asyncimage)
7. [セットアップ手順](#セットアップ手順)
8. [コスト](#コスト)
9. [登録済みRSSフィード](#登録済みrssフィード)

---

## アプリの全体像

```
ユーザーがアプリを開く
        │
        ▼
┌─────────────────────────┐
│   iOS App (SwiftUI)     │
│                         │
│  ・日付別の記事一覧表示   │  ← Supabase から翻訳済み記事を取得
│  ・左右スワイプで日付移動  │
│  ・記事タップ→WebView    │  ← Apple Translation でオンデバイス翻訳
│  ・フィード管理画面       │  ← Supabase の feeds テーブルを CRUD
└────────────┬────────────┘
             │ HTTPS (Supabase REST API)
             ▼
┌─────────────────────────────────────────────┐
│   Supabase (BaaS)                           │
│                                             │
│  PostgreSQL                                 │
│  ├── feeds テーブル（RSSフィード一覧）        │
│  └── articles テーブル（記事＋翻訳データ）     │
│                                             │
│  Edge Function: fetch-and-translate         │
│  ├── RSS/Atom フィードを HTTP で取得          │
│  ├── XML パース → 記事データ抽出             │
│  ├── DeepL API でタイトル・要約を日本語翻訳   │
│  ├── OGP 画像 URL を記事ページから取得        │
│  └── articles テーブルに upsert              │
│                                             │
│  pg_cron: 毎朝 6:00 UTC に自動実行          │
└─────────────────────────────────────────────┘
```

---

## 技術スタック

| レイヤー | 技術 | 用途 |
|---------|------|------|
| **iOS フロントエンド** | Swift / SwiftUI | UI 構築 |
| | WKWebView | 記事本文の表示 |
| | Apple Translation framework | WebView 内テキストのオンデバイス翻訳 |
| | Supabase Swift SDK | Supabase との通信 |
| | XcodeGen | Xcode プロジェクト生成 |
| **バックエンド** | Supabase (PostgreSQL) | データベース |
| | Supabase Edge Functions (Deno) | サーバーレス関数 |
| | Supabase RLS | アクセス制御 |
| | pg_cron | 定期実行 |
| **外部 API** | DeepL API (Free) | タイトル・要約の日本語翻訳 |
| **RSS パーサー** | deno.land/x/rss (Deno) | Edge Function 内での RSS 解析 |

---

## システムアーキテクチャ

```
┌──────────────────────────────────────────────────────────┐
│                      iOS App                              │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │  Views       │  │  ViewModels  │  │  Services     │  │
│  │              │←─│              │←─│               │  │
│  │ ArticleList  │  │ ArticleList  │  │ Supabase      │──┼── HTTPS → Supabase REST API
│  │ ArticleWeb   │  │ FeedSettings │  │ Service       │  │
│  │ FeedSettings │  │              │  │               │  │
│  │ ContentView  │  │              │  │ Translation   │  │
│  └──────────────┘  └──────────────┘  │ Service       │  │
│                                      └───────────────┘  │
│                         ↕                                │
│              Apple Translation API                       │
│              (オンデバイス・無料)                           │
└──────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────┐
│                    Supabase                               │
│                                                          │
│  ┌─────────────┐   ┌──────────────────────────────────┐  │
│  │ PostgreSQL  │   │ Edge Function                    │  │
│  │             │←──│ fetch-and-translate              │  │
│  │ feeds       │   │                                  │  │
│  │ articles    │   │ RSS取得 → パース → 翻訳 → 保存   │──┼── HTTPS → DeepL API
│  │             │   │                    ↓              │──┼── HTTPS → RSS Feed URLs
│  │ RLS: anon   │   │           OGP画像取得             │──┼── HTTPS → Article Pages
│  │   = 読取専用 │   └──────────────────────────────────┘  │
│  └─────────────┘                                         │
│         ↑                                                │
│    pg_cron (毎朝6:00 UTC)                                │
└──────────────────────────────────────────────────────────┘
```

---

## データフロー

### 1. バックエンド：記事の取得・翻訳・保存

```
pg_cron (毎朝6:00 UTC)
    │
    ▼
Edge Function 起動
    │
    ├─① feeds テーブルから is_enabled=true のフィードを全取得
    │
    ├─② 各フィード URL に HTTP GET → RSS/Atom XML を取得
    │
    ├─③ XML パース → エントリごとに以下を抽出:
    │     ・title (記事タイトル)
    │     ・description / content (要約、HTMLタグ除去、500文字制限)
    │     ・link (記事URL)
    │     ・published / updated (公開日時)
    │     ・画像URL (enclosure → img タグ → entry.image → OGP)
    │
    ├─④ 全タイトル＋全要約をまとめて DeepL API にバッチ送信
    │     → 1回の API コールで複数テキストを翻訳（効率化）
    │
    ├─⑤ OGP 画像がないエントリは記事ページの先頭50KBを取得
    │     → <meta property="og:image" content="..."> を正規表現で抽出
    │
    └─⑥ articles テーブルに UPSERT
          → article_url の UNIQUE 制約で重複スキップ
```

### 2. フロントエンド：記事の表示

```
アプリ起動 / 日付変更
    │
    ├─① SupabaseService.fetchFeeds() → 全フィード取得
    ├─② is_enabled=true の feed_id を抽出
    ├─③ SupabaseService.fetchArticles(date, feedIds)
    │     → published_at を JST の 0:00〜23:59 でフィルタ
    │     → published_at DESC でソート
    │
    └─④ ArticleListView で表示
          ・title_ja があれば日本語タイトル表示
          ・なければ title_original にフォールバック
          ・AsyncImage で画像表示
```

### 3. フロントエンド：WebView 翻訳

```
記事タップ → ArticleWebView 表示
    │
    ├─① WKWebView が記事ページを読み込み
    │
    ├─② didFinish → 抽出 JavaScript を注入
    │     → TreeWalker でテキストノードを走査
    │     → SCRIPT/STYLE/CODE/PRE を除外
    │     → 40件ずつバッチに分割
    │     → window.webkit.messageHandlers で Swift に送信
    │
    ├─③ Swift 側 Coordinator が受信
    │     → WebViewBridge.pendingBatches にセット
    │     → readyToTranslate = true
    │
    ├─④ .translationTask が発火
    │     → Apple TranslationSession で各バッチを翻訳
    │     → clientIdentifier でソートして順序保持
    │
    └─⑤ 翻訳結果を JavaScript で DOM に適用
          → window.__scouterTextNodes[offset + i].textContent = 翻訳文
          → ローディングインジケーター削除
```

---

## Supabase バックエンド詳細

### データベース設計

#### feeds テーブル

```sql
CREATE TABLE feeds (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name       text NOT NULL,          -- フィード表示名 (例: "Product Hunt")
  url        text UNIQUE NOT NULL,   -- RSS/Atom フィード URL
  is_enabled boolean DEFAULT true,   -- 有効/無効フラグ（アプリから切替）
  created_at timestamptz DEFAULT now()
);
```

**設計ポイント:**
- `url` に UNIQUE 制約 → 同じフィードの重複登録を防止
- `is_enabled` → Edge Function は true のフィードのみ取得。アプリ側もフィルタに使用
- `gen_random_uuid()` → PostgreSQL のネイティブ UUID 生成

#### articles テーブル

```sql
CREATE TABLE articles (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  feed_id          uuid NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
  title_original   text,              -- 原文タイトル
  title_ja         text,              -- DeepL 翻訳済みタイトル
  summary_original text,              -- 原文要約 (HTML除去済み、500文字上限)
  summary_ja       text,              -- DeepL 翻訳済み要約
  article_url      text UNIQUE NOT NULL,  -- 記事元 URL
  image_url        text,              -- アイキャッチ画像 URL (OGP等)
  published_at     timestamptz,       -- RSS の pubDate / updated
  fetched_at       timestamptz DEFAULT now()  -- Edge Function 実行時刻
);

CREATE INDEX idx_articles_published_at ON articles(published_at DESC);
CREATE INDEX idx_articles_feed_id ON articles(feed_id);
```

**設計ポイント:**
- `ON DELETE CASCADE` → フィード削除時に関連記事も自動削除
- `article_url` の UNIQUE → upsert 時の重複判定キー
- `title_original` / `title_ja` の二重構造 → 翻訳失敗時に原文フォールバック可能
- `published_at` の DESC インデックス → 日付降順クエリの高速化
- `image_url` → RSS に画像がない場合は OGP から取得して格納

#### ER図

```
feeds                          articles
┌──────────────┐              ┌────────────────────┐
│ id (PK)      │──────1:N────→│ id (PK)            │
│ name         │              │ feed_id (FK)       │
│ url (UNIQUE) │              │ title_original     │
│ is_enabled   │              │ title_ja           │
│ created_at   │              │ summary_original   │
└──────────────┘              │ summary_ja         │
                              │ article_url (UNQ)  │
                              │ image_url          │
                              │ published_at       │
                              │ fetched_at         │
                              └────────────────────┘
```

### Row Level Security (RLS)

```sql
-- RLS 有効化
ALTER TABLE feeds ENABLE ROW LEVEL SECURITY;
ALTER TABLE articles ENABLE ROW LEVEL SECURITY;

-- anon ロール（= アプリからのアクセス）は読み取りのみ
CREATE POLICY "anon_read_feeds" ON feeds
  FOR SELECT TO anon USING (true);

CREATE POLICY "anon_read_articles" ON articles
  FOR SELECT TO anon USING (true);
```

**仕組み:**
- Supabase には `anon` と `service_role` の2つのロールがある
- `anon` キーはアプリに埋め込まれる公開キー → **読み取りのみ許可**
- `service_role` キーは Edge Function の環境変数にのみ設定 → **RLS をバイパスして全操作可能**
- これにより、アプリから直接 articles を DELETE/INSERT することは不可能

### Edge Function: fetch-and-translate

ファイル: `supabase/functions/fetch-and-translate/index.ts`

Deno ランタイム上で動作するサーバーレス関数。以下の処理を順番に実行する。

#### 環境変数

```typescript
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const DEEPL_API_KEY = Deno.env.get("DEEPL_API_KEY")!;
```

- `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` → Supabase が自動で注入
- `DEEPL_API_KEY` → `supabase secrets set` で手動設定

#### DeepL バッチ翻訳

```typescript
async function translateBatch(texts: string[]): Promise<string[]> {
  const params = new URLSearchParams({ target_lang: "JA" });
  nonEmpty.forEach((t) => params.append("text", t));

  const res = await fetch("https://api-free.deepl.com/v2/translate", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "Authorization": `DeepL-Auth-Key ${DEEPL_API_KEY}`,
    },
    body: params,
  });
}
```

**ポイント:**
- `text` パラメータを複数回 append することで1回の API コールで複数テキストを翻訳
- タイトル20件 + 要約20件 = 40テキストを1コールで処理（API 効率化）
- 認証はヘッダーベース（2025年11月以降、body 認証は廃止）

#### 画像 URL 抽出（4段階フォールバック）

```
1. entry.attachments?.[0]?.url     ← RSS <enclosure> タグ
2. <img src="..."> in description  ← HTML 内の最初の画像
3. entry.image?.url                ← Atom フィードの image 要素
4. fetchOgImage(articleUrl)        ← 記事ページの <meta property="og:image">
```

OGP 取得は記事ページの先頭 50KB のみ読み取り、ストリーミングで効率化:

```typescript
const reader = res.body?.getReader();
let html = "";
while (html.length < 50000) {
  const { done, value } = await reader.read();
  if (done) break;
  html += new TextDecoder().decode(value);
}
reader.cancel();  // 残りは読まない
```

#### Upsert（重複スキップ挿入）

```typescript
const { error } = await supabase
  .from("articles")
  .upsert(articles, { onConflict: "article_url", ignoreDuplicates: true });
```

- `article_url` が既存なら何もしない（ignoreDuplicates）
- 新しい記事のみ INSERT される
- これにより Edge Function を何回実行しても安全（冪等性）

### pg_cron 定期実行

```sql
SELECT cron.schedule(
  'fetch-and-translate-daily',
  '0 6 * * *',  -- 毎日 6:00 UTC = 15:00 JST
  $$
  SELECT net.http_post(
    url := 'https://xxx.supabase.co/functions/v1/fetch-and-translate',
    headers := '{"Authorization": "Bearer <service_role_key>", "Content-Type": "application/json"}'::jsonb,
    body := '{}'::jsonb
  );
  $$
);
```

**注意:** pg_cron は Supabase ダッシュボードで拡張機能を有効化した後、SQL Editor から手動実行が必要。

---

## iOS アプリ詳細

### プロジェクト構成

```
NewsFeed/
├── project.yml                     # XcodeGen 設定ファイル
├── NewsFeed.xcodeproj/             # 生成された Xcode プロジェクト
└── NewsFeed/
    ├── App/
    │   └── NewsFeedApp.swift       # @main エントリポイント
    ├── Config/
    │   └── SupabaseConfig.swift    # Supabase URL・Key 定数
    ├── Models/
    │   ├── Article.swift           # 記事モデル (Codable)
    │   └── Feed.swift              # フィードモデル (Codable)
    ├── Services/
    │   ├── SupabaseService.swift   # Supabase クライアント (Singleton)
    │   └── TranslationService.swift # WKWebView 用 JavaScript 生成
    ├── Views/
    │   ├── ContentView.swift       # ルートビュー
    │   ├── ArticleListView.swift   # メイン記事一覧画面
    │   ├── ArticleWebView.swift    # WKWebView + 翻訳ブリッジ
    │   └── FeedSettingsView.swift  # フィード管理画面
    └── ViewModels/
        ├── ArticleListViewModel.swift   # 記事一覧のロジック
        └── FeedSettingsViewModel.swift  # フィード管理のロジック
```

### MVVM アーキテクチャ

```
View (SwiftUI)           ViewModel (@ObservableObject)      Service (Singleton)
┌─────────────┐          ┌──────────────────────┐           ┌──────────────────┐
│ ArticleList │──@State──→│ ArticleListViewModel │──async───→│ SupabaseService  │
│   View      │←@Published│                      │←throws───│                  │
│             │          │ articles: [Article]   │           │ fetchArticles()  │
│             │          │ selectedDate: Date    │           │ fetchFeeds()     │
│             │          │ isLoading: Bool       │           │ updateFeed()     │
└─────────────┘          └──────────────────────┘           │ deleteFeed()     │
                                                            │ addFeed()        │
                                                            └──────────────────┘
```

**パターンの解説:**
- **View** は `@StateObject` で ViewModel を保持。UI の描画のみ担当
- **ViewModel** は `@Published` プロパティで状態を管理。View が自動更新される
- **Service** は Singleton で Supabase クライアントをラップ。async/await で非同期通信
- View → ViewModel → Service の単方向依存。テスタビリティが高い

### Supabase Swift SDK の使い方

#### クライアント初期化

```swift
// Config/SupabaseConfig.swift
enum SupabaseConfig {
    static let url = URL(string: "https://xxx.supabase.co")!
    static let anonKey = "sb_publishable_xxx"
}

// Services/SupabaseService.swift
let client = SupabaseClient(
    supabaseURL: SupabaseConfig.url,
    supabaseKey: SupabaseConfig.anonKey
)
```

#### クエリ例：日付・フィードでフィルタして記事取得

```swift
let articles: [Article] = try await client
    .from("articles")                          // テーブル指定
    .select()                                  // 全カラム取得
    .gte("published_at", value: startStr)      // >= 開始日時
    .lt("published_at", value: endStr)         // <  終了日時
    .in("feed_id", values: feedIdStrings)      // IN (有効フィードのみ)
    .order("published_at", ascending: false)   // 新しい順
    .execute()                                 // 実行
    .value                                     // [Article] にデコード
```

**ポイント:**
- `.execute().value` で自動的に `Decodable` な型にデコードされる
- CodingKeys でスネークケース（DB）↔ キャメルケース（Swift）を変換
- JST タイムゾーンで日付境界を計算してから ISO8601 文字列でクエリ

#### 更新・削除

```swift
// Toggle feed enabled
try await client
    .from("feeds")
    .update(["is_enabled": isEnabled])
    .eq("id", value: id.uuidString.lowercased())
    .execute()

// Delete feed (articles cascade-delete)
try await client
    .from("feeds")
    .delete()
    .eq("id", value: id.uuidString.lowercased())
    .execute()
```

### WKWebView 翻訳ブリッジ

DeepL API を WKWebView 内の JavaScript から直接呼ぶと CORS でブロックされる。
そのため JavaScript ↔ Swift のブリッジを構築し、Apple Translation framework で翻訳する。

#### アーキテクチャ

```
WKWebView (JavaScript)              Swift (Native)
┌──────────────────────┐            ┌──────────────────────────┐
│                      │            │                          │
│ 1. TreeWalker で     │            │ 3. Coordinator が受信    │
│    テキストノード抽出  │   ──②──→  │    WebViewBridge に格納  │
│                      │  Message   │                          │
│                      │  Handler   │ 4. TranslationSession    │
│ 6. DOM のテキストを   │            │    で翻訳 (オンデバイス)  │
│    翻訳文に書き換え   │   ←⑤───   │                          │
│                      │ evaluateJS │ 5. 翻訳結果を JS で返す   │
└──────────────────────┘            └──────────────────────────┘
```

#### Step 1: テキストノード抽出（JavaScript）

```javascript
// TranslationService.extractionJavaScript
const walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT, {
    acceptNode: function(n) {
        if (!n.textContent.trim()) return NodeFilter.FILTER_REJECT;
        const tag = n.parentElement?.tagName;
        if (['SCRIPT','STYLE','NOSCRIPT','CODE','PRE','SVG'].includes(tag))
            return NodeFilter.FILTER_REJECT;
        if (n.textContent.trim().length < 3) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
    }
});
```

- `TreeWalker` で DOM 全体のテキストノードを走査
- SCRIPT/STYLE/CODE 等を除外（翻訳不要なノード）
- 3文字未満を除外（アイコンテキスト等のノイズ排除）

#### Step 2: Swift に送信

```javascript
window.__scouterTextNodes = getTextNodes(document.body);
const texts = window.__scouterTextNodes.map(n => n.textContent.trim());

// 40件ずつバッチに分割して送信
const batches = [];
for (let i = 0; i < texts.length; i += batchSize) {
    batches.push(texts.slice(i, i + batchSize));
}
window.webkit.messageHandlers.translateBatch.postMessage(JSON.stringify(batches));
```

- `window.__scouterTextNodes` にノード参照を保持（後で書き換えるため）
- `WKScriptMessageHandler` 経由で Swift 側に JSON 文字列として送信

#### Step 3-4: Swift 側で翻訳

```swift
// ArticleWebView.swift
func performTranslation(with session: TranslationSession) async {
    for (batchIndex, batch) in pendingBatches.enumerated() {
        let requests = batch.enumerated().map { idx, text in
            TranslationSession.Request(sourceText: text, clientIdentifier: "\(idx)")
        }
        let responses = try await session.translations(from: requests)
        let sorted = responses.sorted {
            Int($0.clientIdentifier ?? "0") ?? 0 < Int($1.clientIdentifier ?? "0") ?? 0
        }
        let translated = sorted.map(\.targetText)
        // JavaScript で DOM に適用
        let applyJS = TranslationService.applyTranslationsJavaScript(
            batchIndex: batchIndex, translations: translated
        )
        webView?.evaluateJavaScript(applyJS) { _, _ in }
    }
}
```

- `TranslationSession` は Apple の `.translationTask` modifier から提供される
- `clientIdentifier` で順序を保持（API の応答順が不定のため）
- 翻訳はオンデバイスで実行されるため **API コスト 0、通信不要**

#### Step 5-6: DOM に翻訳を適用

```javascript
// TranslationService.applyTranslationsJavaScript
const nodes = window.__scouterTextNodes;
const offset = batchIndex * 40;
for (let i = 0; i < translations.length; i++) {
    if (nodes[offset + i]) {
        nodes[offset + i].textContent = translations[i];
    }
}
```

### スワイプアニメーション

iOS の日付切り替えに使われるカルーセル風アニメーション。

#### ジェスチャー検出

```swift
DragGesture()
    .onChanged { value in
        dragOffset = value.translation.width  // 指の動きに追従
    }
    .onEnded { value in
        let threshold = geo.size.width * 0.25     // 画面幅の25%
        let velocity = value.predictedEndTranslation.width  // 予測速度

        if translation > threshold || velocity > 300 {
            swipeOut(direction: .right) { viewModel.goToPreviousDay() }
        } else if translation < -threshold || velocity < -300 {
            swipeOut(direction: .left) { viewModel.goToNextDay() }
        } else {
            // スナップバック（元の位置に戻る）
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                dragOffset = 0
            }
        }
    }
```

**判定基準:** 画面幅の25%以上ドラッグ **または** 予測速度300pt/s以上

#### 2フェーズアニメーション

```swift
func swipeOut(direction: SwipeDirection, screenWidth: CGFloat, then action: () -> Void) {
    let exitX = direction == .right ? screenWidth : -screenWidth
    let enterX = direction == .right ? -screenWidth : screenWidth

    // Phase 1: 現在のコンテンツを画面外へスライドアウト (0.2秒)
    withAnimation(.easeIn(duration: 0.2)) {
        dragOffset = exitX
    }

    // Phase 2: 日付変更 → 新コンテンツを反対側からスライドイン
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        action()                    // 日付を変更
        dateId = UUID()             // View を強制再生成
        dragOffset = enterX         // 画面外（反対側）に配置
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            dragOffset = 0          // 中央にスプリングアニメーション
        }
    }
}
```

**ポイント:**
- `dateId = UUID()` で `.id()` modifier を更新 → SwiftUI が View を完全に再生成
- Phase 1 は `easeIn` でスムーズに加速して退場
- Phase 2 は `spring` で弾むように入場（dampingFraction 0.85 = やや弾む）

### 画像表示（AsyncImage）

```swift
if let imageUrl = item.article.imageUrl, let url = URL(string: imageUrl) {
    AsyncImage(url: url) { phase in
        switch phase {
        case .success(let image):
            image.resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 180)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
        default:
            // プレースホルダー
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
                .frame(height: 180)
        }
    }
}
```

- `AsyncImage` は SwiftUI ネイティブの非同期画像読み込み
- `.fill` + `.clipped()` でアスペクト比を保ちつつフレームに収める
- `phase` で読み込み中/成功/失敗を分岐

---

## セットアップ手順

### 前提条件

- macOS + Xcode 16.0+
- Homebrew
- Supabase アカウント
- DeepL API アカウント (Free)

### 1. リポジトリクローン

```bash
git clone git@github.com:s-mizushima/scouter.git
cd scouter
```

### 2. Supabase CLI インストール・セットアップ

```bash
brew install supabase/tap/supabase
brew install xcodegen

supabase login
supabase link --project-ref <your-project-ref>
```

### 3. データベースマイグレーション

```bash
supabase db push              # テーブル作成 + RLS 設定
supabase db push --include-seed  # デフォルトフィード挿入
```

### 4. Edge Function デプロイ

```bash
supabase secrets set DEEPL_API_KEY=<your-deepl-key>
supabase functions deploy fetch-and-translate --no-verify-jwt
```

### 5. 初回記事取得（手動実行）

```bash
curl -X POST "https://<project>.supabase.co/functions/v1/fetch-and-translate" \
  -H "Authorization: Bearer <service_role_key>" \
  -H "Content-Type: application/json" \
  -d '{}'
```

### 6. iOS アプリビルド

```bash
cd NewsFeed
xcodegen generate
open NewsFeed.xcodeproj
# Xcode で Run (⌘R)
```

---

## コスト

| サービス | プラン | 月額 | 備考 |
|---------|--------|------|------|
| Supabase | Free | ¥0 | DB 500MB / Edge Function 500K回 |
| DeepL API | Free | ¥0 | 50万文字/月（超過時は翻訳停止、課金なし） |
| Apple Translation | - | ¥0 | オンデバイス処理 |
| **合計** | | **¥0** | |

※ App Store 公開時のみ Apple Developer Program 年額 ¥15,800 が必要

---

## 登録済みRSSフィード

| フィード | URL | 内容 |
|---------|-----|------|
| Product Hunt | `producthunt.com/feed` | 毎日の新プロダクトローンチ |
| HN Launches (YC) | `hnrss.org/launches` | Y Combinator 企業のローンチ発表 |
| Show HN | `hnrss.org/show` | 開発者・創業者のプロダクト紹介 |
| Launching Next | `launchingnext.com/rss/` | スタートアップ発見プラットフォーム |
| Ben's Bites | `bensbites.com/feed` | AI 系プロダクト・ツール紹介 |
| TechCrunch Startups | `techcrunch.com/category/startups/feed/` | スタートアップカテゴリ限定記事 |

フィード管理画面からアプリ内で追加・削除・有効/無効の切り替えが可能。
