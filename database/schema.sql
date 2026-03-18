-- ============================================================
-- CONTENT REPURPOSER BOT — Supabase Schema
-- ============================================================
-- Projeto de portfólio: n8n + Apify + Ollama + Gemini Flash
-- Autor: Gabriel Alves
-- ============================================================

-- 1. Perfis monitorados (perfis do X que servem de fonte)
CREATE TABLE IF NOT EXISTS source_profiles (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,          -- @handle do X
  display_name TEXT,
  niche TEXT DEFAULT 'ia_marketing',      -- ia_marketing, growth, ads, etc
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Posts originais coletados do X
CREATE TABLE IF NOT EXISTS source_posts (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  profile_id UUID REFERENCES source_profiles(id) ON DELETE CASCADE,
  tweet_id TEXT NOT NULL UNIQUE,           -- ID original do tweet
  content TEXT NOT NULL,                   -- Texto do tweet
  url TEXT,                                -- Link direto pro tweet
  likes INTEGER DEFAULT 0,
  retweets INTEGER DEFAULT 0,
  replies INTEGER DEFAULT 0,
  engagement_score NUMERIC(5,2),           -- Score calculado pelo n8n
  language TEXT DEFAULT 'en',              -- en, pt, es
  scraped_at TIMESTAMPTZ DEFAULT now(),
  is_processed BOOLEAN DEFAULT false       -- Já passou pelo Ollama?
);

-- 3. Conteúdo gerado (output do Ollama + Gemini)
CREATE TABLE IF NOT EXISTS generated_content (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  source_post_id UUID REFERENCES source_posts(id) ON DELETE CASCADE,
  
  -- LinkedIn
  linkedin_post TEXT,                      -- Texto do post LinkedIn
  linkedin_hashtags TEXT[],                -- Array de hashtags
  
  -- Blog SEO
  blog_title TEXT,
  blog_meta_description TEXT,
  blog_content TEXT,                       -- Markdown do artigo
  blog_keywords TEXT[],                    -- Array de keywords SEO
  
  -- Imagem gerada
  image_prompt TEXT,                       -- Prompt enviado pro Gemini
  image_url TEXT,                          -- URL da imagem (Supabase Storage ou base64)
  image_generated BOOLEAN DEFAULT false,
  
  -- Status e controle
  status TEXT DEFAULT 'draft' CHECK (status IN ('draft', 'approved', 'published', 'rejected')),
  quality_score NUMERIC(3,1),             -- Nota de qualidade (1-10) do Ollama
  
  generated_at TIMESTAMPTZ DEFAULT now(),
  published_at TIMESTAMPTZ,
  
  -- Metadados
  ollama_model TEXT DEFAULT 'llama3',
  generation_time_ms INTEGER              -- Tempo de geração em ms
);

-- 4. Configurações do bot
CREATE TABLE IF NOT EXISTS bot_config (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  key TEXT NOT NULL UNIQUE,
  value JSONB NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 5. Log de execuções do workflow
CREATE TABLE IF NOT EXISTS workflow_runs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  workflow_name TEXT NOT NULL,             -- 'scraping', 'repurposing', 'image_gen'
  status TEXT DEFAULT 'running' CHECK (status IN ('running', 'success', 'error')),
  posts_scraped INTEGER DEFAULT 0,
  posts_filtered INTEGER DEFAULT 0,
  content_generated INTEGER DEFAULT 0,
  images_generated INTEGER DEFAULT 0,
  error_message TEXT,
  started_at TIMESTAMPTZ DEFAULT now(),
  finished_at TIMESTAMPTZ
);

-- ============================================================
-- INDEXES para performance
-- ============================================================

CREATE INDEX idx_source_posts_processed ON source_posts(is_processed) WHERE is_processed = false;
CREATE INDEX idx_source_posts_engagement ON source_posts(engagement_score DESC);
CREATE INDEX idx_source_posts_scraped_at ON source_posts(scraped_at DESC);
CREATE INDEX idx_generated_content_status ON generated_content(status);
CREATE INDEX idx_generated_content_date ON generated_content(generated_at DESC);

-- ============================================================
-- INSERTS INICIAIS — Configuração padrão
-- ============================================================

INSERT INTO bot_config (key, value) VALUES
  ('min_engagement_score', '{"value": 7.0}'::jsonb),
  ('scraping_interval_hours', '{"value": 6}'::jsonb),
  ('ollama_model', '{"value": "llama3"}'::jsonb),
  ('max_posts_per_run', '{"value": 20}'::jsonb),
  ('target_language', '{"value": "pt-br"}'::jsonb),
  ('linkedin_tone', '{"value": "profissional, storytelling, direto"}'::jsonb),
  ('blog_word_count', '{"value": {"min": 800, "max": 1200}}'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- ============================================================
-- PERFIS DE EXEMPLO — Referências de IA/Marketing
-- ============================================================

INSERT INTO source_profiles (username, display_name, niche) VALUES
  ('levelsio', 'Pieter Levels', 'ia_marketing'),
  ('sweatystartup', 'Nick Huber', 'growth'),
  ('gregisenberg', 'Greg Isenberg', 'ia_marketing'),
  ('thiagofilemon', 'Thiago Filemon', 'ia_marketing'),
  ('joaopcampos_', 'João Campos', 'ia_marketing')
ON CONFLICT (username) DO NOTHING;

-- ============================================================
-- RLS (Row Level Security) — Opcional mas recomendado
-- ============================================================

-- Habilitar RLS em todas as tabelas
ALTER TABLE source_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE source_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE generated_content ENABLE ROW LEVEL SECURITY;
ALTER TABLE bot_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflow_runs ENABLE ROW LEVEL SECURITY;

-- Política permissiva para service_role (usado pelo n8n)
-- O n8n se conecta via service_role key, então precisa acesso total
CREATE POLICY "Service role full access" ON source_profiles FOR ALL USING (true);
CREATE POLICY "Service role full access" ON source_posts FOR ALL USING (true);
CREATE POLICY "Service role full access" ON generated_content FOR ALL USING (true);
CREATE POLICY "Service role full access" ON bot_config FOR ALL USING (true);
CREATE POLICY "Service role full access" ON workflow_runs FOR ALL USING (true);
