// FleetPay — Edge Function: convidar-motorista
// Cria perfil auth + motorista + envia magic link numa só transação.
// O trigger auto_ligar_perfil_motorista trata da ligação.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  );

  try {
    // 1. Auth: operador/superadmin pode convidar
    const authHeader = req.headers.get('authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Sem autorização' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    const token = authHeader.replace('Bearer ', '');
    const { data: { user }, error: errUser } = await supabase.auth.getUser(token);
    if (errUser || !user) {
      return new Response(JSON.stringify({ error: 'Sessão inválida' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    const { data: perfil } = await supabase
      .from('perfis').select('role, empresa_id').eq('id', user.id).single();
    if (!perfil || !['operador', 'superadmin'].includes(perfil.role)) {
      return new Response(JSON.stringify({ error: 'Sem permissão' }), {
        status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // 2. Input
    const body = await req.json();
    const email = (body.email || '').toLowerCase().trim();
    const nome = (body.nome || '').trim();
    const telefone = body.telefone || null;
    const nif = body.nif || null;
    const empresaId = perfil.role === 'superadmin' && body.empresa_id ? body.empresa_id : perfil.empresa_id;

    if (!email || !nome) {
      return new Response(JSON.stringify({ error: 'Email e nome são obrigatórios' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // 3. Cria auth user com magic link (não precisa de password)
    // Usa generateLink para que o operador possa enviar manualmente se preferir
    const { data: linkData, error: linkErr } = await supabase.auth.admin.inviteUserByEmail(email, {
      data: { role: 'motorista', empresa_id: empresaId, nome },
      redirectTo: `${req.headers.get('origin') || 'https://fleetpay.pt'}/motorista.html`,
    });

    let authUserId: string | null = null;
    if (linkErr) {
      // Pode ja existir — tenta apanhar o id existente
      const { data: existing } = await supabase.auth.admin.listUsers();
      const found = existing?.users.find(u => u.email?.toLowerCase() === email);
      if (!found) {
        return new Response(JSON.stringify({ error: 'Não foi possível criar utilizador: ' + linkErr.message }), {
          status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
      authUserId = found.id;
    } else {
      authUserId = linkData.user?.id || null;
    }

    if (!authUserId) {
      return new Response(JSON.stringify({ error: 'Auth user sem id' }), {
        status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // 4. Upsert perfil (se ja existe via signup, actualiza role+empresa)
    const { error: perfilErr } = await supabase
      .from('perfis')
      .upsert({
        id: authUserId,
        email,
        role: 'motorista',
        empresa_id: empresaId,
        nome,
      }, { onConflict: 'id' });
    if (perfilErr) {
      return new Response(JSON.stringify({ error: 'Erro a criar perfil: ' + perfilErr.message }), {
        status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // 5. Cria motorista (se ja existe um com este email na empresa, devolve esse)
    const { data: existingMot } = await supabase
      .from('motoristas')
      .select('id')
      .eq('empresa_id', empresaId)
      .ilike('email', email)
      .maybeSingle();

    let motoristaId = existingMot?.id;
    if (!motoristaId) {
      const { data: newMot, error: motErr } = await supabase
        .from('motoristas')
        .insert({ empresa_id: empresaId, nome, email, telefone, nif, ativo: true })
        .select('id')
        .single();
      if (motErr) {
        return new Response(JSON.stringify({ error: 'Erro a criar motorista: ' + motErr.message }), {
          status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
      motoristaId = newMot.id;
    }

    // 6. O trigger auto_ligar_perfil_motorista trata da ligacao;
    //    mas força-a aqui também para garantir
    await supabase.from('motoristas').update({ perfil_id: authUserId }).eq('id', motoristaId);

    return new Response(JSON.stringify({
      ok: true,
      auth_user_id: authUserId,
      motorista_id: motoristaId,
      email,
      message: linkErr ? 'Já existia, ligado.' : 'Convite enviado por email.',
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    console.error('[convidar-motorista]', e);
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
