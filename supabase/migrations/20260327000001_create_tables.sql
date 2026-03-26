-- Create feeds table
CREATE TABLE feeds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  url text UNIQUE NOT NULL,
  is_enabled boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

-- Create articles table
CREATE TABLE articles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  feed_id uuid NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
  title_original text,
  title_ja text,
  summary_original text,
  summary_ja text,
  article_url text UNIQUE NOT NULL,
  published_at timestamptz,
  fetched_at timestamptz DEFAULT now()
);

-- Indexes for common queries
CREATE INDEX idx_articles_published_at ON articles(published_at DESC);
CREATE INDEX idx_articles_feed_id ON articles(feed_id);
