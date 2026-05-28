// FleetPay — Edge Function "enviar-email-motorista"
// Envia emails via Resend para motoristas com templates HTML profissionais.
// Suporta tipos: pagamento_criado | pagamento_pago | documento_expira | termo_novo | personalizado
// Logs em notificacoes_enviadas (deduplicação via UNIQUE INDEX).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") || "";
const RESEND_FROM = Deno.env.get("RESEND_FROM") || "FleetPay <noreply@fleetpay.pt>";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const APP_URL = Deno.env.get("APP_URL") || "https://fleetpay.pt";

// ─── Paleta sage + gold (igual ao admin / motorista) ───
const PAL = {
  ink: "#111418",
  paper: "#f4f1ea",
  gold: "#c8922a",
  sage: "#7a8c66",
  sub: "#888",
  line: "#e6e1d6",
  red: "#c44545",
  orange: "#e8943a",
};

interface ReqBody {
  motorista_id: string;
  tipo: "pagamento_criado" | "pagamento_pago" | "documento_expira" | "termo_novo" | "personalizado";
  referencia_id?: string | null;
  dados?: Record<string, unknown>;
  forcar?: boolean;   // ignora dedupe
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json(405, { ok: false, error: "Method not allowed" });

  if (!RESEND_API_KEY) {
    return json(500, { ok: false, error: "RESEND_API_KEY não configurada nos secrets da Edge Function" });
  }

  let body: ReqBody;
  try { body = await req.json(); } catch { return json(400, { ok: false, error: "JSON inválido" }); }

  const { motorista_id, tipo, referencia_id, dados, forcar } = body;
  if (!motorista_id || !tipo) return json(400, { ok: false, error: "motorista_id e tipo são obrigatórios" });

  const db = createClient(SUPABASE_URL, SERVICE_ROLE);

  // 1) busca motorista + empresa
  const { data: mot, error: motErr } = await db
    .from("motoristas")
    .select("id, nome, email, empresa_id, empresas(nome, logo_path)")
    .eq("id", motorista_id)
    .maybeSingle();

  if (motErr || !mot) return json(404, { ok: false, error: "Motorista não encontrado" });
  if (!mot.email) return json(400, { ok: false, error: "Motorista sem email" });

  const empresaNome = (mot.empresas as any)?.nome || "FleetPay";

  // 2) dedupe — se já enviou e !forcar
  if (!forcar && referencia_id) {
    const { data: jaEnviado } = await db.from("notificacoes_enviadas")
      .select("id")
      .eq("motorista_id", motorista_id)
      .eq("tipo", tipo)
      .eq("referencia_id", referencia_id)
      .eq("canal", "email")
      .eq("sucesso", true)
      .limit(1)
      .maybeSingle();
    if (jaEnviado) {
      return json(200, { ok: true, skipped: true, reason: "já enviado", id: jaEnviado.id });
    }
  }

  // 3) constrói template
  const { assunto, html } = construirTemplate(tipo, {
    nome: mot.nome || "Motorista",
    empresa: empresaNome,
    appUrl: APP_URL,
    dados: dados || {},
  });

  // 4) envia via Resend
  let providerResp: any = null;
  let sucesso = true;
  let erro: string | null = null;

  try {
    const resp = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: RESEND_FROM,
        to: [mot.email],
        subject: assunto,
        html,
      }),
    });
    providerResp = await resp.json();
    if (!resp.ok) {
      sucesso = false;
      erro = providerResp?.message || `HTTP ${resp.status}`;
    }
  } catch (e) {
    sucesso = false;
    erro = (e as Error).message;
  }

  // 5) log
  await db.from("notificacoes_enviadas").insert({
    empresa_id: mot.empresa_id,
    motorista_id,
    tipo,
    referencia_id: referencia_id || null,
    canal: "email",
    destino: mot.email,
    assunto,
    sucesso,
    erro,
    resposta_provider: providerResp,
  });

  return json(sucesso ? 200 : 500, {
    ok: sucesso,
    erro,
    provider: providerResp,
  });
});

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

// ─── Templates HTML ───
function construirTemplate(
  tipo: string,
  ctx: { nome: string; empresa: string; appUrl: string; dados: Record<string, unknown> }
): { assunto: string; html: string } {
  const { nome, empresa, appUrl, dados } = ctx;
  const firstName = nome.split(" ")[0];

  let assunto = "FleetPay";
  let titulo = "";
  let corpo = "";
  let ctaTexto = "";
  let ctaUrl = appUrl;

  switch (tipo) {
    case "pagamento_criado": {
      const semana = (dados.semana as string) || "esta semana";
      const valor = (dados.valor as string) || "—";
      assunto = `[FleetPay] Tens um novo pagamento para validar — ${semana}`;
      titulo = "Valida o teu pagamento";
      corpo = `
        <p>Olá ${firstName},</p>
        <p>A operadora <strong>${empresa}</strong> lançou o pagamento da semana <strong>${semana}</strong>.</p>
        <p>Confirma que estás de acordo com o valor antes da transferência ser feita:</p>
        <table style="width:100%;background:${PAL.paper};border:1px solid ${PAL.line};border-radius:6px;padding:18px;margin:18px 0">
          <tr><td style="color:${PAL.sub};font-size:12px;letter-spacing:1px;text-transform:uppercase">Valor a transferir</td></tr>
          <tr><td style="font-size:32px;color:${PAL.gold};font-weight:300;padding-top:4px">${valor}</td></tr>
        </table>
      `;
      ctaTexto = "✓ Validar agora";
      ctaUrl = `${appUrl}/motorista.html`;
      break;
    }
    case "pagamento_pago": {
      const semana = (dados.semana as string) || "—";
      const valor = (dados.valor as string) || "—";
      const reciboNum = (dados.recibo_numero as string) || "";
      assunto = `[FleetPay] Pagamento concluído — ${semana}${reciboNum ? ` (Recibo ${reciboNum})` : ""}`;
      titulo = "Pagamento concluído";
      corpo = `
        <p>Olá ${firstName},</p>
        <p>Foi feita a transferência do teu pagamento da semana <strong>${semana}</strong>.</p>
        <table style="width:100%;background:${PAL.paper};border:1px solid ${PAL.line};border-radius:6px;padding:18px;margin:18px 0">
          <tr><td style="color:${PAL.sub};font-size:12px;letter-spacing:1px;text-transform:uppercase">Valor transferido</td></tr>
          <tr><td style="font-size:32px;color:${PAL.sage};font-weight:300;padding-top:4px">${valor}</td></tr>
          ${reciboNum ? `<tr><td style="padding-top:10px;color:${PAL.sub};font-size:11px;font-family:monospace">Recibo nº ${reciboNum}</td></tr>` : ""}
        </table>
        <p>Podes descarregar o recibo na app — útil para a tua contabilidade fiscal.</p>
      `;
      ctaTexto = "📥 Descarregar recibo";
      ctaUrl = `${appUrl}/motorista.html`;
      break;
    }
    case "documento_expira": {
      const docTipo = (dados.doc_tipo as string) || "Documento";
      const validade = (dados.validade as string) || "";
      const dias = (dados.dias as number) ?? 0;
      assunto = `[FleetPay] ${docTipo} expira em ${dias} dias`;
      titulo = "Documento prestes a expirar";
      const cor = dias <= 7 ? PAL.red : PAL.orange;
      corpo = `
        <p>Olá ${firstName},</p>
        <p>O teu documento <strong>${docTipo}</strong> expira em <strong style="color:${cor}">${dias} dia${dias===1?'':'s'}</strong> (${validade}).</p>
        <p>Renova-o atempadamente para não ficares impedido de trabalhar em caso de fiscalização.</p>
        <p>Depois de renovar, podes carregar o documento actualizado na app, no teu Perfil → 📑 Os meus documentos.</p>
      `;
      ctaTexto = "📑 Ir aos meus documentos";
      ctaUrl = `${appUrl}/motorista.html`;
      break;
    }
    case "termo_novo": {
      assunto = `[FleetPay] Atualização de Termos e Condições`;
      titulo = "Novos termos para aceitar";
      corpo = `
        <p>Olá ${firstName},</p>
        <p>A operadora <strong>${empresa}</strong> publicou uma nova versão dos termos.</p>
        <p>Tens de aceitar os novos termos no próximo acesso à app para continuar a usar o FleetPay.</p>
      `;
      ctaTexto = "Aceitar termos";
      ctaUrl = `${appUrl}/motorista.html`;
      break;
    }
    case "personalizado": {
      assunto = (dados.assunto as string) || `[FleetPay] Mensagem de ${empresa}`;
      titulo = (dados.titulo as string) || "Mensagem";
      corpo = `
        <p>Olá ${firstName},</p>
        <p>${dados.mensagem || "(sem conteúdo)"}</p>
      `;
      ctaTexto = "Abrir app";
      ctaUrl = `${appUrl}/motorista.html`;
      break;
    }
    default: {
      assunto = "[FleetPay] Notificação";
      titulo = "Notificação";
      corpo = `<p>Olá ${firstName},</p><p>Tens uma nova notificação na app FleetPay.</p>`;
      ctaTexto = "Abrir app";
    }
  }

  const html = layout({ titulo, corpo, ctaTexto, ctaUrl, empresa });
  return { assunto, html };
}

function layout(args: { titulo: string; corpo: string; ctaTexto: string; ctaUrl: string; empresa: string }): string {
  const { titulo, corpo, ctaTexto, ctaUrl, empresa } = args;
  return `<!DOCTYPE html>
<html lang="pt-PT">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${titulo}</title>
</head>
<body style="margin:0;padding:0;background:${PAL.paper};font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;color:${PAL.ink};line-height:1.6">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background:${PAL.paper};padding:40px 20px">
    <tr><td align="center">
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:560px;background:#fff;border:1px solid ${PAL.line};border-radius:8px;overflow:hidden">

        <!-- Header -->
        <tr><td style="background:${PAL.ink};padding:24px 32px;text-align:center">
          <div style="color:${PAL.gold};font-size:22px;font-weight:300;letter-spacing:2px">
            <span style="display:inline-block;width:14px;height:14px;border:2.5px solid ${PAL.gold};border-radius:50%;vertical-align:middle;margin-right:8px"></span>
            Fleet<em style="font-style:italic">Pay</em>
          </div>
          <div style="color:#888;font-size:10px;letter-spacing:2px;text-transform:uppercase;margin-top:4px">${empresa}</div>
        </td></tr>

        <!-- Body -->
        <tr><td style="padding:36px 32px 24px 32px">
          <h1 style="font-family:Georgia,serif;font-weight:300;font-size:26px;color:${PAL.ink};margin:0 0 18px 0">${titulo}</h1>
          <div style="font-size:15px;color:#444">${corpo}</div>

          <div style="text-align:center;margin:28px 0 12px 0">
            <a href="${ctaUrl}" style="display:inline-block;background:${PAL.gold};color:${PAL.ink};text-decoration:none;padding:14px 32px;border-radius:4px;font-size:13px;font-weight:600;letter-spacing:1.5px;text-transform:uppercase">${ctaTexto}</a>
          </div>
        </td></tr>

        <!-- Footer -->
        <tr><td style="background:${PAL.paper};padding:20px 32px;border-top:1px solid ${PAL.line};text-align:center;font-size:11px;color:${PAL.sub}">
          Recebes este email porque és motorista registado em ${empresa}.<br>
          Esta é uma mensagem automática da plataforma FleetPay.
        </td></tr>

      </table>
      <div style="max-width:560px;margin-top:14px;font-size:10px;color:${PAL.sub};font-family:monospace">fleetpay.pt</div>
    </td></tr>
  </table>
</body>
</html>`;
}
