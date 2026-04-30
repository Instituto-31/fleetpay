# 📧 Setup Email Automático (Resend + Supabase Edge Function)

Este guia configura o envio automático de **2 emails** quando um amigo de motorista preenche o form em `oferta.html`:

1. **Lead** (amigo) → recebe confirmação com info do cupão e contactos do parceiro
2. **Operador** (empresa) → recebe alerta de lead novo com botão para abrir o admin

Tempo total: **~10 min**.

---

## Passo 1 — Criar conta Resend (2 min)

1. Vai a https://resend.com/signup
2. Cria conta com o teu email (`flaviasofiacorrea@gmail.com`)
3. Confirma o email
4. **API Keys** (menu lateral) → **Create API Key** → nome: `fleetpay` → **Add**
5. **Copia a chave** (formato `re_...`) — só aparece uma vez. Guarda no 1Password ou similar.

> **Free tier**: 100 emails/dia, 3000/mês. Suficiente para começar. Sender default: `onboarding@resend.dev` (funciona mas tem aspecto de teste). Para produção, vais querer verificar o domínio `fleetpay.pt` no Resend (15 min extra) — fica para depois.

---

## Passo 2 — Aplicar SQL na Supabase (30s)

1. https://supabase.com/dashboard/project/udqddasbfqbeeaxtnsoj/sql/new
2. Cola: https://raw.githubusercontent.com/Instituto-31/fleetpay/master/sql/oferta_emails_fix.sql
3. **Run**

Esperado: `Schema atualizado para emails automáticos`

---

## Passo 3 — Deploy da Edge Function (3 min, via dashboard)

### 3a. Criar a função
1. Supabase Dashboard → menu **Edge Functions** (ícone ⚡)
2. **Deploy a new function** ou **Create new function**
3. Nome: `send-oferta-emails` (exactamente este, com hífen)

### 3b. Copiar o código
1. Browser nova tab → https://raw.githubusercontent.com/Instituto-31/fleetpay/master/supabase/functions/send-oferta-emails/index.ts
2. **Ctrl+A** → **Ctrl+C**
3. Volta ao Supabase → cola no editor (substitui o que estiver lá)
4. **Deploy** (botão verde)

Esperado: estado `Active` ✅

---

## Passo 4 — Adicionar secrets (1 min)

A Edge Function precisa da chave Resend (e a service-role para ler dados).

1. Supabase Dashboard → **Project Settings** (engrenagem em baixo) → **Edge Functions**
2. Procura a secção **Secrets**
3. **Add new secret**:
   - Name: `RESEND_API_KEY`
   - Value: (cola a chave `re_...` do Passo 1)
   - **Save**
4. (Opcional) Adiciona outra secret:
   - Name: `RESEND_FROM`
   - Value: `FleetPay <onboarding@resend.dev>` (ou o teu domínio quando verificares)

> A `SUPABASE_SERVICE_ROLE_KEY` e `SUPABASE_URL` são **automáticas** — não precisas de adicionar.

---

## Passo 5 — Configurar email da empresa (1 min)

Para o operador receber emails, a empresa tem que ter `email` preenchido na BD.

1. https://fleetpay.pt/admin.html → **Configurações** (ou edita directo a empresa)
2. Garante que tens campo Email preenchido com `flaviasofiacorrea@gmail.com` (ou outro que verifiques)

> Se ainda não há campo na UI, pode ser editado directamente na Supabase: Table Editor → `empresas` → edita a tua linha → preenche `email`.

---

## Passo 6 — Testar end-to-end

1. **Motorista** (janela anónima) → Vantagens → 📤 Partilhar → Copia link
2. **Janela limpa** → cola link `oferta.html?t=...` → preenche nome+telefone+**email** (usa um email teu real para receber o teste)
3. **QUERO ESTA OFERTA** → vê confirmação verde
4. Em **30 segundos**:
   - **Email "Lead"** chega à caixa que indicaste no form
   - **Email "Operador"** chega à `empresa.email`
5. **Admin** → Cupões mostra **badge dourado** com `1` ao lado de Cupões na sidebar
6. Entra em **Indicações ★** → badge desaparece automaticamente

---

## Debug

Se os emails não chegarem:

### A. Verificar logs da Edge Function
- Dashboard → Edge Functions → `send-oferta-emails` → tab **Logs**
- Procura linhas vermelhas com `error` ou `RESEND_API_KEY`

### B. Verificar consola do browser na oferta.html
- F12 → Console
- Procura por `[oferta] email envio:` ou `[oferta] email falhou:`
- Vai mostrar o que a Edge Function devolveu

### C. Erros típicos
- **`RESEND_API_KEY não configurada`** → Passo 4 não foi feito
- **Email lead chega, operador não** → `empresa.email` está vazio (Passo 5)
- **`Indicação não encontrada`** → o `t=` na URL não corresponde a nenhuma indicação na BD
- **`already_sent`** → já foi enviado antes (idempotência) — comportamento correcto

### D. Testar Resend isolado
Resend Dashboard → **Logs** mostra todos os emails tentados, com erro se falhou (ex: domínio não verificado).

---

## Custos / limites

| | Free | Pro ($20/mês) |
|---|---|---|
| Emails / dia | 100 | 50.000 |
| Domínios verificados | 1 | 1.000 |
| Logs | 24h | 30 dias |

100/dia = ~3.000/mês = suficiente para uma operação pequena/média.

---

## Próximos passos (opcional, depois de funcionar)

- **Verificar domínio `fleetpay.pt`** no Resend (15 min) → emails saem como `noreply@fleetpay.pt` em vez de `@resend.dev`
- **Webhook de delivery** → atualizar BD quando email é entregue/aberto/bounced
- **Template multilíngue** (PT-PT / EN) para clientes internacionais
