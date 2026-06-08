// FleetPay — Edge Function: definir-password-motorista
// Cria ou actualiza auth.user com password definida pelo operador.
// Garante que o user existe e fica ligado ao motorista.

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
    // 1. Auth: operador/superadmin
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
    const { data: perfilOp } = await supabase
      .from('perfis').select('role, empresa_id').eq('id', user.id).single();
    if (!perfilOp || !['operador', 'superadmin', 'admin'].includes(perfilOp.role)) {
      return new Response(JSON.stringify({ error: 'Sem permissão' }), {
        status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // 2. Input
    const body = await req.json();
    const motoristaId = (body.motorista_id || '').trim();
    const password = (body.password || '').trim();
    if (!motoristaId || !password || password.length < 6) {
      return new Response(JSON.stringify({ error: 'motorista_id e password (>=6 chars) obrigatórios' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // 3. Busca motorista (e verifica empresa)
    const { data: mot, error: motErr } = await supabase
      .from('motoristas')
      .select('id, email, nome, empresa_id, perfil_id')
      .eq('id', motoristaId)
      .maybeSingle();
    if (motErr || !mot) {
      return new Response(JSON.stringify({ error: 'Motorista não encontrado' }), {
        status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    if (!mot.email) {
      return new Response(JSON.stringify({ error: 'Motorista sem email' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Superadmin pode qualquer empresa; operador só a sua
    if (perfilOp.role !== 'superadmin' && mot.empresa_id !== perfilOp.empresa_id) {
      return new Response(JSON.stringify({ error: 'Motorista de outra empresa' }), {
        status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const email = mot.email.toLowerCase().trim();
    let authUserId = mot.perfil_id;

    // 4. Procura auth user por email
    if (!authUserId) {
      const { data: users } = await supabase.auth.admin.listUsers();
      const found = users?.users.find(u => u.email?.toLowerCase() === email);
      if (found) authUserId = found.id;
    }

    // 5. Cria ou actualiza
    if (authUserId) {
      // Actualiza password do user existente
      const { error: updErr } = await supabase.auth.admin.updateUserById(authUserId, {
        password,
        email_confirm: true,
      });
      if (updErr) {
        return new Response(JSON.stringify({ error: 'Erro a actualizar password: ' + updErr.message }), {
          status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
    } else {
      // Cria user novo com password
      const { data: created, error: createErr } = await supabase.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { nome: mot.nome, role: 'motorista', empresa_id: mot.empresa_id },
      });
      if (createErr || !created.user) {
        return new Response(JSON.stringify({ error: 'Erro a criar conta: ' + (createErr?.message || 'desconhecido') }), {
          status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
      authUserId = created.user.id;
    }

    // 6. Upsert perfil + liga motorista
    await supabase.from('perfis').upsert({
      id: authUserId,
      email,
      role: 'motorista',
      empresa_id: mot.empresa_id,
      nome: mot.nome,
    }, { onConflict: 'id' });

    await supabase.from('motoristas').update({ perfil_id: authUserId }).eq('id', motoristaId);

    return new Response(JSON.stringify({
      ok: true,
      auth_user_id: authUserId,
      email,
      message: 'Password definida. O motorista pode entrar com este email e password.',
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    console.error('[definir-password-motorista]', e);
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
