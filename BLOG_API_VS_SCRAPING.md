# Porque o FleetPay nunca pede a tua password do portal Uber ou Bolt

> Conteúdo pronto para usar como blog post, landing copy, post LinkedIn ou página "Sobre/Segurança" do FleetPay.

---

## Versão hero (10s de leitura, para landing page)

🔒 **FleetPay nunca pede a tua password.**

Outros sistemas TVDE pedem o teu login do portal Uber e Bolt para "integrar".
Isso é scraping. Viola TOS. E pode banir-te a conta.

Nós usamos só **API oficial**. Credenciais que tu geras e podes revogar.
Sem riscos. Sem violar regras. Sem dores de cabeça.

**A diferença que protege o teu negócio.**

---

## Versão completa (blog / página Sobre)

### Olá. Sou a Flávia, fundadora do FleetPay.

Quando começámos a construir o FleetPay para operadores TVDE em Portugal, tomámos uma decisão técnica que custou-nos meses de espera mas vai compensar para sempre: **nunca pedir aos operadores a sua password do portal Uber ou fleets.bolt.eu**.

### O caminho fácil que outros escolheram

Vê os SaaS de gestão TVDE no mercado. Quase todos têm um passo de onboarding parecido com este:

> "Login Uber: ____________"
>
> "Senha Uber: ____________"

Isto **não é integração**. É **automação que faz login com as tuas credenciais e raspa dados do portal**. Tem 3 problemas graves:

1. **Viola Termos de Serviço** da Uber e Bolt. Ambas proíbem expressamente automação de acesso.

2. **Arrisca banimento** da tua conta TVDE — se Uber/Bolt detectarem padrão de bot (e detectam, eventualmente), perdes acesso à plataforma. Adeus negócio.

3. **Frágil** — cada vez que Uber ou Bolt actualizam o portal, a integração parte. O SaaS que escolheste fica off-line e não recebes pagamentos.

### O caminho difícil que escolhemos

**API oficial.** Credenciais que tu geras no portal Uber/Bolt e podes revogar a qualquer momento sem afectar o teu login. Documentação estável. SLA garantido. Versionamento.

A **Bolt** já temos integrada — confirma em [fleets.bolt.eu](https://fleets.bolt.eu) → Definições → Ligações API de dados → secção "Renovação". Geras Client ID + Secret e colas no FleetPay. A tua password de login do portal **nunca passa por nós**.

A **Uber** estamos em processo de aprovação como Vehicle Suppliers Partner — leva tempo (a Uber é exigente, e bem), mas é o único caminho sustentável. Quando aprovarem, é igual: API oficial, sem passwords.

### Porque importa para ti

Quando escolheres um SaaS para gerir a tua frota TVDE, faz uma pergunta simples:

**"Pedem a minha password do portal?"**

- Se **sim**, sai dali. Não importa quão bom é o produto — estás a um update do Uber/Bolt de perderes a conta.
- Se **não**, está no caminho certo.

A tua conta Uber e Bolt é **o teu negócio**. Não a entregues a um SaaS que faça login com ela cada hora.

### Como verificar antes de assinar

Pede ao SaaS que estás a avaliar:

1. **"Que tipo de credenciais pedem para integrar com Uber e Bolt?"**
   - Resposta correcta: "Client ID e Client Secret gerados no portal API oficial"
   - Resposta de fugir: "Email e password do portal"

2. **"O vosso SaaS está aprovado como Fleet Partner pela Bolt e Vehicle Supplier pela Uber?"**
   - Resposta correcta: "Sim, temos credenciais oficiais aprovadas"
   - Resposta de fugir: silêncio ou desvio

3. **"Posso revogar o acesso ao SaaS sem afectar o meu login do portal?"**
   - Resposta correcta: "Sim, basta apagar a Client Secret no portal"
   - Resposta de fugir: "Tem que mudar a password" (= scraping)

---

## Quem somos

**FleetPay** é o SaaS de gestão de frotas TVDE construído para operadores Portugueses que valorizam segurança, robustez e relação correcta com os Termos de Serviço das plataformas.

Construído pelo Instituto 31, operador TVDE com licença IMT em Portugal. Conhecemos a dor do operador porque vivemos ela todos os dias.

— **Flávia Correia**, FleetPay

---

*[Este conteúdo está sob licença creative commons. Sente-te à vontade para partilhar.]*
