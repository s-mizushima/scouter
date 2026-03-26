-- Enable RLS
ALTER TABLE feeds ENABLE ROW LEVEL SECURITY;
ALTER TABLE articles ENABLE ROW LEVEL SECURITY;

-- Anon can read feeds and articles
CREATE POLICY "anon_read_feeds" ON feeds
  FOR SELECT TO anon USING (true);

CREATE POLICY "anon_read_articles" ON articles
  FOR SELECT TO anon USING (true);

-- Service role has full access (implicit via bypass RLS)

-- NOTE: pg_cron setup requires the pg_cron extension to be enabled in the Supabase dashboard.
-- Once enabled, run the following SQL manually in the SQL Editor:
--
-- SELECT cron.schedule(
--   'fetch-and-translate-daily',
--   '0 6 * * *',
--   $$
--   SELECT net.http_post(
--     url := '<SUPABASE_URL>/functions/v1/fetch-and-translate',
--     headers := '{"Authorization": "Bearer <SERVICE_ROLE_KEY>", "Content-Type": "application/json"}'::jsonb,
--     body := '{}'::jsonb
--   );
--   $$
-- );
