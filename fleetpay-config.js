// fleetpay-config.js
// Configuração central do Supabase para o FleetPay
// Inclui este ficheiro em todas as páginas HTML

const FLEETPAY_CONFIG = {
  supabase: {
    url: 'https://udqddasbfqbeeaxtnsoj.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVkcWRkYXNiZnFiZWVheHRuc29qIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcwMzQ1NzAsImV4cCI6MjA5MjYxMDU3MH0.bFr5wrwwJOyNLI8-3NyGZ18SxcnDHgmJ01z8TXU4yhQ'
  },
  app: {
    nome: 'FleetPay',
    versao: '2.0.0',
    empresa_demo_id: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
  }
};

// Inicializar cliente Supabase
const { createClient } = supabase;
const db = createClient(FLEETPAY_CONFIG.supabase.url, FLEETPAY_CONFIG.supabase.anonKey);

// Auth helpers
const auth = {
  // Login com email + password
  async login(email, password) {
    const { data, error } = await db.auth.signInWithPassword({ email, password });
    if (error) throw error;
    return data;
  },

  // Login com magic link (para motoristas)
  async loginMagicLink(email) {
    const redirectTo = new URL('motorista.html', window.location.href).href;
    const { error } = await db.auth.signInWithOtp({ email, options: { emailRedirectTo: redirectTo } });
    if (error) throw error;
  },

  // Logout
  async logout() {
    await db.auth.signOut();
    window.location.href = '/login.html';
  },

  // Obter user atual
  async getUser() {
    const { data: { user } } = await db.auth.getUser();
    return user;
  },

  // Obter perfil + role
  async getPerfil() {
    const user = await this.getUser();
    if (!user) return null;
    const { data } = await db.from('perfis').select('*, empresas(*)').eq('id', user.id).single();
    return data;
  },

  // Redirecionar por role
  async redirectByRole() {
    const perfil = await this.getPerfil();
    if (!perfil) { window.location.href = '/login.html'; return; }
    if (perfil.role === 'superadmin') window.location.href = '/superadmin.html';
    else if (perfil.role === 'operador') window.location.href = '/admin.html';
    else window.location.href = '/motorista.html';
  }
};

// Database helpers
const fleetDB = {
  // ── MOTORISTAS ──
  async getMotoristas(empresa_id) {
    const { data, error } = await db.from('motoristas').select('*').eq('empresa_id', empresa_id).eq('ativo', true).order('nome');
    if (error) throw error;
    return data;
  },

  async saveMotorista(motorista) {
    if (motorista.id) {
      const { data, error } = await db.from('motoristas').update(motorista).eq('id', motorista.id).select().single();
      if (error) throw error;
      return data;
    } else {
      const { data, error } = await db.from('motoristas').insert(motorista).select().single();
      if (error) throw error;
      return data;
    }
  },

  // ── VEÍCULOS ──
  async getVeiculos(empresa_id) {
    const { data, error } = await db.from('veiculos').select('*, motoristas(nome)').eq('empresa_id', empresa_id).order('matricula');
    if (error) throw error;
    return data;
  },

  // ── PAGAMENTOS ──
  async getPagamentos(empresa_id, semana_inicio) {
    let query = db.from('pagamentos').select('*, motoristas(nome, email, whatsapp, iban)').eq('empresa_id', empresa_id);
    if (semana_inicio) query = query.eq('semana_inicio', semana_inicio);
    const { data, error } = await query.order('criado_em', { ascending: false });
    if (error) throw error;
    return data;
  },

  async savePagamento(pagamento) {
    if (pagamento.id) {
      const { data, error } = await db.from('pagamentos').update(pagamento).eq('id', pagamento.id).select().single();
      if (error) throw error;
      return data;
    } else {
      const { data, error } = await db.from('pagamentos').insert(pagamento).select().single();
      if (error) throw error;
      return data;
    }
  },

  async marcarPago(pagamento_id, referencia) {
    const { data, error } = await db.from('pagamentos').update({
      estado: 'pago',
      data_pagamento: new Date().toISOString(),
      referencia_transferencia: referencia
    }).eq('id', pagamento_id).select().single();
    if (error) throw error;
    return data;
  },

  // ── PRIO ──
  async getPrio(empresa_id, semana_inicio) {
    let query = db.from('prio_carregamentos').select('*').eq('empresa_id', empresa_id);
    if (semana_inicio) query = query.eq('semana_inicio', semana_inicio);
    const { data, error } = await query.order('data');
    if (error) throw error;
    return data;
  },

  async savePrioLote(carregamentos) {
    const { data, error } = await db.from('prio_carregamentos').insert(carregamentos).select();
    if (error) throw error;
    return data;
  },

  // ── VIA VERDE ──
  async getViaVerde(empresa_id, semana_inicio) {
    let query = db.from('viaverde_portagens').select('*').eq('empresa_id', empresa_id);
    if (semana_inicio) query = query.eq('semana_inicio', semana_inicio);
    const { data, error } = await query.order('data');
    if (error) throw error;
    return data;
  },

  async saveViaVerdeLote(portagens) {
    const { data, error } = await db.from('viaverde_portagens').insert(portagens).select();
    if (error) throw error;
    return data;
  },

  // ── MOTORISTA: ver próprios dados ──
  async getMeusPagamentos() {
    const { data, error } = await db.from('pagamentos')
      .select('*, veiculos(matricula, marca, modelo)')
      .eq('motorista_id', await db.rpc('get_motorista_id'))
      .order('semana_inicio', { ascending: false });
    if (error) throw error;
    return data;
  },

  // ── ALERTAS (documentos a expirar) ──
  async getAlertas(empresa_id) {
    const hoje = new Date();
    const em30dias = new Date(hoje.getTime() + 30 * 24 * 60 * 60 * 1000).toISOString().split('T')[0];
    
    const { data: motoristas } = await db.from('motoristas').select('nome, licenca_tvde_validade, carta_conducao_validade, cartao_cidadao_validade, registo_criminal_validade').eq('empresa_id', empresa_id).eq('ativo', true);
    
    const { data: veiculos } = await db.from('veiculos').select('matricula, seguro_validade, inspecao_validade, extintor_validade').eq('empresa_id', empresa_id).neq('estado', 'inativo');

    const alertas = [];
    const hoje_str = hoje.toISOString().split('T')[0];

    motoristas?.forEach(m => {
      [['Licença TVDE', m.licenca_tvde_validade], ['Carta Condução', m.carta_conducao_validade], ['Cartão Cidadão', m.cartao_cidadao_validade], ['Registo Criminal', m.registo_criminal_validade]].forEach(([tipo, val]) => {
        if (val && val <= em30dias) alertas.push({ tipo, nome: m.nome, validade: val, expirado: val < hoje_str });
      });
    });

    veiculos?.forEach(v => {
      [['Seguro', v.seguro_validade], ['Inspeção', v.inspecao_validade], ['Extintor', v.extintor_validade]].forEach(([tipo, val]) => {
        if (val && val <= em30dias) alertas.push({ tipo, nome: v.matricula, validade: val, expirado: val < hoje_str });
      });
    });

    return alertas.sort((a, b) => a.validade > b.validade ? 1 : -1);
  }
};

// Utilitários
const utils = {
  formatEur: (v) => new Intl.NumberFormat('pt-PT', { style: 'currency', currency: 'EUR' }).format(v || 0),
  formatData: (d) => d ? new Date(d).toLocaleDateString('pt-PT') : '—',
  semanaLabel: (inicio, fim) => `${utils.formatData(inicio)} – ${utils.formatData(fim)}`,
  toast: (msg, tipo = 'success') => {
    const t = document.createElement('div');
    t.className = `toast toast-${tipo}`;
    t.textContent = msg;
    document.body.appendChild(t);
    setTimeout(() => t.remove(), 3500);
  }
};

// ── TEMAS ──
// 6 paletas com tier (free/pro). Aplicado via classe no body. Persistência em localStorage.
// O acesso a temas pro é controlado via canUse() — o plano da empresa vem de window.fleetpayPlano.
const themes = {
  list: [
    { id: 'default',  label: 'Black & Gold',       icon: '🌙', vibe: 'Premium escuro · atual',     tier: 'free' },
    { id: 'sage',     label: 'Sage Instituto 31',  icon: '🌿', vibe: 'Calmo claro · brand I31',    tier: 'free' },
    { id: 'light',    label: 'Modern Minimal',     icon: '☀️', vibe: 'Limpo moderno · Linear',     tier: 'free' },
    { id: 'tech-pro', label: 'Tech Pro',           icon: '💼', vibe: 'Fintech azul · Wise/Revolut', tier: 'pro'  },
    { id: 'forest',   label: 'Forest Premium',     icon: '🌲', vibe: 'Verde + champanhe · Audi',   tier: 'pro'  },
    { id: 'warm',     label: 'Warm Mediterranean', icon: '🍅', vibe: 'Terracota acolhedor',         tier: 'pro'  }
  ],
  current() { return localStorage.getItem('fleetpay-theme') || 'default'; },
  // Verifica se o plano da empresa permite usar este tema
  canUse(id, plano) {
    const t = this.list.find(x => x.id === id);
    if (!t) return false;
    if (t.tier === 'free') return true;
    const p = plano || window.fleetpayPlano || 'free';
    return p === 'pro' || p === 'enterprise';
  },
  // Classificação por luminosidade (para toggle inteligente)
  escuros: ['default','tech-pro','forest'],
  claros: ['sage','light','warm'],
  isDark(id) { return this.escuros.includes(id); },
  apply(id) {
    // Valida tier — se não pode, força default
    if (!this.canUse(id)) id = 'default';
    document.body.classList.remove('theme-sage','theme-light','light','theme-tech-pro','theme-forest','theme-warm');
    if (id === 'sage')          document.body.classList.add('theme-sage');
    else if (id === 'light')    document.body.classList.add('theme-light','light'); // 'light' por compat. com CSS antigo
    else if (id === 'tech-pro') document.body.classList.add('theme-tech-pro');
    else if (id === 'forest')   document.body.classList.add('theme-forest');
    else if (id === 'warm')     document.body.classList.add('theme-warm');
    localStorage.setItem('fleetpay-theme', id);
    // Memorizar último escuro / último claro (para o toggle do header)
    if (this.isDark(id)) localStorage.setItem('fleetpay-last-dark', id);
    else                 localStorage.setItem('fleetpay-last-light', id);
    // Atualizar ícone do botão de tema
    const btn = document.getElementById('theme-btn');
    if (btn) btn.textContent = (this.list.find(t => t.id === id) || this.list[0]).icon;
  },
  cycle() {
    // Toggle inteligente: alterna entre o último tema escuro e o último tema claro
    // que o utilizador escolheu. Se nunca escolheu, fallback default↔sage.
    const cur = this.current();
    let next;
    if (this.isDark(cur)) {
      next = localStorage.getItem('fleetpay-last-light') || 'sage';
    } else {
      next = localStorage.getItem('fleetpay-last-dark') || 'default';
    }
    if (!this.canUse(next)) next = this.isDark(cur) ? 'sage' : 'default';
    this.apply(next);
    return next;
  },
  init() {
    if (document.body) this.apply(this.current());
    else document.addEventListener('DOMContentLoaded', () => this.apply(this.current()));
  }
};
themes.init();
// Compat: HTMLs antigos chamam toggleTheme() — mapear para cycle()
function toggleTheme() { themes.cycle(); }

console.log('✅ FleetPay v2.0 — Supabase + temas inicializados');
