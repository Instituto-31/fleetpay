# 🚗 FleetPay — Estado do Projeto
*Atualizado: Abril 2025*

---

## Credenciais Supabase
- **Project ID:** udqddasbfqbeeaxtnsoj
- **Project URL:** https://udqddasbfqbeeaxtnsoj.supabase.co
- **Anon Key:** eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVkcWRkYXNiZnFiZWVheHRuc29qIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcwMzQ1NzAsImV4cCI6MjA5MjYxMDU3MH0.bFr5wrwwJOyNLI8-3NyGZ18SxcnDHgmJ01z8TXU4yhQ
- **Organização:** Instituto-31's Org
- **Empresa demo ID:** a1b2c3d4-e5f6-7890-abcd-ef1234567890

---

## Stack
- **Frontend:** HTML/JS (existente v18 + novo)
- **Base de dados:** Supabase (PostgreSQL)
- **Auth:** Supabase Auth
- **Hosting:** GitHub Pages (instituto-31.github.io)

---

## Ficheiros Criados
| Ficheiro | Estado | Descrição |
|----------|--------|-----------|
| fleetpay_schema.sql | ✅ Executado no Supabase | Schema completo BD |
| login.html | ✅ Pronto | Página de login operador + motorista |
| motorista.html | ✅ Pronto | App motorista (ver recibos) |
| fleetpay-config.js | ✅ Pronto | Config Supabase centralizada |
| admin.html | ⏳ Por fazer | Painel operador (migração v18) |

---

## Estado Atual
- ✅ Schema SQL criado e executado no Supabase
- ✅ Tabelas: empresas, perfis, motoristas, veiculos, pagamentos, prio, viaverde, contratos
- ✅ RLS (Row Level Security) configurado
- ✅ Empresa Instituto 31 inserida como demo
- ⚠️ Trigger de criação de perfil com problema — a resolver
- ⏳ Criar utilizador operador (coordenacao@instituto31.pt)
- ⏳ Criar admin.html

---

## Próximo Passo — Resolver trigger
Correr este SQL no Supabase SQL Editor:
```sql
DROP TRIGGER IF EXISTS tr_novo_user_perfil ON auth.users;
DROP FUNCTION IF EXISTS criar_perfil_novo_user() CASCADE;

CREATE OR REPLACE FUNCTION criar_perfil_novo_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  BEGIN
    INSERT INTO public.perfis (id, email, role)
    VALUES (NEW.id, NEW.email, 'motorista')
    ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
  RETURN NEW;
END;
$$;

CREATE TRIGGER tr_novo_user_perfil
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE criar_perfil_novo_user();
```

---

## Roadmap
- **Fase 1** ✅ Schema Supabase
- **Fase 2** 🔄 Auth + Login (em curso)
- **Fase 3** ⏳ App motorista completa
- **Fase 4** ⏳ Painel operador (admin.html)
- **Fase 5** ⏳ Multi-tenant SaaS
- **Fase 6** ⏳ API Bolt + Uber

---

## App Original
- URL: https://instituto-31.github.io/tvde-i31/TVDE_Instituto31_v18%20(26).html
- Landing page: fleetpay-landing.html (local)

---

## Modelo de Negócio
| Plano | Preço | Motoristas |
|-------|-------|------------|
| Grátis | €0 | até 3 |
| Pro | €29/mês | até 15 |
| Enterprise | €59/mês | ilimitados |
