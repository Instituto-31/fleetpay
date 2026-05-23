// FleetPay — Edge Function: gerar-pdf-assinado
// Recebe { token, signature_png_base64, signature_mode, user_agent } do motorista
// que está em assinar.html. Gera um PDF profissional a partir do template
// .docx + página de assinatura digital + selo de validação. Faz upload do PDF
// para Storage e marca o contrato como assinado.
//
// Conversor DOCX→PDF: Aspose Cloud REST API (free tier 150 chamadas/mês).
// Bibliotecas Deno: pdf-lib (anexar página assinatura), pizzip + docxtemplater
// (substituir placeholders DOCX preservando formatação).
//
// Setup necessário (uma vez, via Supabase Dashboard → Settings → Edge Functions → Secrets):
//   ASPOSE_CLIENT_ID      = (da conta Aspose Cloud)
//   ASPOSE_CLIENT_SECRET  = (da conta Aspose Cloud)

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { PDFDocument, StandardFonts, rgb } from 'https://esm.sh/pdf-lib@1.17.1';
import PizZip from 'https://esm.sh/pizzip@3.1.6';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

// ─── Aspose Cloud auth ───────────────────────────────────────────────────────
let asposeToken: { value: string; expires: number } | null = null;
async function asposeAccessToken(): Promise<string> {
  if (asposeToken && asposeToken.expires > Date.now() + 60_000) {
    return asposeToken.value;
  }
  const clientId = Deno.env.get('ASPOSE_CLIENT_ID');
  const clientSecret = Deno.env.get('ASPOSE_CLIENT_SECRET');
  if (!clientId || !clientSecret) {
    throw new Error('Aspose credentials missing (set ASPOSE_CLIENT_ID and ASPOSE_CLIENT_SECRET secrets)');
  }
  const res = await fetch('https://api.aspose.cloud/connect/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: clientId,
      client_secret: clientSecret,
    }),
  });
  if (!res.ok) {
    const txt = await res.text();
    throw new Error('Aspose auth failed: ' + res.status + ' ' + txt);
  }
  const j = await res.json();
  asposeToken = {
    value: j.access_token,
    expires: Date.now() + (j.expires_in || 3600) * 1000,
  };
  return asposeToken.value;
}

// ─── Aspose Cloud: convert DOCX (Uint8Array) → PDF (Uint8Array) ─────────────
async function convertDocxToPdf(docxBytes: Uint8Array): Promise<Uint8Array> {
  const token = await asposeAccessToken();
  // Endpoint: POST /words/convert?format=pdf  (body = raw DOCX bytes)
  const res = await fetch('https://api.aspose.cloud/v4.0/words/convert?format=pdf', {
    method: 'PUT',
    headers: {
      Authorization: 'Bearer ' + token,
      'Content-Type': 'application/octet-stream',
    },
    body: docxBytes,
  });
  if (!res.ok) {
    const txt = await res.text();
    throw new Error('Aspose convert failed: ' + res.status + ' ' + txt);
  }
  const buf = await res.arrayBuffer();
  return new Uint8Array(buf);
}

// ─── Substituir placeholders «KEY» no document.xml do DOCX ─────────────────
// Preserva formatação (substituição text-only dentro de <w:t>). Para
// runs partidos, faz uma pré-passagem que junta runs adjacentes do mesmo
// estilo. NÃO usa docxtemplater porque a dependência é pesada e o nosso
// caso é simples (text replace + smart quotes).
function substituirPlaceholdersDocx(
  docxBytes: Uint8Array,
  dados: Record<string, string>,
): Uint8Array {
  const zip = new PizZip(docxBytes);
  const file = zip.file('word/document.xml');
  if (!file) throw new Error('Ficheiro DOCX inválido: sem word/document.xml');
  let xml = file.asText();

  // Passagem 1: substituições directas (runs únicos)
  for (const [key, valRaw] of Object.entries(dados)) {
    const val = String(valRaw ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
    const variants = ['«' + key + '»', '&#xAB;' + key + '&#xBB;', '«' + key + '»'];
    for (const v of variants) {
      xml = xml.split(v).join(val);
    }
  }

  // Passagem 2 (heurística): se ainda houver «KEY» partidos em runs,
  // achatar runs adjacentes e tentar de novo.
  const stillHas = /«[A-Z_]+»/g.test(xml);
  if (stillHas) {
    let achatado = xml.replace(/<\/w:t><\/w:r><w:r[^>]*><w:t[^>]*>/g, '');
    for (const [key, valRaw] of Object.entries(dados)) {
      const val = String(valRaw ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');
      const variants = ['«' + key + '»', '&#xAB;' + key + '&#xBB;', '«' + key + '»'];
      for (const v of variants) {
        achatado = achatado.split(v).join(val);
      }
    }
    if (!/«[A-Z_]+»/g.test(achatado)) xml = achatado;
  }

  zip.file('word/document.xml', xml);
  return zip.generate({ type: 'uint8array', compression: 'DEFLATE' });
}

// ─── Anexar página de assinatura ao PDF gerado ─────────────────────────────
async function anexarPaginaAssinatura(
  pdfBytes: Uint8Array,
  ctx: {
    token: string;
    motoristaNome: string;
    motoristaEmail: string;
    empresaNome: string;
    empresaNipc: string;
    empresaLicenca: string;
    templateNome: string;
    contratoIdCurto: string;
    dataAssStr: string;
    signaturePngBytes: Uint8Array;
    signatureMode: string;
    plataforma: string;
  },
): Promise<Uint8Array> {
  const pdfDoc = await PDFDocument.load(pdfBytes);
  const page = pdfDoc.addPage([595.28, 841.89]); // A4 portrait
  const { width, height } = page.getSize();

  const fontReg = await pdfDoc.embedFont(StandardFonts.Helvetica);
  const fontBold = await pdfDoc.embedFont(StandardFonts.HelveticaBold);
  const fontItalic = await pdfDoc.embedFont(StandardFonts.HelveticaOblique);

  const colInk = rgb(0.1, 0.1, 0.1);
  const colSub = rgb(0.4, 0.4, 0.4);
  const colGold = rgb(0.78, 0.57, 0.16);

  let y = height - 60;

  // Linha dourada superior
  page.drawRectangle({ x: 40, y: y + 18, width: width - 80, height: 2, color: colGold });

  // Título
  page.drawText('ASSINATURA DIGITAL', {
    x: 40, y, size: 18, font: fontBold, color: colInk,
  });
  y -= 28;
  page.drawText('Contrato #' + ctx.contratoIdCurto + ' · ' + ctx.templateNome, {
    x: 40, y, size: 10, font: fontReg, color: colSub,
  });
  y -= 50;

  // ─── Bloco motorista (esquerda) ──────────────────────────────────────
  const colW = (width - 100) / 2;
  const xLeft = 40;
  const xRight = 40 + colW + 20;

  page.drawText('O(A) MOTORISTA', {
    x: xLeft, y, size: 9, font: fontBold, color: colSub,
  });

  // Inserir imagem da assinatura
  const sigImg = await pdfDoc.embedPng(ctx.signaturePngBytes);
  const sigMaxW = Math.min(colW - 20, 260);
  const sigMaxH = 90;
  const sigDims = sigImg.scale(1);
  const scale = Math.min(sigMaxW / sigDims.width, sigMaxH / sigDims.height);
  const sigW = sigDims.width * scale;
  const sigH = sigDims.height * scale;
  page.drawImage(sigImg, {
    x: xLeft, y: y - 100, width: sigW, height: sigH,
  });

  // Linha + nome
  page.drawLine({
    start: { x: xLeft, y: y - 110 }, end: { x: xLeft + colW - 20, y: y - 110 },
    thickness: 0.8, color: colInk,
  });
  page.drawText(ctx.motoristaNome, {
    x: xLeft, y: y - 124, size: 11, font: fontBold, color: colInk,
  });
  page.drawText('Assinado em ' + ctx.dataAssStr, {
    x: xLeft, y: y - 138, size: 8, font: fontReg, color: colSub,
  });
  if (ctx.motoristaEmail) {
    page.drawText(ctx.motoristaEmail, {
      x: xLeft, y: y - 150, size: 8, font: fontReg, color: colSub,
    });
  }

  // ─── Bloco operador (direita) ────────────────────────────────────────
  page.drawText('PELO OPERADOR', {
    x: xRight, y, size: 9, font: fontBold, color: colSub,
  });
  page.drawLine({
    start: { x: xRight, y: y - 110 }, end: { x: xRight + colW - 20, y: y - 110 },
    thickness: 0.8, color: colInk,
  });
  page.drawText(ctx.empresaNome, {
    x: xRight, y: y - 124, size: 11, font: fontBold, color: colInk,
  });
  page.drawText('NIPC ' + ctx.empresaNipc + (ctx.empresaLicenca ? ' · Licença TVDE ' + ctx.empresaLicenca : ''), {
    x: xRight, y: y - 138, size: 8, font: fontReg, color: colSub,
  });

  // ─── Selo de validação digital (rodapé) ──────────────────────────────
  y = 180;
  page.drawRectangle({ x: 40, y: y - 130, width: width - 80, height: 140, color: rgb(0.98, 0.97, 0.94) });
  page.drawRectangle({ x: 40, y: y - 130, width: 3, height: 140, color: colGold });

  page.drawText('🔒 SELO DE VALIDAÇÃO DIGITAL', {
    x: 56, y: y - 16, size: 10, font: fontBold, color: colInk,
  });

  const seloLines = [
    ['Token único:', ctx.token],
    ['Data/hora:', ctx.dataAssStr],
    ['Método:', ctx.signatureMode === 'desenhar' ? 'Assinatura desenhada (canvas)' : ctx.signatureMode === 'escrever' ? 'Assinatura em fonte cursiva' : 'Imagem carregada'],
    ['Plataforma:', 'FleetPay · ' + ctx.plataforma],
  ];
  let yLine = y - 36;
  for (const [k, v] of seloLines) {
    page.drawText(k, { x: 56, y: yLine, size: 9, font: fontBold, color: colInk });
    page.drawText(v, { x: 140, y: yLine, size: 9, font: fontReg, color: colInk });
    yLine -= 16;
  }
  page.drawText('Esta assinatura é juridicamente vinculativa nos termos do Decreto-Lei 12/2021', {
    x: 56, y: yLine - 6, size: 8, font: fontItalic, color: colSub,
  });
  page.drawText('e do Regulamento (UE) 910/2014 (eIDAS).', {
    x: 56, y: yLine - 18, size: 8, font: fontItalic, color: colSub,
  });

  return pdfDoc.save();
}

// ─── Main handler ────────────────────────────────────────────────────────────
serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  // Service role para ter acesso a Storage e BD (independente da sessão do motorista)
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  try {
    const body = await req.json();
    const token = String(body.token || '').trim();
    const signaturePngB64 = String(body.signature_png || '').trim();
    const signatureMode = String(body.signature_mode || 'desenhar').trim();
    const userAgent = String(body.user_agent || req.headers.get('user-agent') || '').slice(0, 500);
    const plataforma = String(body.plataforma || 'fleetpay.pt').trim();

    if (!token) return json({ error: 'token em falta' }, 400);
    if (!signaturePngB64.startsWith('data:image/')) {
      return json({ error: 'signature_png inválido (esperado data:image/...)' }, 400);
    }

    // 1. Buscar contrato pelo token
    const { data: contrato, error: errC } = await supabase
      .from('contratos_assinados')
      .select('*, motoristas(nome, email), empresas(nome, nipc, morada, codigo_postal, licenca_tvde, telefone, email, logo_path)')
      .eq('link_token', token)
      .single();
    if (errC || !contrato) return json({ error: 'Contrato não encontrado' }, 404);
    if (contrato.estado === 'assinado') {
      return json({ error: 'Já assinado anteriormente', ficheiro_path: contrato.ficheiro_path }, 409);
    }
    if (!contrato.template_id) return json({ error: 'Contrato sem template_id' }, 400);

    // 2. Buscar template do Storage
    const { data: tpl, error: errT } = await supabase
      .from('contratos_templates')
      .select('ficheiro_path')
      .eq('id', contrato.template_id)
      .single();
    if (errT || !tpl?.ficheiro_path) return json({ error: 'Template não encontrado' }, 404);

    const { data: tplFile, error: errDl } = await supabase.storage
      .from('contratos-templates')
      .download(tpl.ficheiro_path);
    if (errDl || !tplFile) return json({ error: 'Download do template falhou: ' + (errDl?.message || '') }, 500);
    const tplBytes = new Uint8Array(await tplFile.arrayBuffer());

    // 3. Substituir placeholders
    const dados = contrato.dados_substituidos || {};
    const docxBytes = substituirPlaceholdersDocx(tplBytes, dados);

    // 4. Converter DOCX → PDF via Aspose
    const pdfBytes = await convertDocxToPdf(docxBytes);

    // 5. Anexar página de assinatura digital
    const sigPngBytes = Uint8Array.from(
      atob(signaturePngB64.replace(/^data:image\/\w+;base64,/, '')),
      (c) => c.charCodeAt(0),
    );
    const dataAss = new Date();
    const dataAssStr = dataAss.toLocaleString('pt-PT');
    const finalPdf = await anexarPaginaAssinatura(pdfBytes, {
      token,
      motoristaNome: contrato.motoristas?.nome || '—',
      motoristaEmail: contrato.motoristas?.email || '',
      empresaNome: contrato.empresas?.nome || '',
      empresaNipc: contrato.empresas?.nipc || '—',
      empresaLicenca: contrato.empresas?.licenca_tvde || '',
      templateNome: contrato.template_nome || '',
      contratoIdCurto: String(contrato.id).substring(0, 8).toUpperCase(),
      dataAssStr,
      signaturePngBytes: sigPngBytes,
      signatureMode,
      plataforma,
    });

    // 6. Upload PDF para Storage
    const path = `${contrato.empresa_id}/${contrato.id}.pdf`;
    const { error: errUp } = await supabase.storage
      .from('contratos-assinados')
      .upload(path, finalPdf, {
        contentType: 'application/pdf',
        upsert: true,
      });
    if (errUp) return json({ error: 'Upload do PDF falhou: ' + errUp.message }, 500);

    // 7. Update DB
    const { error: errUpd } = await supabase
      .from('contratos_assinados')
      .update({
        estado: 'assinado',
        assinado_em: dataAss.toISOString(),
        ficheiro_path: path,
        assinatura_png: signaturePngB64,
        user_agent_assinatura: userAgent,
      })
      .eq('id', contrato.id);
    if (errUpd) return json({ error: 'Update DB falhou: ' + errUpd.message }, 500);

    return json({
      ok: true,
      ficheiro_path: path,
      tamanho_pdf: finalPdf.byteLength,
    });
  } catch (e) {
    console.error('gerar-pdf-assinado error:', e);
    return json({ error: (e as Error).message || 'Erro inesperado' }, 500);
  }
});
