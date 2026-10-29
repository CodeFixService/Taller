/* BiciTaller · núcleo compartido: conexión, sesión, campanita en vivo, push,
   imágenes, fechas y utilidades. */
(function (global) {
  'use strict';
  const cfg = global.BT_CONFIG;
  const sb = global.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
    auth: { persistSession: true, autoRefreshToken: true, storageKey: 'bt-auth', detectSessionInUrl: true }
  });
  const ROOT = (() => {
    const s = document.querySelector('script[src*="shared/app.js"]');
    return s ? s.src.replace(/shared\/app\.js.*$/, '') : location.origin + '/';
  })();

  /* ---------- Utilidades ---------- */
  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const plata = (n) => '$' + Math.round(Number(n) || 0).toLocaleString('es-CL');
  const numero = (v) => { const n = Number(String(v == null ? '' : v).replace(/[^\d-]/g, '')); return isFinite(n) ? n : 0; };
  const iso = (d) => d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
  const fechaDe = (s) => { const [y, m, d] = String(s).slice(0, 10).split('-').map(Number); return new Date(y, m - 1, d); };
  const sumarDias = (s, n) => { const d = fechaDe(s); d.setDate(d.getDate() + n); return iso(d); };
  const hoy = () => iso(new Date());
  const fCorta = (s) => s ? fechaDe(s).toLocaleDateString('es-CL', { weekday: 'short', day: 'numeric', month: 'short' }) : '';
  const fLarga = (s) => s ? fechaDe(s).toLocaleDateString('es-CL', { weekday: 'long', day: 'numeric', month: 'long' }) : '';
  const fHora = (t) => t ? new Date(t).toLocaleString('es-CL', { dateStyle: 'medium', timeStyle: 'short' }) : '';
  const hace = (t) => {
    if (!t) return 'nunca';
    const m = Math.round((Date.now() - new Date(t)) / 60000);
    if (m < 2) return 'recién'; if (m < 60) return 'hace ' + m + ' min';
    const h = Math.round(m / 60); if (h < 24) return 'hace ' + h + ' h';
    const d = Math.round(h / 24); return d < 60 ? 'hace ' + d + ' días' : fHora(t);
  };
  const DIAS = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];
  const telNorm = (t) => { let d = String(t || '').replace(/\D/g, ''); if (d.length === 9 && d[0] === '9') d = '56' + d; if (d.length === 8) d = '569' + d; return d; };
  const wa = (tel, txt) => 'https://wa.me/' + telNorm(tel) + (txt ? '?text=' + encodeURIComponent(txt) : '');
  const estrellas = (n) => { n = Math.round(Number(n) || 0); return '★'.repeat(n) + '☆'.repeat(5 - n); };
  const nota = (o) => o && o.total ? '<span class="stars">★ ' + String(o.promedio).replace('.', ',') + '</span> <span class="sub">(' + o.total + ')</span>' : '<span class="sub">Sin calificaciones</span>';

  let toastT;
  function toast(msg) {
    let el = $('toast');
    if (!el) { el = document.createElement('div'); el.id = 'toast'; el.setAttribute('role', 'status'); document.body.appendChild(el); }
    el.textContent = msg; el.classList.add('show');
    clearTimeout(toastT); toastT = setTimeout(() => el.classList.remove('show'), 2800);
  }

  // Diálogo simple: contenido HTML; devuelve el <dialog> (se borra al cerrar).
  function modal(html, onReady) {
    const d = document.createElement('dialog');
    d.innerHTML = '<div class="card">' + html + '</div>';
    document.body.appendChild(d);
    d.addEventListener('close', () => setTimeout(() => d.remove(), 50));
    d.addEventListener('click', (e) => { if (e.target === d) d.close(); });
    d.querySelectorAll('[data-cerrar]').forEach((b) => { b.onclick = () => d.close(); });
    d.showModal();
    if (onReady) onReady(d);
    return d;
  }
  function confirmar(msg, si) {
    return new Promise((ok) => {
      const d = modal('<p style="margin:0 0 6px;white-space:pre-line">' + esc(msg) + '</p><div class="btns"><button class="ghost" data-no>Cancelar</button><button data-si>' + esc(si || 'Sí, continuar') + '</button></div>');
      let r = false;
      d.querySelector('[data-si]').onclick = () => { r = true; d.close(); };
      d.querySelector('[data-no]').onclick = () => d.close();
      d.addEventListener('close', () => ok(r));
    });
  }

  function tema(color) {
    if (!/^#[0-9a-f]{6}$/i.test(color || '')) return;
    const n = parseInt(color.slice(1), 16);
    const l = (0.299 * (n >> 16) + 0.587 * ((n >> 8) & 255) + 0.114 * (n & 255)) / 255;
    document.documentElement.style.setProperty('--brand', color);
    document.documentElement.style.setProperty('--brand-ink', l > 0.62 ? '#0f172a' : '#ffffff');
    let m = document.querySelector('meta[name=theme-color]');
    if (!m) { m = document.createElement('meta'); m.name = 'theme-color'; document.head.appendChild(m); }
    m.content = color;
  }
  // Logo (o ícono) dentro de un elemento .logo
  function pintarLogo(el, t) {
    if (!el || !t) return;
    const ok = /^data:image\/(jpeg|png|webp);base64,/.test(t.logo || '');
    el.style.backgroundImage = ok ? 'url("' + t.logo + '")' : '';
    el.textContent = ok ? '' : (t.icono || '🚲');
  }

  function friendly(err) {
    const m = String((err && (err.message || err.error_description)) || err || '');
    if (/Invalid login credentials/i.test(m)) return 'Correo o contraseña incorrectos';
    if (/Email not confirmed/i.test(m)) return 'Confirma tu correo (revisa tu bandeja y spam)';
    if (/already registered|already been registered/i.test(m)) return 'Ese correo ya tiene cuenta. Inicia sesión.';
    if (/Password should be/i.test(m)) return 'La contraseña debe tener al menos 6 caracteres';
    if (/rate limit|too many/i.test(m)) return 'Demasiados intentos. Espera unos minutos.';
    if (/Failed to fetch|NetworkError|Load failed/i.test(m)) return 'Sin conexión. Revisa tu internet.';
    if (/Could not find the function|schema cache|does not exist/i.test(m)) return 'Falta instalar la base de datos: corre supabase/schema.sql en Supabase → SQL Editor (guía, paso 1).';
    if (/Database error saving new user/i.test(m)) return 'No se pudo crear la cuenta: el registro está cerrado, se llegó al límite o hubo muchos registros seguidos. Intenta más tarde o escríbenos.';
    return m.replace(/^\w*Error:\s*/, '') || 'Error';
  }
  async function rpc(name, args) {
    const { data, error } = await sb.rpc(name, args || {});
    if (error) throw new Error(friendly(error));
    return data;
  }
  async function q(p) {
    const { data, error } = await p;
    if (error) throw new Error(friendly(error));
    return data;
  }

  /* ---------- Configuración pública y textos ---------- */
  let publica = null;
  try { publica = JSON.parse(localStorage.getItem('bt:publica')); } catch (e) { publica = null; }
  async function cargarPublica() {
    try { publica = await rpc('config_publica'); localStorage.setItem('bt:publica', JSON.stringify(publica)); } catch (e) { /* usa la copia */ }
    return publica || { config: {}, textos: {}, planes: {} };
  }
  function txt(clave, vars) {
    let s = (publica && publica.textos && publica.textos[clave]) || '';
    Object.keys(vars || {}).forEach((k) => { s = s.split('{' + k + '}').join(vars[k]); });
    return s;
  }

  /* ---------- Sesión ---------- */
  let cuenta = null;
  try { cuenta = JSON.parse(localStorage.getItem('bt:cuenta')); } catch (e) { cuenta = null; }
  async function refrescar() {
    const { data } = await sb.auth.getSession();
    if (!data.session) { cuenta = null; localStorage.removeItem('bt:cuenta'); return null; }
    try {
      cuenta = await rpc('mi_cuenta');
      if (cuenta) localStorage.setItem('bt:cuenta', JSON.stringify(cuenta));
    } catch (e) {
      if (!/Sin conexión/.test(e.message)) throw e;
    }
    if (cuenta) sb.rpc('registrar_visto').then(() => {}, () => {});
    return cuenta;
  }
  const destino = (c) => !c ? 'index.html' : c.rol === 'admin' || c.rol === 'socio' ? 'admin/' : c.rol === 'cliente' ? 'cliente/' : 'taller/';
  // Úsalo al abrir cada panel: sin sesión o con otro rol, vuelve al inicio.
  async function requerir(roles) {
    let c = null;
    try { c = await refrescar(); } catch (e) { c = cuenta; }
    if (!c) { location.replace(ROOT + 'index.html?volver=' + encodeURIComponent(location.pathname + location.hash)); return new Promise(() => {}); }
    if (c.suspendido) { document.body.innerHTML = '<main><div class="card"><h2>Cuenta suspendida</h2><p class="muted">Contacta al administrador.</p><button onclick="App.salir()">Salir</button></div></main>'; return new Promise(() => {}); }
    if (roles && !roles.includes(c.rol)) { location.replace(ROOT + destino(c)); return new Promise(() => {}); }
    if (c.taller && c.taller.color) tema(c.taller.color);
    // Núcleo (ayuda.js): cabecera común [campana][FREE/PRO][foto], menú de la cuenta, ayuda y sensación Premium.
    const adm = c.rol === 'admin' || c.rol === 'socio';
    window.CFX_AYUDA_PEND = Object.assign(window.CFX_AYUDA_PEND || {}, { rpc, app: 'taller', admin: adm, socio: c.rol === 'socio', premium: !!c.premium, id: c.id, hasta: c.premium_hasta || (c.taller && c.taller.premium_hasta),
      nombre: c.nombre || (c.taller && c.taller.nombre), email: c.email, quitar: '#hRol, #perfilBtn, #chatBtn', salir,
      cuenta: adm ? '#cuenta' : c.rol === 'cliente' ? '#cuenta' : '#mas/cuenta', panel: adm && !/\/admin\//.test(location.pathname) ? ROOT + 'admin/' : null });
    if (window.CFX_AYUDA) window.CFX_AYUDA.iniciar(window.CFX_AYUDA_PEND);
    return c;
  }
  async function entrar(email, password) {
    const { error } = await sb.auth.signInWithPassword({ email: email.trim(), password });
    if (error) throw new Error(friendly(error));
    const c = await refrescar();
    if (!c) throw new Error('Tu cuenta no tiene perfil. Contacta al administrador.');
    sincronizarPush();
    return c;
  }
  async function salir() {
    try { const s = await subActual(); if (s) await sb.rpc('push_quitar', { p_endpoint: s.endpoint }); } catch (e) { /* sin red */ }
    try { await sb.auth.signOut(); } catch (e) { /* sin red */ }
    cuenta = null; localStorage.removeItem('bt:cuenta');
    location.replace(ROOT + 'index.html');
  }
  // Cuentas de taller y de equipo: las crea el servidor (nadie se registra solo).
  async function crearCuenta(d) {
    const { data, error } = await sb.functions.invoke('servidor', { body: Object.assign({ accion: 'crear_cuenta' }, d) });
    if (error) {
      let det = '';
      try { det = await error.context.text(); } catch (e) { /* sin detalle */ }
      throw new Error('No se pudo conectar con la función "servidor". Revisa que esté creada en Supabase (guía, paso 4).' + (det ? ' ' + det.slice(0, 120) : ''));
    }
    if (!data || !data.ok) throw new Error((data && data.error) || 'No se pudo crear la cuenta');
    return data;
  }
  function clave() {
    const L = 'abcdefghjkmnpqrstuvwxyz', r = crypto.getRandomValues(new Uint32Array(9));
    const l = (i) => L[r[i] % L.length], n = (i) => String(r[i] % 10);
    return l(0).toUpperCase() + l(1) + l(2) + n(3) + n(4) + n(5) + n(6) + l(7) + l(8);
  }
  function mensajeAcceso(d) {
    return 'Hola ' + d.nombre + ' 👋\nTe creamos tu cuenta en ' + (d.lugar || 'BiciTaller') + '.\n\n📲 Entra aquí e instala la app: ' + ROOT +
      '\n👤 Correo: ' + d.email + '\n🔑 Contraseña: ' + d.password + '\n\nCambia tu contraseña en "Mi cuenta" la primera vez que entres.';
  }

  // Calidad de fotos según su uso: viene del núcleo (fotos.js); estos valores son el respaldo.
  const FOTO = (k) => (global.CFX_FOTO && global.CFX_FOTO[k]) || { comprobante: { lado: 1000, calidad: 0.6, kb: 110 }, documento: { lado: 1400, calidad: 0.72, kb: 300 }, vitrina: { lado: 1080, calidad: 0.8, kb: 220 }, portada: { lado: 1280, calidad: 0.8, kb: 300 }, perfil: { lado: 400, calidad: 0.8, kb: 45 }, logo: { lado: 256, calidad: 0.85, kb: 30 } }[k];
  /* ---------- Imágenes (comprobantes y logo) ---------- */
  function achicar(file, lado, maxLargo, tipo) {
    return new Promise((ok, ko) => {
      const img = new Image();
      img.onload = () => {
        const k = Math.min(1, lado / Math.max(img.width, img.height));
        const c = document.createElement('canvas');
        c.width = Math.max(1, Math.round(img.width * k)); c.height = Math.max(1, Math.round(img.height * k));
        const g = c.getContext('2d');
        g.fillStyle = '#fff'; g.fillRect(0, 0, c.width, c.height);
        g.drawImage(img, 0, 0, c.width, c.height);
        URL.revokeObjectURL(img.src);
        let qa = 0.82, d = c.toDataURL(tipo || 'image/jpeg', qa);
        while (d.length > maxLargo && qa > 0.3) { qa -= 0.1; d = c.toDataURL('image/jpeg', qa); }
        if (d.length > maxLargo) { ko(new Error('La imagen es muy pesada')); return; }
        ok(d);
      };
      img.onerror = () => ko(new Error('No se pudo leer la imagen'));
      img.src = URL.createObjectURL(file);
    });
  }
  const comprimirComprobante = (file) => achicar(file, FOTO('comprobante').lado, FOTO('comprobante').kb * 1400); // base64 ≈ 1,37 × bytes
  const comprimirLogo = (file) => achicar(file, FOTO('logo').lado, 110000);
  const comprimirFoto = (file) => achicar(file, FOTO('vitrina').lado, 155000); // fotos del trabajo (las ve el cliente): tope de la base 160000
  function descargar(dataUrl, nombre) {
    const a = document.createElement('a');
    a.href = dataUrl; a.download = nombre; document.body.appendChild(a); a.click(); a.remove();
  }
  function verImagen(dataUrl, titulo, nombreArchivo) {
    const d = modal('<h2>' + esc(titulo || 'Comprobante') + '</h2><div class="comprobante"><img alt="Comprobante" src="' + dataUrl + '"></div>' +
      '<div class="btns"><button class="ghost" data-cerrar>Cerrar</button><button data-bajar>⬇️ Descargar</button></div>');
    d.querySelector('[data-bajar]').onclick = () => descargar(dataUrl, nombreArchivo || 'comprobante.jpg');
    return d;
  }

  /* ---------- Campanita (avisos dentro de la app, en vivo) ---------- */
  let avisos = [], canal = null;
  async function campana(btn) {
    if (!btn || !cuenta) return;
    btn.innerHTML = '🔔<span class="badge hidden"></span>';
    btn.setAttribute('aria-label', 'Avisos');
    const badge = btn.querySelector('.badge');
    async function cargar() {
      try { avisos = await q(sb.from('notificaciones').select('*').order('created_at', { ascending: false }).limit(60)); } catch (e) { return; }
      const n = avisos.filter((a) => !a.leida).length;
      badge.textContent = n > 99 ? '99+' : n; badge.classList.toggle('hidden', !n);
      document.dispatchEvent(new CustomEvent('bt:avisos', { detail: n }));
    }
    btn.onclick = () => {
      const d = modal('<div style="display:flex;align-items:center;gap:8px"><h2 style="flex:1;margin:0">🔔 Avisos</h2><button class="small ghost" data-cerrar>Cerrar</button></div>' +
        '<div id="btAvisos" style="max-height:65vh;overflow:auto;margin-top:6px">' + (avisos.length ? avisos.map((a) =>
          '<div class="notif' + (a.leida ? '' : ' nueva') + '" data-url="' + esc(a.url) + '" style="position:relative;padding-right:34px"><b>' + esc(a.titulo) + '</b><div class="sub">' + esc(a.cuerpo) + '</div><div class="sub">' + hace(a.created_at) + '</div>' +
          '<button type="button" class="small ghost" data-quitar="' + a.id + '" aria-label="Borrar aviso" style="position:absolute;top:6px;right:4px;padding:2px 8px;min-height:0">✕</button></div>').join('')
          : '<p class="empty">Sin avisos por ahora.</p>') + '</div>' +
        (avisos.length ? '<div class="btns"><button class="small ghost" data-borrar>Borrar todos</button></div><p class="sub">Los avisos y mensajes se borran solos a los 30 días.</p>' : '') + '<div id="btPush"></div>');
      d.querySelector('#btAvisos').onclick = async (e) => {
        const q1 = e.target.closest('[data-quitar]');
        if (q1) { e.stopPropagation(); q1.parentNode.remove(); await sb.from('notificaciones').delete().eq('id', q1.dataset.quitar); cargar(); return; }
        const n = e.target.closest('[data-url]'); if (!n || !n.dataset.url) return;
        d.close(); irA(n.dataset.url);
      };
      const bb = d.querySelector('[data-borrar]');
      if (bb) bb.onclick = async () => { if (!(await confirmar('¿Borrar todos tus avisos?', 'Borrar'))) return; await sb.from('notificaciones').delete().eq('para', cuenta.id); d.close(); cargar(); };
      ofrecerPush(d.querySelector('#btPush'));
      const ids = avisos.filter((a) => !a.leida).map((a) => a.id);
      if (ids.length) sb.from('notificaciones').update({ leida: true }).in('id', ids).then(() => cargar());
    };
    await cargar();
    insistirPush();
    if (canal) sb.removeChannel(canal);
    canal = sb.channel('avisos-' + cuenta.id)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'notificaciones', filter: 'para=eq.' + cuenta.id }, (p) => {
        toast('🔔 ' + (p.new && p.new.titulo || 'Nuevo aviso'));
        cargar();
      })
      .subscribe();
    // Si la app estuvo en segundo plano, refresca al volver.
    document.addEventListener('visibilitychange', () => { if (!document.hidden) cargar(); });
  }
  function irA(url) {
    if (/^https?:/.test(url)) { location.href = url; return; }
    const destinoUrl = ROOT + url.replace(/^\//, '');
    const a = new URL(destinoUrl, location.href), b = new URL(location.href);
    if (a.pathname === b.pathname && a.search === b.search) { location.hash = a.hash; window.dispatchEvent(new HashChangeEvent('hashchange')); }
    else location.href = destinoUrl;
  }

  /* ---------- Push (notificaciones con la app cerrada) ---------- */
  const pushSoportado = () => 'serviceWorker' in navigator && 'PushManager' in global && 'Notification' in global;
  const b64 = (s) => { const p = '='.repeat((4 - (s.length % 4)) % 4); const r = atob((s + p).replace(/-/g, '+').replace(/_/g, '/')); return Uint8Array.from(r, (c) => c.charCodeAt(0)); };
  async function subActual() {
    if (!pushSoportado() || Notification.permission !== 'granted') return null;
    const reg = await navigator.serviceWorker.getRegistration();
    return reg && reg.pushManager ? reg.pushManager.getSubscription() : null;
  }
  async function activarPush() {
    if (!pushSoportado()) {
      throw new Error(/iPhone|iPad/.test(navigator.userAgent) ? 'En iPhone primero instala la app: Compartir → "Agregar a inicio" y ábrela desde ahí.'
        : 'Este navegador no permite notificaciones');
    }
    const p = await cargarPublica();
    const pub = p.config && p.config.vapid_publica;
    if (!pub) throw new Error('El administrador aún no activa las notificaciones');
    if (await Notification.requestPermission() !== 'granted') throw new Error('Permiso de notificaciones denegado');
    const reg = await navigator.serviceWorker.ready;
    const key = b64(pub);
    let s = await reg.pushManager.getSubscription();
    if (s) {
      const cur = s.options && s.options.applicationServerKey ? new Uint8Array(s.options.applicationServerKey) : null;
      if (!cur || cur.length !== key.length || cur.some((x, i) => x !== key[i])) { await s.unsubscribe(); s = null; }
    }
    if (!s) s = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: key });
    const j = s.toJSON();
    await rpc('push_guardar', { p_endpoint: j.endpoint, p_p256dh: j.keys.p256dh, p_auth: j.keys.auth });
    return true;
  }
  async function sincronizarPush() {
    try { const s = await subActual(); if (!s) return; const j = s.toJSON(); await rpc('push_guardar', { p_endpoint: j.endpoint, p_p256dh: j.keys.p256dh, p_auth: j.keys.auth }); } catch (e) { /* nada */ }
  }
  async function ofrecerPush(el) {
    if (!el) return;
    if (await subActual()) { el.innerHTML = '<p class="sub" style="margin-top:10px">✅ Notificaciones activas en este celular.</p>'; return; }
    el.innerHTML = '<div class="aviso" style="margin-top:12px"><div class="grow">📲 Activa las notificaciones para enterarte aunque tengas la app cerrada.</div>' +
      '<button class="small" type="button">Activar</button></div>';
    el.querySelector('button').onclick = async () => {
      try { await activarPush(); toast('✅ Notificaciones activadas'); ofrecerPush(el); } catch (e) { toast(e.message); }
    };
  }

  /* ---------- Notificaciones: insistir hasta que se activen ---------- */
  async function insistirPush() {
    if (!cuenta || sessionStorage.getItem('bt:pushPedido')) return;
    if (await subActual()) return;
    sessionStorage.setItem('bt:pushPedido', '1');
    const ios = /iPhone|iPad/.test(navigator.userAgent), instalada = matchMedia('(display-mode: standalone)').matches || navigator.standalone;
    const negado = 'Notification' in global && Notification.permission === 'denied';
    const msg = ios && !instalada ? 'Para recibir avisos en iPhone: toca Compartir → "Agregar a inicio" y abre la app desde ese ícono.'
      : negado ? 'Las notificaciones están bloqueadas. Actívalas en los ajustes del navegador (candado junto a la dirección → Notificaciones → Permitir).'
      : 'Actívalas para enterarte al instante de reservas, pagos, mensajes y cuando tu bici esté lista.';
    const d = modal('<h2>🔔 Activa las notificaciones</h2><p class="muted" style="margin-top:0">' + esc(msg) + '</p><div class="btns"><button class="ghost" data-cerrar>Ahora no</button>' +
      (!negado && !(ios && !instalada) ? '<button id="btPushSi">Activar</button>' : '') + '</div>');
    const b = d.querySelector('#btPushSi');
    if (b) b.onclick = async () => { try { await activarPush(); toast('✅ Notificaciones activadas'); d.close(); } catch (e) { toast(e.message); } };
  }

  /* ---------- Chat (cliente ↔ taller · taller ↔ administrador) ---------- */
  let chatCanal = null;
  async function chatBoton(btn, icono) {
    if (!btn || !cuenta) return;
    btn.innerHTML = (icono || '💬') + '<span class="badge hidden"></span>'; btn.setAttribute('aria-label', 'Mensajes');
    const badge = btn.querySelector('.badge');
    let lista = [];
    async function cargar() {
      try { lista = await rpc('chat_lista'); } catch (e) { return; }
      const n = lista.reduce((a, c) => a + (+c.no_leidos || 0), 0);
      badge.textContent = n; badge.classList.toggle('hidden', !n);
      document.querySelectorAll('.chat-num').forEach((x) => { x.textContent = n; x.classList.toggle('hidden', !n); });
    }
    btn.onclick = async () => { await cargar(); abrirLista(); };
    function abrirLista() {
      if (cuenta.rol === 'cliente' && lista[0]) { abrirChat(lista[0].taller_id, lista[0].cliente_id, lista[0].nombre, cargar); return; }
      const d = modal('<div style="display:flex;align-items:center;gap:8px"><h2 style="flex:1;margin:0">💬 Mensajes</h2><button class="small ghost" data-cerrar>Cerrar</button></div><ul class="list" id="btChats">' +
        (lista.length ? lista.map((c, i) => '<li class="clic" data-i="' + i + '"><span class="grow"><b>' + esc(c.nombre) + '</b><div class="sub">' + (c.ultimo ? hace(c.ultimo) : 'Sin mensajes') + '</div></span>' +
          (+c.no_leidos ? '<span class="pill bad">' + c.no_leidos + '</span>' : '') + '</li>').join('') : '<li class="muted">Sin conversaciones todavía.</li>') + '</ul>');
      d.querySelector('#btChats').onclick = (e) => { const li = e.target.closest('[data-i]'); if (!li) return; const c = lista[+li.dataset.i]; d.close(); abrirChat(c.taller_id, c.cliente_id, c.nombre, cargar); };
    }
    await cargar();
    if (chatCanal) sb.removeChannel(chatCanal);
    chatCanal = sb.channel('chat-' + cuenta.id).on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'mensajes' }, () => cargar()).subscribe();
    document.addEventListener('visibilitychange', () => { if (!document.hidden) cargar(); });
    if (location.hash === '#chat') abrirLista();
    window.addEventListener('hashchange', () => { if (location.hash === '#chat') abrirLista(); });
  }
  // Ventana de chat flotante: se minimiza y sigue recibiendo mensajes en vivo.
  let chatAbierto = null;
  function abrirChat(taller, cliente, titulo, alCerrar) {
    if (chatAbierto) chatAbierto.cerrar();
    const w = document.createElement('div');
    w.className = 'chatwin';
    w.innerHTML = '<div class="chathead"><b class="grow">💬 ' + esc(titulo || 'Mensajes') + '</b><span class="badge hidden"></span>' +
      '<button class="icon-btn" data-l title="Limpiar conversación" aria-label="Limpiar">🧹</button><button class="icon-btn" data-m aria-label="Minimizar">–</button>' +
      '<button class="icon-btn" data-x aria-label="Cerrar">✕</button></div><div class="chatbody"><div class="chatmsgs"></div>' +
      '<div class="chatin"><label class="icon-btn" title="Adjuntar foto" aria-label="Adjuntar foto">📎<input type="file" accept="image/*" hidden></label>' +
      '<input class="chattxt" maxlength="1000" placeholder="Escribe un mensaje…"><button class="chatenv">➤</button></div></div>';
    document.body.appendChild(w);
    const box = w.querySelector('.chatmsgs'), txt = w.querySelector('.chattxt'), bdg = w.querySelector('.chathead .badge');
    let min = false, nuevos = 0;
    async function leer() {
      if (min) { nuevos++; bdg.textContent = nuevos; bdg.classList.remove('hidden'); return; }
      let m = [];
      try { m = await rpc('chat_leer', { p_taller: taller, p_cliente: cliente }); } catch (e) { box.innerHTML = '<p class="err">' + esc(e.message) + '</p>'; return; }
      box.innerHTML = m.length ? m.map((x) => '<div class="burb' + (x.mio ? ' mia' : '') + '">' + (x.imagen ? '<img src="' + x.imagen + '" alt="Foto" data-img>' : '') +
        (x.texto ? esc(x.texto) : '') + '<div class="hora">' + hace(x.created_at) + '</div></div>').join('') : '<p class="empty">Escribe el primer mensaje 👋</p>';
      box.scrollTop = box.scrollHeight;
    }
    const can = sb.channel('conv-' + taller + (cliente || '')).on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'mensajes', filter: 'taller_id=eq.' + taller }, leer).subscribe();
    async function enviar(img) {
      const t = txt.value.trim(); if (!t && !img) return;
      txt.value = '';
      try { await rpc('chat_enviar', { p_taller: taller, p_cliente: cliente, p_texto: t, p_imagen: img || null }); sb.functions.invoke('servidor').catch(() => {}); leer(); }
      catch (e) { toast(e.message); txt.value = t; }
    }
    const cerrar = () => { sb.removeChannel(can); w.remove(); chatAbierto = null; if (alCerrar) alCerrar(); };
    chatAbierto = { cerrar };
    w.querySelector('[data-x]').onclick = cerrar;
    w.querySelector('[data-m]').onclick = () => { min = !min; w.classList.toggle('min', min); if (!min) { nuevos = 0; bdg.classList.add('hidden'); leer(); } };
    w.querySelector('.chathead b').onclick = () => { if (min) w.querySelector('[data-m]').click(); };
    w.querySelector('[data-l]').onclick = async () => {
      if (!await confirmar('¿Borrar todos los mensajes de esta conversación?', 'Sí, limpiar')) return;
      try { await rpc('chat_limpiar', { p_taller: taller, p_cliente: cliente }); leer(); } catch (e) { toast(e.message); }
    };
    w.querySelector('input[type=file]').onchange = async (e) => {
      const f = e.target.files[0]; e.target.value = ''; if (!f) return;
      try { enviar(await achicar(f, 1100, 380000)); } catch (err) { toast(err.message); }
    };
    box.onclick = (e) => { const i = e.target.closest('[data-img]'); if (i) verImagen(i.src, 'Foto', 'foto.jpg'); };
    w.querySelector('.chatenv').onclick = () => enviar();
    txt.onkeydown = (e) => { if (e.key === 'Enter') enviar(); };
    leer(); setTimeout(() => txt.focus(), 100);
  }

  /* ---------- Compartir un enlace y su QR (con afiche para imprimir) ---------- */
  async function compartir(url, texto, titulo) {
    if (navigator.share) { try { await navigator.share({ title: titulo || texto, text: texto, url }); return; } catch (e) { /* cancelado */ } }
    window.open('https://wa.me/?text=' + encodeURIComponent(texto + ': ' + url), '_blank');
  }
  function qrImagen(url, celda) {
    try { const qr = global.qrcode(0, 'M'); qr.addData(url); qr.make(); return qr.createDataURL(celda || 8, 8); } catch (e) { return ''; }
  }
  // d = { url, titulo, archivo, afiche: { titulo, texto } }
  function verQR(d) {
    const img = qrImagen(d.url);
    const m = modal('<h2>📱 ' + esc(d.titulo || 'Código QR') + '</h2><div class="qr" style="text-align:center"><img alt="QR" src="' + img + '"></div><p class="sub" style="text-align:center">' + esc(d.url) +
      '</p><div class="btns"><button class="ghost" data-cerrar>Cerrar</button><button class="alt" data-copiar>📋 Copiar link</button><button data-bajar>⬇️ Descargar</button>' +
      (d.afiche ? '<button class="alt" data-afiche>🖨️ Afiche</button>' : '') + '</div>');
    m.querySelector('[data-bajar]').onclick = () => descargar(img, d.archivo || 'qr.gif');
    m.querySelector('[data-copiar]').onclick = () => { navigator.clipboard.writeText(d.url).then(() => toast('🔗 Link copiado'), () => toast(d.url)); };
    const af = m.querySelector('[data-afiche]');
    if (af) af.onclick = () => afiche(d.url, d.afiche.titulo, d.afiche.texto);
  }
  // Hoja para imprimir y pegar en el mesón o en la vitrina.
  function afiche(url, titulo, texto) {
    const w = window.open('', '_blank');
    if (!w) { toast('Permite las ventanas emergentes para imprimir'); return; }
    w.document.write('<!doctype html><html lang="es"><head><meta charset="utf-8"><title>' + esc(titulo) + '</title><style>body{font-family:system-ui,sans-serif;text-align:center;padding:40px 24px;color:#0f172a}' +
      'h1{font-size:40px;margin:0 0 12px}p{font-size:22px;margin:0 auto 28px;max-width:560px}img{width:340px;height:340px;image-rendering:pixelated}small{display:block;margin-top:18px;font-size:15px;color:#475569;word-break:break-all}</style></head><body>' +
      '<h1>' + esc(titulo) + '</h1><p>' + esc(texto) + '</p><img alt="QR" src="' + qrImagen(url, 12) + '"><small>' + esc(url) + '</small>' +
      '<script>window.onload=function(){setTimeout(function(){window.print()},300)}<\/script></body></html>');
    w.document.close();
  }

  // Solo el administrador: borra un usuario o un taller completo (lo hace el servidor).
  async function borrarCuenta(tipo, id, motivo) {
    const { data, error } = await sb.functions.invoke('servidor', { body: { accion: 'borrar', tipo, id, motivo: motivo || '' } });
    if (error) throw new Error('No se pudo conectar con la función "servidor".');
    if (!data || !data.ok) throw new Error((data && data.error) || 'No se pudo borrar');
    return data;
  }

  // Horario legible: "Lun–Vie 10:00–19:00 · Sáb 10:00–14:00"
  function horarioTxt(t) {
    const h = t.horarios || {}, a = String(t.abre).slice(0, 5), c = String(t.cierra).slice(0, 5);
    const g = [];
    [1, 2, 3, 4, 5, 6, 0].filter((d) => t.dias.includes(d)).forEach((d) => {
      const r = (h[d] ? String(h[d].abre).slice(0, 5) + '–' + String(h[d].cierra).slice(0, 5) : a + '–' + c);
      const u = g[g.length - 1];
      if (u && u.r === r && u.fin === (d === 0 ? 6 : d - 1)) { u.fin = d; u.n++; } else g.push({ ini: d, fin: d, r, n: 1 });
    });
    return g.map((x) => DIAS[x.ini] + (x.n > 1 ? '–' + DIAS[x.fin] : '') + ' ' + x.r).join(' · ');
  }

  /* ---------- Apariencia: modo claro/oscuro (por celular) y color de la app ---------- */
  function aplicarModo() {
    let m = 'auto';
    try { m = localStorage.getItem('bt:modo') || 'auto'; } catch (e) { /* sin almacenamiento */ }
    if (m === 'claro') document.documentElement.dataset.theme = 'light';
    else if (m === 'oscuro') document.documentElement.dataset.theme = 'dark';
    else delete document.documentElement.dataset.theme;
  }
  aplicarModo();
  // Selector "Automático / Claro / Oscuro" dentro de un elemento.
  function selectorModo(el) {
    if (!el) return;
    let m = 'auto';
    try { m = localStorage.getItem('bt:modo') || 'auto'; } catch (e) { /* nada */ }
    el.innerHTML = '<label>🌓 Modo de pantalla (este celular)</label><div class="seg" style="margin:0">' +
      [['auto', 'Automático'], ['claro', '☀️ Claro'], ['oscuro', '🌙 Oscuro']].map((x) => '<button type="button" data-modo="' + x[0] + '" class="' + (m === x[0] ? 'on' : '') + '">' + x[1] + '</button>').join('') + '</div>';
    el.onclick = (e) => {
      const b = e.target.closest('[data-modo]'); if (!b) return;
      try { localStorage.setItem('bt:modo', b.dataset.modo); } catch (err) { /* nada */ }
      aplicarModo(); selectorModo(el);
    };
  }
  // Color de la app (lo elige el administrador): inicio, registro, directorio y panel del administrador.
  const colorApp = () => tema(((publica && publica.config) || {}).color_app || '#16a34a');
  const COLORES = ['#16a34a', '#059669', '#0f766e', '#0891b2', '#2563eb', '#4f46e5', '#7c3aed', '#db2777', '#dc2626', '#ea580c', '#d97706', '#334155', '#111827'];

  /* ---------- App instalable ---------- */
  function registrarSW() {
    if (!('serviceWorker' in navigator) || location.protocol === 'file:') return;
    navigator.serviceWorker.register(ROOT + 'sw.js', { scope: ROOT }).then((r) => r.update()).catch(() => {});
  }
  let instalar = null;
  global.addEventListener('beforeinstallprompt', (e) => { e.preventDefault(); instalar = e; document.dispatchEvent(new Event('bt:instalable')); });
  async function pedirInstalar() { if (!instalar) return false; instalar.prompt(); await instalar.userChoice; instalar = null; return true; }

  /* ---------- Versión nueva: ventana para actualizar ---------- */
  const mayor = (a, b) => {
    const x = String(a).split('.').map(Number), y = String(b).split('.').map(Number);
    for (let i = 0; i < Math.max(x.length, y.length); i++) if ((x[i] || 0) !== (y[i] || 0)) return (x[i] || 0) > (y[i] || 0);
    return false;
  };
  let avisada = false;
  async function revisarVersion() {
    if (avisada || document.hidden) return;
    let v = '';
    try { v = String((await (await fetch(ROOT + 'version.json?_=' + Date.now(), { cache: 'no-store' })).json()).version || ''); } catch (e) { return; }
    if (!v || !mayor(v, cfg.VERSION)) return;
    // Llega a todos solo cuando el admin la libera; el admin la ve antes para probarla.
    let lib = '';
    try { lib = String((((await cargarPublica()) || {}).config || {}).version_liberada || ''); } catch (e) { /* sin red */ }
    const esAdmin = !!(cuenta && ['admin', 'socio'].includes(cuenta.rol));
    if (lib && mayor(v, lib) && !esAdmin) return;
    if (!lib && !esAdmin) return;
    avisada = true;
    if (esAdmin && (!lib || mayor(v, lib))) { // el admin: aviso para probarla (no se instala sola)
      const d = modal('<h2>🔄 Versión nueva para probar</h2><p class="muted" style="margin-top:0">Está publicada la v' + esc(v) + ' (tus usuarios siguen en la v' + esc(lib || cfg.VERSION) + '). Pruébala y libérala en Ajustes → Actualizar.</p><div class="btns"><button class="ghost" data-cerrar>Después</button><button id="btActualizar">Probar ahora</button></div>');
      d.querySelector('#btActualizar').onclick = actualizar; return;
    }
    // Recién abierta la app: se actualiza sola (una vez por versión, para no quedar en un bucle si el servidor aún no publica).
    let intento = '';
    try { intento = sessionStorage.getItem('bt:autoAct') || ''; } catch (e) { /* nada */ }
    if (global.CodeFixAuto) { global.CodeFixAuto(v, actualizar); return; } // núcleo: siempre sola, sin ventana
    if (performance.now() < 20000 && intento !== v) {
      try { sessionStorage.setItem('bt:autoAct', v); } catch (e) { /* nada */ }
      toast('🔄 Actualizando a la v' + v + '…');
      actualizar();
      return;
    }
    const d = modal('<h2>🔄 Hay una versión nueva</h2><p class="muted" style="margin-top:0">Tienes la v' + esc(cfg.VERSION) + ' y ya está disponible la v' + esc(v) +
      '. Actualiza para tener las últimas mejoras.</p><div class="btns"><button class="ghost" data-cerrar>Después</button><button id="btActualizar">Actualizar ahora</button></div>');
    d.querySelector('#btActualizar').onclick = actualizar;
  }
  async function actualizar() {
    const b = document.getElementById('btActualizar');
    if (b) { b.disabled = true; b.textContent = 'Actualizando…'; }
    try {
      if ('caches' in global) { const k = await caches.keys(); await Promise.all(k.map((x) => caches.delete(x))); }
      const reg = 'serviceWorker' in navigator && await navigator.serviceWorker.getRegistration();
      if (reg) await reg.update();
    } catch (e) { /* igual recarga */ }
    location.reload();
  }
  setTimeout(revisarVersion, 3000);
  setInterval(revisarVersion, 10 * 60 * 1000);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) revisarVersion(); });

  function pie() {
    const f = document.createElement('footer');
    f.className = 'pie';
    f.innerHTML = '© ' + new Date().getFullYear() + ' ' + esc(txt('app_nombre') || 'BiciTaller') + ' · CodeFix · v' + cfg.VERSION +
      ' · <button type="button" title="Descarga la última versión de la app">🔄 Actualizar</button>';
    f.querySelector('button').onclick = actualizar;
    (document.querySelector('main') || document.body).appendChild(f);
  }

  // Pestañas inferiores: <nav class="tabs"><button data-v="x">…; vistas: <section class="view" id="v-x">
  function pestanas(onShow) {
    const nav = document.querySelector('nav.tabs');
    function show(v, push) {
      if (!document.getElementById('v-' + v)) return;
      document.querySelectorAll('.view').forEach((x) => x.classList.toggle('on', x.id === 'v-' + v));
      if (nav) nav.querySelectorAll('button[data-v]').forEach((b) => b.classList.toggle('on', b.dataset.v === v || b.dataset.v === (document.getElementById('v-' + v).dataset.tab || '')));
      if (push !== false && location.hash !== '#' + v) history.replaceState(null, '', '#' + v);
      scrollTo(0, 0);
      if (onShow) onShow(v);
    }
    if (nav) nav.querySelectorAll('button[data-v]').forEach((b) => { b.onclick = () => show(b.dataset.v); });
    window.addEventListener('hashchange', () => { const h = location.hash.slice(1); if (h) show(h, false); });
    return show;
  }

  global.App = {
    sb, ROOT, $, esc, plata, numero, iso, fechaDe, sumarDias, hoy, fCorta, fLarga, fHora, hace, DIAS, telNorm, wa, estrellas, nota,
    toast, modal, confirmar, tema, selectorModo, colorApp, COLORES, pintarLogo, friendly, rpc, q, cargarPublica, txt, refrescar, requerir, entrar, salir, crearCuenta,
    clave, mensajeAcceso, comprimirComprobante, comprimirLogo, comprimirFoto, descargar, verImagen, compartir, verQR, afiche, campana, irA, activarPush, ofrecerPush,
    pushSoportado, registrarSW, pedirInstalar, pie, pestanas, destino, revisarVersion, actualizar, mayor, chatBoton, abrirChat, borrarCuenta, horarioTxt,
    get cuenta() { return cuenta; },
    get publica() { return publica; }
  };
})(window);
