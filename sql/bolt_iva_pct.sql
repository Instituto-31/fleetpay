-- Adiciona coluna bolt_iva_pct (default 6%) ao schema empresas.
-- Usado pela Edge Function bolt-earnings para calcular bolt_iva = bolt_bruto * pct/(100+pct).

ALTER TABLE empresas
  ADD COLUMN IF NOT EXISTS bolt_iva_pct NUMERIC(5,2) DEFAULT 6;

-- Garante que empresas existentes ficam com 6 caso a coluna já existisse sem default
UPDATE empresas SET bolt_iva_pct = 6 WHERE bolt_iva_pct IS NULL;
