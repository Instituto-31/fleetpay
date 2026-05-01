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
// 6 paletas estéticas, cada uma com 2 modos (dark/light) = 12 visuais totais.
// O ID do tema (paleta) e o modo (dark/light) são guardados separadamente.
// Body classes: 'theme-{id}-{modo}' (ex: 'theme-sage-dark', 'theme-default-light')
// Acesso a temas pro controlado via canUse() — plano da empresa em window.fleetpayPlano.
const themes = {
  list: [
    { id: 'default',  label: 'Black & Gold',       icon: '🟡', vibe: 'Premium · ouro sobre carvão',  tier: 'free' },
    { id: 'sage',     label: 'Sage Instituto 31',  icon: '🌿', vibe: 'Calmo · sage Instituto 31',     tier: 'free' },
    { id: 'minimal',  label: 'Modern Minimal',     icon: '🔷', vibe: 'Limpo · índigo Linear',         tier: 'free' },
    { id: 'tech',     label: 'Tech Pro',           icon: '💼', vibe: 'Fintech · ciano Wise',          tier: 'pro'  },
    { id: 'forest',   label: 'Forest Premium',     icon: '🌲', vibe: 'Audi · champanhe sobre verde',  tier: 'pro'  },
    { id: 'warm',     label: 'Warm Mediterranean', icon: '🍅', vibe: 'Acolhedor · terracota',         tier: 'pro'  }
  ],
  // === Estado ===
  currentTheme() { return localStorage.getItem('fleetpay-theme-id') || 'default'; },
  currentMode()  { return localStorage.getItem('fleetpay-theme-mode') || 'dark'; },
  // Compat com versão antiga (mapeia IDs antigos → novos)
  _migrate() {
    // Migração one-time do esquema antigo para o novo
    const legacy = localStorage.getItem('fleetpay-theme');
    if (legacy && !localStorage.getItem('fleetpay-theme-id')) {
      const map = {
        'default':  ['default','dark'],
        'sage':     ['sage','light'],
        'light':    ['minimal','light'],
        'tech-pro': ['tech','dark'],
        'forest':   ['forest','dark'],
        'warm':     ['warm','light']
      };
      const [id, mode] = map[legacy] || ['default','dark'];
      localStorage.setItem('fleetpay-theme-id', id);
      localStorage.setItem('fleetpay-theme-mode', mode);
      localStorage.removeItem('fleetpay-theme');
    }
  },
  current() { return this.currentTheme(); },  // alias para compat
  canUse(id, plano) {
    const t = this.list.find(x => x.id === id);
    if (!t) return false;
    if (t.tier === 'free') return true;
    const p = plano || window.fleetpayPlano || 'free';
    return p === 'pro' || p === 'enterprise';
  },
  // === Aplicar tema + modo ===
  apply(themeId, mode) {
    if (typeof themeId === 'undefined') themeId = this.currentTheme();
    if (typeof mode === 'undefined')    mode    = this.currentMode();
    if (!this.canUse(themeId)) themeId = 'default';
    if (mode !== 'dark' && mode !== 'light') mode = 'dark';

    // Remove todas as combinações possíveis (incluindo classes legacy)
    const todasClasses = [];
    this.list.forEach(t => {
      todasClasses.push(`theme-${t.id}-dark`, `theme-${t.id}-light`);
    });
    todasClasses.push('light','theme-mode-dark','theme-mode-light',
      'theme-sage','theme-light','theme-tech-pro','theme-forest','theme-warm'); // legacy classes
    document.body.classList.remove(...todasClasses);

    // Adiciona as novas
    document.body.classList.add(`theme-${themeId}-${mode}`);
    document.body.classList.add(`theme-mode-${mode}`);

    // Mapping para classes legacy (reaproveita CSS atual para o modo padrão de cada tema)
    const legacyMap = {
      'default-light': null,         // novo, sem mapping
      'default-dark':  null,         // default sem classe (CSS root)
      'sage-light':    'theme-sage',
      'sage-dark':     null,         // novo
      'minimal-light': 'light',      // Modern Minimal claro = body.light antigo
      'minimal-dark':  null,         // novo
      'tech-dark':     'theme-tech-pro',
      'tech-light':    null,         // novo
      'forest-dark':   'theme-forest',
      'forest-light':  null,         // novo
      'warm-light':    'theme-warm',
      'warm-dark':     null          // novo
    };
    const legacy = legacyMap[`${themeId}-${mode}`];
    if (legacy) document.body.classList.add(legacy);
    if (mode === 'light') document.body.classList.add('light'); // compat global com CSS antigo

    localStorage.setItem('fleetpay-theme-id', themeId);
    localStorage.setItem('fleetpay-theme-mode', mode);

    // Ícone do botão mostra o OPOSTO ao atual (clica para mudar)
    const btn = document.getElementById('theme-btn');
    if (btn) btn.textContent = mode === 'dark' ? '☀️' : '🌙';

    document.dispatchEvent(new CustomEvent('fleetpay:theme', { detail: { themeId, mode } }));
  },
  // Apenas troca a paleta, mantém o modo
  setTheme(themeId) {
    this.apply(themeId, this.currentMode());
  },
  // Apenas troca o modo, mantém a paleta
  setMode(mode) {
    this.apply(this.currentTheme(), mode);
  },
  // Toggle do modo (chamado pelo botão 🌙 do header)
  toggleMode() {
    this.setMode(this.currentMode() === 'dark' ? 'light' : 'dark');
  },
  // Compat: cycle() agora alterna o modo (mantém o tema)
  cycle() { this.toggleMode(); return this.currentMode(); },
  init() {
    this._migrate();
    const apply = () => this.apply(this.currentTheme(), this.currentMode());
    if (document.body) apply();
    else document.addEventListener('DOMContentLoaded', apply);
  }
};
themes.init();
// Compat: HTMLs antigos chamam toggleTheme() — mapear para toggleMode()
function toggleTheme() { themes.toggleMode(); }

console.log('✅ FleetPay v2.0 — Supabase + temas inicializados');

// ── Service Worker registration (PWA) ──
// Registo: detecta nova versão e mostra toast para o user actualizar
if ('serviceWorker' in navigator && location.protocol !== 'file:') {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').then((reg) => {
      console.log('[PWA] Service Worker registado');

      // Detectar nova versão disponível
      reg.addEventListener('updatefound', () => {
        const newWorker = reg.installing;
        if (!newWorker) return;
        newWorker.addEventListener('statechange', () => {
          if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
            // Há nova versão pronta para activar
            mostrarToastNovaVersao(newWorker);
          }
        });
      });
    }).catch((err) => console.warn('[PWA] SW registration failed:', err));

    // Quando SW activa (após user aceitar), recarregar página
    let refreshing = false;
    navigator.serviceWorker.addEventListener('controllerchange', () => {
      if (refreshing) return;
      refreshing = true;
      window.location.reload();
    });
  });

  function mostrarToastNovaVersao(newWorker) {
    // Não mostra se já existe
    if (document.getElementById('pwa-update-toast')) return;
    const toast = document.createElement('div');
    toast.id = 'pwa-update-toast';
    toast.style.cssText = 'position:fixed;bottom:20px;left:50%;transform:translateX(-50%);background:#c8922a;color:#000;padding:14px 20px;border-radius:8px;font-family:-apple-system,BlinkMacSystemFont,sans-serif;font-size:13px;font-weight:500;z-index:9999;display:flex;gap:14px;align-items:center;box-shadow:0 6px 20px rgba(0,0,0,0.4);max-width:90%;animation:slideUp .3s ease-out';
    toast.innerHTML = `
      <span>✨ Nova versão disponível</span>
      <button id="pwa-update-btn" style="background:#000;color:#c8922a;border:none;padding:7px 14px;border-radius:5px;font-weight:700;cursor:pointer;font-size:12px;letter-spacing:.5px;text-transform:uppercase">Actualizar</button>
      <button id="pwa-update-dismiss" style="background:transparent;color:#000;border:none;font-size:18px;cursor:pointer;padding:0 4px">×</button>
      <style>@keyframes slideUp{from{transform:translateX(-50%) translateY(20px);opacity:0}to{transform:translateX(-50%) translateY(0);opacity:1}}</style>
    `;
    document.body.appendChild(toast);
    document.getElementById('pwa-update-btn').onclick = () => {
      newWorker.postMessage('SKIP_WAITING');
      toast.remove();
    };
    document.getElementById('pwa-update-dismiss').onclick = () => toast.remove();
  }
}

// ── Botão "Instalar app" (PWA install prompt) ──
let deferredInstallPrompt = null;
window.addEventListener('beforeinstallprompt', (e) => {
  e.preventDefault();
  deferredInstallPrompt = e;
  const btn = document.getElementById('pwa-install-btn');
  if (btn) btn.style.display = '';
});

// Mostrar botão também em iOS (que não dispara beforeinstallprompt)
// e esconder se já está instalada (display-mode standalone)
document.addEventListener('DOMContentLoaded', () => {
  const isStandalone = window.matchMedia('(display-mode: standalone)').matches
                    || window.navigator.standalone === true;
  if (isStandalone) return; // já instalada, não mostrar botão

  const isMobile = /Android|iPhone|iPad|iPod/i.test(navigator.userAgent);
  if (isMobile) {
    setTimeout(() => {
      const btn = document.getElementById('pwa-install-btn');
      if (btn) btn.style.display = '';
    }, 1500);
  }
});

window.fleetpayInstallApp = async function() {
  if (!deferredInstallPrompt) {
    // iOS / browsers que não suportam beforeinstallprompt
    alert('Para instalar a app FleetPay no telemóvel:\n\n' +
          '📱 iOS (Safari): Carrega em Partilhar (□↑) → "Adicionar ao ecrã principal"\n\n' +
          '📱 Android (Chrome): Menu (⋮) → "Adicionar ao ecrã principal" ou "Instalar app"');
    return;
  }
  deferredInstallPrompt.prompt();
  const { outcome } = await deferredInstallPrompt.userChoice;
  console.log('[PWA] install', outcome);
  deferredInstallPrompt = null;
  const btn = document.getElementById('pwa-install-btn');
  if (btn) btn.style.display = 'none';
};
