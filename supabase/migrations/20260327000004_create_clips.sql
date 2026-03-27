-- Create clips table
CREATE TABLE clips (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  article_id uuid NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  UNIQUE(article_id)
);

CREATE INDEX idx_clips_created_at ON clips(created_at DESC);

-- RLS
ALTER TABLE clips ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_read_clips" ON clips FOR SELECT TO anon USING (true);
CREATE POLICY "anon_insert_clips" ON clips FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "anon_delete_clips" ON clips FOR DELETE TO anon USING (true);
