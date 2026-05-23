# SQL migrations / scripts — FleetPay

Esta pasta tem todos os scripts SQL aplicados manualmente no Supabase
SQL Editor. Cada um é idempotente (pode correr-se várias vezes sem
efeitos secundários) — usa `IF EXISTS` / `IF NOT EXISTS` em todo o lado.

## Ordem cronológica (em caso de fresh install)

| Data | Ficheiro | O que faz |
|---|---|---|
| 2026-04-25 | `mensagens_schema.sql` | Sistema de chat motorista ↔ operador |
| 2026-04-25 | `signup_publico.sql` | Self-signup de novas empresas via landing |
| 2026-04-25 | `bolt_sync_schema.sql` | Tabelas para sync da API Bolt |
| 2026-04-25 | `uber_sync_schema.sql` | Tabelas para sync da API Uber |
| 2026-04-25 | `onboarding_schema.sql` | Wizard de onboarding multi-step |
| 2026-04-25 | `comunicacoes_schema.sql` | Mensagens broadcast operador → motoristas |
| 2026-04-26 | `cupoes_schema.sql` | Sistema de cupões de desconto |
| 2026-04-26 | `cupoes_psi_formacao_global.sql` | Cupões PSI/Formação globais (cross-sell) |
| 2026-04-26 | `cupoes_psi_formacao_restriction.sql` | Restrições de visibilidade |
| 2026-04-26 | `cupoes_rls_fix.sql` | Fix RLS dos cupões |
| 2026-04-26 | `oferta_emails_fix.sql` | Fix do envio de emails de oferta |
| 2026-04-26 | `indicacoes_schema.sql` | Sistema de indicações de candidatos |
| 2026-04-26 | `limite_motoristas_trigger.sql` | Enforce limite por plano (Free=3, Pro=15) |
| 2026-04-26 | `ligar_perfis_motoristas.sql` | Liga `perfis.id` ↔ `motoristas.perfil_id` |
| 2026-04-26 | `trigger_auto_ligar_perfil_motorista.sql` | Auto-link após signup motorista |
| 2026-04-26 | `uber_bolt_nome.sql` | Colunas uber_nome / bolt_nome em motoristas |
| 2026-04-29 | `fundir_duplicados_motoristas.sql` | Limpeza motoristas duplicados |
| 2026-04-29 | `importar_motoristas_inst31.sql` | Import inicial Inst31 (one-off) |
| 2026-05-19 | `comissao_motorista.sql` | Coluna `motoristas.comissao_pct` (default 6) |
| 2026-05-20 | `storage_superadmin_contratos.sql` | Storage policies para superadmin copiar templates |
| 2026-05-20 | `termos_aceitacoes_completo.sql` | **(novo)** RLS + UNIQUE + validação operador |
| 2026-05-20 | `contratos_assinados_anon_policies.sql` | **(novo)** Anon SELECT/UPDATE para assinar.html via token |
| 2026-05-23 | `empresas_assinatura_png.sql` | **(novo)** Coluna `empresas.assinatura_png` |

## Como aplicar

1. Abre Supabase Dashboard → SQL Editor
2. Cola o conteúdo do ficheiro `.sql`
3. **Run** (Ctrl+Enter)
4. Confirma a mensagem de sucesso no fim do script

## Notas

- Os scripts são desenhados para a estrutura actual de tabelas (`empresas`, `perfis`, `motoristas`, etc.) já criada via `fleetpay_schema.sql` inicial.
- Funções helpers usadas: `get_role()` (devolve 'superadmin'/'operador'/'motorista' do perfil autenticado), `auth.uid()` (UUID do utilizador autenticado).
- Tabelas Compliance (`termos_versoes`, `termos_aceitacoes`, `checklist_items_config`, `checklists_diarios`) e Contratos (`contratos_templates`, `contratos_assinados`) foram criadas via Dashboard UI (não estão como SQL no repo). Estas migrations só ajustam policies/colunas dessas tabelas.

## Buckets Storage

- `empresa-logos` (público) — logos das empresas
- `contratos-templates` (privado) — templates .docx
- `contratos-assinados` (privado) — PDFs assinados arquivados

## Edge Functions

Em `supabase/functions/`:
- `convidar-motorista` — magic link + auto-link perfil
- `bolt-sync`, `bolt-earnings` — sync API Bolt
- `uber-sync` — sync API Uber
- `send-oferta-emails` — emails de oferta (Resend)
- `gerar-pdf-assinado` — **(novo 2026-05-23)** geração PDF via Aspose Cloud + pdf-lib
