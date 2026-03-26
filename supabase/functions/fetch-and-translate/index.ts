import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { parseFeed } from "https://deno.land/x/rss@1.0.0/mod.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const DEEPL_API_KEY = Deno.env.get("DEEPL_API_KEY")!;

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

interface FeedRow {
  id: string;
  name: string;
  url: string;
}

interface ArticleInsert {
  feed_id: string;
  title_original: string;
  title_ja: string;
  summary_original: string;
  summary_ja: string;
  article_url: string;
  published_at: string | null;
  image_url: string | null;
}

async function translateText(text: string): Promise<string> {
  if (!text || text.trim() === "") return "";

  const res = await fetch("https://api-free.deepl.com/v2/translate", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "Authorization": `DeepL-Auth-Key ${DEEPL_API_KEY}`,
    },
    body: new URLSearchParams({
      text: text,
      target_lang: "JA",
    }),
  });

  if (!res.ok) {
    console.error(`DeepL API error: ${res.status} ${await res.text()}`);
    return text;
  }

  const data = await res.json();
  return data.translations?.[0]?.text ?? text;
}

async function translateBatch(texts: string[]): Promise<string[]> {
  const nonEmpty = texts.filter((t) => t && t.trim() !== "");
  if (nonEmpty.length === 0) return texts.map(() => "");

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

  if (!res.ok) {
    console.error(`DeepL API error: ${res.status} ${await res.text()}`);
    return texts;
  }

  const data = await res.json();
  const translations = data.translations?.map((t: { text: string }) => t.text) ?? [];

  // Map back to original positions
  let idx = 0;
  return texts.map((t) => {
    if (!t || t.trim() === "") return "";
    return translations[idx++] ?? t;
  });
}

function stripHtml(html: string): string {
  return html.replace(/<[^>]*>/g, "").replace(/&[^;]+;/g, " ").trim();
}

// deno-lint-ignore no-explicit-any
function extractImageUrl(entry: any): string | null {
  // 1. Enclosure (e.g. podcast/media attachments)
  const enclosureUrl = entry.attachments?.[0]?.url;
  if (enclosureUrl) return enclosureUrl;

  // 2. First <img src="..."> in description or content
  const htmlContent = entry.description?.value ?? entry.content?.value ?? "";
  const imgMatch = htmlContent.match(/<img[^>]+src=["']([^"']+)["']/);
  if (imgMatch?.[1]) return imgMatch[1];

  // 3. entry.image.url (some Atom feeds)
  const imageUrl = entry.image?.url;
  if (imageUrl) return imageUrl;

  return null;
}

async function fetchOgImage(articleUrl: string): Promise<string | null> {
  try {
    const res = await fetch(articleUrl, {
      headers: { "User-Agent": "Scouter RSS Reader/1.0" },
      redirect: "follow",
    });
    if (!res.ok) return null;
    // Only read first 50KB to find og:image
    const reader = res.body?.getReader();
    if (!reader) return null;
    let html = "";
    while (html.length < 50000) {
      const { done, value } = await reader.read();
      if (done) break;
      html += new TextDecoder().decode(value);
    }
    reader.cancel();
    const ogMatch = html.match(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/);
    if (ogMatch?.[1]) return ogMatch[1];
    const ogMatch2 = html.match(/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']/);
    if (ogMatch2?.[1]) return ogMatch2[1];
    return null;
  } catch {
    return null;
  }
}

async function fetchAndParseFeed(feed: FeedRow): Promise<ArticleInsert[]> {
  try {
    const res = await fetch(feed.url, {
      headers: { "User-Agent": "Scouter RSS Reader/1.0" },
    });
    if (!res.ok) {
      console.error(`Failed to fetch ${feed.url}: ${res.status}`);
      return [];
    }

    const xml = await res.text();
    const parsed = await parseFeed(xml);

    const entries = parsed.entries ?? [];
    const articles: ArticleInsert[] = [];

    // Collect texts for batch translation
    const titles: string[] = [];
    const summaries: string[] = [];
    const articleData: { url: string; title: string; summary: string; published: string | null; image_url: string | null }[] = [];

    for (const entry of entries.slice(0, 20)) {
      const articleUrl = entry.links?.[0]?.href ?? entry.id ?? "";
      if (!articleUrl) continue;

      const title = entry.title?.value ?? entry.title ?? "";
      const summary = stripHtml(
        entry.description?.value ?? entry.content?.value ?? ""
      ).slice(0, 500);
      const published = entry.published
        ? new Date(entry.published).toISOString()
        : entry.updated
        ? new Date(entry.updated).toISOString()
        : null;

      const imageUrl = extractImageUrl(entry);

      titles.push(typeof title === "string" ? title : "");
      summaries.push(summary);
      articleData.push({ url: articleUrl, title: typeof title === "string" ? title : "", summary, published, image_url: imageUrl });
    }

    if (articleData.length === 0) return [];

    // Fetch og:image for articles missing images (parallel, max 5 concurrent)
    const ogPromises = articleData.map(async (a) => {
      if (a.image_url) return a.image_url;
      return await fetchOgImage(a.url);
    });
    const resolvedImages = await Promise.all(ogPromises);
    for (let i = 0; i < articleData.length; i++) {
      articleData[i].image_url = resolvedImages[i];
    }

    // Batch translate titles and summaries
    const allTexts = [...titles, ...summaries];
    const allTranslated = await translateBatch(allTexts);
    const translatedTitles = allTranslated.slice(0, titles.length);
    const translatedSummaries = allTranslated.slice(titles.length);

    for (let i = 0; i < articleData.length; i++) {
      articles.push({
        feed_id: feed.id,
        title_original: articleData[i].title,
        title_ja: translatedTitles[i],
        summary_original: articleData[i].summary,
        summary_ja: translatedSummaries[i],
        article_url: articleData[i].url,
        published_at: articleData[i].published,
        image_url: articleData[i].image_url,
      });
    }

    return articles;
  } catch (err) {
    console.error(`Error processing feed ${feed.name}:`, err);
    return [];
  }
}

serve(async (_req) => {
  try {
    // 1. Get all enabled feeds
    const { data: feeds, error: feedsError } = await supabase
      .from("feeds")
      .select("id, name, url")
      .eq("is_enabled", true);

    if (feedsError) {
      throw new Error(`Failed to fetch feeds: ${feedsError.message}`);
    }

    console.log(`Processing ${feeds.length} feeds...`);

    let totalInserted = 0;

    // 2. Process each feed
    for (const feed of feeds as FeedRow[]) {
      const articles = await fetchAndParseFeed(feed);

      if (articles.length === 0) continue;

      // 3. Upsert articles (skip duplicates by article_url)
      const { error: upsertError, count } = await supabase
        .from("articles")
        .upsert(articles, { onConflict: "article_url", ignoreDuplicates: true });

      if (upsertError) {
        console.error(`Upsert error for ${feed.name}:`, upsertError.message);
      } else {
        totalInserted += articles.length;
        console.log(`${feed.name}: ${articles.length} articles processed`);
      }
    }

    return new Response(
      JSON.stringify({ success: true, totalProcessed: totalInserted }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("Error:", err);
    return new Response(
      JSON.stringify({ success: false, error: (err as Error).message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
