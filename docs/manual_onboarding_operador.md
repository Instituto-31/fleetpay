# Manual de Onboarding — Operador FleetPay

**Bem-vindo ao FleetPay.** Este manual leva-te do primeiro login até teres a tua frota a funcionar — em ~20 minutos.

> 💡 **Dica:** Mantém este manual aberto numa janela e o FleetPay noutra. Vai bater certinho passo a passo.

---

## 0. Antes de começar — o que precisas à mão

- **Dados da empresa:** nome legal, NIPC, morada, código postal, número da licença TVDE
- **Logo** da empresa (PNG/SVG transparente, idealmente 512×512px)
- **IBAN** das contas a usar para pagamentos
- **Lista de motoristas** com: nome, email (importante!), telefone WhatsApp, NIF
- **Lista de viaturas** com: matrícula, marca, modelo, ano, motoristas atribuídos
- **Datas dos documentos:** seguros, inspecções, alvarás, cartas de condução

---

## 1. Primeiro login (2 min)

1. Recebes email "O teu acesso ao FleetPay" com link
2. Carrega em **"Esqueci-me da password"** em https://fleetpay.pt/login.html
3. Recebes link para definires password tua
4. Login com email + nova password → entras no admin
5. Verás um **banner laranja: "⏱️ Trial gratuito — 30 dias restantes"**

---

## 2. Configurar identidade da empresa (3 min)

**Sidebar → Configurações**

### 2.1 Dados legais
- **Identidade visual** → Carrega logo (drag and drop ou seleccionar)
- Preenche: Nome legal, NIPC, Morada, Código postal, Licença TVDE
- Telefone + email da empresa
- ✅ **Guardar**

### 2.2 Assinatura digital (para contratos)
- Secção **"🖋️ A minha assinatura digital"**
- Desenha com rato/dedo ou carrega imagem PNG fundo transparente
- Guarda

### 2.3 Tema (opcional)
- Escolhe paleta (sage, gold, tech-pro, etc.)
- Modo claro / escuro alternam separadamente

---

## 3. Adicionar motoristas (5 min)

**Sidebar → Motoristas → "+ Novo motorista"**

Para cada motorista:

| Campo | Notas |
|---|---|
| **Nome completo** | Como está na carta de condução |
| **Email** | ⚠️ Tem de ser válido — o motorista recebe magic link |
| **WhatsApp** | Formato `+351 9XX XXX XXX` |
| **NIF** | 9 dígitos |
| **IBAN** | PT50... (formato português) |
| **Carta condução · validade** | Para alertas automáticos |
| **CC · validade** | Idem |
| **Cert. TVDE · validade** | Idem |
| **Reg. criminal · validade** | Idem |

✅ **Guardar** → motorista recebe email automático com instrução de login.

> 💡 **Bulk import:** Se tens motoristas no Bolt Fleet, podes carregar CSV em **Sistema → Bolt Sync**.

---

## 4. Adicionar viaturas (5 min)

**Sidebar → Frota → "+ Nova viatura"**

Para cada viatura:

| Campo | Notas |
|---|---|
| **Matrícula** | Formato `XX-00-XX` |
| **Marca + Modelo** | Toyota Corolla, BMW iX1, etc. |
| **Ano** | 4 dígitos |
| **Tipo** | Combustão · Eléctrico · Híbrido · Plug-in |
| **Atribuir motorista** | Dropdown — escolhe o motorista actual |
| **Seguro · validade** | Para alertas |
| **Inspecção · validade** | Idem |
| **Extintor · validade** | Idem |
| **KM atuais** | Tracking opcional |

> 💡 **Dica:** Mais tarde podes mudar o motorista atribuído sem perder histórico.

---

## 5. Carregar o primeiro CSV semanal (3 min)

**Sidebar → Carregar CSV**

### 5.1 Onde descarregar os CSVs

**Uber:**
1. https://fleet.uber.com/ → Earnings → Driver Payouts
2. Escolhe a semana → "Download CSV"

**Bolt:**
1. https://fleets.bolt.eu/ → Reports → Driver Earnings
2. Escolhe a semana → "Export"

### 5.2 Carregar

1. Arrasta os 2 ficheiros para a app (ou clica "Escolher ficheiros")
2. App detecta automaticamente a semana
3. **Preview** mostra valores calculados:
   - Uber bruto → líquido
   - Bolt líquido → após IVA
   - Comissão da operadora (default 6% configurável)
   - Despesas (PRIO + Via Verde se carregaste)
   - **Valor final a transferir**

4. ✅ **Confirmar** → pagamentos criados, motoristas notificados por email

### 5.3 Despesas (opcional, melhora exactidão)

**Sidebar → Combustível** → carrega CSV PRIO (Combustível ou E-Charge)
**Sidebar → Via Verde** → carrega XLSX Via Verde

> 💡 Carregar **antes** do Uber/Bolt — assim entram automaticamente no cálculo.

---

## 6. Validação bilateral (1 min explicação, 1 dia espera)

### O que acontece no telemóvel do motorista
1. Recebe email "Já tens novo pagamento para validar"
2. Abre app PWA → vê valor da semana
3. ✓ Concordo OU ⚠️ Não concordo (com motivo)

### O que vês no admin
- Coluna estado vai de **🔔 A validar** → **✓ Pronto p/ transferir**
- Se contestou: **⚠️ Contestado** com motivo visível ao hover

> 💡 **Modo seguro:** "Marcar todos pagos" só marca os confirmados. Os contestados/por validar ficam de fora.

---

## 7. Marcar pago + recibo automático (30s)

**Sidebar → Pagamentos → "Marcar todos pagos"**

Para cada pagamento marcado pago:
- Recibo PDF gera-se automaticamente (formato profissional)
- Email automático ao motorista com link de download
- WhatsApp opcional (clica 📤 ao lado de cada motorista)

### Onde ver os recibos
- Histórico de pagamentos pagos: ícone 📄 para descarregar PDF
- Motorista vê os recibos dele na app dele (botão "📥 Descarregar Recibo")

---

## 8. Compliance TVDE (10 min, uma vez)

### 8.1 Termos & Condições
- **Sidebar → Compliance → Termos**
- Cria a versão actual (ex: "v1 — 2026")
- Motoristas vão ter de aceitar ao próximo login
- Antes de aceitar, **NÃO conseguem usar a app** (bloqueante)

### 8.2 Checklist diário 19 itens
- Pré-configurado com requisitos TVDE PT
- Motorista preenche **antes de cada turno**
- Operador vê histórico de checklists no admin

### 8.3 Tempos de condução
- **Sidebar → Tempos**
- Vê em tempo real quem está a conduzir / pausa / disponível
- 5 estados oficiais Reg. UE 165/2014
- Auditoria em PDF/CSV para inspecção ANSR

---

## 9. Contratos digitais (15 min, uma vez)

### 9.1 Carregar templates DOCX
- **Sidebar → Contratos → tab Templates**
- ✅ Já tens **templates matriz** (FleetPay base) disponíveis directamente
- OU carrega `.docx` com placeholders `«MOTORISTA_NOME»`, `«VEICULO_MATRICULA»`, etc.

### 9.2 Gerar contrato para motorista
- Tab **Gerar contrato** → escolhe template + motorista
- App preenche automaticamente os placeholders
- Descarrega `.docx` pronto a assinar
- OU clica **"Gerar PDF assinado"** → cria PDF com a tua assinatura digital + cláusula eIDAS

### 9.3 Carregar assinado
- Quando motorista assinar (Adobe Sign, DocuSign, etc.)
- **Tab Histórico → "+ Carregar PDF assinado"**
- Fica associado ao motorista para fiscalização

---

## 10. Bónus — funcionalidades que ajudam

- **🎟️ Cupões**: Motoristas indicam outros motoristas → ganham 50€ + 10% no mês (sistema de referrals)
- **💬 Mensagens**: Chat interno operador ↔ motoristas (alternativa ao WhatsApp)
- **📑 Documentos**: Carrega doc da empresa (alvará), da viatura (DUA, seguro), pessoais do motorista (certificado) — todos disponíveis ao motorista em caso de fiscalização
- **📣 Comunicações**: Anúncios em massa para todos os motoristas (notas, avisos)

---

## 11. Suporte

### Dúvida durante setup
- WhatsApp: +351 [número da Flávia]
- Email: flaviasofiacorrea@gmail.com

### Problema técnico
- Hard refresh: `Ctrl+Shift+R` (PC) ou fecha-reabre PWA (telemóvel)
- Manda screenshot por WhatsApp — respondo em 4h em horário útil

### Após os 30 dias de trial
- Subscreve em https://fleetpay.pt/upgrade.html
- Plano Pro (49€/mês) cobre frotas até 20 motoristas — o mais comum
- Sem fidelização. Cancelas quando quiseres.

---

## 12. Resumo — checklist de "estou pronto"

- [ ] Logo + dados da empresa preenchidos
- [ ] Assinatura digital guardada
- [ ] Pelo menos 1 motorista adicionado
- [ ] Pelo menos 1 viatura adicionada e atribuída
- [ ] Templates de contrato disponíveis (matriz ou próprios)
- [ ] Termos & Condições criados e activos
- [ ] Primeiro CSV carregado (mesmo que da semana passada)

**Se tudo isto está ✓ → estás pronto para o próximo domingo.**

Boas voltas. 🚗
