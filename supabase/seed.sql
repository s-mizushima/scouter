INSERT INTO feeds (name, url) VALUES
  ('Product Hunt', 'https://www.producthunt.com/feed'),
  ('HN Launches (YC)', 'https://hnrss.org/launches'),
  ('Show HN', 'https://hnrss.org/show'),
  ('Launching Next', 'https://www.launchingnext.com/rss/'),
  ('Bens Bites', 'https://bensbites.com/feed'),
  ('TechCrunch Startups', 'https://techcrunch.com/category/startups/feed/')
ON CONFLICT (url) DO NOTHING;
