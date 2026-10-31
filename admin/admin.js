/* BiciTaller · Panel del administrador general: talleres, usuarios y ajustes propios.
   Precios, planes, textos, avisos a todos, pagos Premium y versiones se manejan en el Centro de Mando. */
(async function () {
  'use strict';
  const { $, esc, plata, rpc, toast, modal, confirmar } = App;
  App.registrarSW();
  const yo = await App.requerir(['admin', 'socio']);
  let pub = await App.cargarPublica();
  App.colorApp();
  // Socio: ve todo, no crea ni elimina, y cada cambio lleva un motivo (te llega como aviso y queda en el Registro).
  const socio = yo.rol === 'socio';
  if (socio) { $('hRol').textContent = 'SOCIO'; document.querySelectorAll('.solo-admin').forEach((x) => x.remove()); }
  function pedirMotivo(que) {
    if (!socio) return Promise.resolve(null);
    return new Promise((ok) => {
      const d = modal('<h2>✏️ Motivo del cambio</h2><p class="muted" style="margin-top:0">' + esc(que) + '. El administrador recibe el aviso con tu motivo.</p>' +
        '<textarea id="moTxt" maxlength="200" placeholder="Ej.: compensación por una falla del sistema"></textarea><p class="err" id="moErr"></p>' +
        '<div class="btns"><button class="ghost" data-cerrar>Cancelar</button><button id="moOk">Guardar cambio</button></div>');
      let r = null;
      d.querySelector('#moOk').onclick = () => {
        const v = d.querySelector('#moTxt').value.trim();
        if (v.length < 5) { d.querySelector('#moErr').textContent = 'Escribe el motivo (mínimo 5 letras)'; return; }
        r = v; d.close();
      };
      d.addEventListener('close', () => ok(r));
    });
  }
  const MB = (b) => (b / 1048576).toFixed(1) + ' MB';

  const show = App.pestanas((v) => {
    if (v === 'resumen') verResumen();
    if (v === 'talleres') cargarTalleres();
    if (v === 'clientes') cargarClientes();
    if (v === 'ajustes') verAjuste();
  });

  /* ---------- Resumen y servidor ---------- */
  async function verResumen() {
    let r;
    pub = await App.cargarPublica();
    try { r = await rpc('admin_resumen'); }
    catch (e) { $('v-resumen').innerHTML = '<p class="err">' + esc(e.message) + '</p>'; return; }
    $('v-resumen').innerHTML =
      '<div class="stats">' +
      [['🚲 Talleres', r.talleres], ['⭐ Talleres Premium', r.talleres_premium], ['🟢 Activos 7 días', r.talleres_activos_7d], ['⏳ Vencen en 7 días', r.por_vencer],
        ['👥 Clientes con cuenta', r.clientes], ['⭐ Clientes Premium', r.clientes_premium], ['🔧 Personas de equipo', r.equipo], ['📅 Reservas este mes', r.reservas_mes],
        ['📅 Reservas hoy', r.reservas_hoy], ['💰 Ingresos del mes', plata(r.ingresos_mes)], ['🆕 Talleres nuevos (7 días)', r.talleres_nuevos_7d == null ? '—' : r.talleres_nuevos_7d]].map((x) => '<div class="card"><span>' + x[0] + '</span><b>' + x[1] + '</b></div>').join('') + '</div>' +
      '<div class="card"><h2>🧹 Limpieza</h2>' +  // el uso del servidor se ve en el Centro de Mando

      (socio ? '' : '<p class="sub">Se hace sola todos los días a las 4 AM. También puedes limpiar ahora:</p>' +
      '<div class="btns"><button class="ghost small" data-l="comprobantes">Comprobantes revisados</button><button class="ghost small" data-l="notificaciones">Avisos viejos</button>' +
      '<button class="ghost small" data-l="fotos">Fotos más antiguas que ' + ((pub.config || {}).dias_fotos || 365) + ' días</button>' +
      '<button class="ghost small" data-l="reservas">Reservas expiradas/rechazadas (+60 días)</button><button class="danger small" data-l="todo">Limpiar todo</button></div>') +
      '<p class="sub">Versión de la base de datos: ' + esc(r.version) + ' · App: ' + esc(window.BT_CONFIG.VERSION) + '</p></div>';
    $('v-resumen').onclick = async (e) => {
      const ir = e.target.closest('[data-ir]');
      if (ir) { show(ir.dataset.ir); return; }
      const b = e.target.closest('[data-l]'); if (!b) return;
      if (!await confirmar(b.dataset.l === 'comprobantes' ? 'Se borran TODOS los comprobantes ya revisados (los en revisión se mantienen). ¿Seguir?' : '¿Limpiar ahora?')) return;
      try { const x = await rpc('limpiar', { p_que: b.dataset.l }); toast('🧹 Borrados: ' + x.comprobantes + ' comprobantes, ' + x.notificaciones + ' avisos, ' + x.reservas + ' reservas, ' + (x.fotos || 0) + ' fotos'); verResumen(); }
      catch (err) { toast(err.message); }
    };
  }

  /* ---------- Talleres ---------- */
  let talleres = [], tFiltro = '';
  if (!socio) $('nPass').value = App.clave();
  document.querySelectorAll('.nRegalo').forEach((x) => { x.textContent = (pub.config || {}).dias_regalo_taller || 30; });
  // Registro abierto: link y QR para publicar (un mismo link sirve a talleres y ciclistas).
  const linkRegistro = App.ROOT + 'n/';
  $('rLink').textContent = linkRegistro; $('rDir').href = App.ROOT + 'd/';
  $('rCerrado').classList.toggle('hidden', String((pub.config || {}).registro_talleres) !== '0');
  $('rCompartir').onclick = () => App.compartir(linkRegistro, '🚲 ¿Tienes un taller de bicicletas? Crea tu cuenta gratis en BiciTaller y recibe reservas online. ¿Eres ciclista? Encuentra tu taller aquí', 'BiciTaller');
  $('rQR').onclick = () => App.verQR({ url: linkRegistro, titulo: 'QR para crear cuentas', archivo: 'bicitaller-registro.gif',
    afiche: { titulo: '🚲 BiciTaller', texto: '¿Tienes un taller? Crea tu cuenta gratis y recibe reservas online. ¿Eres ciclista? Encuentra tu taller y reserva tu hora.' } });
  async function cargarTalleres() {
    try { talleres = await rpc('admin_talleres'); } catch (e) { $('tLista').innerHTML = '<p class="err">' + esc(e.message) + '</p>'; return; }
    pintarTalleres();
  }
  $('tBuscar').oninput = pintarTalleres;
  $('tSeg').onclick = (e) => { const b = e.target.closest('[data-f]'); if (!b) return; tFiltro = b.dataset.f; $('tSeg').querySelectorAll('button').forEach((x) => x.classList.toggle('on', x === b)); pintarTalleres(); };
  function pintarTalleres() {
    const f = $('tBuscar').value.trim().toLowerCase(), semana = Date.now() - 7 * 864e5, enSiete = Date.now() + 7 * 864e5;
    const l = talleres.filter((t) => (!f || (t.nombre + ' ' + t.email + ' ' + t.comuna + ' ' + t.dueno).toLowerCase().includes(f)) && (
      !tFiltro || (tFiltro === 'premium' && t.premium) || (tFiltro === 'free' && !t.premium) || (tFiltro === 'suspendidos' && t.suspendido) || (tFiltro === 'solos' && t.autoregistro) ||
      (tFiltro === 'vence' && t.premium && new Date(t.premium_hasta) < enSiete) || (tFiltro === 'inactivos' && (!t.visto_at || new Date(t.visto_at) < semana))));
    $('tLista').innerHTML = l.length ? l.map((t) => {
      const logo = /^data:image/.test(t.logo || '') ? 'background-image:url(\'' + t.logo + '\');' : '';
      return '<div class="card"><div style="display:flex;gap:12px;align-items:flex-start"><div class="mini-logo" style="background-color:' + esc(t.color) + ';' + logo + '">' + (logo ? '' : esc(t.icono)) + '</div>' +
        '<div class="grow"><b>' + esc(t.nombre) + '</b> ' + (t.premium ? '<span class="pill pro">PREMIUM</span>' : '<span class="pill">GRATIS</span>') + (t.suspendido ? ' <span class="pill bad">Suspendido</span>' : '') +
        (t.cobra_abono ? '' : ' <span class="pill warn">Sin link de abono</span>') + (t.autoregistro ? ' <span class="pill info">🆕 Se registró solo</span>' : '') +
        (t.referido_por ? ' <span class="pill">🤝 Invitado por ' + esc(t.referido_por) + '</span>' : '') + (t.invitados ? ' <span class="pill ok">🤝 Invitó a ' + t.invitados + '</span>' : '') +
        '<div class="sub">' + esc(t.dueno || '') + ' · ' + esc(t.email || '') + (t.comuna ? ' · ' + esc(t.comuna) : '') + '</div>' +
        '<div class="sub">' + (t.premium ? '⭐ Premium hasta ' + new Date(t.premium_hasta).toLocaleDateString('es-CL') : t.premium_hasta ? 'Premium venció el ' + new Date(t.premium_hasta).toLocaleDateString('es-CL') : 'Nunca fue Premium') +
        ' · 🟢 visto ' + App.hace(t.visto_at) + '</div>' +
        '<div class="sub">👥 ' + t.clientes + ' clientes (' + t.clientes_cuenta + ' con cuenta) · 🔧 ' + t.equipo + ' equipo · 📅 ' + t.reservas_mes + ' reservas este mes (' + t.reservas_total + ' total) · 🛠️ ' + t.servicios +
        ' servicios · 🏷️ ' + t.promos + ' promos · ' + App.nota(t.nota) + '</div></div></div>' +
        '<div class="acc"><select data-prem="' + t.id + '" aria-label="Premium"><option value="">⭐ Premium…</option><option value="7">+7 días</option><option value="30">+30 días</option><option value="90">+90 días</option>' +
        '<option value="365">+1 año</option><option value="otro">Otro número de días…</option><option value="0">Quitar Premium</option></select>' +
        '<a class="btn small ghost" target="_blank" rel="noopener" href="../t/?s=' + encodeURIComponent(t.slug) + '">🔗 Página</a>' +
        (t.telefono ? '<a class="btn small alt" target="_blank" rel="noopener" href="' + App.wa(t.telefono, 'Hola ' + (t.dueno || '') + ' 👋') + '">📲</a>' : '') +
        '<button class="small ghost" data-chat="' + t.id + '" data-n="' + esc(t.nombre) + '">💬</button>' + (socio ? '' : '<button class="small alt" data-add="' + t.id + '" data-n="' + esc(t.nombre) + '">👤＋</button>') +
        '<button class="small ' + (t.suspendido ? 'okb' : 'danger') + '" data-susp="' + t.id + '" data-s="' + (t.suspendido ? 0 : 1) + '">' + (t.suspendido ? 'Reactivar' : 'Suspender') + '</button>' +
        '<button class="small danger" data-del="' + t.id + '" data-n="' + esc(t.nombre) + '">🗑️</button></div></div>';
    }).join('') : '<p class="empty">No hay talleres aquí.</p>';
  }
  $('tLista').onchange = async (e) => {
    const s = e.target.closest('[data-prem]'); if (!s || !s.value) return;
    let dias = s.value === 'otro' ? parseInt(prompt('¿Cuántos días de Premium?'), 10) : +s.value;
    s.value = '';
    if (isNaN(dias)) return;
    if (dias === 0 && !await confirmar('¿Quitar el Premium a este taller? Vuelve a la versión gratis.')) return;
    const motivo = await pedirMotivo(dias ? 'Dar ' + dias + ' días de Premium' : 'Quitar el Premium'); if (socio && !motivo) return;
    try { await rpc('admin_premium', { p_tipo: 'taller', p_id: s.dataset.prem, p_dias: dias, p_motivo: motivo }); App.sb.functions.invoke('servidor').catch(() => {}); toast(dias ? '⭐ +' + dias + ' días' : 'Premium quitado'); cargarTalleres(); }
    catch (err) { toast(err.message); }
  };
  $('tLista').onclick = async (e) => {
    const ch = e.target.closest('[data-chat]'); if (ch) { App.abrirChat(ch.dataset.chat, null, ch.dataset.n); return; }
    const ad = e.target.closest('[data-add]'); if (ad) { agregarUsuario(ad.dataset.add, ad.dataset.n); return; }
    const dl = e.target.closest('[data-del]');
    if (dl) {
      if (!await confirmar('¿ELIMINAR "' + dl.dataset.n + '" con todo: equipo, clientes con cuenta, reservas y comprobantes?\nNo se puede deshacer.', 'Sí, eliminar todo')) return;
      const motivo = await pedirMotivo('Eliminar el taller "' + dl.dataset.n + '"'); if (socio && !motivo) return;
      try { const r = await App.borrarCuenta('taller', dl.dataset.del, motivo); toast('🗑️ Taller eliminado (' + r.borrados + ' cuentas)'); cargarTalleres(); } catch (err) { toast(err.message); }
      return;
    }
    const b = e.target.closest('[data-susp]'); if (!b) return;
    if (b.dataset.s === '1' && !await confirmar('¿Suspender el taller? Ni el taller ni su equipo podrán entrar y su página se cierra.')) return;
    const motivo = await pedirMotivo(b.dataset.s === '1' ? 'Suspender el taller' : 'Reactivar el taller'); if (socio && !motivo) return;
    try { await rpc('admin_suspender', { p_tipo: 'taller', p_id: b.dataset.susp, p_suspender: b.dataset.s === '1', p_motivo: motivo }); cargarTalleres(); } catch (err) { toast(err.message); }
  };
  if (!socio) $('nCrear').onclick = async () => {
    const b = $('nCrear'); $('nErr').textContent = '';
    const d = { taller_nombre: $('nTaller').value.trim(), nombre: $('nDueno').value.trim(), email: $('nEmail').value.trim(), telefono: $('nTel').value.trim(), password: $('nPass').value.trim(), rol: 'taller' };
    if (!d.taller_nombre || !d.nombre || !d.email) { $('nErr').textContent = 'Completa el nombre del taller, del dueño y el correo'; return; }
    b.disabled = true; b.textContent = 'Creando…';
    try {
      await App.crearCuenta(d);
      const msg = App.mensajeAcceso({ nombre: d.nombre.split(' ')[0], email: d.email, password: d.password, lugar: 'BiciTaller (' + d.taller_nombre + ')' }) +
        '\n\nTienes ' + ((pub.config || {}).dias_regalo_taller || 30) + ' días de Premium de regalo 🎁';
      modal('<h2>✅ Taller creado</h2><p class="muted">Envíale sus datos de acceso:</p><pre class="link" style="white-space:pre-wrap;font:inherit">' + esc(msg) + '</pre><div class="btns"><button class="ghost" data-cerrar>Cerrar</button>' +
        (d.telefono ? '<a class="btn" target="_blank" rel="noopener" href="' + App.wa(d.telefono, msg) + '">📲 Enviar por WhatsApp</a>' : '') + '</div>');
      ['nTaller', 'nDueno', 'nEmail', 'nTel'].forEach((k) => { $(k).value = ''; }); $('nPass').value = App.clave();
      cargarTalleres();
    } catch (e) { $('nErr').textContent = e.message; }
    b.disabled = false; b.textContent = 'Crear taller';
  };

  // Agregar un mecánico o un cliente a un taller.
  function agregarUsuario(tid, nombre) {
    const d = modal('<h2>👤 Agregar a ' + esc(nombre) + '</h2><label for="uR">Tipo</label><select id="uR"><option value="cliente">Cliente</option><option value="equipo">Equipo (mecánico)</option></select>' +
      '<div class="row"><div><label for="uN">Nombre</label><input id="uN" maxlength="80"></div><div><label for="uT">WhatsApp</label><input id="uT" inputmode="tel"></div></div>' +
      '<label for="uE">Correo</label><input id="uE" type="email" autocomplete="off"><label for="uP">Contraseña</label><input id="uP" value="' + App.clave() + '">' +
      '<div class="btns"><button class="ghost" data-cerrar>Cancelar</button><button id="uOk">Crear</button></div><p class="err" id="uErr"></p>');
    d.querySelector('#uOk').onclick = async () => {
      const v = (id) => d.querySelector(id).value.trim();
      const x = { rol: v('#uR'), nombre: v('#uN'), telefono: v('#uT'), email: v('#uE'), password: v('#uP'), taller_id: tid };
      try {
        await App.crearCuenta(x);
        const msg = App.mensajeAcceso({ nombre: x.nombre.split(' ')[0], email: x.email, password: x.password, lugar: nombre });
        d.close();
        modal('<h2>✅ Cuenta creada</h2><pre class="link" style="white-space:pre-wrap;font:inherit">' + esc(msg) + '</pre><div class="btns"><button class="ghost" data-cerrar>Cerrar</button>' +
          (x.telefono ? '<a class="btn" target="_blank" rel="noopener" href="' + App.wa(x.telefono, msg) + '">📲 WhatsApp</a>' : '') + '</div>');
        cargarTalleres();
      } catch (err) { d.querySelector('#uErr').textContent = err.message; }
    };
  }

  /* ---------- Usuarios (clientes y equipo) ---------- */
  let clientes = [];
  async function cargarClientes() {
    try { clientes = await rpc('admin_clientes'); } catch (e) { $('cLista').innerHTML = '<li class="err">' + esc(e.message) + '</li>'; return; }
    const ts = Array.from(new Map(clientes.map((c) => [c.taller_id, c.taller])).entries());
    const sel = $('cTaller').value;
    $('cTaller').innerHTML = '<option value="">Todos los talleres</option>' + ts.map(([id, n]) => '<option value="' + id + '"' + (id === sel ? ' selected' : '') + '>' + esc(n) + '</option>').join('');
    pintarClientes();
  }
  $('cBuscar').oninput = pintarClientes; $('cTaller').onchange = pintarClientes;
  function pintarClientes() {
    const f = $('cBuscar').value.trim().toLowerCase(), t = $('cTaller').value;
    const l = clientes.filter((c) => (!f || (c.nombre + ' ' + c.email + ' ' + c.telefono).toLowerCase().includes(f)) && (!t || c.taller_id === t));
    $('cCuenta').textContent = l.length + ' usuarios · ' + l.filter((c) => c.premium).length + ' Premium';
    $('cLista').innerHTML = l.length ? l.slice(0, 500).map((c) => '<li><div class="grow"><b>' + esc(c.nombre || c.email) + '</b> ' + (c.rol === 'equipo' ? '<span class="pill info">Equipo</span> ' : '') + (c.premium ? '<span class="pill pro">PREMIUM</span> ' : '') +
      (c.suspendido ? '<span class="pill bad">Suspendido</span> ' : '') + App.nota(c.nota) + '<div class="sub">' + esc(c.email) + ' · ' + esc(c.telefono) + ' · ' + esc(c.taller || '') + ' · ' + c.visitas + ' visitas · visto ' + App.hace(c.visto_at) +
      (c.premium ? ' · Premium hasta ' + new Date(c.premium_hasta).toLocaleDateString('es-CL') : '') + '</div></div>' +
      '<select data-cp="' + c.id + '" style="width:auto" aria-label="Acción"><option value="">Acción…</option><option value="30">⭐ +30 días</option><option value="90">⭐ +90 días</option><option value="0">Quitar Premium</option>' +
      '<option value="' + (c.suspendido ? 'react' : 'susp') + '">' + (c.suspendido ? 'Reactivar' : 'Suspender') + '</option>' + '<option value="del">🗑️ Eliminar</option>' + '</select></li>').join('') : '<li class="muted">Sin usuarios.</li>';
  }
  $('cLista').onchange = async (e) => {
    const s = e.target.closest('[data-cp]'); if (!s || !s.value) return;
    const v = s.value; s.value = '';
    try {
      if (v === 'del') {
        if (!await confirmar('¿Eliminar este usuario? Sus reservas quedan, sin la cuenta. No se puede deshacer.', 'Sí, eliminar')) return;
        const motivo = await pedirMotivo('Eliminar al usuario'); if (socio && !motivo) return;
        await App.borrarCuenta('perfil', s.dataset.cp, motivo);
      } else {
        const motivo = await pedirMotivo(v === 'susp' ? 'Suspender al usuario' : v === 'react' ? 'Reactivar al usuario' : +v ? 'Dar ' + v + ' días de Premium' : 'Quitar el Premium');
        if (socio && !motivo) return;
        if (v === 'susp' || v === 'react') await rpc('admin_suspender', { p_tipo: 'perfil', p_id: s.dataset.cp, p_suspender: v === 'susp', p_motivo: motivo });
        else await rpc('admin_premium', { p_tipo: 'cliente', p_id: s.dataset.cp, p_dias: +v, p_motivo: motivo });
      }
      toast('Listo'); cargarClientes();
    } catch (err) { toast(err.message); }
  };

  // Menú de la cuenta (núcleo) → Mi perfil.
  addEventListener('hashchange', () => { if (location.hash === '#cuenta') { show('ajustes'); verAjuste('cuenta'); } });
  /* ---------- Ajustes (cuadrícula del núcleo: solo lo propio de BiciTaller) ---------- */
  let AJ = null, zona = null;
  const aBody = () => zona;
  function verAjuste(k) {
    const S = [
      { k: 'cuenta', ico: '👤', t: 'Mi perfil', d: 'Nombre, WhatsApp, color y clave', f: verCuenta },
      { k: 'reglas', ico: '⚖️', t: 'Reglas', d: 'Días, abonos y límites', f: verReglas },
      socio ? null : { k: 'push', ico: '🔔', t: 'Notificaciones', d: 'Claves push y servidor', f: verPush },
      { k: 'calif', ico: '⭐', t: 'Calificaciones', d: 'Revisar y borrar', f: verCalif },
      socio ? null : { k: 'socios', ico: '🤝', t: 'Socios', d: 'Quién te ayuda y qué puede hacer', f: verSocios },
      { k: 'registro', ico: '📜', t: 'Registro de cambios', d: 'Lo que se hizo en el panel', f: verRegistro }
    ].filter(Boolean).map((x) => Object.assign(x, { abrir: (z) => { zona = z; return x.f(); } }));
    AJ = window.CFX_AJUSTES.montar($('v-ajustes'), S, { arriba: '<p class="muted" style="margin:0 0 10px">Precios, planes, textos, avisos a todos, pagos Premium y versiones se manejan en el Centro de Mando.</p>' });
    if (k) AJ.abrir(k);
  }

  function verReglas() {
    const c = pub.config || {};
    const campos = [['minutos_pago', 'Minutos para pagar el abono y subir el comprobante'], ['minutos_devolucion', 'Minutos para cancelar con devolución del abono'],
      ['horas_cancelacion', 'Horas mínimas para cancelar/reagendar con saldo a favor'], ['dias_saldo', 'Días que dura el saldo a favor'],
      ['dias_regalo_taller', 'Días de Premium de regalo al crear un taller (también si se registra solo)'], ['dias_aviso_vencimiento', 'Días antes del vencimiento para avisar'],
      ['dias_comprobantes', 'Días que se guardan los comprobantes'], ['dias_referido', 'Días de Premium para el taller que invita (cuando el invitado paga su primer Premium; 0 = sin premio)'],
      ['horas_libera_premium', 'Horas antes de la cita en que una hora exclusiva Premium se abre a todos'], ['dias_fotos', 'Días que se guardan las fotos antes/después']];
    aBody().innerHTML = '<div class="card"><h2>⚖️ Reglas</h2>' +
      '<label for="rReg">Registro abierto de talleres (link y QR)</label><select id="rReg" data-c="registro_talleres"><option value="1"' + (String(c.registro_talleres) !== '0' ? ' selected' : '') +
      '>✅ Abierto: cualquier taller crea su cuenta gratis</option><option value="0"' + (String(c.registro_talleres) === '0' ? ' selected' : '') + '>⛔ Cerrado: solo yo creo talleres</option></select>' + campos.map(([k, t]) => '<label>' + esc(t) + '</label><input data-c="' + k + '" inputmode="numeric" value="' + esc(c[k]) + '">').join('') +
      '<label>Tu WhatsApp de soporte</label><input data-c="soporte_whatsapp" data-txt="1" value="' + esc(c.soporte_whatsapp || '') + '" placeholder="+56 9 …">' +
      '<div class="btns"><button id="rG">💾 Guardar reglas</button></div></div>';
    $('rG').onclick = async () => {
      const cambios = Array.from(aBody().querySelectorAll('[data-c]')).map((i) => [i.dataset.c, i.dataset.txt ? i.value.trim() : App.numero(i.value)])
        .filter(([k, val]) => String(c[k]) !== String(val));
      if (!cambios.length) { toast('Sin cambios'); return; }
      const motivo = await pedirMotivo('Cambiar ' + cambios.length + ' regla(s)'); if (socio && !motivo) return;
      try {
        for (const [k, val] of cambios) await rpc('admin_config_guardar', { p_clave: k, p_valor: val, p_motivo: motivo });
        pub = await App.cargarPublica(); toast('⚖️ Reglas guardadas');
        $('rCerrado').classList.toggle('hidden', String((pub.config || {}).registro_talleres) !== '0');
      } catch (e) { toast(e.message); }
    };
  }

  // Textos de la app
  const TXT = { app_nombre: 'Nombre de la app', app_lema: 'Frase de bienvenida', reserva_pago: 'Instrucciones del abono (usa {minutos})',
    reserva_politica: 'Política de cancelación (usa {devolucion} y {horas})', premium_taller_titulo: 'Título Premium taller', premium_taller_texto: 'Texto Premium taller',
    premium_cliente_titulo: 'Título Premium cliente', premium_cliente_texto: 'Texto Premium cliente', pago_instrucciones: 'Instrucciones para pagar Premium',
    bienvenida_taller: 'Bienvenida del taller nuevo', terminos: 'Términos (al crear cuenta)' };
  // Notificaciones push: claves
  function verPush() {
    const pubk = (pub.config || {}).vapid_publica;
    aBody().innerHTML = '<div class="card"><h2>🔔 Notificaciones al celular</h2><p class="muted" style="margin-top:0">' + (pubk ? '✅ Las claves están creadas.' : '⚠️ Falta crear las claves.') +
      ' La función "servidor" las usa para enviar los avisos (guía, pasos 4 y 5).</p><div class="btns"><button id="kG" class="' + (pubk ? 'ghost' : '') + '">' + (pubk ? 'Crear claves nuevas' : 'Crear claves') + '</button>' +
      '<button class="alt" id="kP">Probar función servidor</button><button class="ghost" id="kF">📋 Copiar código de la función</button></div><div id="kPush"></div><p class="sub" id="kR"></p></div>';
    App.ofrecerPush($('kPush'));
    $('kG').onclick = async () => {
      if (pubk && !await confirmar('Al crear claves nuevas, todos deberán activar las notificaciones de nuevo. ¿Seguir?')) return;
      try {
        const k = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
        const raw = new Uint8Array(await crypto.subtle.exportKey('raw', k.publicKey)), jwk = await crypto.subtle.exportKey('jwk', k.privateKey);
        const b64u = (u) => btoa(String.fromCharCode.apply(null, u)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
        await rpc('admin_push_claves', { p_publica: b64u(raw), p_privada: jwk.d });
        pub = await App.cargarPublica(); toast('🔔 Claves creadas'); verPush();
      } catch (e) { toast(e.message); }
    };
    // Solo si cambia la función "servidor": se pega en Supabase → Edge Functions → servidor → Code → Deploy.
    $('kF').onclick = async () => {
      try {
        const t = (await (await fetch(App.ROOT + 'supabase/functions/servidor/corto.ts?_=' + Date.now(), { cache: 'no-store' })).text()).trim();
        if (!/import|serve|Deno/.test(t)) throw new Error('no se pudo leer el código');
        await navigator.clipboard.writeText(t); toast('📋 Copiado: pégalo en Supabase → Edge Functions → servidor → Code → Deploy');
      } catch (e) { toast('No se pudo copiar: ' + e.message); }
    };
    $('kP').onclick = async () => {
      const { data, error } = await App.sb.functions.invoke('servidor', { body: { accion: 'ping' } });
      $('kR').textContent = error ? '❌ No responde: créala en Supabase (guía, paso 4).' : data && data.servicio ? '✅ Funciona (versión ' + data.version + ').' : '⚠️ Responde, pero sin clave de servicio.';
    };
  }

  async function verCalif() {
    let l = [];
    try { l = await rpc('admin_calificaciones'); } catch (e) { aBody().innerHTML = '<p class="err">' + esc(e.message) + '</p>'; return; }
    aBody().innerHTML = '<div class="card"><h2>⭐ Calificaciones</h2><p class="muted" style="margin-top:0">Borra las injustas u ofensivas. Los comentarios solo los ves tú.</p><ul class="list">' +
      (l.map((q) => '<li><div class="grow"><span class="stars">' + App.estrellas(q.estrellas) + '</span> ' + (q.autor === 'cliente' ? esc(q.cliente) + ' → ' + esc(q.taller) : esc(q.taller) + ' → ' + esc(q.cliente)) +
        (q.comentario ? '<div class="sub">“' + esc(q.comentario) + '”</div>' : '') + '<div class="sub">' + App.fHora(q.created_at) + '</div></div>' + '<button class="small danger" data-x="' + q.id + '">Borrar</button>' + '</li>').join('') || '<li class="muted">Sin calificaciones.</li>') + '</ul></div>';
    aBody().onclick = async (e) => {
      const b = e.target.closest('[data-x]'); if (!b || !await confirmar('¿Borrar la calificación?')) return;
      const motivo = await pedirMotivo('Borrar una calificación'); if (socio && !motivo) return;
      try { await rpc('admin_calificacion_borrar', { p_id: b.dataset.x, p_motivo: motivo }); verCalif(); } catch (err) { toast(err.message); }
    };
  }

  async function verRegistro() {
    let l = [];
    try { l = await rpc('admin_auditoria'); } catch (e) { aBody().innerHTML = '<p class="err">' + esc(e.message) + '</p>'; return; }
    aBody().innerHTML = '<div class="card"><ul class="list">' + (l.map((a) => '<li><div class="grow"><b>' + esc(a.accion) + '</b> ' +
      (a.quien_rol === 'socio' ? '<span class="pill info">👥 ' + esc(a.quien_nombre) + '</span> ' : '') + '<span class="sub">' + esc(a.detalle) + '</span></div><span class="sub">' + App.fHora(a.created_at) + '</span></li>').join('') ||
      '<li class="muted">Sin registros.</li>') + '</ul></div>';
    if (!socio) window.CFX_AJUSTES.registro(aBody(), rpc, { recargar: verRegistro });
  }

  // Socios: solo el administrador los crea, suspende o elimina.
  async function verSocios() {
    let l = [];
    try { l = await rpc('admin_socios'); } catch (e) { aBody().innerHTML = '<p class="err">' + esc(e.message) + '</p>'; return; }
    aBody().innerHTML = '<div class="card"><h2>👥 Socios</h2><p class="muted" style="margin-top:0">Un socio entra a este mismo panel y ve todo: talleres, usuarios, pagos y ajustes. ' +
      'Puede chatear con los talleres y aprobar o rechazar pagos. <b>No puede crear</b> talleres ni usuarios, ni cambiar los links de pago, avisos o limpieza. ' +
      'Cada cambio o eliminación que haga (Premium, suspender, eliminar talleres o usuarios, planes, reglas, textos) le pide un <b>motivo</b>: te llega como aviso y queda en 📜 Registro.</p><ul class="list">' +
      (l.map((x) => '<li><div class="grow"><b>' + esc(x.nombre || x.email) + '</b>' + (x.suspendido ? ' <span class="pill bad">Suspendido</span>' : '') +
        '<div class="sub">' + esc(x.email) + ' · visto ' + App.hace(x.visto_at) + ' · ' + x.cambios + ' cambio' + (x.cambios === 1 ? '' : 's') + '</div></div>' +
        '<button class="small ' + (x.suspendido ? 'okb' : 'ghost') + '" data-ss="' + x.id + '" data-s="' + (x.suspendido ? 0 : 1) + '">' + (x.suspendido ? 'Reactivar' : 'Suspender') + '</button>' +
        '<button class="small danger" data-sd="' + x.id + '" data-n="' + esc(x.nombre || x.email) + '">🗑️</button></li>').join('') || '<li class="muted">Aún no tienes socios.</li>') + '</ul>' +
      '<h3>➕ Crear socio</h3><div class="row"><div><label for="soN">Nombre</label><input id="soN" maxlength="80"></div><div><label for="soT">WhatsApp</label><input id="soT" inputmode="tel"></div></div>' +
      '<label for="soE">Correo</label><input id="soE" type="email" autocomplete="off"><label for="soP">Contraseña inicial</label><input id="soP" value="' + App.clave() + '">' +
      '<div class="btns"><button id="soOk">Crear socio</button></div><p class="err" id="soErr"></p></div>';
    $('soOk').onclick = async () => {
      const b = $('soOk'), d = { rol: 'socio', nombre: $('soN').value.trim(), telefono: $('soT').value.trim(), email: $('soE').value.trim(), password: $('soP').value.trim() };
      $('soErr').textContent = '';
      if (!d.nombre || !d.email) { $('soErr').textContent = 'Escribe el nombre y el correo'; return; }
      b.disabled = true; b.textContent = 'Creando…';
      try {
        await App.crearCuenta(d);
        const msg = App.mensajeAcceso({ nombre: d.nombre.split(' ')[0], email: d.email, password: d.password, lugar: 'BiciTaller como socio administrador' });
        modal('<h2>✅ Socio creado</h2><pre class="link" style="white-space:pre-wrap;font:inherit">' + esc(msg) + '</pre><div class="btns"><button class="ghost" data-cerrar>Cerrar</button>' +
          (d.telefono ? '<a class="btn" target="_blank" rel="noopener" href="' + App.wa(d.telefono, msg) + '">📲 Enviar por WhatsApp</a>' : '') + '</div>');
        verSocios();
      } catch (e) { $('soErr').textContent = e.message; b.disabled = false; b.textContent = 'Crear socio'; }
    };
    aBody().onclick = async (e) => {
      const ss = e.target.closest('[data-ss]'), sd = e.target.closest('[data-sd]');
      try {
        if (ss) { await rpc('admin_suspender', { p_tipo: 'perfil', p_id: ss.dataset.ss, p_suspender: ss.dataset.s === '1' }); verSocios(); }
        if (sd) {
          if (!await confirmar('¿Eliminar al socio "' + sd.dataset.n + '"? Ya no podrá entrar. El registro de sus cambios se mantiene.', 'Sí, eliminar')) return;
          await App.borrarCuenta('perfil', sd.dataset.sd); toast('🗑️ Socio eliminado'); verSocios();
        }
      } catch (err) { toast(err.message); }
    };
  }

  // Nombre, WhatsApp, color de la app, modo, contraseña y notificaciones: perfil común del núcleo (CFX_PERFIL).
  function verCuenta() {
    const sop = String((pub.config || {}).soporte_whatsapp || '');
    aBody().innerHTML = '<div class="card" id="uPerfil"></div>' +
      (socio ? '' : '<div class="card"><h2>📲 WhatsApp de soporte</h2><p class="sub" style="margin-top:0">Los talleres y clientes te escriben a este número.</p>' +
        '<input id="uSopT" inputmode="tel" maxlength="30" placeholder="+56 9 1234 5678" value="' + esc(sop || yo.telefono || '') + '"><div class="btns"><button id="uSopG">💾 Guardar</button></div></div>') +
      '<p class="sub">Cada taller elige sus propios colores en Más → Perfil; los clientes Premium, en su cuenta.</p>' +
      '<div class="btns"><button class="danger" id="uS">Cerrar sesión</button></div>';
    window.CFX_PERFIL.montar($('uPerfil'), { alGuardar: async () => { Object.assign(yo, App.cuenta); pub = await App.cargarPublica(); } });
    if ($('uSopG')) $('uSopG').onclick = async () => {
      try { await rpc('admin_config_guardar', { p_clave: 'soporte_whatsapp', p_valor: $('uSopT').value.trim() }); pub = await App.cargarPublica(); toast('💾 Guardado'); } catch (e) { toast(e.message); }
    };
    $('uS').onclick = () => App.salir();
  }


  $('cargando').classList.add('hidden');
  App.campana($('campana'));
  App.pie();
  const h = location.hash.slice(1);
  show(['resumen', 'talleres', 'clientes', 'pagos', 'ajustes'].includes(h) ? h : 'resumen');
})();
