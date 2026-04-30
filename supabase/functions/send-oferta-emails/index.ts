// FleetPay — Edge Function: send-oferta-emails
// Envia 2 emails quando alguém preenche o form em oferta.html:
//   1. Para o LEAD (amigo do motorista)         — confirmação + info do cupão
//   2. Para o OPERADOR (empresa.email)          — alerta de lead novo
//
// Trigger: chamado por oferta.html após UPDATE em cupoes_indicacoes
// Auth:    requer apikey anon (qualquer pessoa pode disparar — protegido
//          pelo facto de só funciona se a indicação existir e tiver email)
//
// Secrets necessários (Project Settings → Edge Functions → Secrets):
//   RESEND_API_KEY   — chave da conta Resend
//   RESEND_FROM      — opcional (default: 'FleetPay <onboarding@resend.dev>')

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const CATS: Record<string, string> = {
  psi: '🧠', formacao: '🎓', slot: '⏰', combustivel: '⛽',
  seguro: '🛡️', oficina: '🔧', saas: '💻', servico: '✨', outro: '🎟️',
};

function valorTexto(c: any): string {
  if (c.tipo === 'gratis') return 'GRÁTIS';
  if (c.tipo === 'oferta') return 'OFERTA';
  if (c.tipo === 'percentagem') return `${c.valor}%`;
  return `${c.valor}€`;
}

function emailLead(opts: { lead: any; cupao: any; empresa: any; indicador: any; ofertaUrl: string }): string {
  const { lead, cupao, empresa, indicador, ofertaUrl } = opts;
  const cat = CATS[cupao.categoria] || '🎟️';
  const valor = valorTexto(cupao);
  return `<!DOCTYPE html>
<html lang="pt-PT">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"></head>
<body style="margin:0;padding:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#f7f4ef;color:#0a0905">
  <div style="max-width:560px;margin:0 auto;background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 4px 20px rgba(0,0,0,0.08);margin-top:20px;margin-bottom:20px">
    <div style="background:linear-gradient(135deg,#0a0905 0%,#1a1407 100%);padding:30px 28px;text-align:center;color:#fff">
      <div style="font-family:Georgia,serif;font-size:22px;font-weight:300;letter-spacing:.5px">Fleet<span style="color:#c8922a;font-style:italic">Pay</span></div>
      <div style="font-family:'Courier New',monospace;font-size:10px;letter-spacing:2px;color:#c8922a;margin-top:6px">CUPÃO PARTILHADO POR UM AMIGO</div>
    </div>
    <div style="padding:32px 28px">
      <p style="font-size:15px;color:#5a5147;margin:0 0 20px;line-height:1.6">Olá <strong>${lead.indicado_nome || ''}</strong>!</p>
      <p style="font-size:15px;color:#5a5147;margin:0 0 24px;line-height:1.6"><strong>${indicador?.nome?.split(' ')[0] || 'Um amigo'}</strong> partilhou contigo uma oferta exclusiva${empresa?.nome ? ' do <strong>' + empresa.nome + '</strong>' : ''}.</p>
      <div style="background:#fefcf8;border:2px solid #c8922a;border-radius:10px;padding:24px;text-align:center;margin:24px 0">
        <div style="font-size:42px;margin-bottom:6px">${cat}</div>
        <div style="font-family:Georgia,serif;font-weight:300;font-size:22px;color:#0a0905;margin-bottom:6px">${cupao.titulo}</div>
        ${cupao.parceiro_nome ? `<div style="font-size:11px;color:#a89c87;font-family:'Courier New',monospace;letter-spacing:.5px;text-transform:uppercase;margin-bottom:12px">${cupao.parceiro_nome}</div>` : ''}
        <div style="font-family:Georgia,serif;font-weight:300;font-size:54px;color:#c8922a;line-height:1;margin:14px 0">${valor}</div>
        ${cupao.descricao ? `<div style="font-size:13px;color:#5a5147;line-height:1.6;margin-top:12px">${cupao.descricao}</div>` : ''}
        <div style="font-family:'Courier New',monospace;font-size:11px;color:#a89c87;margin-top:14px;padding-top:14px;border-top:1px solid #e8e2d8;letter-spacing:1px">CÓDIGO: <strong style="color:#0a0905">${cupao.codigo}</strong></div>
        ${cupao.valido_ate ? `<div style="font-family:'Courier New',monospace;font-size:11px;color:#a89c87;letter-spacing:.5px;margin-top:6px">Válido até ${new Date(cupao.valido_ate).toLocaleDateString('pt-PT')}</div>` : ''}
      </div>
      <div style="background:#f0ebe0;border-radius:8px;padding:18px;margin:24px 0">
        <div style="font-family:'Courier New',monospace;font-size:10px;color:#a89c87;letter-spacing:1px;text-transform:uppercase;margin-bottom:8px">Próximo passo</div>
        <div style="font-size:14px;color:#5a5147;line-height:1.6">${empresa?.nome || 'O parceiro'} vai contactar-te no telefone que indicaste${empresa?.telefone ? '. Podes também ligar diretamente: <strong>' + empresa.telefone + '</strong>' : '.'}</div>
      </div>
      ${cupao.parceiro_link ? `<div style="text-align:center;margin:30px 0"><a href="${cupao.parceiro_link}" style="display:inline-block;padding:14px 32px;background:#c8922a;color:#000;text-decoration:none;border-radius:6px;font-family:'Courier New',monospace;font-size:11px;letter-spacing:1.5px;text-transform:uppercase;font-weight:700">↗ Visitar ${cupao.parceiro_nome || empresa?.nome || 'parceiro'}</a></div>` : ''}
      <div style="text-align:center;margin:30px 0 0"><a href="${ofertaUrl}" style="font-size:12px;color:#a89c87;text-decoration:underline">Ver oferta no FleetPay</a></div>
    </div>
    <div style="padding:18px 28px;background:#0a0905;color:#a89c87;text-align:center;font-family:'Courier New',monospace;font-size:9px;letter-spacing:1px">FLEETPAY · CUPÃO EXCLUSIVO · PARTILHADO POR UM AMIGO</div>
  </div>
</body>
</html>`;
}

function emailOperador(opts: { lead: any; cupao: any; empresa: any; indicador: any; adminUrl: string }): string {
  const { lead, cupao, empresa, indicador, adminUrl } = opts;
  const valor = valorTexto(cupao);
  return `<!DOCTYPE html>
<html lang="pt-PT">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"></head>
<body style="margin:0;padding:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#f7f4ef;color:#0a0905">
  <div style="max-width:560px;margin:0 auto;background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 4px 20px rgba(0,0,0,0.08);margin-top:20px;margin-bottom:20px">
    <div style="background:linear-gradient(135deg,#c8922a 0%,#e0a93e 100%);padding:24px 28px;color:#000">
      <div style="font-family:'Courier New',monospace;font-size:10px;letter-spacing:2px;font-weight:700">🎯 LEAD NOVO</div>
      <div style="font-family:Georgia,serif;font-weight:300;font-size:24px;margin-top:6px">${lead.indicado_nome || 'Sem nome'}</div>
    </div>
    <div style="padding:28px">
      <p style="font-size:14px;color:#5a5147;margin:0 0 20px;line-height:1.6">Um amigo de <strong>${indicador?.nome || 'um motorista'}</strong> manifestou interesse no teu cupão.</p>

      <table style="width:100%;border-collapse:collapse;margin:20px 0;font-size:14px">
        <tr><td style="padding:10px 0;color:#a89c87;font-family:'Courier New',monospace;font-size:11px;letter-spacing:.5px;text-transform:uppercase;border-bottom:1px solid #e8e2d8;width:35%">Nome</td><td style="padding:10px 0;color:#0a0905;border-bottom:1px solid #e8e2d8"><strong>${lead.indicado_nome || '—'}</strong></td></tr>
        <tr><td style="padding:10px 0;color:#a89c87;font-family:'Courier New',monospace;font-size:11px;letter-spacing:.5px;text-transform:uppercase;border-bottom:1px solid #e8e2d8">Telefone</td><td style="padding:10px 0;color:#0a0905;border-bottom:1px solid #e8e2d8"><a href="tel:${lead.indicado_telefone || ''}" style="color:#c8922a;text-decoration:none;font-weight:600">${lead.indicado_telefone || '—'}</a></td></tr>
        ${lead.indicado_email ? `<tr><td style="padding:10px 0;color:#a89c87;font-family:'Courier New',monospace;font-size:11px;letter-spacing:.5px;text-transform:uppercase;border-bottom:1px solid #e8e2d8">Email</td><td style="padding:10px 0;color:#0a0905;border-bottom:1px solid #e8e2d8"><a href="mailto:${lead.indicado_email}" style="color:#c8922a;text-decoration:none">${lead.indicado_email}</a></td></tr>` : ''}
        ${lead.indicado_notas ? `<tr><td style="padding:10px 0;color:#a89c87;font-family:'Courier New',monospace;font-size:11px;letter-spacing:.5px;text-transform:uppercase;border-bottom:1px solid #e8e2d8;vertical-align:top">Mensagem</td><td style="padding:10px 0;color:#0a0905;border-bottom:1px solid #e8e2d8;font-style:italic">"${lead.indicado_notas}"</td></tr>` : ''}
        <tr><td style="padding:10px 0;color:#a89c87;font-family:'Courier New',monospace;font-size:11px;letter-spacing:.5px;text-transform:uppercase">Indicado por</td><td style="padding:10px 0;color:#0a0905">${indicador?.nome || '—'}${indicador?.email ? ' · '+indicador.email : ''}</td></tr>
      </table>

      <div style="background:#fefcf8;border:1px solid #e8d5a8;border-radius:8px;padding:18px;margin:20px 0">
        <div style="font-family:'Courier New',monospace;font-size:10px;color:#a89c87;letter-spacing:1px;text-transform:uppercase;margin-bottom:8px">Cupão</div>
        <div style="font-size:15px;color:#0a0905;font-weight:600">${cupao.titulo} · <span style="color:#c8922a">${valor}</span></div>
        <div style="font-family:'Courier New',monospace;font-size:11px;color:#a89c87;margin-top:4px">${cupao.codigo}</div>
      </div>

      <p style="font-size:13px;color:#5a5147;margin:24px 0 8px;line-height:1.6"><strong>O que fazer agora:</strong></p>
      <ol style="font-size:13px;color:#5a5147;line-height:1.8;padding-left:20px;margin:0">
        <li>Contacta o lead em até 24h (telefone preferencialmente)</li>
        <li>Quando converter (compra/contrato fechado), entra no admin → Cupões → Indicações → ✓ <strong>Converter</strong></li>
        <li>O motorista que indicou ganha automaticamente os créditos configurados no cupão</li>
      </ol>

      <div style="text-align:center;margin:30px 0 0"><a href="${adminUrl}" style="display:inline-block;padding:13px 28px;background:#0a0905;color:#c8922a;text-decoration:none;border-radius:6px;font-family:'Courier New',monospace;font-size:11px;letter-spacing:1.5px;text-transform:uppercase;font-weight:600">→ Abrir admin FleetPay</a></div>
    </div>
    <div style="padding:14px 28px;background:#f0ebe0;color:#a89c87;text-align:center;font-family:'Courier New',monospace;font-size:9px;letter-spacing:1px">FLEETPAY · NOTIFICAÇÃO AUTOMÁTICA · NÃO RESPONDAS A ESTE EMAIL</div>
  </div>
</body>
</html>`;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { indicacao_id, oferta_url, admin_url } = await req.json();
    if (!indicacao_id) {
      return new Response(JSON.stringify({ error: 'indicacao_id em falta' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    // Fetch tudo o que precisamos
    const { data: ind, error: errInd } = await supabase
      .from('cupoes_indicacoes')
      .select('*, cupoes(*, empresas(nome, email, telefone, nipc)), motoristas:indicador_motorista_id(nome, email)')
      .eq('id', indicacao_id)
      .single();

    if (errInd || !ind) {
      return new Response(JSON.stringify({ error: 'Indicação não encontrada', detail: errInd?.message }), {
        status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Idempotência básica: se já enviou, não re-enviar
    if (ind.email_enviado_em) {
      return new Response(JSON.stringify({ ok: true, skipped: 'already_sent', sent_at: ind.email_enviado_em }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const cupao = ind.cupoes;
    const empresa = cupao?.empresas;
    const indicador = ind.motoristas;

    const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
    if (!RESEND_API_KEY) {
      return new Response(JSON.stringify({ error: 'RESEND_API_KEY não configurada' }), {
        status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    const FROM = Deno.env.get('RESEND_FROM') || 'FleetPay <onboarding@resend.dev>';

    const ofertaUrl = oferta_url || 'https://fleetpay.pt/oferta.html?t=' + ind.token;
    const adminUrl = admin_url || 'https://fleetpay.pt/admin.html';

    const sends: any[] = [];

    // Email 1: Lead
    if (ind.indicado_email) {
      sends.push({
        target: 'lead',
        promise: fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${RESEND_API_KEY}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            from: FROM,
            to: ind.indicado_email,
            subject: `${cupao.titulo} — partilhado por ${indicador?.nome?.split(' ')[0] || 'um amigo'}`,
            html: emailLead({ lead: ind, cupao, empresa, indicador, ofertaUrl }),
          }),
        }),
      });
    }

    // Email 2: Operador
    if (empresa?.email) {
      sends.push({
        target: 'operador',
        promise: fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${RESEND_API_KEY}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            from: FROM,
            to: empresa.email,
            subject: `🎯 Lead novo: ${ind.indicado_nome || 'Sem nome'} interessado em ${cupao.titulo}`,
            html: emailOperador({ lead: ind, cupao, empresa, indicador, adminUrl }),
          }),
        }),
      });
    }

    if (!sends.length) {
      return new Response(JSON.stringify({ ok: true, skipped: 'no_recipients' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const results = await Promise.allSettled(sends.map(s => s.promise));
    const summary = await Promise.all(results.map(async (r, i) => {
      if (r.status === 'fulfilled') {
        const ok = r.value.ok;
        const body = await r.value.json().catch(() => ({}));
        return { target: sends[i].target, ok, status: r.value.status, body };
      }
      return { target: sends[i].target, ok: false, error: String(r.reason) };
    }));

    // Marca como enviado se pelo menos um teve sucesso
    if (summary.some(s => s.ok)) {
      await supabase.from('cupoes_indicacoes').update({
        email_enviado_em: new Date().toISOString(),
      }).eq('id', indicacao_id);
    }

    return new Response(JSON.stringify({ ok: true, sent: summary }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
