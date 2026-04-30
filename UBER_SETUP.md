# 🚗 Integração Uber API — Guia de Setup (Operador FleetPay)

Este guia explica como qualquer operador TVDE com conta Uber Fleet pode integrar a sua frota Uber no FleetPay para sincronização automática de motoristas e viaturas.

**Tempo total**: ~15 min de configuração + 1-7 dias de aprovação Uber (aguardado).

---

## Pré-requisitos

✅ Tens conta activa em https://supplier.uber.com (portal Uber Fleet)
✅ És **Owner** ou **Admin** da organização Uber (não basta ser membro normal)
✅ Tens NIPC + dados da empresa em ordem na Uber
✅ A Uber considera a tua frota elegível (geralmente operadores TVDE com licença válida)

---

## Passo 1 — Aceder ao Developer Dashboard (1 min)

1. Abre https://developer.uber.com em nova tab
2. Carrega em **"Sign In"** (canto superior direito)
3. Faz login com a **mesma conta** com que geres o supplier.uber.com
4. Vai para o **Dashboard** (developer.uber.com/dashboard)

⚠️ Se o teu login não tiver acesso a Developer Dashboard, vê a secção **"Conta sem acesso"** no fim deste guia.

---

## Passo 2 — Identificar o teu Org ID (1 min)

Quando estiveres dentro do Developer Dashboard, **olha para o URL** na barra de endereço:

```
https://developer.uber.com/dashboard/organization/cdfbe538-f52e-4c3f-83a3-64b14ceef7e9/applications
                                                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                                                  ESTE é o teu Org ID (UUID)
```

**Copia o UUID** que aparece entre `/organization/` e `/applications` para um ficheiro de notas. Vais precisar dele no Passo 7.

---

## Passo 3 — Criar Application (3 min)

1. Sidebar esquerda → **Applications**
2. Botão **"Create Application"** (canto superior direito)
3. Preenche:
   - **Application Name**: `FleetPay` (ou nome da tua empresa, mas **não pode conter "Uber"**)
   - **Application Description**: `Operador de frota TVDE em Portugal a integrar a Vehicle Suppliers API para sincronização automática de motoristas e viaturas com o sistema interno de gestão.`
     (mínimo 5 palavras, máximo 400 caracteres)
   - **API Suite**: escolhe **"Vehicles"** se aparecer. Se só aparecer **"Others"**, escolhe **"Others"** — vamos pedir o upgrade no Passo 4.
4. **Create**

---

## Passo 4 — Pedir acesso à Vehicle Suppliers API (5 min + 1-7 dias espera)

A API que precisas chama-se **Vehicle Suppliers API** (também conhecida como Supplier Performance Data API). É **restrita** — só para operadores TVDE/Fleet aprovados.

### 4a. Procurar o pedido de acesso

Dentro da tua app, procura uma destas opções:
- Botão **"Request API Access"** ou **"Add API"**
- Tab **"Agreements"** com link "Request agreement"
- Email tipo "Apply for Vehicle Suppliers API"

### 4b. Preencher o pedido

A Uber vai pedir:
- **Empresa**: nome legal + NIPC
- **Licença TVDE**: nº da licença IMT
- **Caso de uso**: *"Sincronização automática de motoristas e viaturas entre a Uber e o nosso sistema de gestão interna FleetPay para reduzir entrada manual de dados e garantir consistência de informação"*
- **Volume estimado**: nº de motoristas e viaturas que tens

### 4c. Aprovação

- Tipicamente **1-7 dias úteis**
- Recebes email da Uber a confirmar
- Volta ao Developer Dashboard → app → secção **Agreements** deve mostrar o agreement como **Approved** (verde)

⚠️ Se for **rejeitado**, abre ticket em https://help.uber.com/h/business com link da rejeição e pede revisão.

---

## Passo 5 — Obter Client ID e Client Secret (1 min)

Depois da aprovação:

1. Carrega na app **Fleetpay** dentro do Developer Dashboard
2. Vês o **Application ID** (= Client ID) — copia para notas
3. Em **Authentication** → secção **"Authenticate with Client Secret"**:
   - Carrega no botão **olho 👁** ao lado do Secret para revelar
   - Carrega no botão **copiar 📋** para copiar
   - Cola nas tuas notas
4. **Guarda Client ID + Secret num gestor de passwords** (1Password, Bitwarden) — não os partilhes nem os comites em código

---

## Passo 6 — Aplicar SQL na Supabase (30s, só uma vez por instância FleetPay)

Se ainda não foi feito (é o teu admin do FleetPay, faz 1x):

1. https://supabase.com/dashboard/project/&lt;TEU_PROJETO&gt;/sql/new
2. Cola: https://raw.githubusercontent.com/Instituto-31/fleetpay/master/sql/uber_sync_schema.sql
3. **Run**

✅ Esperado: `Schema Uber sync criado!`

---

## Passo 7 — Deploy da Edge Function (3 min, só uma vez por instância)

Se ainda não foi feito:

1. Supabase Dashboard → **Edge Functions** → **Deploy a new function** → Via Editor
2. Function name: `uber-sync`
3. Cola código de https://raw.githubusercontent.com/Instituto-31/fleetpay/master/supabase/functions/uber-sync/index.ts
4. **Deploy**

A Edge Function usa as **mesmas Supabase secrets** já configuradas (SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY são automáticas). Não precisas adicionar nada novo.

---

## Passo 8 — Configurar credenciais no FleetPay (1 min)

Finalmente:

1. Abre o admin do FleetPay (`fleetpay.pt/admin.html`)
2. Confirma que a empresa selecionada (canto superior esquerdo) é a **mesma** que tem acesso à API Uber
3. **⚙️ Configurações** (sidebar) → faz scroll até **"Integração Uber API"**
4. Preenche:
   - **Uber Client ID**: o Application ID do Passo 5
   - **Uber Client Secret**: o Secret do Passo 5
   - **Uber Org ID**: o UUID do Passo 2
5. **💾 Guardar credenciais** — confirma toast verde

---

## Passo 9 — Primeiro Sincronizar (30s)

1. Mesma página → carrega em **🔄 Sincronizar agora**
2. Confirma o popup
3. Espera 10-30s
4. Resultado esperado:
   ```
   ✅ Sincronização Uber concluída
   👤 Motoristas: 12 recebidos (8 novos, 4 atualizados)
   🚗 Viaturas: 8 recebidas (5 novas, 3 atualizadas)
   ```

5. Vai a **👤 Motoristas** e **🚗 Frota** no admin → confirma que aparecem os dados Uber

---

## Conta sem acesso

Se developer.uber.com diz que não tens permissões:

1. Vai a https://supplier.uber.com → Definições → **Membros da organização**
2. Confirma que tens role **Owner** ou **Admin** (não basta "Driver Manager")
3. Se não tiveres, pede ao Owner da conta para te promover ou criar a app por ti

Outro caminho: **Owner cria a app dele** e **partilha as credenciais (Client ID + Secret + Org ID)** com quem vai usar o FleetPay.

---

## Resolução de problemas

### "Uber OAuth falhou" no FleetPay
- Client ID ou Secret estão errados → vai ao Passo 5 e re-copia
- Secret expirou ou foi revogado → renova no developer.uber.com → re-cola

### "Empresa não encontrada"
- Org ID está errado → confirma o UUID do URL no Passo 2
- A app não tem acesso à organização indicada → erro de configuração no developer.uber.com

### "Forbidden" / "403" / "no agreement"
- A Vehicle Suppliers API ainda **não foi aprovada** → repete Passo 4 ou contacta Uber Support

### "Funciona mas devolve 0 motoristas"
- A frota Uber está vazia (não tens motoristas atribuídos)
- Ou estás a sincronizar a empresa errada (verifica seletor de empresa no admin)

### "Time-out / Failed to fetch"
- A função demorou muito → frota muito grande, podemos paginar mais agressivamente. Abre issue.

---

## Multi-tenant — para outras empresas usando FleetPay

Cada empresa cliente do FleetPay faz **o seu próprio** Passo 1 a 9 — cada uma:
- Cria a sua própria conta no developer.uber.com
- Pede a sua própria aprovação à Vehicle Suppliers API
- Tem o seu próprio Org ID, Client ID, Secret
- Configura no admin do FleetPay deles (a sua linha em `empresas` na BD)

A integração é **isolada por empresa**: zero conflito entre clientes do FleetPay. Cada empresa só vê os seus próprios motoristas/viaturas Uber.

---

## Recursos

- [Uber Developer Dashboard](https://developer.uber.com/dashboard)
- [Uber Vehicle Suppliers API docs (overview)](https://developer.uber.com/docs/vehicles/introduction)
- [Get Drivers Information](https://developer.uber.com/docs/vehicles/references/api/v1/supplier-performance-data/get-drivers-information)
- [Get Vehicles Information](https://developer.uber.com/docs/vehicles/references/api/v2/supplier-performance-data/get-vehicles-information)
- [Uber Help Center (suporte)](https://help.uber.com/h/business)
