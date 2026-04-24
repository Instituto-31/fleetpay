# 🚗 FleetPay — Estado do Projeto
*Atualizado: 2026-04-24*

---

## Credenciais Supabase
- **Project ID:** udqddasbfqbeeaxtnsoj
- **Project URL:** https://udqddasbfqbeeaxtnsoj.supabase.co
- **Organização:** Instituto-31's Org
- **Empresa demo ID:** a1b2c3d4-e5f6-7890-abcd-ef1234567890
- **Anon Key:** centralizada em `fleetpay-config.js` (alterar só num sítio)

---

## Stack
- **Frontend:** HTML/JS estático (sem build)
- **Base de dados:** Supabase (PostgreSQL + RLS)
- **Auth:** Supabase Auth (password operador + magic link motorista)
- **Hosting:** GitHub Pages (planeado)
- **Versionamento:** Git local (`master`, ainda sem remote)

---

## Ficheiros
| Ficheiro | Estado | Notas |
|----------|--------|-------|
| `fleetpay_schema.sql` | ✅ Aplicado | 10 tabelas + RLS |
| `fleetpay-config.js` | ✅ Em uso | Config Supabase + helpers `auth.*` e `fleetDB.*` (helpers ainda não consumidos pelos HTMLs) |
| `login.html` | ✅ Funcional | Operador (password) + motorista (magic link), dark/light mode |
| `motorista.html` | ✅ Funcional | Recibos, expandir cards, filtro meses, dark mode. Pendente: páginas Perfil + Viatura (são alerts) |
| `admin.html` | ✅ Funcional | 10 páginas: dashboard/KPIs, pagamentos (CRUD + marcar pago + exportar), CSV Uber+Bolt+PRIO+Via Verde (parse + preview + guardar), motoristas (CRUD + convidar), frota (CRUD), alertas, histórico. Pendente: módulo Contratos (placeholder "Em breve") |

---

## Funcionalidades reais (admin.html)
- **Dashboard** — KPIs + alertas + atalhos
- **Pagamentos** — semana selector, editar valores, marcar pago/todos pagos, exportar CSV
- **Enviar recibo** — abre `wa.me/<num>?text=...` ou `mailto:` com mensagem pré-preenchida
- **CSV Upload** — drag & drop Uber + Bolt, parse, preview, confirmar e gravar
- **PRIO + Via Verde** — upload CSV separado, resumo por matrícula, aplicação automática a pagamentos
- **Motoristas** — adicionar/editar, convidar via email, validade docs (TVDE, carta, CC, registo criminal)
- **Frota** — adicionar/editar viaturas, validade docs (seguro, inspeção, extintor)
- **Alertas** — agregação automática de docs a expirar em 30 dias
- **Histórico** — lista pagamentos antigos + exportar CSV
- **Dark/Light mode** — persiste em `localStorage`

---

## Pendentes / TODO real
- [ ] **Contratos** — `admin.html:1557` é placeholder. Falta geração de Word/PDF.
- [ ] **App motorista** — botões "Perfil" e "Viatura" são `alert("Em breve")`.
- [ ] **Recibos PDF** — campo `recibo_pdf_url` esperado mas sem upload implementado.
- [ ] **Aplicar paleta Instituto 31** (sage + gold dos emails)? — atualmente usa dourado #c8922a sobre preto, mais "luxury" que "instituto".
- [ ] **Deploy GitHub Pages** — repo dedicado ou pasta no `instituto-31.github.io`.
- [ ] **Comprar domínio** (`fleetpay.pt`?) e apontar via CNAME.
- [ ] **Multi-tenant SaaS** — onboarding de novas empresas.
- [ ] **Integração Bolt + Uber API** — substituir CSV.

---

## Fixes aplicados (2026-04-24)
- Bug em `login.html`: tag `<script src="...supabase">` tinha código JS dentro (era ignorado pelo browser) → separado em duas tags.
- `SUPABASE_URL`/`SUPABASE_KEY` duplicado em 3 HTMLs → centralizado em `fleetpay-config.js`. Trocar a chave passa a ser uma única edição.
- Comentário enganador `// SUBSTITUI PELA TUA ANON KEY COMPLETA` removido (a chave já estava lá).
- Inicializado git local + commit inicial.

---

## Modelo de Negócio
| Plano | Preço | Motoristas |
|-------|-------|------------|
| Grátis | €0 | até 3 |
| Pro | €29/mês | até 15 |
| Enterprise | €59/mês | ilimitados |

---

## App Original (referência)
- URL: https://instituto-31.github.io/tvde-i31/TVDE_Instituto31_v18%20(26).html
