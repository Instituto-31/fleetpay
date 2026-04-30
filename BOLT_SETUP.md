# 🚗 Setup Bolt API Sync (Parte A: motoristas + viaturas)

Sincroniza automaticamente motoristas e viaturas a partir do portal **fleets.bolt.eu** para o admin do FleetPay.

Tempo total: **~5 min** (depois de teres credenciais Bolt válidas).

---

## Pré-requisitos

Tens que ser **Fleet Partner** aprovado pela Bolt. Confirma que tens:

- ✅ Acesso a https://fleets.bolt.eu com login
- ✅ **Settings → API → Generate credentials**
   - Client ID (formato `bolt_xxx...` ou `xxxxxxxx-xxxx-...`)
   - Client Secret (string longa)
- ✅ **Company ID** (numérico, visível em `Settings → Company` ou no URL do portal `?company_id=XXXXX`)

Se ainda não tens credenciais, candidata-te ao programa Fleet Partners (geralmente Bolt só aprova operadores com 50+ viaturas ou parcerias estabelecidas).

---

## Passo 1 — Aplicar SQL na Supabase (30s)

1. https://supabase.com/dashboard/project/udqddasbfqbeeaxtnsoj/sql/new
2. Cola: https://raw.githubusercontent.com/Instituto-31/fleetpay/master/sql/bolt_sync_schema.sql
3. **Run**

Esperado: `Schema bolt-sync pronto`

---

## Passo 2 — Configurar credenciais no admin (1 min)

1. https://fleetpay.pt/admin.html → **⚙️ Configurações**
2. Scroll até **Integração Bolt API**
3. Preenche:
   - **Bolt Client ID**: cola da Bolt
   - **Bolt Client Secret**: cola da Bolt
   - **Bolt Company ID**: o número (sem letras)
4. **💾 Guardar credenciais**

---

## Passo 3 — Deploy da Edge Function (3 min, via Dashboard)

1. Supabase Dashboard → **Edge Functions** (ícone ⚡)
2. **Deploy a new function** ou **Create new function**
3. Nome: **`bolt-sync`** (exactamente este, com hífen)
4. Browser nova tab → https://raw.githubusercontent.com/Instituto-31/fleetpay/master/supabase/functions/bolt-sync/index.ts
5. **Ctrl+A** → **Ctrl+C**
6. Volta ao Supabase → cola no editor → **Deploy**

Esperado: estado **Active** ✅

> ℹ️ **Não precisas de adicionar nenhum secret novo** — `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` são automáticas, e as credenciais Bolt vêm da BD da empresa.

---

## Passo 4 — Sincronizar pela primeira vez

1. Admin → Configurações → **🔄 Sincronizar agora**
2. Confirma o aviso
3. Espera 5-30s (depende de quantos motoristas/viaturas tens na Bolt)
4. Aparece alert com resumo:
   - 👤 Motoristas: N recebidos (X novos, Y atualizados)
   - 🚗 Viaturas: N recebidas (X novas, Y atualizadas)

5. Vai a **👤 Motoristas** → vês a lista atualizada com os nomes da Bolt
6. Vai a **🚗 Frota** → vês as viaturas com matrículas, marcas, modelos

---

## Como funciona o **match**

Quando a Bolt devolve um motorista, o sistema procura por esta ordem:
1. **`bolt_driver_id`** já existente → atualiza
2. **email igual** → atualiza + linka Bolt ID
3. **telefone igual** → atualiza + linka Bolt ID
4. **Nada igual** → cria novo motorista

Igual para viaturas, mas por **matrícula** em vez de email/telefone.

Vantagem: se já tinhas um motorista no admin manualmente, na 1ª sincronização ele é **linkado** (não duplicado). Sincronizações seguintes só atualizam.

---

## Limitações da Parte A

- ❌ **Não puxa pagamentos** (continua a ser via CSV) — fica para Parte B
- ❌ **Não puxa validades de documentos** (CC, carta, TVDE, etc.) — esses dados não estão na Bolt
- ❌ **Não é automático** — tens que carregar no botão. Sync agendada fica para Parte C

---

## Debug

### A. Edge Function logs
Dashboard → Edge Functions → `bolt-sync` → tab **Logs** → procura linhas com `[bolt-sync]` ou `error`.

### B. Consola do browser
Quando carregas em "Sincronizar agora":
1. F12 → Console
2. Procura linha `[bolt-sync] resposta:` — mostra exactamente o que a função devolveu
3. Se houver `errors[]` no summary, são erros por motorista/viatura específico

### C. Erros típicos

| Erro | Causa | Fix |
|---|---|---|
| `Bolt OAuth 401` | Client ID/Secret errados | Verifica copy/paste das credenciais |
| `Bolt OAuth 400 invalid_scope` | Conta não é Fleet Partner | Pede acesso à Bolt |
| `getDrivers 403` | Permissão em falta | Confirma que a conta API tem scope completo |
| `getDrivers 400 missing company_id` | Company ID em falta ou errado | Preenche `bolt_company_id` no admin |
| `Sem permissão` | Estás logado como motorista | Login como operador/superadmin |
| `Credenciais Bolt não configuradas` | Configurações vazias | Passo 2 |

### D. Testar OAuth isolado (curl)

Se queres confirmar que as credenciais funcionam fora do FleetPay:

```bash
curl -X POST https://oidc.bolt.eu/token \
  -d "grant_type=client_credentials" \
  -d "client_id=SEU_CLIENT_ID" \
  -d "client_secret=SEU_SECRET" \
  -d "scope=fleet-integration:api"
```

Resposta esperada: `{"access_token":"...","expires_in":3600,...}`

Se der 401/400, o problema está nas credenciais (não no FleetPay).

---

## Próximos passos (Partes B e C)

Depois de validares que a **Parte A** funciona:

**Parte B — Pagamentos** (~2h)
- Endpoint `getOrdersForApiCalls` ou `getDriverEarnings`
- Cria pagamentos automaticamente (substitui upload CSV)

**Parte C — Sync diário automático** (~2h)
- Supabase pg_cron + função wrapper
- Corre todas as noites, atualiza tudo

Avisa quando a Parte A estiver a passar dados reais e arrancamos com B.
