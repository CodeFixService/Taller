/* BiciTaller · Panel del taller (dueño y equipo). */
(async function () {
  'use strict';
  const { $, esc, plata, rpc, q, sb, toast, modal, confirmar } = App;
  App.registrarSW();
  const yo = await App.requerir(['taller', 'equipo']);
  // Núcleo (pagos.js): taller nuevo que debe su primer pago → pantalla de activación.
  if (yo.rol === 'taller') { const ir = () => CFX_PAGOS.revisar({ rpc, salir: () => App.salir() }); if (window.CFX_PAGOS) ir(); else addEventListener('load', ir); }
  const pub = await App.cargarPublica();
  const T = yo.taller_id;

  const ESTADOS = {
    por_pagar: ['⏳ Esperando pago', 'warn'], en_revision: ['🧾 Por revisar', 'info'], confirmada: ['✅ Confirmada', 'ok'],
    recibida: ['🚲 Recibida', 'info'], en_reparacion: ['🔧 En reparación', 'info'], esperando_repuesto: ['📦 Esperando repuesto', 'warn'],
    lista: ['✅ Lista', 'ok'], completada: ['🎉 Completada', 'ok'], no_asistio: ['🚫 No llegó', 'bad'], rechazada: ['❌ Rechazada', 'bad'],
    expirada: ['⌛ Expirada', ''], cancelada: ['❌ Cancelada', 'bad']
  };
  const ABONO = { pendiente: 'Abono pendiente', en_revision: 'Abono por revisar', pagado: 'Abono pagado', rechazado: 'Abono rechazado',
    devolver: '💸 Devolver abono', devuelto: 'Abono devuelto', saldo: 'Saldo a favor', perdido: 'Abono perdido', aplicado: 'Abono aplicado',
    sin_abono: 'Sin abono', no_pagado: 'No pagó' };
  const EN_TALLER = ['recibida', 'en_reparacion', 'esperando_repuesto', 'lista'];
  // G59 🧾 Checklist de revisión (FREE): cada toque cambia sin revisar → ✅ bien → 🔧 ajustado → 🔁 cambiar.
  const CHECK = [['frenos', 'Frenos'], ['cambios', 'Cambios'], ['ruedas', 'Ruedas'], ['neumaticos', 'Neumáticos'], ['cadena', 'Cadena'],
    ['pedalier', 'Pedalier'], ['direccion', 'Dirección'], ['suspension', 'Suspensión'], ['cuadro', 'Cuadro'], ['luces', 'Luces']];
  const CHECK_V = { ok: '✅', ajuste: '🔧', cambio: '🔁' }, CHECK_SIG = { '': 'ok', ok: 'ajuste', ajuste: 'cambio', cambio: '' };
  const COLORES = ['#16a34a', '#059669', '#0891b2', '#2563eb', '#4f46e5', '#7c3aed', '#db2777', '#dc2626', '#ea580c', '#d97706', '#334155', '#111827'];
  const ICONOS = ['🚲', '🚴', '🔧', '🛠️', '⚙️', '🏔️', '🏁', '⚡', '🛞', '🔩'];

  let P = null;           // taller_panel()
  let servicios = [], promos = [];
  let vista = 'hoy';

  /* ---------- Carga ---------- */
  async function cargarPanel() {
    P = await rpc('taller_panel');
    const t = P.taller;
    App.tema(t.color);
    App.pintarLogo($('hLogo'), t);
    $('hNombre').textContent = t.nombre;
    $('tabRev').textContent = P.por_revisar; $('tabRev').classList.toggle('hidden', !P.por_revisar);
    document.querySelectorAll('#mSeg .dueno').forEach((b) => b.classList.toggle('hidden', !P.dueno));
    $('mSeg').querySelector('[data-m=modulos]').classList.toggle('hidden', !P.dueno || !P.venta);  // 🧩 solo con la venta prendida (CM → Apps → 🚲 → 🧩)
    $('mSeg').querySelector('[data-m=stock]').classList.toggle('hidden', !P.dueno && !tiene('stock'));  // G59d 📦: el equipo solo si el taller lo tiene
    ['usadas', 'tradein', 'pasaporte', 'domicilio', 'garantias', 'planes'].forEach((m) => $('mSeg').querySelector('[data-m=' + m + ']').classList.toggle('hidden', !P.dueno && !tiene(m === 'usadas' ? 'certificadas' : m === 'planes' ? 'plan_mant' : m)));  // G59e · G59f · G59i
  }
  // G59 🧩 ¿El taller puede usar este módulo? (venta apagada = todos lo tienen)
  const tiene = (k) => !!(P && P.modulos && P.modulos[k]);
  const recargar = () => setTimeout(() => location.reload(), 1500);
  function ofrecer(k) {
    if (P.dueno && window.CFX_MODULOS_TIENDA) window.CFX_MODULOS_TIENDA.probar(k, { rpc, alCambiar: recargar });
    else toast('Pídele al dueño del taller que active este módulo');
  }
  // G59c 🔔 Aviso "bici lista": al dejarla lista, ventana con el WhatsApp listo (total + link).
  function avisoLista(r) {
    if (!r || !r.telefono || !tiene('aviso_lista')) return;
    const msg = 'Hola ' + String(r.nombre || '').split(' ')[0] + ' 👋 Te escribimos de ' + P.taller.nombre + ': ¡tu bici está lista para retirar! ✅' +
      (r.total ? '\nTotal: ' + plata(r.total) : '') + '\nDetalle y fotos: ' + App.ROOT + 'r/?t=' + r.token;
    modal('<h2>🔔 Avísale a ' + esc(String(r.nombre || '').split(' ')[0]) + '</h2><p class="muted">Su bici está lista. Mándale el aviso con el total y el link. Si no la retira en 2 días, le recordamos solo.</p>' +
      '<div class="btns"><button class="ghost" data-cerrar>Ahora no</button><a class="btn" id="avLista" target="_blank" rel="noopener" href="' + App.wa(r.telefono, msg) + '">📲 Avisar por WhatsApp</a></div>', (d) => { d.querySelector('#avLista').addEventListener('click', () => setTimeout(() => d.close(), 400)); });
  }
  document.addEventListener('click', (e) => { const o = e.target.closest('[data-ofrecer]'); if (o) { e.preventDefault(); ofrecer(o.dataset.ofrecer); } });
  async function cargarCatalogo() {
    [servicios, promos] = await Promise.all([
      q(sb.from('servicios').select('*').eq('taller_id', T).order('orden').order('nombre')),
      q(sb.from('promos').select('*').eq('taller_id', T).order('created_at', { ascending: false }))
    ]);
  }
  const linkReservas = () => App.ROOT + 't/?s=' + P.taller.slug;
  const reservas = (desde, hasta, estados) => rpc('taller_reservas', { p_desde: desde, p_hasta: hasta, p_estados: estados || null });

  /* ---------- Navegación ---------- */
  // #plan y #mas/<sección> (perfil, horario, servicios, abono…): abren esa parte de Más (la guía para partir los usa).
  window.addEventListener('hashchange', () => { if (location.hash === '#mas') { subMas = null; show('mas'); return; } const m = /^#(?:mas\/)?(plan|perfil|horario|servicios|abono|promos|equipo|stats|recordar|cuenta|compartir|modulos|stock|usadas|tradein|pasaporte|domicilio|garantias|planes|caja)$/.exec(location.hash); if (m && (m[1] === 'plan' || /^#mas\//.test(location.hash))) { subMas = m[1]; show('mas'); } });
  const show = App.pestanas((v) => {
    vista = v;
    if (v === 'hoy') pintarHoy();
    if (v === 'agenda') cargarAgenda();
    if (v === 'reservas') cargarReservas();
    if (v === 'clientes') cargarClientes();
    if (v === 'mas') verMas(subMas);
  });

  // En vivo: cualquier cambio en las reservas del taller refresca la vista.
  let refT;
  sb.channel('reservas-' + T).on('postgres_changes', { event: '*', schema: 'public', table: 'reservas', filter: 'taller_id=eq.' + T }, () => {
    clearTimeout(refT);
    refT = setTimeout(async () => {
      try { await cargarPanel(); } catch (e) { return; }
      if (vista === 'hoy') pintarHoy(); else if (vista === 'agenda') cargarAgenda(); else if (vista === 'reservas') cargarReservas();
    }, 600);
  }).subscribe();
  document.addEventListener('visibilitychange', () => { if (!document.hidden && P) cargarPanel().then(() => { if (vista === 'hoy') pintarHoy(); }).catch(() => {}); });

  /* =====================================================================
     HOY
     ===================================================================== */
  function tarjeta(r, extra) {
    const e = ESTADOS[r.estado] || [r.estado, ''];
    return '<div class="card clic" data-r="' + r.id + '"><div style="display:flex;justify-content:space-between;gap:8px;flex-wrap:wrap;align-items:flex-start"><div class="grow"><b>' + esc(r.nombre) + '</b> ' +
      (r.nota_cliente && r.nota_cliente.total ? '<span class="stars">★ ' + String(r.nota_cliente.promedio).replace('.', ',') + '</span> ' : '') +
      (r.faltas ? '<span class="pill bad">' + r.faltas + ' falta' + (r.faltas > 1 ? 's' : '') + '</span>' : '') +
      '<div class="sub">' + App.fCorta(r.fecha) + ' · ' + r.hora + ' · ' + esc(r.servicio_nombre) + (r.bici ? ' · 🚲 ' + esc(r.bici) : '') + '</div>' +
      (r.origen !== 'taller' ? '<div class="sub">' + (r.origen === 'cliente' ? '📱 Cliente con cuenta' : '🌐 Reserva online') + ' · ' + ABONO[r.abono_estado] + (r.abono_monto ? ' ' + plata(r.abono_monto) : '') + '</div>' : '') +
      '</div><span class="pill ' + e[1] + '">' + e[0] + '</span></div>' + (extra || '') + '</div>';
  }
  function botonesRevisar(r) {
    return '<div class="btns" style="margin-top:10px"><button class="small ghost" data-comp="' + r.id + '">👁️ Ver comprobante</button>' +
      '<button class="small okb" data-aprobar="' + r.id + '">Aprobar</button><button class="small danger" data-rechazar="' + r.id + '">Rechazar</button></div>';
  }
  async function pintarHoy() {
    try { await cargarPanel(); } catch (e) { /* sin red: usa lo último */ }
    const t = P.taller, hoy = P.hoy;
    // Lo que falta para recibir reservas online
    const falta = [];
    if (P.dueno) {
      if (!t.logo) falta.push(['perfil', 'Sube tu logo y elige tus colores']);
      if (!servicios.length) falta.push(['servicios', 'Agrega tus servicios y precios (así apareces en el directorio de talleres)']);
      if (!(P.links || []).some((l) => l.activo && l.url)) falta.push(['abono', 'Configura el link de pago del abono (sin esto no recibes reservas online)']);
      if (!t.direccion) falta.push(['perfil', 'Escribe tu dirección']);
    }
    $('bienvenida').innerHTML = falta.length ? '<div class="card"><h2>👋 ' + esc(App.txt('bienvenida_taller') ? 'Para empezar' : '') + '</h2><p class="muted" style="margin-top:0">' +
      esc(App.txt('bienvenida_taller')) + '</p><ul class="list">' + falta.map((f) => '<li class="clic" data-m="' + f[0] + '" style="display:flex;align-items:center;gap:12px"><span aria-hidden="true" style="flex:none;width:22px;height:22px;border-radius:50%;border:2px solid color-mix(in srgb,var(--brand,#0ea5e9) 55%,transparent)"></span><span class="grow">' + esc(f[1]) + '</span><span>›</span></li>').join('') + '</ul></div>' : '';
    $('hStock').innerHTML = tiene('stock') && P.stock_bajo ? '<div class="aviso warn"><div class="grow">📦 ' + P.stock_bajo + ' repuesto' + (P.stock_bajo === 1 ? '' : 's') + ' por pedir a tu proveedor.</div><button class="small" type="button" data-m="stock">🛒 Ver</button></div>' : '';
    $('hDom').innerHTML = tiene('domicilio') && P.domicilio_hoy ? '<div class="aviso"><div class="grow">🚐 ' + P.domicilio_hoy + ' visita' + (P.domicilio_hoy === 1 ? '' : 's') + ' a domicilio hoy.</div><button class="small" type="button" data-m="domicilio">🗺️ Ruta</button></div>' : '';  // G59g
    $('hGar').innerHTML = tiene('garantias') && P.garantia_reclamos ? '<div class="aviso bad"><div class="grow">🛡️ ' + P.garantia_reclamos + ' cliente' + (P.garantia_reclamos === 1 ? ' usó su' : 's usaron su') + ' garantía.</div><button class="small" type="button" data-m="garantias">👀 Ver</button></div>' : '';  // G59h
    $('hPlanes').innerHTML = tiene('plan_mant') && P.planes_vencen ? '<div class="aviso warn"><div class="grow">🔁 ' + P.planes_vencen + ' plan' + (P.planes_vencen === 1 ? '' : 'es') + ' de mantención por vencer: avísales para renovar.</div><button class="small" type="button" data-m="planes">👀 Ver</button></div>' : '';  // G59i
    $('hLink').textContent = linkReservas(); $('hAbrir').href = linkReservas();
    $('kRev').textContent = P.por_revisar; $('kDev').textContent = P.por_devolver;
    // Plan
    const prem = P.premium, hasta = t.premium_hasta ? new Date(t.premium_hasta) : null;
    const dias = hasta ? Math.ceil((hasta - Date.now()) / 864e5) : 0;
    $('hPlanCard').innerHTML = P.dueno ? '<div class="card plan' + (prem ? ' premium' : '') + '"><h2>' + (prem ? '⭐ Premium activo' : 'Plan gratis') + '</h2><p class="muted" style="margin:0">' +
      (prem ? 'Hasta el ' + hasta.toLocaleDateString('es-CL') + (dias <= 3 ? ' · ⚠️ vence en ' + dias + ' día' + (dias === 1 ? '' : 's') : '')
        : 'Reservas online este mes: ' + P.uso.reservas_mes + ' de ' + P.plan.limites.reservas_mes + '.') + '</p>' +
      '<div class="btns"><button class="' + (prem ? 'alt' : 'gold') + '" data-m="plan">' + (prem ? 'Ver mi plan' : '⭐ Activar Premium') + '</button></div></div>' : '';
    let lista = [];
    try { lista = await reservas(hoy, hoy, null); } catch (e) { $('hHoy').innerHTML = '<p class="err">' + esc(e.message) + '</p>'; return; }
    let rev = [], dev = [], pag = [], taller = [];
    try {
      [rev, dev, pag, taller] = await Promise.all([reservas(hoy, hoy, ['en_revision']), reservas(hoy, hoy, ['cancelada']).then((l) => l.filter((r) => r.abono_estado === 'devolver')),
        reservas(hoy, App.sumarDias(hoy, 120), ['por_pagar']), reservas(hoy, hoy, EN_TALLER)]);
    } catch (e) { /* sin red */ }
    pintarReferidos();
    const hoyAct = lista.filter((r) => !['cancelada', 'rechazada', 'expirada', 'por_pagar'].includes(r.estado));
    $('kHoy').textContent = hoyAct.length; $('kTaller').textContent = taller.length;
    pintarTablero(taller);
    $('cRevisar').classList.toggle('hidden', !rev.length);
    $('hRevisar').innerHTML = rev.map((r) => tarjeta(r, botonesRevisar(r))).join('');
    $('hHoy').innerHTML = hoyAct.length ? hoyAct.map((r) => tarjeta(r)).join('') : '<p class="muted" style="margin:0">Sin reservas para hoy.</p>';
    $('cDevolver').classList.toggle('hidden', !dev.length);
    $('hDevolver').innerHTML = dev.map((r) => tarjeta(r, '<div class="btns" style="margin-top:10px"><a class="btn small alt" target="_blank" rel="noopener" href="' +
      App.wa(r.telefono, 'Hola ' + r.nombre.split(' ')[0] + ', te escribimos de ' + P.taller.nombre + ' por la devolución de tu abono de ' + plata(r.abono_monto) + '. ¿A qué cuenta te transferimos?') +
      '">📲 Pedir datos</a><button class="small okb" data-devuelto="' + r.id + '">✓ Ya lo devolví</button></div>')).join('');
    $('cPagando').classList.toggle('hidden', !pag.length);
    $('hPagando').innerHTML = pag.map((r) => '<li><span class="grow"><b>' + esc(r.nombre) + '</b><div class="sub">' + App.fCorta(r.fecha) + ' ' + r.hora +
      ' · vence ' + new Date(r.expira_at).toLocaleTimeString('es-CL', { hour: '2-digit', minute: '2-digit' }) + '</div></span></li>').join('');
  }
  // G59 🚦 Tablero del taller (FREE): una columna por paso; ‹ › mueve la bici y le avisa al cliente.
  let tabLista = [];
  const diasLista = (r) => r.estado === 'lista' && r.lista_at ? Math.floor((Date.now() - new Date(r.lista_at)) / 864e5) : 0;
  // G91 🧑‍🔧 Carga por mecánico: cuántas bicis tiene cada uno en el taller; tocar filtra el tablero.
  let tabMec = ''; try { tabMec = localStorage.getItem('bt-mec') || ''; } catch (e) { /* sin almacenamiento */ }
  function pintarMecs(lista) {
    const n = {}; lista.forEach((r) => { const k = r.mecanico_id || 'sin'; n[k] = (n[k] || 0) + 1; });
    const eq = (P.equipo || []).filter((p) => !p.suspendido || n[p.id]);
    if (tabMec && !n[tabMec] && !eq.some((p) => p.id === tabMec)) tabMec = '';
    $('hMecs').innerHTML = eq.length > 1 || (eq.length && n.sin) ? [['', 'Todos', lista.length]].concat(eq.map((p) => [p.id, p.nombre, n[p.id] || 0]), n.sin ? [['sin', 'Sin asignar', n.sin]] : [])
      .map(([k, nom, c]) => '<button type="button" data-sin-atras data-mec="' + k + '" class="' + (tabMec === k ? 'on' : '') + '" aria-pressed="' + (tabMec === k) + '">' + (k && k !== 'sin' ? '🧑‍🔧 ' : '') + esc(nom) + ' · <b>' + c + '</b></button>').join('') : '';
  }
  function pintarTablero(lista) {
    tabLista = lista;
    pintarMecs(lista);
    $('hTablero').innerHTML = EN_TALLER.map((est, i) => {
      const l = lista.filter((r) => r.estado === est && (!tabMec || (tabMec === 'sin' ? !r.mecanico_id : r.mecanico_id === tabMec)));
      return '<div class="col" data-col="' + est + '"><h3>' + ESTADOS[est][0] + '<b>' + l.length + '</b></h3>' + (l.length ? l.map((r) =>
        '<div class="tj" data-tj="' + r.id + '"><b>' + esc(r.nombre) + '</b>' + (r.bici ? '<div class="sub">🚲 ' + esc(r.bici) + '</div>' : '') +
        (r.mecanico ? '<div class="sub">🧑‍🔧 ' + esc(r.mecanico) + '</div>' : '') + (diasLista(r) >= 1 ? '<div class="sub" style="color:var(--warn)">⏳ Lista hace ' + diasLista(r) + ' día' + (diasLista(r) > 1 ? 's' : '') + '</div>' : '') + '<div class="btns">' +
        (i > 0 ? '<button class="small ghost" type="button" data-sin-atras data-mover="' + r.id + '" data-a="' + EN_TALLER[i - 1] + '" aria-label="Mover a ' + ESTADOS[EN_TALLER[i - 1]][0] + '">‹</button>' : '') +
        '<span class="grow"></span>' + (i < EN_TALLER.length - 1
          ? '<button class="small" type="button" data-mover="' + r.id + '" data-a="' + EN_TALLER[i + 1] + '" aria-label="Pasar a ' + ESTADOS[EN_TALLER[i + 1]][0] + '">›</button>'
          : '<button class="small okb" type="button" data-mover="' + r.id + '" data-a="completada">🎉 Entregar</button>') + '</div></div>').join('')
        : '<p class="sub" style="margin:0">Vacío</p>') + '</div>';
    }).join('');
    $('cTablero').classList.toggle('hidden', !lista.length);
  }
  $('hMecs').addEventListener('click', (e) => {
    const b = e.target.closest('[data-mec]'); if (!b) return;
    e.stopPropagation(); tabMec = b.dataset.mec; try { localStorage.setItem('bt-mec', tabMec); } catch (x) { /* sin almacenamiento */ }
    pintarTablero(tabLista);
  });
  $('hTablero').addEventListener('click', async (e) => {
    const m = e.target.closest('[data-mover]');
    if (m) {
      e.stopPropagation();
      if (m.dataset.a === 'completada' && !await confirmar('¿Entregar la bici al cliente? La orden queda terminada.')) return;
      m.disabled = true;
      try {
        await rpc('taller_estado', { p_id: m.dataset.mover, p_estado: m.dataset.a }); sb.functions.invoke('servidor').catch(() => {}); toast((ESTADOS[m.dataset.a] || [''])[0]);
        if (m.dataset.a === 'lista') avisoLista(tabLista.find((x) => x.id === m.dataset.mover));
        pintarHoy();
      }
      catch (err) { m.disabled = false; toast(err.message); }
      return;
    }
    const tj = e.target.closest('[data-tj]'); if (tj) { volverA = 'hoy'; abrirDetalle(tj.dataset.tj); }
  });
  $('v-hoy').addEventListener('click', async (e) => {
    const ir = e.target.closest('[data-ir]');
    if (ir) { const [v, f] = ir.dataset.ir.split(':'); if (f) filtroR = f; show(v); return; }
    const m = e.target.closest('[data-m]');
    if (m) { subMas = m.dataset.m; show('mas'); return; }
    if (await accionesComunes(e)) return;
    const c = e.target.closest('[data-r]'); if (c) abrirDetalle(c.dataset.r);
  });
  // G74a 🧾 Orden rápida y presupuesto (FREE): sin hora, el cliente está en el mesón.
  function ordenNueva(pres) {
    const d = modal('<h2>' + (pres ? '🧾 Presupuesto' : '＋ Nueva orden') + '</h2><p class="sub" style="margin-top:0">' + (pres ? 'Anota la bici y después agrega los arreglos con su precio para mandárselo.' : 'Para la bici que llega al taller. Queda 🚲 Recibida y se abre la orden.') + '</p>' +
      '<div class="row"><div><label for="oN">Nombre</label><input id="oN" maxlength="80" autocomplete="off"></div><div><label for="oT">WhatsApp</label><input id="oT" inputmode="tel" maxlength="30"></div></div>' +
      '<label for="oB">Bici</label><input id="oB" maxlength="120" placeholder="Elige o escribe: Trek Marlin 5…"><label for="oO">¿Qué trae?</label><input id="oO" maxlength="500" placeholder="Ej: frena mal, cambios saltan">' +
      '<div class="btns"><button class="ghost" data-cerrar>Cancelar</button><button id="oOk">' + (pres ? '🧾 Armar presupuesto' : '✅ Crear orden') + '</button></div><p class="err" id="oErr"></p>');
    if (window.CFX_FABRICA) { CFX_FABRICA.bici(d.querySelector('#oB')); CFX_FABRICA.notas(d.querySelector('#oO')); }
    d.querySelector('#oOk').onclick = async (e) => {
      e.target.disabled = true;
      try {
        const id = await rpc('taller_orden_nueva', { p_nombre: d.querySelector('#oN').value, p_telefono: d.querySelector('#oT').value, p_bici: d.querySelector('#oB').value, p_nota: d.querySelector('#oO').value, p_presupuesto: !!pres });
        d.close(); toast(pres ? '🧾 Agrega los arreglos y envíalo' : '🚲 Orden creada'); volverA = 'hoy'; await abrirDetalle(id);
        const it = $('dItems'); if (it) it.scrollIntoView({ block: 'center' });
      } catch (err) { e.target.disabled = false; d.querySelector('#oErr').textContent = err.message; }
    };
  }
  $('hOrden').onclick = () => ordenNueva(false);
  $('hPres').onclick = () => ordenNueva(true);
  $('hCompartir').onclick = () => compartir(linkReservas(), '🚲 Reserva tu hora en ' + P.taller.nombre);
  $('hQR').onclick = () => App.verQR({ url: linkReservas(), titulo: 'QR de tu página de reservas', archivo: 'qr-' + P.taller.slug + '.gif',
    afiche: { titulo: '🚲 ' + P.taller.nombre, texto: 'Escanea y reserva tu hora online. Sigue el estado de tu bici desde el celular.' } });
  const compartir = (url, texto) => App.compartir(url, texto, P.taller.nombre);

  // Referidos: el dueño invita a otros talleres y gana días de Premium cuando el invitado paga su primer Premium.
  let referidos = null;
  async function pintarReferidos() {
    if (!P.dueno) { $('hReferidos').innerHTML = ''; return; }
    // Si la base de datos aún no se actualiza, igual se muestra el link para invitar.
    try { referidos = await rpc('taller_referidos'); }
    catch (e) { referidos = { slug: P.taller.slug, dias: +((pub.config || {}).dias_referido || 30), abierto: true, invitados: [] }; }
    if (!referidos.abierto || !referidos.dias) { $('hReferidos').innerHTML = ''; return; }
    const inv = referidos.invitados, gan = inv.filter((x) => x.premiado).length;
    $('hReferidos').innerHTML = '<div class="card"><h2>🤝 Invita a otro taller y gana ' + referidos.dias + ' días de Premium</h2><p class="muted" style="margin-top:0">' +
      'Comparte tu link con otro taller: se crea su cuenta gratis y, cuando active su Premium, te regalamos ' + referidos.dias + ' días.</p>' +
      (inv.length ? '<p class="sub">Invitaste a ' + inv.length + ' taller' + (inv.length > 1 ? 'es' : '') + ' · ' + gan + ' ya te dio' + (gan === 1 ? '' : 'eron') + ' Premium: ' +
        inv.map((x) => esc(x.nombre) + (x.premiado ? ' ✅' : ' ⏳')).join(', ') + '</p>' : '') +
      '<div class="btns"><button id="rfCompartir" type="button">📤 Invitar</button><button class="alt" id="rfQR" type="button">QR</button></div></div>';
    const url = App.ROOT + 'n/?ref=' + encodeURIComponent(referidos.slug);
    $('rfCompartir').onclick = () => compartir(url, '🚲 Te recomiendo BiciTaller para recibir reservas online en tu taller. Crea tu cuenta gratis aquí');
    $('rfQR').onclick = () => App.verQR({ url, titulo: 'Invita a otro taller', archivo: 'invita-' + P.taller.slug + '.gif' });
  }

  // Botones que aparecen en varias vistas (comprobante, aprobar, rechazar, devuelto).
  async function accionesComunes(e) {
    const b = e.target.closest('[data-comp],[data-aprobar],[data-rechazar],[data-devuelto]');
    if (!b) return false;
    e.stopPropagation();
    try {
      if (b.dataset.comp) {
        const img = await rpc('taller_comprobante', { p_id: b.dataset.comp });
        if (!img) { toast('El comprobante ya fue borrado'); return true; }
        App.verImagen(img, 'Comprobante del abono', 'comprobante-' + b.dataset.comp.slice(0, 8) + '.jpg');
        return true;
      }
      if (b.dataset.aprobar) {
        if (!await confirmar('Antes de aprobar, revisa en tu Mercado Pago que el abono realmente llegó.\n\n¿Aprobar y confirmar la hora?', 'Sí, aprobar')) return true;
        await rpc('taller_revisar', { p_id: b.dataset.aprobar, p_aprobar: true, p_motivo: null });
        toast('✅ Reserva confirmada');
      }
      if (b.dataset.rechazar) {
        const motivo = await pedirTexto('Rechazar comprobante', 'Motivo (el cliente lo verá)', 'El pago no aparece en nuestra cuenta');
        if (motivo === null) return true;
        await rpc('taller_revisar', { p_id: b.dataset.rechazar, p_aprobar: false, p_motivo: motivo });
        toast('Comprobante rechazado: la hora quedó libre');
      }
      if (b.dataset.devuelto) {
        await rpc('taller_devuelto', { p_id: b.dataset.devuelto });
        toast('💸 Marcado como devuelto');
      }
      sb.functions.invoke('servidor').catch(() => {});
      await cargarPanel();
      if (vista === 'hoy') pintarHoy(); else if (vista === 'reservas') cargarReservas(); else if (vista === 'detalle' && detalle) abrirDetalle(detalle.id);
    } catch (err) { toast(err.message); }
    return true;
  }
  function pedirTexto(titulo, etiqueta, valor) {
    return new Promise((ok) => {
      const d = modal('<h2>' + esc(titulo) + '</h2><label>' + esc(etiqueta) + '</label><input id="ptx" maxlength="300" value="' + esc(valor || '') + '">' +
        '<div class="btns"><button class="ghost" data-cerrar>Cancelar</button><button id="ptok">Aceptar</button></div>');
      let r = null;
      d.querySelector('#ptok').onclick = () => { r = d.querySelector('#ptx').value; d.close(); };
      d.addEventListener('close', () => ok(r));
    });
  }

  /* =====================================================================
     AGENDA (con bloqueos de días y horas)
     ===================================================================== */
  let agFecha = null, agRes = [], agBloq = [];
  async function cargarAgenda() {
    if (!agFecha) { agFecha = P.hoy; $('agFecha').value = agFecha; }
    const desde = App.sumarDias(agFecha, -2), hasta = App.sumarDias(agFecha, 12);
    try {
      [agRes, agBloq] = await Promise.all([reservas(desde, hasta, null), q(sb.from('bloqueos').select('*').eq('taller_id', T).gte('fecha', desde).lte('fecha', hasta))]);
    } catch (e) { $('agSlots').innerHTML = '<p class="err">' + esc(e.message) + '</p>'; return; }
    let html = '';
    for (let i = 0; i <= 14; i++) {
      const f = App.sumarDias(desde, i), d = App.fechaDe(f);
      const n = agRes.filter((r) => r.fecha === f && !['cancelada', 'rechazada', 'expirada'].includes(r.estado)).length;
      const cerrado = !P.taller.dias.includes(d.getDay()) || agBloq.some((b) => b.fecha === f && !b.desde);
      html += '<button type="button" data-f="' + f + '" class="' + (f === agFecha ? 'on' : '') + '" style="' + (cerrado ? 'opacity:.45' : '') + '">' + App.DIAS[d.getDay()] +
        '<b>' + d.getDate() + '</b>' + (n ? n + ' 🚲' : '&nbsp;') + '</button>';
    }
    $('agDias').innerHTML = html;
    const on = $('agDias').querySelector('.on'); if (on) on.scrollIntoView({ inline: 'center', block: 'nearest' });
    pintarDia();
  }
  const mins = (h) => { const [a, b] = String(h).slice(0, 5).split(':').map(Number); return a * 60 + b; };
  const hhmm = (m) => String(Math.floor(m / 60)).padStart(2, '0') + ':' + String(m % 60).padStart(2, '0');
  function pintarDia() {
    const t = P.taller, d = App.fechaDe(agFecha);
    const diaBloq = agBloq.find((b) => b.fecha === agFecha && !b.desde);
    const abierto = t.dias.includes(d.getDay()) && !diaBloq;
    $('agTit').innerHTML = App.fLarga(agFecha) + (abierto ? '' : ' · <span class="pill bad">' + (diaBloq ? '⛔ Bloqueado' + (diaBloq.motivo ? ': ' + esc(diaBloq.motivo) : '') : 'Cerrado') + '</span>');
    const delDia = agRes.filter((r) => r.fecha === agFecha && !['cancelada', 'rechazada', 'expirada'].includes(r.estado));
    const tramos = agBloq.filter((b) => b.fecha === agFecha && b.desde);
    const horas = [];
    const hd = (t.horarios || {})[d.getDay()] || { abre: t.abre, cierra: t.cierra };
    for (let m = mins(hd.abre); m + t.bloque_min <= mins(hd.cierra); m += t.bloque_min) horas.push(m);
    delDia.forEach((r) => { const m = mins(r.hora); if (!horas.includes(m)) horas.push(m); });
    horas.sort((a, b) => a - b);
    const col = t.colacion_desde ? [mins(t.colacion_desde), mins(t.colacion_hasta)] : null;
    $('agSlots').innerHTML = (diaBloq ? '<div class="aviso bad"><div class="grow">Día bloqueado. Nadie puede reservar.</div><button class="small ghost" data-desbloq="' + diaBloq.id + '">Desbloquear</button></div>' : '') +
      horas.map((m) => {
        const rs = delDia.filter((r) => mins(r.hora) <= m && mins(r.hora_fin) > m);
        const empiezan = rs.filter((r) => mins(r.hora) === m);
        const sigue = rs.filter((r) => mins(r.hora) !== m);
        const bq = tramos.find((b) => mins(b.desde) <= m && mins(b.hasta) > m);
        const enCol = col && m >= col[0] && m < col[1];
        const libres = Math.max(t.cupos - rs.length, 0);
        return '<div class="slot"><div class="h">' + hhmm(m) + '</div><div class="c">' +
          empiezan.map((r) => '<div class="res" data-r="' + r.id + '"><b>' + esc(r.nombre) + '</b> <span class="pill ' + (ESTADOS[r.estado] || ['', ''])[1] + '">' + (ESTADOS[r.estado] || [r.estado])[0] +
            '</span><div class="sub">' + esc(r.servicio_nombre) + ' · hasta ' + r.hora_fin + (r.bici ? ' · ' + esc(r.bici) : '') + '</div></div>').join('') +
          sigue.map((r) => '<div class="sub">↳ ' + esc(r.nombre) + ' (sigue)</div>').join('') +
          (bq ? '<div class="res bloq"><b>⛔ Bloqueado</b> ' + esc(bq.motivo || '') + ' <button class="small ghost" data-desbloq="' + bq.id + '">Quitar</button></div>'
            : enCol ? '<div class="sub">🍽️ Colación</div>'
            : abierto ? '<button class="small alt" style="justify-self:start" data-nueva="' + hhmm(m) + '">' + (libres ? '＋ ' + libres + ' libre' + (libres > 1 ? 's' : '') : '＋ Sobrecupo') + '</button>' : '') +
          '</div></div>';
      }).join('');
  }
  $('agFecha').onchange = () => { if ($('agFecha').value) { agFecha = $('agFecha').value; cargarAgenda(); } };
  $('agDias').onclick = (e) => { const b = e.target.closest('[data-f]'); if (b) { agFecha = b.dataset.f; $('agFecha').value = agFecha; cargarAgenda(); } };
  $('agSlots').onclick = async (e) => {
    const n = e.target.closest('[data-nueva]'); if (n) { reservaManual(agFecha, n.dataset.nueva); return; }
    const u = e.target.closest('[data-desbloq]');
    if (u) { try { await q(sb.from('bloqueos').delete().eq('id', u.dataset.desbloq)); toast('Desbloqueado'); cargarAgenda(); } catch (err) { toast(err.message); } return; }
    const c = e.target.closest('[data-r]'); if (c) abrirDetalle(c.dataset.r);
  };
  $('agNueva').onclick = () => reservaManual(agFecha || P.hoy, '');
  $('agBloq').onclick = () => {
    const d = modal('<h2>⛔ Bloquear agenda</h2><p class="muted" style="margin-top:0">Nadie podrá reservar en ese día u horario (feriado, vacaciones, trámite…).</p>' +
      '<label for="bqF">Fecha</label><input type="date" id="bqF" value="' + (agFecha || P.hoy) + '">' +
      '<label class="check"><input type="checkbox" id="bqTodo" checked> Todo el día</label>' +
      '<div class="row hidden" id="bqHoras"><div><label for="bqD">Desde</label><input type="time" id="bqD" value="13:00"></div><div><label for="bqH">Hasta</label><input type="time" id="bqH" value="15:00"></div></div>' +
      '<label for="bqM">Motivo (opcional)</label><input id="bqM" maxlength="80" placeholder="Feriado">' +
      '<div class="btns"><button class="ghost" data-cerrar>Cancelar</button><button id="bqOk">Bloquear</button></div><p class="err" id="bqErr"></p>');
    d.querySelector('#bqTodo').onchange = (ev) => d.querySelector('#bqHoras').classList.toggle('hidden', ev.target.checked);
    d.querySelector('#bqOk').onclick = async () => {
      const todo = d.querySelector('#bqTodo').checked;
      try {
        await q(sb.from('bloqueos').insert({ taller_id: T, fecha: d.querySelector('#bqF').value, desde: todo ? null : d.querySelector('#bqD').value,
          hasta: todo ? null : d.querySelector('#bqH').value, motivo: d.querySelector('#bqM').value.trim() }));
        d.close(); toast('⛔ Bloqueado'); agFecha = d.querySelector('#bqF').value; $('agFecha').value = agFecha; cargarAgenda();
      } catch (err) { d.querySelector('#bqErr').textContent = err.message; }
    };
  };

  // Reserva que toma el taller (por teléfono o en el mesón): sin abono.
  function reservaManual(fecha, hora) {
    const d = modal('<h2>📅 Nueva reserva</h2><p class="sub" style="margin-top:0">Para clientes que reservan por teléfono o en el taller (sin abono).</p>' +
      '<label for="mS">Servicio</label><select id="mS"><option value="">Revisión general</option>' + servicios.filter((s) => s.activo && !s.adicional).map((s) => '<option value="' + s.id + '">' + esc(s.nombre) + ' · ' + s.duracion_min + ' min</option>').join('') + '</select>' +
      '<div class="row"><div><label for="mF">Fecha</label><input type="date" id="mF" value="' + fecha + '"></div><div><label for="mH">Hora</label><input type="time" id="mH" value="' + hora + '" step="300"></div></div>' +
      '<div class="row"><div><label for="mN">Nombre</label><input id="mN" maxlength="80"></div><div><label for="mT">WhatsApp</label><input id="mT" inputmode="tel" maxlength="30"></div></div>' +
      '<label for="mB">Bici</label><input id="mB" maxlength="120" placeholder="Elige o escribe: Trek Marlin 5…"><label for="mO">Nota</label><input id="mO" maxlength="500">' +
      '<label class="check"><input type="checkbox" id="mSc"> Agendar aunque no haya cupo (sobrecupo)</label>' +
      '<div class="btns"><button class="ghost" data-cerrar>Cancelar</button><button id="mOk">Guardar</button></div><p class="err" id="mErr"></p>');
    if (window.CFX_FABRICA) { CFX_FABRICA.bici(d.querySelector('#mB')); CFX_FABRICA.notas(d.querySelector('#mO')); }
    d.querySelector('#mOk').onclick = async () => {
      try {
        await rpc('taller_reserva_manual', { p_fecha: d.querySelector('#mF').value, p_hora: d.querySelector('#mH').value, p_servicio: d.querySelector('#mS').value || null,
          p_nombre: d.querySelector('#mN').value, p_telefono: d.querySelector('#mT').value, p_bici: d.querySelector('#mB').value, p_nota: d.querySelector('#mO').value,
          p_sobrecupo: d.querySelector('#mSc').checked });
        d.close(); toast('📅 Reserva guardada'); agFecha = d.querySelector('#mF').value; $('agFecha').value = agFecha;
        if (vista === 'agenda') cargarAgenda(); else show('agenda');
      } catch (err) { d.querySelector('#mErr').textContent = err.message; }
    };
  }

  /* =====================================================================
     RESERVAS (por estado) y DETALLE / TRABAJO
     ===================================================================== */
  let filtroR = 'revisar', listaR = [];
  $('rSeg').onclick = (e) => { const b = e.target.closest('[data-f]'); if (b) { filtroR = b.dataset.f; cargarReservas(); } };
  $('rBuscar').oninput = pintarReservas;
  async function cargarReservas() {
    $('rSeg').querySelectorAll('button').forEach((b) => b.classList.toggle('on', b.dataset.f === filtroR));
    const hoy = P.hoy;
    try {
      listaR = filtroR === 'revisar' ? await reservas(hoy, hoy, ['en_revision'])
        : filtroR === 'proximas' ? await reservas(hoy, App.sumarDias(hoy, 120), ['confirmada'])
        : filtroR === 'taller' ? await reservas(hoy, hoy, EN_TALLER)
        : filtroR === 'pagando' ? await reservas(hoy, hoy, ['por_pagar'])
        : filtroR === 'devolver' ? (await reservas(hoy, hoy, ['cancelada'])).filter((r) => r.abono_estado === 'devolver')
        : (await reservas(App.sumarDias(hoy, -90), App.sumarDias(hoy, 1), null)).filter((r) => ['completada', 'no_asistio', 'cancelada', 'rechazada', 'expirada'].includes(r.estado)).reverse();
    } catch (e) { $('rLista').innerHTML = '<p class="err">' + esc(e.message) + '</p>'; return; }
    pintarReservas();
  }
  function pintarReservas() {
    const f = $('rBuscar').value.trim().toLowerCase();
    const l = listaR.filter((r) => !f || (r.nombre + ' ' + r.telefono + ' ' + r.bici + ' ' + r.servicio_nombre).toLowerCase().includes(f));
    $('rLista').innerHTML = l.length ? l.slice(0, 200).map((r) => tarjeta(r, r.estado === 'en_revision' ? botonesRevisar(r)
      : r.abono_estado === 'devolver' ? '<div class="btns" style="margin-top:10px"><button class="small okb" data-devuelto="' + r.id + '">✓ Ya lo devolví</button></div>' : '')).join('')
      : '<p class="empty">Nada por aquí.</p>';
  }
  $('rLista').onclick = async (e) => {
    if (await accionesComunes(e)) return;
    const c = e.target.closest('[data-r]'); if (c) abrirDetalle(c.dataset.r);
  };

  let detalle = null, items = [];
  async function abrirDetalle(id) {
    let r = null;
    try { r = (await rpc('taller_reservas', { p_desde: P.hoy, p_hasta: P.hoy, p_estados: null, p_id: id }))[0]; }
    catch (e) { toast(e.message); return; }
    if (!r) { toast('No encontré la reserva'); return; }
    detalle = r; items = JSON.parse(JSON.stringify(r.items || [])); fotosR = [];
    // Reserva online sin detalle todavía: parte con el servicio reservado.
    if (!items.length && r.servicio_id && r.precio) items = [{ nombre: r.servicio_nombre, cant: 1, precio: r.precio }];
    const e = ESTADOS[r.estado] || [r.estado, ''];
    const trabajando = ['confirmada'].concat(EN_TALLER, ['completada']).includes(r.estado);
    const sig = { confirmada: ['recibida', '🚲 Recibir bici'], recibida: ['en_reparacion', '🔧 En reparación'], en_reparacion: ['lista', '✅ Lista'],
      esperando_repuesto: ['en_reparacion', '🔧 Volver a reparación'], lista: ['completada', '🎉 Entregada'] }[r.estado];
    const equipo = (P.equipo || []).filter((p) => !p.suspendido);
    const msgCliente = {
      confirmada: '¡Te esperamos el ' + App.fLarga(r.fecha) + ' a las ' + r.hora + '!', recibida: 'recibimos tu bici 🚲', en_reparacion: 'tu bici está en reparación 🔧',
      esperando_repuesto: 'estamos esperando un repuesto para tu bici 📦', lista: '¡tu bici está lista para retirar! ✅', completada: '¡gracias por venir! 🙌'
    }[r.estado];
    const link = App.ROOT + 'r/?t=' + r.token;
    $('v-detalle').innerHTML = '<div class="card"><div style="display:flex;gap:8px;align-items:center"><button class="small ghost" id="dVolver">‹ Volver</button><span class="grow"></span>' +
      '<span class="pill ' + e[1] + '">' + e[0] + '</span></div>' +
      '<h2 style="margin-top:12px">' + esc(r.nombre) + ' ' + (r.nota_cliente && r.nota_cliente.total ? '<span class="stars">★ ' + String(r.nota_cliente.promedio).replace('.', ',') + '</span>' : '') +
      (r.faltas ? ' <span class="pill bad">' + r.faltas + ' falta' + (r.faltas > 1 ? 's' : '') + '</span>' : '') + '</h2>' +
      '<div class="muted">' + App.fLarga(r.fecha) + ' · ' + r.hora + '–' + r.hora_fin + (r.entrega_estimada ? ' · 📦 entrega ' + App.fCorta(r.entrega_estimada) : '') + '</div><div class="muted">' + esc(r.servicio_nombre) + (r.precio ? ' · ' + plata(r.precio) : '') + '</div>' +
      (r.bici ? '<div>🚲 ' + esc(r.bici) + '</div>' : '') + (r.domicilio ? '<div id="dDomTxt">🏠 A domicilio: <b>' + esc([r.domicilio.direccion, r.domicilio.comuna].filter(Boolean).join(', ')) + '</b>' + (r.domicilio.ref ? '<div class="sub">' + esc(r.domicilio.ref) + '</div>' : '') + (r.domicilio.camino_at ? '<div class="sub">🚐 Avisado: vamos en camino</div>' : '') + '</div>' : '') + (r.nota ? '<div class="sub">📝 ' + esc(r.nota) + '</div>' : '') +
      '<div class="sub">📞 ' + esc(r.telefono) + (r.email ? ' · ' + esc(r.email) : '') + ' · ' + (r.origen === 'taller' ? 'Reserva del taller' : r.origen === 'cliente' ? 'Cliente con cuenta' : 'Reserva online') + '</div>' +
      '<div class="sub">💳 ' + ABONO[r.abono_estado] + (r.abono_monto ? ' · ' + plata(r.abono_monto) : '') + (r.reagendada ? ' · reagendada ' + r.reagendada + ' vez/veces' : '') + '</div>' +
      (r.motivo ? '<div class="sub">Motivo: ' + esc(r.motivo) + '</div>' : '') +
      '<div class="btns">' + (r.telefono ? '<a class="btn small alt" target="_blank" rel="noopener" href="' + App.wa(r.telefono, 'Hola ' + r.nombre.split(' ')[0] + ' 👋 Te escribimos de ' + P.taller.nombre + ': ' +
        (msgCliente || '') + '\nTu reserva: ' + link) + '">📲 WhatsApp</a>' : '') +
      '<button class="small ghost" id="dLink">🔗 Enlace del cliente</button>' + (tiene('domicilio') && !['completada', 'rechazada', 'expirada', 'cancelada', 'no_asistio'].includes(r.estado) ? '<button class="small ghost" id="dDom" type="button">🚐 ' + (r.domicilio ? 'Domicilio' : 'A domicilio') + '</button>' : '') + (tiene('pasaporte') ? '<button class="small ghost" id="dPas">🪪 Pasaporte</button>' : P.venta && r.bici ? '<button class="small ghost" type="button" data-sin-atras data-ofrecer="pasaporte">🪪 Pasaporte</button>' : '') + (r.estado === 'completada' && r.telefono && tiene('resenas') && P.taller.google_resenas ? '<a class="btn small ghost" id="dGoo" target="_blank" rel="noopener" href="' + esc(App.wa(r.telefono, 'Hola ' + String(r.nombre || '').split(' ')[0] + ' 👋 Gracias por confiar en ' + P.taller.nombre + ' 🚲 ¿Nos ayudas con una reseña en Google? Es 1 minuto: ' + P.taller.google_resenas)) + '">⭐ Pedir reseña</a>' : '') + (['lista', 'completada'].includes(r.estado) ? (tiene('garantias') ? '<button class="small ghost" id="dGar" type="button">🛡️ Garantía</button>' : P.venta ? '<button class="small ghost" type="button" data-sin-atras data-ofrecer="garantias">🛡️ Garantía</button>' : '') : '') + (r.tiene_comprobante ? '<button class="small ghost" data-comp="' + r.id + '">👁️ Comprobante</button>' : '') + '</div>' +
      (r.estado === 'en_revision' ? botonesRevisar(r) : '') +
      (r.estado === 'lista' && !tiene('aviso_lista') && P.venta ? '<div class="aviso" style="margin-top:12px"><div class="grow">🔔 Avísale solo con el total y el link, y recuérdale si no la retira.</div><button class="small" type="button" data-sin-atras data-ofrecer="aviso_lista">🧩 Ver</button></div>' : '') +
      (r.abono_estado === 'devolver' ? '<div class="aviso warn" style="margin-top:12px"><div class="grow">Devuelve el abono de ' + plata(r.abono_monto) + ' al cliente.</div><button class="small okb" data-devuelto="' + r.id + '">✓ Ya lo devolví</button></div>' : '') +
      '</div>' +
      (trabajando ? '<div class="card"><h2>🔧 Estado del trabajo</h2><div class="btns" style="margin-top:0">' + (sig ? '<button id="dSig" data-e="' + sig[0] + '">' + sig[1] + '</button>' : '') +
        (['recibida', 'en_reparacion'].includes(r.estado) ? '<button class="alt" data-e="esperando_repuesto">📦 Esperando repuesto</button>' : '') +
        (r.estado === 'lista' ? '<button class="okb" type="button" id="dCobrar">💵 Cobrar y entregar</button>' : '') +
        (['recibida', 'en_reparacion', 'esperando_repuesto'].includes(r.estado) && r.abono_estado === 'sin_abono' ? '<button class="ghost" data-e="cancelada">❌ Anular</button>' : '') +
        (r.estado === 'confirmada' ? '<button class="danger" data-e="no_asistio">🚫 No llegó</button><button class="danger" data-e="cancelada">Cancelar (devolver abono)</button>' : '') + '</div></div>' +
        '<div class="card"><h2>🧾 Servicios y repuestos</h2><div class="items" id="dItems"></div>' +
        '<div class="row" style="margin-top:6px"><select id="dAddS" aria-label="Agregar servicio"><option value="">＋ Agregar servicio…</option>' +
          servicios.map((s) => '<option value="' + s.id + '">' + esc(s.nombre) + ' · ' + plata(s.precio) + '</option>').join('') + '</select>' +
          '<button class="alt" id="dAddR" type="button" style="flex:0 0 auto">＋ Repuesto</button></div>' +
        '<p style="margin:12px 0 0">Total: <b class="precio" id="dTotal"></b><span class="sub" id="dSaldo"></span></p>' +
        '<div id="dPres"></div><div id="dPlan"></div>' +
        '<label for="dDiag">Diagnóstico (lo ve el cliente)</label><textarea id="dDiag" maxlength="1000">' + esc(r.diagnostico) + '</textarea>' +
        '<label for="dNotas">Notas internas (solo el taller)</label><textarea id="dNotas" maxlength="1000">' + esc(r.notas_internas) + '</textarea>' +
        '<div class="row"><div><label for="dMec">Mecánico</label><select id="dMec"><option value="">Sin asignar</option>' + equipo.map((p) => '<option value="' + p.id + '"' + (p.id === r.mecanico_id ? ' selected' : '') + '>' + esc(p.nombre) + '</option>').join('') + '</select></div>' +
        '<div><label for="dProx">Próxima mantención</label><input type="date" id="dProx" value="' + (r.proxima_mantencion || '') + '"></div></div>' +
        '<div class="btns"><button id="dGuardar">💾 Guardar</button><button class="ghost" onclick="window.print()">🖨️ Imprimir</button></div></div>' +
        '<div class="card"><h2>🧾 Revisión de la bici</h2><p class="sub" style="margin-top:0">Toca cada punto: ✅ bien · 🔧 ajustado · 🔁 hay que cambiar. El cliente lo ve en su enlace.</p><div class="check" id="dCheck"></div></div>' +
        '<div class="card"><h2>📸 Fotos de llegada y entrega</h2><div id="dFotos"></div></div>' : '') +
      (['completada', 'lista', 'no_asistio'].includes(r.estado) ? '<div class="card"><h2>⭐ Califica al cliente</h2><p class="sub" style="margin-top:0">Los otros talleres y clientes solo ven el promedio de estrellas.</p>' +
        (r.calificado ? '<p class="muted">✅ Ya lo calificaste.</p>' : '<div class="row"><select id="dEst"><option value="5">★★★★★ Excelente</option><option value="4">★★★★ Bueno</option><option value="3">★★★ Regular</option>' +
          '<option value="2">★★ Llegó tarde / mal trato</option><option value="1">★ No llegó / problemas</option></select><button id="dCal" style="flex:0 0 auto">Calificar</button></div>' +
          '<input id="dCalTxt" maxlength="300" placeholder="Comentario privado (opcional)" style="margin-top:8px">') + '</div>' : '');
    show('detalle');
    $('dVolver').onclick = () => history.length > 1 ? show(volverA) : show('reservas');
    $('dLink').onclick = () => { navigator.clipboard.writeText(link).then(() => toast('🔗 Enlace copiado')); };
    const dom = $('dDom'); if (dom) dom.onclick = () => editarDomicilio(r, () => abrirDetalle(r.id));  // G59g
    const gar = $('dGar'); if (gar) gar.onclick = () => editarGarantia(null, { reserva: r.id, nombre: r.nombre, telefono: r.telefono, bici: r.bici || r.servicio_nombre, detalle: r.servicio_nombre }, () => abrirDetalle(r.id));  // G59h
    const pas = $('dPas'); if (pas) pas.onclick = () => editarPasaporte(r.pasaporte_id || null, { bici: r.bici, dueno: r.nombre, telefono: r.telefono, reserva: r.id }, () => abrirDetalle(r.id));  // G59f
    $('v-detalle').onclick = async (ev) => {
      if (await accionesComunes(ev)) return;
      if (ev.target.closest('#dCobrar')) { await guardarTrabajo(true); cobrarOrden(r.id, () => abrirDetalle(r.id)); return; }
      const be = ev.target.closest('[data-e]'); if (!be) return;
      const est = be.dataset.e;
      if (['no_asistio', 'cancelada'].includes(est) && !await confirmar(est === 'no_asistio' ? 'El cliente no llegó: pierde el abono. ¿Confirmar?' : r.abono_estado === 'sin_abono' ? '¿Anular esta orden? Sale del tablero.' : 'Cancelar la reserva: tendrás que devolver el abono. ¿Confirmar?')) return;
      try {
        if (est === 'completada' || est === 'lista') await guardarTrabajo(true);
        await rpc('taller_estado', { p_id: r.id, p_estado: est });
        sb.functions.invoke('servidor').catch(() => {});
        toast((ESTADOS[est] || [est])[0]); await abrirDetalle(r.id);
        if (est === 'lista') avisoLista(Object.assign({}, r, { total: detalle && detalle.id === r.id ? detalle.total : r.total }));
      } catch (err) { toast(err.message); }
    };
    if (trabajando) {
      pintarItems();
      // Si cambias un ítem que el cliente ya respondió, vuelve a quedar sin aprobar (se le pide de nuevo).
      if (window.CFX_FABRICA) CFX_FABRICA.repuestos(document.createElement('input'));
      if (tiene('stock')) cargarStock().then(() => { if (ST && detalle && detalle.id === r.id) { listaStock(); pintarItems(); } }).catch(() => {});  // G59d 📦
      $('dItems').oninput = (ev) => {
        const i = ev.target.dataset.i; if (i === undefined) return;
        items[i][ev.target.dataset.k] = ev.target.dataset.k === 'nombre' ? ev.target.value : App.numero(ev.target.value); delete items[i].aprob;
        // 📦 Repuesto de fábrica elegido y sin precio → pone el precio sugerido (se puede cambiar).
        const rs = ev.target.dataset.k === 'nombre' && repDe(ev.target.value);
        const pf = rs ? rs.precio : ev.target.dataset.k === 'nombre' && window.CFX_FABRICA && CFX_FABRICA.precio(ev.target.value);
        if (pf && !items[i].precio) { items[i].precio = pf; const ip = $('dItems').querySelector('[data-i="' + i + '"][data-k=precio]'); if (ip) ip.value = pf; }
        totalItems();
      };
      $('dItems').onclick = async (ev) => {
        const im = ev.target.closest('[data-fver]'); if (im) { App.verImagen(im.src, im.alt, 'dano.jpg'); return; }
        const q = ev.target.closest('[data-fq]'); if (q) { if (!await confirmar('¿Quitar la foto de este ítem?')) return; delete items[+q.dataset.fq].foto; await guardarTrabajo(true).catch(() => {}); pintarFotos(detalle.id); return; }
        const x = ev.target.closest('[data-x]'); if (x) { items.splice(+x.dataset.x, 1); pintarItems(); }
      };
      $('dItems').onchange = async (ev) => {  // G91 📸 foto del daño del ítem
        const fi = ev.target.closest('[data-fi]'); if (!fi || !fi.files[0]) return;
        const f = fi.files[0], i = +fi.dataset.fi; fi.value = '';
        if (!String(items[i].nombre || '').trim()) { toast('Primero escribe qué es el ítem'); return; }
        try {
          const antes = new Set(fotosR.map((x) => x.id));
          fotosR = await rpc('taller_foto_subir', { p_reserva: detalle.id, p_tipo: 'dano', p_imagen: await App.comprimirFoto(f) });
          const nueva = fotosR.find((x) => x.tipo === 'dano' && !antes.has(x.id));
          if (nueva) { items[i].foto = nueva.id; await guardarTrabajo(true); }
          pintarItems(); toast('📸 Foto del daño guardada');
        } catch (err) { toast(err.message); }
      };
      $('dAddS').onchange = () => { const s = servicios.find((x) => x.id === $('dAddS').value); if (s) items.push({ nombre: s.nombre, cant: 1, precio: s.precio }); $('dAddS').value = ''; pintarItems(); };
      $('dAddR').onclick = () => { items.push({ nombre: '', cant: 1, precio: 0 }); pintarItems(); const ins = $('dItems').querySelectorAll('[data-k=nombre]'); ins[ins.length - 1].focus(); };
      $('dGuardar').onclick = () => guardarTrabajo(false);
      pintarPres();
      pintarPlan(r);  // G59i 🔁
      $('dPres').onclick = async (ev) => {
        if (ev.target.closest('#dPresWa')) {  // G74a FREE: el detalle por WhatsApp (sin aprobar en el link)
          const l = items.filter((it) => String(it.nombre || '').trim()), nom = (detalle.nombre || '').split(' ')[0];
          const msg = 'Hola ' + nom + ' 👋 Te escribimos de ' + P.taller.nombre + '. Presupuesto para tu bici' + (detalle.bici ? ' (' + detalle.bici + ')' : '') + ':\n' +
            l.map((it) => '• ' + it.nombre.trim() + ((+it.cant || 1) > 1 ? ' x' + it.cant : '') + ': ' + plata((+it.cant || 1) * (+it.precio || 0))).join('\n') +
            '\nTotal: ' + $('dTotal').textContent + '\n¿Lo hacemos? Responde SÍ 🙌';
          guardarTrabajo(true).catch(() => {}); window.open(App.wa(detalle.telefono, msg), '_blank', 'noopener'); return;
        }
        if (!ev.target.closest('#dPedir')) return;
        if (!tiene('presupuesto')) { ofrecer('presupuesto'); return; }
        try {
          await guardarTrabajo(true);
          const x = await rpc('taller_presupuesto', { p_id: detalle.id });
          sb.functions.invoke('servidor').catch(() => {});
          detalle.presupuesto = { estado: 'enviado' };
          items.forEach((it) => { if (it.aprob !== 'si' && it.aprob !== 'no') it.aprob = 'pend'; });
          pintarItems(); pintarPres(x.pendientes);
          toast('🧾 Presupuesto enviado');
        } catch (err) { toast(err.message); }
      };
      pintarFotos(r.id);
      pintarCheck();
      $('dCheck').onclick = async (ev) => {
        const b = ev.target.closest('[data-ck]'); if (!b) return;
        const k = b.dataset.ck, antes = Object.assign({}, detalle.checklist || {}), v = CHECK_SIG[antes[k] || ''];
        const nuevo = Object.assign({}, antes); if (v) nuevo[k] = v; else delete nuevo[k];
        detalle.checklist = nuevo; pintarCheck();
        try { detalle.checklist = await rpc('taller_checklist', { p_id: detalle.id, p_check: nuevo }); }
        catch (err) { detalle.checklist = antes; pintarCheck(); toast(err.message); }
      };
    }
    const bc = $('dCal');
    if (bc) bc.onclick = async () => {
      try { await rpc('taller_calificar', { p_id: r.id, p_estrellas: +$('dEst').value, p_comentario: $('dCalTxt').value }); toast('⭐ Cliente calificado'); abrirDetalle(r.id); }
      catch (err) { toast(err.message); }
    };
  }
  let volverA = 'reservas';
  // G59 📸 Fotos de llegada y entrega (GRATIS): el cliente las ve en el enlace de su reserva y, si es Premium, siempre en su historial.
  async function pintarFotos(id) {
    const el = $('dFotos');
    let fotos = [];
    try { fotos = await rpc('taller_fotos', { p_reserva: id }); } catch (e) { el.innerHTML = '<p class="err">' + esc(e.message) + '</p>'; return; }
    if (detalle && detalle.id === id) { fotosR = fotos; if ($('dItems') && items.some((it) => it.foto)) pintarItems(); }  // G91 📸 las del daño van en su ítem
    fotos = fotos.filter((f) => f.tipo !== 'dano');
    const n = (t) => fotos.filter((f) => f.tipo === t).length;
    el.innerHTML = '<p class="sub" style="margin-top:0">Hasta 2 al llegar y 2 al entregar. Te cuidan si hay reclamos y el cliente las ve en su enlace.</p>' +
      (fotos.length ? '<div class="fotos">' + fotos.map((f) => '<figure><img alt="Foto ' + f.tipo + '" src="' + f.imagen + '"><figcaption>' + (f.tipo === 'antes' ? 'Llegada' : 'Entrega') + '</figcaption>' +
        '<button class="small danger" type="button" data-fx="' + f.id + '" aria-label="Borrar foto">✕</button></figure>').join('') + '</div>' : '') +
      '<div class="btns">' + ['antes', 'despues'].map((t) => n(t) < 2 ? '<label class="btn alt" style="margin:0;color:var(--brand)">📷 ' + (t === 'antes' ? 'Llegada' : 'Entrega') +
        '<input type="file" accept="image/*" capture="environment" data-ft="' + t + '" hidden></label>' : '').join('') + '</div>';
    el.onchange = async (e) => {
      const i = e.target.closest('[data-ft]'); if (!i || !i.files[0]) return;
      const f = i.files[0]; i.value = '';
      try { await rpc('taller_foto_subir', { p_reserva: id, p_tipo: i.dataset.ft, p_imagen: await App.comprimirFoto(f) }); toast('📷 Foto guardada'); pintarFotos(id); }
      catch (err) { toast(err.message); }
    };
    el.onclick = async (e) => {
      const x = e.target.closest('[data-fx]');
      if (x) { e.stopPropagation(); if (!await confirmar('¿Borrar esta foto?')) return; try { await rpc('taller_foto_borrar', { p_id: x.dataset.fx }); pintarFotos(id); } catch (err) { toast(err.message); } return; }
      const im = e.target.closest('img'); if (im) App.verImagen(im.src, im.alt, 'foto.jpg');
    };
  }
  function pintarCheck() {
    const c = detalle.checklist || {};
    $('dCheck').innerHTML = CHECK.map(([k, n]) => '<button type="button" class="' + (c[k] || '') + '" data-ck="' + k + '" aria-pressed="' + !!c[k] + '">' + (CHECK_V[c[k]] || '⬜') + ' ' + n + '</button>').join('');
  }
  function pintarItems() {
    $('dItems').innerHTML = items.length ? items.map((it, i) => '<div class="it"><input data-i="' + i + '" data-k="nombre" value="' + esc(it.nombre) + '" placeholder="Elige o escribe" aria-label="Descripción" list="' + (ST ? 'stRep' : 'fabRep') + '">' +
      '<input data-i="' + i + '" data-k="cant" value="' + it.cant + '" inputmode="numeric" aria-label="Cantidad"><input data-i="' + i + '" data-k="precio" value="' + it.precio + '" inputmode="numeric" aria-label="Precio">' +
      '<button class="danger" data-x="' + i + '" aria-label="Quitar">✕</button>' + fotoItem(it, i) + (APROB[it.aprob] ? '<div class="ap ' + it.aprob + '">' + APROB[it.aprob] + '</div>' : '') + stockDe(it) + '</div>').join('') : '<p class="sub" style="margin:0">Agrega lo que se hizo y los repuestos.</p>';
    totalItems();
  }
  // G91 📸 Foto del daño por ítem (el cliente la ve al aprobar el presupuesto).
  let fotosR = [];
  const fotoItem = (it, i) => { const f = it.foto && fotosR.find((x) => x.id === it.foto);
    return '<div class="fd">' + (f ? '<img src="' + f.imagen + '" alt="Daño: ' + esc(it.nombre || 'ítem') + '" data-fver><button type="button" class="small ghost" data-fq="' + i + '" data-sin-atras>✕ Quitar foto</button>'
      : it.foto ? '<span class="sub">📸 Foto guardada</span>' : '<label>📷 Foto del daño<input type="file" accept="image/*" capture="environment" data-fi="' + i + '" hidden></label>') + '</div>'; };
  // G59d 📦 Debajo del ítem: cuántos quedan (baja al entregar).
  const stockDe = (it) => { const x = repDe(it.nombre); return x ? '<div class="ap ' + (x.stock < (+it.cant || 1) ? 'no' : x.minimo > 0 && x.stock <= x.minimo ? 'pend' : 'si') + '">📦 ' + (x.stock ? 'Quedan ' + x.stock + ' en stock' : 'Sin stock: pídelo') + '</div>' : ''; };
  const APROB = { pend: '⏳ Esperando al cliente', si: '✅ Aprobado por el cliente', no: '❌ Rechazado: no se cobra' };
  // ✅ Presupuesto por link (módulo): pedir aprobación + qué respondió el cliente.
  function pintarPres(nuevos) {
    const pr = detalle.presupuesto || {}, link = App.ROOT + 'r/?t=' + detalle.token;
    const pend = items.some((it) => it.aprob === 'pend'), sinPedir = items.some((it) => !it.aprob);
    const nom = (detalle.nombre || '').split(' ')[0];
    $('dPres').innerHTML = '<div class="aviso' + (pend ? ' warn' : '') + '" style="margin-top:10px;display:block"><div>' +
      (pend ? '⏳ Esperando que ' + esc(nom) + ' apruebe en su enlace.' : pr.estado === 'respondido' ? '✅ ' + esc(nom) + ' respondió el presupuesto.' : '🧾 ¿Necesitas su OK antes de trabajar? Pídele que apruebe cada arreglo.') + '</div><div class="btns">' +
      (sinPedir && items.length ? '<button type="button" class="small" id="dPedir">✅ Pedir aprobación</button>' : '') +
      (!tiene('presupuesto') && items.length && detalle.telefono ? '<button type="button" class="small alt" id="dPresWa">📲 Enviar presupuesto</button>' : '') +
      ((nuevos || pend) && detalle.telefono ? '<a class="btn small alt" target="_blank" rel="noopener" href="' + App.wa(detalle.telefono, 'Hola ' + nom + ' 👋 Te escribimos de ' + P.taller.nombre +
        ': revisamos tu bici. Aprueba o rechaza cada arreglo aquí 👉 ' + link) + '">📲 Enviar por WhatsApp</a>' : '') + '</div></div>';
  }
  function totalItems() {
    const sub = items.filter((it) => it.aprob !== 'no').reduce((s, it) => s + Math.max(+it.cant || 0, 0) * Math.max(+it.precio || 0, 0), 0);
    const pd = detalle.plan_desc || 0, tot = sub - Math.floor(sub * pd / 100);  // G59i 🔁 igual que orden_total en la base
    const ab = ['pagado', 'aplicado'].includes(detalle.abono_estado) ? detalle.abono_monto : 0;
    $('dTotal').textContent = plata(tot);
    $('dSaldo').textContent = (pd ? ' (🔁 plan −' + pd + '%)' : '') + (ab ? ' · menos abono ' + plata(ab) + ' = a pagar ' + plata(Math.max(tot - ab, 0)) : '');
  }
  async function guardarTrabajo(callado) {
    const limpios = items.filter((it) => String(it.nombre || '').trim()).map((it) => Object.assign({ nombre: String(it.nombre).trim().slice(0, 100), cant: Math.max(+it.cant || 1, 0), precio: Math.max(Math.round(+it.precio || 0), 0) },
      APROB[it.aprob] ? { aprob: it.aprob } : {}, /^[0-9a-f-]{36}$/.test(it.foto || '') ? { foto: it.foto } : {}));
    try {
      await rpc('taller_trabajo', { p_id: detalle.id, p_items: limpios, p_diagnostico: $('dDiag').value, p_notas: $('dNotas').value, p_mecanico: $('dMec').value || null, p_proxima: $('dProx').value || null });
      if (!callado) toast('💾 Guardado');
    } catch (e) { toast(e.message); throw e; }
  }

  /* =====================================================================
     CLIENTES
     ===================================================================== */
  let clientes = [];
  async function cargarClientes() {
    try { clientes = await rpc('taller_clientes'); } catch (e) { $('cLista').innerHTML = '<li class="err">' + esc(e.message) + '</li>'; return; }
    pintarClientes();
  }
  $('cBuscar').oninput = pintarClientes;
  $('cLista').onclick = (e) => { const b = e.target.closest('[data-chat]'); if (b) App.abrirChat(T, b.dataset.chat, b.dataset.n); };
  function pintarClientes() {
    const f = $('cBuscar').value.trim().toLowerCase();
    const l = clientes.filter((c) => !f || (c.nombre + ' ' + c.telefono + ' ' + c.email).toLowerCase().includes(f));
    $('cCuenta').textContent = clientes.length + ' clientes · ' + clientes.filter((c) => c.cuenta).length + ' con cuenta en la app';
    $('cLista').innerHTML = l.length ? l.map((c) => '<li><div class="grow"><b>' + esc(c.nombre || 'Sin nombre') + '</b> ' + (c.cuenta ? '<span class="pill info">App</span> ' : '') +
      (c.premium ? '<span class="pill pro">Premium</span> ' : '') + App.nota(c.nota) +
      '<div class="sub">' + esc(c.telefono || '') + ' · ' + c.visitas + ' visita' + (c.visitas === 1 ? '' : 's') + (c.faltas ? ' · 🚫 ' + c.faltas + ' falta' + (c.faltas > 1 ? 's' : '') : '') +
      (c.gastado ? ' · ' + plata(c.gastado) : '') + (c.ultima ? ' · última ' + App.fCorta(c.ultima) : '') + '</div></div>' +
      (c.cliente_id ? '<button class="small" data-chat="' + c.cliente_id + '" data-n="' + esc(c.nombre || '') + '">💬</button>' : '') +
      (c.telefono ? '<a class="btn small alt" target="_blank" rel="noopener" href="' + App.wa(c.telefono, 'Hola ' + (c.nombre || '').split(' ')[0] + ' 👋 Te escribimos de ' + P.taller.nombre + '.') + '">📲</a>' : '') + '</li>').join('')
      : '<li class="muted">' + (f ? 'Nadie con ese dato.' : 'Tus clientes aparecen aquí cuando reservan.') + '</li>';
  }

  /* =====================================================================
     MÁS
     ===================================================================== */
  let subMas = null;
  $('mSeg').onclick = (e) => { const b = e.target.closest('[data-m]'); if (b) { history.pushState(null, '', '#mas/' + b.dataset.m); verMas(b.dataset.m); } };
  // Más = menú común del núcleo (CFX_MENU): lista por grupos; cada sección se abre en una hoja desde abajo (body() dibuja dentro de ella).
  const GRUPO = { chat: 'Tu taller', compartir: 'Tu taller', perfil: 'Tu taller', horario: 'Tu taller', servicios: 'Tu taller', abono: 'Tu taller', promos: 'Tu taller', equipo: 'Tu taller', stock: 'Tu taller', caja: 'Ventas y clientes', usadas: 'Ventas y clientes', tradein: 'Ventas y clientes', pasaporte: 'Ventas y clientes', domicilio: 'Tu taller', garantias: 'Ventas y clientes', planes: 'Ventas y clientes',
    stats: 'Ventas y clientes', recordar: 'Ventas y clientes', plan: 'Tu plan', modulos: 'Tu plan', cuenta: 'Configuración' };
  const K2 = { plan: 'premium', cuenta: 'micuenta', chat: 'mensajes' };
  const ICO = { chat: '💬', compartir: '📣', perfil: '🏪', horario: '⏰', servicios: '🛠️', abono: '💳', promos: '🏷️', plan: '⭐', equipo: '👥', stats: '📊', recordar: '🔔', modulos: '🧩', stock: '📦', caja: '💵', usadas: '🏷️', tradein: '🔄', pasaporte: '🪪', domicilio: '🚐', garantias: '🛡️', planes: '🔁', cuenta: '👤' };
  let hojaMas = null;
  function abrirSec(m) {
    if (m === 'chat') { $('chatBtn').click(); return; }
    const b = $('mSeg').querySelector('[data-m="' + m + '"]'); if (!b || b.classList.contains('hidden')) return;
    const F = { perfil: verPerfil, horario: verHorario, servicios: verServicios, abono: verAbono, promos: verPromos, plan: verPlan, equipo: verEquipo, stats: verStats, recordar: verRecordar, cuenta: verCuenta, compartir: verCompartir, modulos: verModulos, stock: verStock, caja: verCaja, usadas: verUsadas, tradein: verTradein, pasaporte: verPasaportes, domicilio: verDomicilio, garantias: verGarantias, planes: verPlanes };
    if (!hojaMas || hojaMas.m !== m || !hojaMas.h.d.isConnected) {
      const h = window.CFX_MENU.hoja((ICO[m] || '') + ' ' + esc(b.textContent.replace(/\d+$/, '').replace(/^[^\p{L}]+/u, '').trim()), () => { if (hojaMas && hojaMas.h === h) { hojaMas = null; subMas = null; } });
      hojaMas = { m, h };
    }
    subMas = m;
    F[m]();
  }
  function verMas(m) {
    $('mSeg').classList.add('hidden');
    if (!$('mBody').querySelector(':scope > .cfx-aj-w')) {
      $('mBody').innerHTML = '';
      const L = [...$('mSeg').querySelectorAll('button[data-m]:not(.hidden)')].map((b) => {
        const t = b.textContent.replace(/\d+$/, '').replace(/^[^\p{L}]+/u, '').trim();
        return { k: K2[b.dataset.m] || b.dataset.m, ico: ICO[b.dataset.m] || '•', t: b.dataset.m === 'cuenta' ? 'Mi cuenta' : t, d: b.dataset.m === 'cuenta' ? 'Identidad, respaldo y soporte' : '', grupo: GRUPO[b.dataset.m] || 'Tu taller', accion: () => abrirSec(b.dataset.m) };
      });
      window.CFX_MENU.montar($('mBody'), L, { perfil: { alGuardar: () => { Object.assign(yo, App.cuenta); } } });
    }
    if (m) abrirSec(m);
  }
  const body = () => (hojaMas && hojaMas.h.d.isConnected ? hojaMas.h.zona : $('mBody'));

  // ---- Compartir: link y QR de reservas (clientes) y de invitación (otros talleres)
  async function verCompartir() {
    const url = linkReservas();
    body().innerHTML = '<div class="card"><h2>🚲 Tu página de reservas</h2><p class="muted" style="margin-top:0">Para tus clientes: reservan su hora, pagan el abono y se crean su cuenta gratis. ' +
      'Compártela por WhatsApp e Instagram, o imprime el afiche con el QR para tu mesón.</p><div class="link">' + esc(url) + '</div>' +
      '<div class="btns"><button type="button" id="cpR">📤 Compartir</button><button class="alt" type="button" id="cpRQ">QR y afiche</button><a class="btn ghost" target="_blank" rel="noopener" href="' + esc(url) + '">Ver</a></div></div>' +
      '<div id="cpT"></div>';
    $('cpR').onclick = () => compartir(url, '🚲 Reserva tu hora en ' + P.taller.nombre);
    $('cpRQ').onclick = () => $('hQR').click();
    if (!P.dueno) return;
    if (!referidos) await pintarReferidos();
    if (!referidos || !referidos.abierto) return;
    const ur = App.ROOT + 'n/?ref=' + encodeURIComponent(referidos.slug);
    $('cpT').innerHTML = '<div class="card"><h2>🤝 Invita a otros talleres</h2><p class="muted" style="margin-top:0">Se crean su cuenta gratis con tu link. Cuando un taller invitado activa su Premium, ' +
      'te regalamos ' + referidos.dias + ' días de Premium.</p><div class="link">' + esc(ur) + '</div>' +
      '<div class="btns"><button type="button" id="cpI">📤 Invitar</button><button class="alt" type="button" id="cpIQ">QR</button></div>' +
      (referidos.invitados.length ? '<p class="sub">Invitados: ' + referidos.invitados.map((x) => esc(x.nombre) + (x.premiado ? ' ✅' : ' ⏳')).join(', ') + '</p>' : '') + '</div>';
    $('cpI').onclick = () => compartir(ur, '🚲 Te recomiendo BiciTaller para recibir reservas online en tu taller. Crea tu cuenta gratis aquí');
    $('cpIQ').onclick = () => App.verQR({ url: ur, titulo: 'Invita a otro taller', archivo: 'invita-' + P.taller.slug + '.gif' });
  }

  // ---- Perfil del taller (logo, colores, ícono, datos)
  function verPerfil() {
    const t = P.taller;
    let logo = t.logo || '', color = t.color, icono = t.icono;
    body().innerHTML = '<div class="card"><h2>🏪 Perfil del taller</h2>' +
      '<div class="hero" style="margin-bottom:6px"><div class="logo" id="pLogo"></div><div class="grow"><label for="pFile" class="btn small alt" style="margin:0;color:var(--brand)">📷 Subir logo</label>' +
      '<input type="file" id="pFile" accept="image/*" class="hidden"> <button class="small ghost" id="pSinLogo" type="button">Quitar</button></div></div>' +
      '<label for="pNom">Nombre</label><input id="pNom" maxlength="80" value="' + esc(t.nombre) + '">' +
      '<label for="pSlug">Enlace de reservas</label><div class="row" style="align-items:center"><span class="sub" style="flex:0 0 auto">' + esc(App.ROOT) + 't/?s=</span><input id="pSlug" maxlength="50" value="' + esc(t.slug) + '"></div>' +
      '<label for="pDesc">Descripción</label><textarea id="pDesc" maxlength="500" placeholder="Mantención, reparación y armado de bicicletas…">' + esc(t.descripcion) + '</textarea>' +
      '<div class="row"><div><label for="pDir">Dirección</label><input id="pDir" maxlength="160" value="' + esc(t.direccion) + '"></div><div><label for="pCom">Comuna</label><input id="pCom" maxlength="60" value="' + esc(t.comuna) + '"></div></div>' +
      '<div class="row"><div><label for="pTel">WhatsApp</label><input id="pTel" inputmode="tel" maxlength="30" value="' + esc(t.telefono) + '"></div><div><label for="pIg">Instagram</label><input id="pIg" maxlength="60" value="' + esc(t.instagram) + '" placeholder="@mitaller"></div></div>' +
      '<label>Color de tu marca</label><div class="swatches" id="pCol">' + COLORES.map((c) => '<button type="button" data-c="' + c + '" style="background:' + c + '" aria-label="Color ' + c + '"></button>').join('') +
      '<input type="color" id="pColor" value="' + color + '" style="width:50px;height:36px;padding:2px" aria-label="Otro color"></div>' +
      '<label>Ícono (si no tienes logo)</label><div class="swatches iconos" id="pIco">' + ICONOS.map((i) => '<button type="button" data-i="' + i + '">' + i + '</button>').join('') + '</div>' +
      '<label class="check"><input type="checkbox" id="pDirec"' + (t.en_directorio !== false ? ' checked' : '') + '> Aparecer en el <a href="' + App.ROOT + 'd/" target="_blank" rel="noopener">directorio de talleres</a>' +
      (P.premium ? ' (⭐ como Premium sales primero)' : ' (los Premium salen primero)') + '</label>' +
      '<div class="btns"><button id="pGuardar">💾 Guardar perfil</button></div><p class="err" id="pErr"></p></div>' +
      // G74c ⭐ Reseñas en Google (módulo): el link se le muestra al cliente que califica con 4-5 ★.
      '<div class="card" id="pGoo"><h2>⭐ Reseñas en Google</h2><p class="sub" style="margin-top:0">Al cliente que te pone 4 o 5 ★ le pedimos su reseña en Google: más gente te encuentra en Maps.</p>' +
      (tiene('resenas') ? '<label for="pGLink">Link para dejar reseña</label><input id="pGLink" inputmode="url" maxlength="300" placeholder="https://g.page/r/…/review" value="' + esc(t.google_resenas || '') + '">' +
        '<p class="sub">Dónde está: Google Maps → tu taller → <b>Pedir reseñas</b> → Copiar link.</p><div class="btns"><button id="pGGuardar" type="button">💾 Guardar link</button></div><p class="err" id="pGErr"></p>'
        : P.venta ? '<div class="btns"><button type="button" data-sin-atras data-ofrecer="resenas">🧩 Ver el módulo</button></div>' : '') + '</div>';
    const prev = () => {
      App.pintarLogo($('pLogo'), { logo, icono });
      $('pLogo').style.backgroundColor = color;
      $('pCol').querySelectorAll('[data-c]').forEach((b) => b.classList.toggle('on', b.dataset.c === color));
      $('pIco').querySelectorAll('[data-i]').forEach((b) => b.classList.toggle('on', b.dataset.i === icono));
      App.tema(color);
    };
    prev();
    $('pFile').onchange = async (e) => { const f = e.target.files[0]; if (!f) return; try { logo = await App.comprimirLogo(f); prev(); } catch (err) { toast(err.message); } };
    $('pSinLogo').onclick = () => { logo = ''; prev(); };
    $('pCol').onclick = (e) => { const b = e.target.closest('[data-c]'); if (b) { color = b.dataset.c; $('pColor').value = color; prev(); } };
    $('pColor').oninput = () => { color = $('pColor').value; prev(); };
    $('pIco').onclick = (e) => { const b = e.target.closest('[data-i]'); if (b) { icono = b.dataset.i; prev(); } };
    if ($('pGGuardar')) $('pGGuardar').onclick = async () => {
      $('pGErr').textContent = '';
      try { await rpc('taller_google_guardar', { p_link: $('pGLink').value }); await cargarPanel(); toast('⭐ Link guardado'); }
      catch (e) { $('pGErr').textContent = e.message; }
    };
    $('pGuardar').onclick = async () => {
      $('pErr').textContent = '';
      try {
        P = await rpc('taller_guardar', { p: { nombre: $('pNom').value, slug: $('pSlug').value, descripcion: $('pDesc').value, direccion: $('pDir').value,
          comuna: $('pCom').value, telefono: $('pTel').value, instagram: $('pIg').value, logo, color, icono, en_directorio: $('pDirec').checked } });
        await cargarPanel(); toast('💾 Perfil guardado'); verPerfil();
      } catch (e) { $('pErr').textContent = e.message; }
    };
  }

  // Horas de inicio posibles (horario normal, cada "bloque" minutos) más las exclusivas ya guardadas.
  function horasDelDia() {
    const t = P.taller, l = [];
    for (let m = mins(t.abre); m + t.bloque_min <= mins(t.cierra); m += t.bloque_min) l.push(hhmm(m));
    (t.horas_premium || []).forEach((h) => { if (!l.includes(h)) l.push(h); });
    return l.sort();
  }

  // ---- Horario
  function verHorario() {
    const t = P.taller;
    const hd = (i) => (t.horarios || {})[i] || { abre: t.abre.slice(0, 5), cierra: t.cierra.slice(0, 5) };
    // G91 🚲 Lunes a viernes juntos; sábado y domingo aparte con su intervalo, bicis a la vez y máximo propios (vacío = igual que lunes a viernes).
    const fila = (i) => '<div class="row" style="align-items:center;flex-wrap:nowrap;margin-bottom:6px"><label class="check" style="margin:0;flex:0 0 64px;display:flex;align-items:center;gap:6px;flex-direction:row"><input type="checkbox" data-d="' + i + '"' +
        (t.dias.includes(i) ? ' checked' : '') + '> ' + App.DIAS[i] + '</label><input type="time" class="hora" data-a="' + i + '" value="' + String(hd(i).abre).slice(0, 5) + '" aria-label="Abre ' + App.DIAS[i] + '">' +
        '<input type="time" class="hora" data-c="' + i + '" value="' + String(hd(i).cierra).slice(0, 5) + '" aria-label="Cierra ' + App.DIAS[i] + '"></div>';
    const finde = (i) => '<div class="card" style="margin:10px 0 0;padding:10px 6px;box-shadow:none" data-finde="' + i + '"><h3 style="margin:0 0 6px">' + (i === 6 ? '🗓️ Sábado' : '🗓️ Domingo') + '</h3>' + fila(i) +
      '<div class="row"><div><label for="hB' + i + '">Cada cuánto</label><select id="hB' + i + '" data-fb="' + i + '"><option value="">Igual</option>' + [15, 20, 30, 45, 60, 90, 120, 180, 240].map((m) => '<option' + (+hd(i).bloque === m ? ' selected' : '') + '>' + m + '</option>').join('') + '</select></div>' +
      '<div><label for="hU' + i + '">Bicis a la vez</label><input id="hU' + i + '" data-fu="' + i + '" inputmode="numeric" placeholder="Igual" value="' + (hd(i).cupos || '') + '"></div>' +
      '<div><label for="hM' + i + '">Máx. del día</label><input id="hM' + i + '" data-fm="' + i + '" inputmode="numeric" placeholder="Igual" value="' + (hd(i).max != null && hd(i).max !== '' ? hd(i).max : '') + '"></div></div></div>';
    body().innerHTML = '<div class="card"><h2>⏰ Horario y reservas</h2><label>🗓️ Lunes a viernes (cada día con su horario)</label><div id="hDias">' +
      [1, 2, 3, 4, 5].map(fila).join('') + finde(6) + finde(0) + '</div>' +
      '<div class="row"><div><label for="hMax">Bicis que recibes por día (0 = sin límite)</label><input id="hMax" inputmode="numeric" value="' + (t.max_dia || 0) + '"></div>' +
      '<div><label for="hCap">Mantenciones que terminas por día (0 = no calcular entrega)</label><input id="hCap" inputmode="numeric" value="' + (t.capacidad_dia || 0) + '"></div></div>' +
      '<label for="hEsp">Máximo de días hasta la entrega (si la cola pasa de esto, ese día se cierra)</label><input id="hEsp" inputmode="numeric" value="' + (t.max_espera_dias || 14) + '">' +
      '<div class="row"><div><label for="hCd">Colación desde</label><input type="time" id="hCd" value="' + (t.colacion_desde || '').slice(0, 5) + '"></div><div><label for="hCh">Colación hasta</label><input type="time" id="hCh" value="' + (t.colacion_hasta || '').slice(0, 5) + '"></div></div>' +
      '<div class="row"><div><label for="hBl">Cada cuánto (minutos)</label><select id="hBl">' + [15, 20, 30, 45, 60, 90, 120, 180, 240].map((m) => '<option' + (m === t.bloque_min ? ' selected' : '') + '>' + m + '</option>').join('') + '</select></div>' +
      '<div><label for="hCu">Bicis a la vez</label><input id="hCu" inputmode="numeric" value="' + t.cupos + '"></div></div>' +
      '<div class="row"><div><label for="hAn">Se puede reservar hasta (días)</label><input id="hAn" inputmode="numeric" value="' + t.anticipacion_dias + '"></div>' +
      '<div><label for="hMe">Mantención cada (meses)</label><input id="hMe" inputmode="numeric" value="' + t.meses_mantencion + '"></div></div>' +
      '<label class="check"><input type="checkbox" id="hOn"' + (t.reservas_online ? ' checked' : '') + '> Recibir reservas online</label>' +
      '<h3>⭐ Horas exclusivas para clientes Premium</h3><p class="sub" style="margin-top:0">Solo los clientes Premium pueden reservar estas horas (es lo que más los motiva a pagar). ' +
      'Si nadie Premium la toma, se abre para todos ' + ((pub.config || {}).horas_libera_premium || 24) + ' horas antes, así no pierdes la hora.</p>' +
      '<div class="chips" id="hVip">' + horasDelDia().map((h) => '<label><input type="checkbox" data-v="' + h + '"' + ((t.horas_premium || []).includes(h) ? ' checked' : '') + '> ' + h + '</label>').join('') + '</div>' +
      '<div class="btns"><button id="hGuardar">💾 Guardar horario</button></div><p class="err" id="hErr"></p></div>' +
      '<div class="card"><h2>⛔ Días cerrados</h2><p class="sub" style="margin-top:0">Feriados, vacaciones o un día que no atiendes: ese día nadie puede reservar. Para cerrar solo unas horas usa ⛔ Bloquear en la Agenda.</p>' +
      '<ul class="list" id="hCerr"></ul><div class="row"><div><label for="hCd1">Desde</label><input type="date" id="hCd1" min="' + P.hoy + '"></div><div><label for="hCd2">Hasta (opcional)</label><input type="date" id="hCd2" min="' + P.hoy + '"></div></div>' +
      '<input id="hCm" maxlength="80" placeholder="Motivo (ej: Feriado, vacaciones)" style="margin-top:8px"><div class="btns"><button type="button" class="alt" id="hCerrar">⛔ Cerrar esos días</button></div></div>';
    pintarCerrados();
    $('hCerrar').onclick = async () => {  // G91 🚲 bloquear días completos (uno o un rango, máx. 62)
      const d1 = $('hCd1').value, d2 = $('hCd2').value || d1;
      if (!d1) { toast('Elige el día'); return; }
      if (d2 < d1) { toast('"Hasta" debe ser después de "Desde"'); return; }
      const L = []; for (let d = d1; d <= d2 && L.length < 62; d = App.sumarDias(d, 1)) L.push(d);
      try {
        const ya = await q(sb.from('bloqueos').select('fecha').eq('taller_id', T).is('desde', null).gte('fecha', d1).lte('fecha', d2));
        const nuevos = L.filter((d) => !(ya || []).some((b) => b.fecha === d)).map((d) => ({ taller_id: T, fecha: d, desde: null, hasta: null, motivo: $('hCm').value.trim().slice(0, 80) }));
        if (nuevos.length) await q(sb.from('bloqueos').insert(nuevos));
        toast('⛔ ' + L.length + ' día' + (L.length > 1 ? 's' : '') + ' cerrado' + (L.length > 1 ? 's' : '')); $('hCd1').value = $('hCd2').value = $('hCm').value = ''; pintarCerrados();
      } catch (e) { toast(e.message); }
    };
    $('hCerr').onclick = async (e) => {
      const x = e.target.closest('[data-abrir]'); if (!x) return;
      try { await q(sb.from('bloqueos').delete().eq('id', x.dataset.abrir)); toast('✅ Día abierto otra vez'); pintarCerrados(); } catch (err) { toast(err.message); }
    };
    $('hGuardar').onclick = async () => {
      $('hErr').textContent = '';
      const cd = $('hCd').value, ch = $('hCh').value;
      if ((cd && !ch) || (!cd && ch)) { $('hErr').textContent = 'Completa la colación (desde y hasta) o déjala vacía'; return; }
      try {
        // Horario "normal" = el más repetido; los días distintos se guardan aparte.
        const dias = Array.from($('hDias').querySelectorAll('input[data-d]:checked')).map((i) => +i.dataset.d);
        if (!dias.length) { $('hErr').textContent = 'Marca al menos un día'; return; }
        const par = (i) => $('hDias').querySelector('[data-a="' + i + '"]').value + '-' + $('hDias').querySelector('[data-c="' + i + '"]').value;
        const cuenta = {}; dias.forEach((i) => { cuenta[par(i)] = (cuenta[par(i)] || 0) + 1; });
        const normal = Object.keys(cuenta).sort((a, b) => cuenta[b] - cuenta[a])[0].split('-');
        const horarios = {};
        [0, 1, 2, 3, 4, 5, 6].forEach((i) => { const [a, c] = par(i).split('-'); if (a && c && par(i) !== normal.join('-')) horarios[i] = { abre: a, cierra: c }; });
        [6, 0].forEach((i) => {  // G91 lo propio del fin de semana
          const q = (k) => $('hDias').querySelector('[data-' + k + '="' + i + '"]').value.trim(), [a, c] = par(i).split('-'), x = {};
          if (q('fb')) x.bloque = +q('fb'); if (q('fu')) x.cupos = Math.min(Math.max(App.numero(q('fu')) || 1, 1), 20); if (q('fm') !== '') x.max = Math.min(Math.max(App.numero(q('fm')), 0), 200);
          if (Object.keys(x).length && a && c) horarios[i] = Object.assign({ abre: a, cierra: c }, x);
        });
        P = await rpc('taller_guardar', { p: { dias, horarios, max_dia: Math.max(App.numero($('hMax').value), 0),
          capacidad_dia: Math.max(App.numero($('hCap').value), 0), max_espera_dias: Math.max(App.numero($('hEsp').value) || 14, 1),
          abre: normal[0], cierra: normal[1], colacion_desde: cd, colacion_hasta: ch, bloque_min: +$('hBl').value,
          cupos: Math.min(Math.max(App.numero($('hCu').value) || 1, 1), 20), anticipacion_dias: Math.min(Math.max(App.numero($('hAn').value) || 21, 1), 120),
          meses_mantencion: Math.min(Math.max(App.numero($('hMe').value) || 4, 1), 24), reservas_online: $('hOn').checked,
          horas_premium: Array.from($('hVip').querySelectorAll('input:checked')).map((i) => i.dataset.v) } });
        await cargarPanel(); toast('⏰ Horario guardado');
      } catch (e) { $('hErr').textContent = /check constraint/.test(e.message) ? 'Revisa las horas: el cierre debe ser después de la apertura.' : e.message; }
    };
  }

  async function pintarCerrados() {
    const el = $('hCerr'); if (!el) return;
    let L = []; try { L = await q(sb.from('bloqueos').select('id,fecha,motivo').eq('taller_id', T).is('desde', null).gte('fecha', P.hoy).order('fecha').limit(60)); } catch (e) { el.innerHTML = '<li class="err">' + esc(e.message) + '</li>'; return; }
    el.innerHTML = (L || []).length ? L.map((b) => '<li><div class="grow"><b>' + esc(App.fLarga(b.fecha)) + '</b>' + (b.motivo ? '<div class="sub">' + esc(b.motivo) + '</div>' : '') + '</div>' +
      '<button type="button" class="small ghost" data-abrir="' + b.id + '" data-sin-atras>✅ Abrir</button></li>').join('') : '<li class="muted">No tienes días cerrados.</li>';
  }
  // ---- Servicios
  function verServicios() {
    const lim = P.plan.limites.servicios;
    body().innerHTML = '<div class="card"><h2>🛠️ Servicios <span class="pill">' + servicios.length + ' de ' + lim + '</span></h2><ul class="list" id="sLista"></ul>' +
      '<p class="sub" style="margin:8px 0 0">Vienen los trabajos más pedidos: toca ✏️ para cambiar el precio o pausar.</p>' +
      '<div class="btns"><button id="sNuevo">＋ Nuevo servicio</button><button class="alt" id="sTipicos">✨ Servicios de fábrica</button></div></div>';
    $('sLista').innerHTML = servicios.length ? servicios.map((s) => '<li' + (s.activo ? '' : ' style="opacity:.55"') + '><div class="grow"><b>' + esc(s.nombre) + '</b> <span class="precio">' + plata(s.precio) + '</span>' +
      (s.adicional ? ' <span class="pill info">Adicional</span>' : '') + '<div class="sub">' + (s.adicional ? '' : '⏱️ ' + s.duracion_min + ' min') + (s.descripcion ? ' · ' + esc(s.descripcion) : '') + (s.activo ? '' : ' · pausado') + '</div></div>' +
      '<button class="small ghost" data-e="' + s.id + '">✏️</button></li>').join('') : '<li class="muted">Agrega lo que ofreces: mantención, pinchazo, ajuste de frenos…</li>';
    $('sNuevo').onclick = () => editarServicio(null);
    $('sLista').onclick = (e) => { const b = e.target.closest('[data-e]'); if (b) editarServicio(servicios.find((s) => s.id === b.dataset.e)); };
    const st = $('sTipicos');
    if (st) st.onclick = async () => {
      try { const n = await rpc('taller_servicios_fabrica', {}); await cargarCatalogo(); toast(n ? '✨ Se agregaron ' + n + ': ajusta tus precios' : '✨ Ya tienes todos los de fábrica (o llegaste al máximo)'); verServicios(); }
      catch (e) { toast(e.message); }
    };
  }
  function editarServicio(s) {
    const d = modal('<h2>' + (s ? '✏️ Editar servicio' : '＋ Nuevo servicio') + '</h2><label for="eN">Nombre</label><input id="eN" maxlength="80" value="' + esc(s ? s.nombre : '') + '">' +
      '<div class="row"><div><label for="eP">Precio</label><input id="eP" inputmode="numeric" value="' + (s ? s.precio : '') + '"></div><div><label for="eD">Duración (min)</label><input id="eD" inputmode="numeric" value="' + (s ? s.duracion_min : 60) + '"></div></div>' +
      '<label for="eDs">Descripción</label><textarea id="eDs" maxlength="300">' + esc(s ? s.descripcion : '') + '</textarea>' +
      '<label class="check"><input type="checkbox" id="eA"' + (!s || s.activo ? ' checked' : '') + '> Disponible para reservar</label>' +
      '<label class="check"><input type="checkbox" id="eX2"' + (s && s.adicional ? ' checked' : '') + '> Es adicional (se suma a otro servicio, ej.: cambio de cámara)</label>' +
      '<div class="btns">' + (s ? '<button class="danger" id="eX">Eliminar</button>' : '') + '<button class="ghost" data-cerrar>Cancelar</button><button id="eOk">Guardar</button></div><p class="err" id="eErr"></p>');
    d.querySelector('#eOk').onclick = async () => {
      const row = { taller_id: T, nombre: d.querySelector('#eN').value.trim(), precio: Math.max(App.numero(d.querySelector('#eP').value), 0),
        duracion_min: Math.min(Math.max(App.numero(d.querySelector('#eD').value) || 60, 10), 480), descripcion: d.querySelector('#eDs').value.trim(), activo: d.querySelector('#eA').checked, adicional: d.querySelector('#eX2').checked };
      if (!row.nombre) { d.querySelector('#eErr').textContent = 'Escribe el nombre'; return; }
      try { if (s) await q(sb.from('servicios').update(row).eq('id', s.id)); else await q(sb.from('servicios').insert(row)); d.close(); await cargarCatalogo(); await cargarPanel(); verServicios(); toast('🛠️ Guardado'); }
      catch (e) { d.querySelector('#eErr').textContent = e.message; }
    };
    const x = d.querySelector('#eX');
    if (x) x.onclick = async () => { if (!await confirmar('¿Eliminar "' + s.nombre + '"?')) return; try { await q(sb.from('servicios').delete().eq('id', s.id)); d.close(); await cargarCatalogo(); verServicios(); } catch (e) { toast(e.message); } };
  }

  // ---- Abono: 2 links de pago, uno activo
  function verAbono() {
    const links = [1, 2].map((n) => (P.links || []).find((l) => l.slot === n) || { slot: n, monto: 0, url: '', texto: '', activo: false });
    body().innerHTML = '<div class="card"><h2>💳 Abono de la reserva</h2><p class="muted" style="margin-top:0">El cliente paga este abono con tu link de Mercado Pago y sube el comprobante. ' +
      'Tienes 2 espacios: deja activo el que quieras usar (por ejemplo, para cambiar el monto sin perder el otro). El dinero te llega a ti; solo tú ves estos links.</p>' +
      links.map((l) => '<div class="slotpago' + (l.activo ? ' on' : '') + '"><label class="check" style="margin:0"><input type="radio" name="act" value="' + l.slot + '"' + (l.activo ? ' checked' : '') + '> <b>Espacio ' + l.slot + '</b>' +
        (l.activo ? ' <span class="pill ok">Activo</span>' : '') + '</label>' +
        '<div class="row"><div><label>Monto del abono</label><input data-k="monto" data-s="' + l.slot + '" inputmode="numeric" value="' + (l.monto || '') + '" placeholder="10000"></div>' +
        '<div><label>Texto (opcional)</label><input data-k="texto" data-s="' + l.slot + '" maxlength="300" value="' + esc(l.texto) + '" placeholder="Abono mantención"></div></div>' +
        '<label>Link de pago (Mercado Pago)</label><input data-k="url" data-s="' + l.slot + '" value="' + esc(l.url) + '" placeholder="https://mpago.la/…"></div>').join('') +
      '<div class="btns"><button id="aGuardar">💾 Guardar</button></div><p class="err" id="aErr"></p></div>';
    $('aGuardar').onclick = async () => {
      $('aErr').textContent = '';
      const act = +((body().querySelector('input[name=act]:checked') || {}).value || 0);
      const val = (s, k) => body().querySelector('[data-s="' + s + '"][data-k="' + k + '"]').value.trim();
      try {
        for (const s of [1, 2]) {
          await rpc('link_guardar', { p_tipo: 'abono', p_slot: s, p_monto: App.numero(val(s, 'monto')), p_url: val(s, 'url'), p_texto: val(s, 'texto'), p_activar: s === act });
        }
        await cargarPanel(); toast('💳 Guardado'); verAbono();
      } catch (e) { $('aErr').textContent = e.message; }
    };
  }

  // ---- Promociones (para todos los clientes)
  function verPromos() {
    const lim = P.plan.limites.promos;
    body().innerHTML = '<div class="card"><h2>🏷️ Promociones <span class="pill">' + promos.filter((p) => p.activa).length + ' de ' + lim + ' activas</span></h2>' +
      '<p class="muted" style="margin-top:0">Se ven en tu página de reservas y en la app de tus clientes.</p><div class="grid" id="oLista"></div><div class="btns"><button id="oNueva">＋ Nueva promoción</button></div></div>';
    $('oLista').innerHTML = promos.map((p) => '<div class="card clic" data-e="' + p.id + '" style="' + (p.activa ? '' : 'opacity:.55') + '"><b>' + esc(p.titulo) + '</b>' +
      (p.precio != null ? ' <span class="precio">' + plata(p.precio) + '</span>' : '') + (p.precio_antes != null ? '<span class="antes">' + plata(p.precio_antes) + '</span>' : '') +
      (p.texto ? '<div class="sub">' + esc(p.texto) + '</div>' : '') + '<div class="sub">' + (p.activa ? 'Activa' : 'Pausada') + (p.hasta ? ' · hasta ' + App.fCorta(p.hasta) : '') + '</div></div>').join('') ||
      '<p class="sub" style="margin:0">Sin promociones.</p>';
    $('oNueva').onclick = () => editarPromo(null);
    $('oLista').onclick = (e) => { const b = e.target.closest('[data-e]'); if (b) editarPromo(promos.find((p) => p.id === b.dataset.e)); };
  }
  function editarPromo(p) {
    const d = modal('<h2>' + (p ? '✏️ Editar promoción' : '🏷️ Nueva promoción') + '</h2><label for="oT">Título</label><input id="oT" maxlength="80" value="' + esc(p ? p.titulo : '') + '">' +
      '<label for="oX">Detalle</label><textarea id="oX" maxlength="400">' + esc(p ? p.texto : '') + '</textarea>' +
      '<div class="row"><div><label for="oP">Precio promo</label><input id="oP" inputmode="numeric" value="' + (p && p.precio != null ? p.precio : '') + '"></div>' +
      '<div><label for="oA">Precio normal</label><input id="oA" inputmode="numeric" value="' + (p && p.precio_antes != null ? p.precio_antes : '') + '"></div>' +
      '<div><label for="oH">Hasta</label><input type="date" id="oH" value="' + (p && p.hasta ? p.hasta : '') + '"></div></div>' +
      '<label class="check"><input type="checkbox" id="oOn"' + (!p || p.activa ? ' checked' : '') + '> Activa</label>' +
      '<div class="btns">' + (p ? '<button class="danger" id="oDel">Eliminar</button><button class="alt" id="oSh">📤 Compartir</button>' : '') + '<button class="ghost" data-cerrar>Cancelar</button><button id="oOk">Guardar</button></div><p class="err" id="oErr"></p>');
    const val = (id) => d.querySelector(id).value.trim();
    d.querySelector('#oOk').onclick = async () => {
      const row = { taller_id: T, titulo: val('#oT'), texto: val('#oX'), precio: val('#oP') ? App.numero(val('#oP')) : null, precio_antes: val('#oA') ? App.numero(val('#oA')) : null,
        hasta: val('#oH') || null, activa: d.querySelector('#oOn').checked };
      if (!row.titulo) { d.querySelector('#oErr').textContent = 'Escribe el título'; return; }
      try { if (p) await q(sb.from('promos').update(row).eq('id', p.id)); else await q(sb.from('promos').insert(row)); d.close(); await cargarCatalogo(); verPromos(); toast('🏷️ Guardada'); }
      catch (e) { d.querySelector('#oErr').textContent = e.message; }
    };
    if (p) {
      d.querySelector('#oDel').onclick = async () => { if (!await confirmar('¿Eliminar la promoción?')) return; try { await q(sb.from('promos').delete().eq('id', p.id)); d.close(); await cargarCatalogo(); verPromos(); } catch (e) { toast(e.message); } };
      d.querySelector('#oSh').onclick = () => compartir(linkReservas(), '🏷️ ' + p.titulo + (p.precio != null ? ' — ' + plata(p.precio) : '') + (p.texto ? '\n' + p.texto : '') + '\n📅 Reserva aquí');
    }
  }

  // ---- Plan Premium (pagar con link y subir comprobante)
  // Plan: precios y pago comunes a las 6 apps (núcleo: cfx_pago_estado y pagos.js; se editan en el Centro de Mando → Pagos).
  // G59 🧩 Tienda de módulos del taller (núcleo: modulos.js). Premium paga -20 %; los módulos no vienen en Premium.
  function verModulos() {
    body().innerHTML = '<div class="card"><p class="sub" style="margin-top:0">Suma solo lo que tu taller necesita. Toca ▶️ Probar para ver cómo funciona.</p><div id="modZona"></div></div>';
    window.CFX_MODULOS_TIENDA.montar($('modZona'), { rpc, alCambiar: recargar }).cargar();
  }

  // ---- G59d 🧩 📦 Repuestos y stock + 🛒 pedido a proveedor (G68: genérico, los proveedores del taller)
  /* ---------- G74a 💵 Caja / Mostrador (FREE) ---------- */
  const CAJA_M = [['efectivo', '💵 Efectivo'], ['transferencia', '🏦 Transferencia'], ['tarjeta', '💳 Tarjeta']];
  const medioDe = (m) => (CAJA_M.find((x) => x[0] === m) || ['', m])[1];
  // Elegir cómo pagó (3 botones grandes) → fn(medio)
  function elegirMedio(titulo, fn) {
    const d = modal('<h2>' + titulo + '</h2><p class="sub" style="margin-top:0">¿Cómo pagó?</p><div class="btns" style="flex-direction:column">' +
      CAJA_M.map((m) => '<button type="button" data-medio="' + m[0] + '">' + m[1] + '</button>').join('') + '<button class="ghost" data-cerrar>Cancelar</button></div><p class="err" id="meErr"></p>');
    d.onclick = async (e) => {
      const b = e.target.closest('[data-medio]'); if (!b) return;
      d.querySelectorAll('[data-medio]').forEach((x) => { x.disabled = true; });
      try { await fn(b.dataset.medio); d.close(); }
      catch (err) { d.querySelectorAll('[data-medio]').forEach((x) => { x.disabled = false; }); d.querySelector('#meErr').textContent = err.message; }
    };
  }
  function cobrarOrden(id, luego, monto) {
    elegirMedio('💵 Cobrar' + (monto != null ? ' ' + plata(monto) : ' la orden'), async (m) => {
      const x = await rpc('taller_caja_cobrar', { p_reserva: id, p_medio: m });
      sb.functions.invoke('servidor').catch(() => {});
      toast('✅ Cobrado ' + plata(x.monto) + ' · ' + medioDe(m)); if (luego) luego();
    });
  }
  let cajaF = null;
  async function verCaja() {
    body().innerHTML = '<p class="empty">Cargando…</p>';
    let c;
    try { [c] = await Promise.all([rpc('taller_caja', { p_fecha: cajaF }), tiene('stock') ? cargarStock().catch(() => null) : null]); }
    catch (e) { body().innerHTML = '<p class="err">' + esc(e.message) + '</p>'; return; }
    const m = c.medios, esHoy = c.fecha === c.hoy;
    body().innerHTML = '<div class="card"><h2>🛒 Venta de mostrador</h2><p class="sub" style="margin-top:0">Vende repuestos y accesorios sin orden. ' + (ST ? 'Baja el 📦 stock solo.' : '') + '</p>' +
        '<div class="btns" style="margin-top:0"><button type="button" id="kVender">＋ Nueva venta</button>' + (ST ? '<button class="ghost" type="button" data-m2="stock">📦 Ver stock</button>' : P.venta ? '<button class="ghost" type="button" data-sin-atras data-ofrecer="stock">📦 Controlar stock</button>' : '') + '</div></div>' +
      (c.por_cobrar.length ? '<div class="card"><h2>💵 Por cobrar <span class="pill warn">' + c.por_cobrar.length + '</span></h2><ul class="list">' + c.por_cobrar.map((r) =>
        '<li><div class="grow"><b>' + esc(r.nombre) + '</b><div class="sub">' + (r.bici ? '🚲 ' + esc(r.bici) + ' · ' : '') + (r.estado === 'lista' ? '✅ Lista' : '🎉 Entregada sin cobrar') + '</div></div>' +
        '<button class="small okb" type="button" data-cobrar="' + r.id + '" data-monto="' + r.a_pagar + '">💵 ' + plata(r.a_pagar) + '</button></li>').join('') + '</ul></div>' : '') +
      '<div class="card"><h2>📊 Cierre del día</h2><label for="kF">Día</label><input type="date" id="kF" value="' + c.fecha + '" max="' + c.hoy + '">' +
        '<div class="stats" style="margin-top:10px;grid-template-columns:1fr 1fr">' + CAJA_M.map((x) => '<div class="card"><span>' + x[1] + '</span><b>' + plata(m[x[0]]) + '</b></div>').join('') +
        '<div class="card"><span>🧾 Total (' + m.n + ')</span><b>' + plata(m.total) + '</b></div></div>' +
        (c.cobros.length ? '<ul class="list" id="kLista">' + c.cobros.map((k) => '<li><div class="grow"><b>' + plata(k.total) + '</b> · ' + medioDe(k.medio) +
          '<div class="sub">' + k.hora + ' · ' + esc(k.nombre || (k.reserva ? 'Orden' : 'Venta de mostrador')) + (k.reserva ? '' : ' · ' + esc(k.items.map((i) => i.nombre + (i.cant > 1 ? ' x' + i.cant : '')).join(', ').slice(0, 90))) + '</div>' +
          (k.boleta ? '<div class="sub">🧾 Boleta N° ' + esc(k.boleta) + '</div>' : '') + '</div>' +
          '<button class="small ' + (k.boleta ? 'ghost' : 'alt') + '" type="button" data-bol="' + k.id + '" aria-label="Boleta y comprobante">🧾</button>' +
          (P.dueno ? '<button class="small ghost" type="button" data-anular="' + k.id + '" aria-label="Anular cobro">✕</button>' : '') + '</li>').join('') + '</ul>'
          : '<p class="sub">' + (esHoy ? 'Todavía no hay cobros hoy.' : 'Sin cobros ese día.') + '</p>') +
        (c.cobros.length ? '<div class="btns"><button class="ghost" type="button" id="kCopiar">📋 Copiar cierre</button></div>' : '') + '</div>';
    const z = body();
    z.querySelector('#kF').onchange = (e) => { cajaF = e.target.value || null; verCaja(); };
    z.querySelector('#kVender').onclick = () => ventaMostrador(verCaja);
    const cp = z.querySelector('#kCopiar');
    if (cp) cp.onclick = () => navigator.clipboard.writeText('🧾 Cierre ' + P.taller.nombre + ' · ' + App.fCorta(c.fecha) + '\n' + CAJA_M.map((x) => x[1] + ': ' + plata(m[x[0]])).join('\n') + '\nTotal: ' + plata(m.total) + ' (' + m.n + ' cobros)').then(() => toast('📋 Cierre copiado'));
    z.onclick = async (e) => {
      const st = e.target.closest('[data-m2]'); if (st) { abrirSec(st.dataset.m2); return; }
      const cb = e.target.closest('[data-cobrar]'); if (cb) { cobrarOrden(cb.dataset.cobrar, verCaja, +cb.dataset.monto); return; }
      const bo = e.target.closest('[data-bol]'); if (bo) { boletaCobro(c.cobros.find((k) => k.id === bo.dataset.bol)); return; }
      const an = e.target.closest('[data-anular]');
      if (an) { if (!await confirmar('¿Anular este cobro? Se borra del cierre' + (ST ? ' y vuelve el stock' : '') + '.')) return; try { await rpc('taller_caja_anular', { p_id: an.dataset.anular }); toast('Cobro anulado'); verCaja(); } catch (err) { toast(err.message); } }
    };
  }
  // G91 🧾 Boleta y comprobante de un cobro: 🧾 comprobante (imprimir, PDF, WhatsApp) + N° de la boleta del SII (se anota).
  const cargarComprobante = () => window.CFX_COMPROBANTE ? Promise.resolve(window.CFX_COMPROBANTE) : new Promise((ok) => {
    const sc = document.createElement('script'); sc.src = App.ROOT + 'shared/comprobante.js'; sc.onload = () => ok(window.CFX_COMPROBANTE || null); sc.onerror = () => ok(null); document.head.appendChild(sc); });
  window.CFX_COMPROBANTE_DATOS = window.CFX_COMPROBANTE_DATOS || (async () => ({ logo: P.taller.logo || '', firma: { razon: P.taller.nombre, direccion: P.taller.direccion || '', comuna: P.taller.comuna || '' } }));
  function boletaCobro(k) {
    if (!k) return;
    const d = modal('<h2>🧾 Boleta · ' + plata(k.total) + '</h2><p class="sub" style="margin-top:0">' + esc(k.hora + ' · ' + (k.nombre || (k.reserva ? 'Orden' : 'Venta de mostrador')) + ' · ' + medioDe(k.medio)) + '</p>' +
      '<label for="boF">N° de la boleta del SII</label><input id="boF" inputmode="numeric" maxlength="10" value="' + esc(k.boleta || '') + '" placeholder="Ej: 1234">' +
      '<p class="sub">Emítela en la app o el sitio del SII (gratis) y anota aquí su número: queda en el cierre y en el comprobante.</p>' +
      '<div class="btns"><button type="button" class="alt" id="boC">🧾 Comprobante</button><button type="button" id="boG">💾 Guardar N°</button></div>');
    d.querySelector('#boG').onclick = async () => {
      try { const x = await rpc('taller_caja_boleta', { p_id: k.id, p_folio: d.querySelector('#boF').value }); k.boleta = x.boleta; d.close(); toast(x.boleta ? '🧾 Boleta N° ' + x.boleta + ' anotada' : 'N° de boleta quitado'); verCaja(); }
      catch (err) { toast(err.message); }
    };
    d.querySelector('#boC').onclick = async () => {
      const C = await cargarComprobante(); if (!C) { toast('No se pudo abrir el comprobante'); return; }
      const its = (k.items || []).map((i) => ({ cant: Math.max(+i.cant || 1, 1), nombre: String(i.nombre || 'Ítem'), precio: Math.max(+i.precio || 0, 0) }));
      const suma = its.reduce((s2, i) => s2 + i.cant * i.precio, 0), folio = d.querySelector('#boF').value.replace(/\D/g, '') || k.boleta;
      d.close();
      C.abrir({ negocio: P.taller.nombre, fecha: k.at, numero: String(k.id).slice(0, 6).toUpperCase(), cliente: k.nombre || '', tel: k.tel || '', items: its, total: k.total, medio: k.medio,
        entrega: suma > k.total ? 'Abono o descuento ya aplicado: −' + plata(suma - k.total) : '', boleta: folio ? { folio } : null });
    };
  }
  // 🛒 Venta sin orden: ítems (mis repuestos/fábrica/servicios) → cobrar.
  function ventaMostrador(luego) {
    const its = [{ nombre: '', cant: 1, precio: 0 }];
    const d = modal('<h2>🛒 Nueva venta</h2><div class="items" id="vItems"></div>' +
      '<div class="row" style="margin-top:6px"><select id="vAddS" aria-label="Agregar servicio"><option value="">＋ Servicio…</option>' + servicios.filter((s) => s.activo).map((s) => '<option value="' + s.id + '">' + esc(s.nombre) + ' · ' + plata(s.precio) + '</option>').join('') + '</select>' +
      '<button class="alt" id="vAdd" type="button" style="flex:0 0 auto">＋ Ítem</button></div>' +
      '<label for="vN">Cliente (opcional)</label><input id="vN" maxlength="80" autocomplete="off">' +
      '<p style="margin:12px 0 0">Total: <b class="precio" id="vTot">$0</b></p>' +
      '<div class="btns"><button class="ghost" data-cerrar>Cancelar</button><button class="okb" id="vOk" type="button">💵 Cobrar</button></div><p class="err" id="vErr"></p>');
    if (ST) listaStock(); else if (window.CFX_FABRICA) CFX_FABRICA.repuestos(document.createElement('input'));
    const zi = d.querySelector('#vItems');
    const tot = () => its.reduce((s, it) => s + Math.max(+it.cant || 0, 0) * Math.max(+it.precio || 0, 0), 0);
    const pintar = () => {
      zi.innerHTML = its.map((it, i) => '<div class="it"><input data-i="' + i + '" data-k="nombre" value="' + esc(it.nombre) + '" placeholder="Elige o escribe" aria-label="Qué vendiste" list="' + (ST ? 'stRep' : 'fabRep') + '">' +
        '<input data-i="' + i + '" data-k="cant" value="' + it.cant + '" inputmode="numeric" aria-label="Cantidad"><input data-i="' + i + '" data-k="precio" value="' + it.precio + '" inputmode="numeric" aria-label="Precio">' +
        '<button class="danger" type="button" data-x="' + i + '" aria-label="Quitar">✕</button>' + stockDe(it) + '</div>').join('');
      d.querySelector('#vTot').textContent = plata(tot());
    };
    zi.oninput = (e) => {
      const i = e.target.dataset.i; if (i === undefined) return;
      const k = e.target.dataset.k; its[i][k] = k === 'nombre' ? e.target.value : App.numero(e.target.value);
      if (k === 'nombre') {
        const rs = repDe(e.target.value), pf = rs ? rs.precio : window.CFX_FABRICA && CFX_FABRICA.precio(e.target.value);
        if (pf && !its[i].precio) { its[i].precio = pf; const ip = zi.querySelector('[data-i="' + i + '"][data-k=precio]'); if (ip) ip.value = pf; }
        const fila = e.target.closest('.it'), viejo = fila.querySelector('.ap'); if (viejo) viejo.remove(); fila.insertAdjacentHTML('beforeend', stockDe(its[i]));
      }
      d.querySelector('#vTot').textContent = plata(tot());
    };
    zi.onclick = (e) => { const x = e.target.closest('[data-x]'); if (x) { its.splice(+x.dataset.x, 1); if (!its.length) its.push({ nombre: '', cant: 1, precio: 0 }); pintar(); } };
    d.querySelector('#vAdd').onclick = () => { its.push({ nombre: '', cant: 1, precio: 0 }); pintar(); const l = zi.querySelectorAll('[data-k=nombre]'); l[l.length - 1].focus(); };
    d.querySelector('#vAddS').onchange = (e) => { const s = servicios.find((x) => x.id === e.target.value); if (s) { const v = its.findIndex((it) => !String(it.nombre).trim()); const n = { nombre: s.nombre, cant: 1, precio: s.precio }; if (v >= 0) its[v] = n; else its.push(n); } e.target.value = ''; pintar(); };
    d.querySelector('#vOk').onclick = () => {
      const l = its.filter((it) => String(it.nombre || '').trim());
      if (!l.length) { d.querySelector('#vErr').textContent = 'Agrega lo que vendiste'; return; }
      elegirMedio('💵 Cobrar ' + plata(tot()), async (m) => {
        await rpc('taller_caja_vender', { p_items: l.map((it) => ({ nombre: String(it.nombre).trim(), cant: Math.max(+it.cant || 1, 1), precio: Math.max(Math.round(+it.precio || 0), 0) })), p_medio: m, p_nombre: d.querySelector('#vN').value });
        d.close(); toast('✅ Venta cobrada · ' + medioDe(m)); if (luego) luego();
      });
    };
    pintar();
  }
  let ST = null;  // { repuestos, proveedores } (taller_stock)
  async function cargarStock() { ST = await rpc('taller_stock'); if (ST.bloqueado) ST = null; return ST; }
  const repDe = (nombre) => ST && ST.repuestos.find((x) => x.nombre.trim().toLowerCase() === String(nombre || '').trim().toLowerCase());
  const porPedir = () => (ST ? ST.repuestos.filter((x) => x.minimo > 0 && x.stock <= x.minimo) : []);
  const cantPedir = (x) => Math.max(x.minimo * 2 - x.stock, 1);
  function listaStock() {  // datalist de la orden: mis repuestos + los de fábrica
    let d = document.getElementById('stRep');
    if (!d) { d = document.createElement('datalist'); d.id = 'stRep'; document.body.appendChild(d); }
    const nombres = ST.repuestos.map((x) => x.nombre), fab = window.CFX_FABRICA ? CFX_FABRICA.REPUESTOS.map((r) => r[0]) : [];
    d.innerHTML = nombres.concat(fab.filter((n) => !nombres.some((m) => m.toLowerCase() === n.toLowerCase()))).map((n) => '<option value="' + esc(n) + '">').join('');
  }
  async function verStock() {
    body().innerHTML = '<p class="empty">Cargando…</p>';
    let s;
    try { s = await rpc('taller_stock'); } catch (e) { body().innerHTML = '<p class="err">' + esc(e.message) + '</p>'; return; }
    if (s.bloqueado) {
      body().innerHTML = '<div class="card"><h2>📦 Repuestos y stock <span class="pill pro">🧩 MÓDULO</span></h2><p class="muted">El stock baja solo al entregar cada bici. Cuando algo se acaba, armas el pedido a tu proveedor por WhatsApp con un toque.</p>' +
        '<div class="btns"><button type="button" data-sin-atras data-ofrecer="stock">🧩 Ver el módulo</button></div></div>';
      return;
    }
    ST = s;
    const bajos = porPedir(), f = (body().querySelector('#rBuscar') || {}).value || '';
    body().innerHTML = (bajos.length ? '<div class="aviso warn"><div class="grow">⚠️ ' + bajos.length + ' repuesto' + (bajos.length === 1 ? '' : 's') + ' por pedir.</div><button class="small" id="rPedido" type="button">🛒 Armar pedido</button></div>' : '') +
      '<div class="card"><h2>📦 Repuestos <span class="pill">' + s.repuestos.length + '</span></h2><p class="sub" style="margin-top:0">Baja solo al entregar la orden (si el nombre es igual). Usa ➖ ➕ para corregir.</p>' +
      (s.repuestos.length > 8 ? '<input id="rBuscar" placeholder="🔎 Buscar repuesto" value="' + esc(f) + '">' : '') + '<ul class="list" id="rLista"></ul>' +
      '<div class="btns">' + (P.dueno ? '<button id="rNuevo" type="button">＋ Nuevo repuesto</button><button class="alt" id="rFab" type="button">✨ Repuestos de fábrica</button>' : '') +
      '<button class="ghost" id="rProv" type="button">🚚 Proveedores (' + s.proveedores.length + ')</button></div></div>';
    const pintar = () => {
      const t = ((body().querySelector('#rBuscar') || {}).value || '').trim().toLowerCase();
      const l = s.repuestos.filter((x) => !t || x.nombre.toLowerCase().includes(t));
      body().querySelector('#rLista').innerHTML = l.length ? l.map((x) => {
        const bajo = x.minimo > 0 && x.stock <= x.minimo, pv = s.proveedores.find((p) => p.id === x.proveedor_id);
        return '<li><div class="grow"><b>' + esc(x.nombre) + '</b> <span class="pill ' + (x.stock === 0 ? 'bad' : bajo ? 'warn' : 'ok') + '">' + x.stock + '</span>' +
          '<div class="sub">' + (P.dueno ? plata(x.precio) + ' · ' : '') + (x.minimo ? 'mínimo ' + x.minimo : 'sin mínimo') + (pv ? ' · 🚚 ' + esc(pv.nombre) : '') + '</div></div>' +
          '<button class="small ghost" data-mas="' + x.id + '" data-n="-1" aria-label="Restar uno">➖</button><button class="small ghost" data-mas="' + x.id + '" data-n="1" aria-label="Sumar uno">➕</button>' +
          (P.dueno ? '<button class="small ghost" data-ed="' + x.id + '" aria-label="Editar">✏️</button>' : '') + '</li>';
      }).join('') : '<li class="muted">' + (t ? 'Nada con ese nombre.' : 'Agrega los repuestos que vendes, o toca ✨ para traer los típicos.') + '</li>';
    };
    pintar();
    const rb = body().querySelector('#rBuscar'); if (rb) rb.oninput = pintar;
    body().onclick = async (e) => {
      const m = e.target.closest('[data-mas]');
      if (m) {
        try { await rpc('taller_stock_sumar', { p: { [m.dataset.mas]: +m.dataset.n } }); const x = s.repuestos.find((r) => r.id === m.dataset.mas); x.stock = Math.max(x.stock + +m.dataset.n, 0); pintar(); }
        catch (err) { toast(err.message); }
        return;
      }
      const ed = e.target.closest('[data-ed]'); if (ed) { editarRepuesto(s.repuestos.find((r) => r.id === ed.dataset.ed)); return; }
      if (e.target.closest('#rNuevo')) editarRepuesto(null);
      else if (e.target.closest('#rProv')) verProveedores();
      else if (e.target.closest('#rPedido')) verPedido();
      else if (e.target.closest('#rFab')) {
        try { const n = await rpc('taller_repuestos_fabrica', { p_lista: window.CFX_FABRICA ? CFX_FABRICA.REPUESTOS : [] }); toast(n ? '✨ Se agregaron ' + n + ': pon tu stock y mínimo' : '✨ Ya tienes todos los de fábrica'); verStock(); }
        catch (err) { toast(err.message); }
      }
    };
  }
  function editarRepuesto(x) {
    const pv = ST.proveedores;
    const d = modal('<h2>' + (x ? '✏️ Editar repuesto' : '＋ Nuevo repuesto') + '</h2><label for="rN">Nombre (igual que en la orden)</label><input id="rN" maxlength="100" value="' + esc(x ? x.nombre : '') + '" list="fabRep" autocomplete="off">' +
      '<div class="row"><div><label for="rP">Precio de venta</label><input id="rP" inputmode="numeric" value="' + (x ? x.precio : '') + '"></div><div><label for="rS">Stock hoy</label><input id="rS" inputmode="numeric" value="' + (x ? x.stock : 0) + '"></div></div>' +
      '<div class="row"><div><label for="rM">Pedir cuando queden</label><input id="rM" inputmode="numeric" value="' + (x ? x.minimo : 2) + '"></div><div><label for="rV">Proveedor</label><select id="rV"><option value="">Sin proveedor</option>' +
        pv.map((p) => '<option value="' + p.id + '"' + (x && x.proveedor_id === p.id ? ' selected' : '') + '>' + esc(p.nombre) + '</option>').join('') + '</select></div></div>' +
      '<div class="btns">' + (x ? '<button class="danger" id="rB" type="button">🗑️ Borrar</button>' : '') + '<button class="ghost" data-cerrar>Cancelar</button><button id="rG" type="button">💾 Guardar</button></div>');
    if (window.CFX_FABRICA) CFX_FABRICA.repuestos(d.querySelector('#rN'));
    d.querySelector('#rN').oninput = () => { const pf = window.CFX_FABRICA && CFX_FABRICA.precio(d.querySelector('#rN').value); if (pf && !+d.querySelector('#rP').value) d.querySelector('#rP').value = pf; };
    d.querySelector('#rG').onclick = async () => {
      try {
        await rpc('taller_repuesto_guardar', { p: { id: x ? x.id : null, nombre: d.querySelector('#rN').value, precio: App.numero(d.querySelector('#rP').value), stock: App.numero(d.querySelector('#rS').value),
          minimo: App.numero(d.querySelector('#rM').value), proveedor_id: d.querySelector('#rV').value || null } });
        d.close(); toast('💾 Guardado'); verStock();
      } catch (e) { toast(e.message); }
    };
    const b = d.querySelector('#rB');
    if (b) b.onclick = async () => { if (!await confirmar('¿Borrar "' + x.nombre + '"?')) return; try { await rpc('taller_repuesto_borrar', { p_id: x.id }); d.close(); verStock(); } catch (e) { toast(e.message); } };
  }
  function verProveedores() {
    const pv = ST.proveedores;
    const d = modal('<h2>🚚 Tus proveedores</h2><p class="muted" style="margin-top:0">A quién le pides los repuestos. El pedido sale por WhatsApp o correo.</p><ul class="list">' +
      (pv.map((p) => '<li><div class="grow"><b>' + esc(p.nombre) + '</b><div class="sub">' + esc([p.telefono, p.email].filter(Boolean).join(' · ') || 'Sin contacto') + '</div></div>' +
        (P.dueno ? '<button class="small ghost" data-pv="' + p.id + '" aria-label="Editar">✏️</button>' : '') + '</li>').join('') || '<li class="muted">Aún no tienes proveedores.</li>') + '</ul>' +
      '<div class="btns"><button class="ghost" data-cerrar>Cerrar</button>' + (P.dueno ? '<button id="pvN" type="button">＋ Nuevo proveedor</button>' : '') + '</div>');
    d.onclick = (e) => {
      const b = e.target.closest('[data-pv]'); if (b) { d.close(); editarProveedor(pv.find((p) => p.id === b.dataset.pv)); }
      if (e.target.closest('#pvN')) { d.close(); editarProveedor(null); }
    };
  }
  function editarProveedor(p) {
    const d = modal('<h2>' + (p ? '✏️ Editar proveedor' : '＋ Nuevo proveedor') + '</h2><label for="pN">Nombre</label><input id="pN" maxlength="80" value="' + esc(p ? p.nombre : '') + '" placeholder="Ej: Distribuidora Andes">' +
      '<label for="pT">WhatsApp</label><input id="pT" inputmode="tel" maxlength="30" value="' + esc(p ? p.telefono : '') + '" placeholder="+56 9 1234 5678">' +
      '<label for="pE">Correo</label><input id="pE" type="email" maxlength="120" value="' + esc(p ? p.email : '') + '">' +
      '<label for="pO">Nota (vendedor, día de despacho…)</label><input id="pO" maxlength="300" value="' + esc(p ? p.nota : '') + '">' +
      '<div class="btns">' + (p ? '<button class="danger" id="pB" type="button">🗑️ Borrar</button>' : '') + '<button class="ghost" data-cerrar>Cancelar</button><button id="pG" type="button">💾 Guardar</button></div>');
    d.querySelector('#pG').onclick = async () => {
      try {
        await rpc('taller_proveedor_guardar', { p: { id: p ? p.id : null, nombre: d.querySelector('#pN').value, telefono: d.querySelector('#pT').value, email: d.querySelector('#pE').value, nota: d.querySelector('#pO').value } });
        d.close(); toast('💾 Guardado'); await cargarStock(); verStock();
      } catch (e) { toast(e.message); }
    };
    const b = d.querySelector('#pB');
    if (b) b.onclick = async () => { if (!await confirmar('¿Borrar a ' + p.nombre + '? Sus repuestos quedan sin proveedor.')) return; try { await rpc('taller_proveedor_borrar', { p_id: p.id }); d.close(); verStock(); } catch (e) { toast(e.message); } };
  }
  // 🛒 Pedido: lo que está en el mínimo o menos, agrupado por proveedor → 📲 WhatsApp / ✉️ correo → 📥 Llegó (suma al stock).
  function verPedido() {
    const bajos = porPedir(), grupos = {};
    bajos.forEach((x) => { (grupos[x.proveedor_id || ''] = grupos[x.proveedor_id || ''] || []).push(x); });
    const texto = (l) => 'Hola 👋 Te escribimos de ' + P.taller.nombre + '. Queremos pedir:\n' + l.map((x) => '• ' + cantPedir(x) + ' × ' + x.nombre).join('\n') + '\n¿Nos confirmas precio y cuándo llega? Gracias 🙌';
    const d = modal('<h2>🛒 Pedido a proveedores</h2><p class="muted" style="margin-top:0">Lo que está en el mínimo o menos. Cuando llegue, toca 📥 y se suma al stock.</p>' +
      Object.keys(grupos).map((k) => {
        const p = ST.proveedores.find((v) => v.id === k), l = grupos[k], t = texto(l);
        return '<div class="card" style="margin:10px 0"><h3 style="margin-top:0">🚚 ' + (p ? esc(p.nombre) : 'Sin proveedor') + '</h3><ul class="list">' + l.map((x) => '<li><span class="grow">' + esc(x.nombre) + ' <span class="sub">(quedan ' + x.stock + ')</span></span><b>' + cantPedir(x) + '</b></li>').join('') + '</ul><div class="btns">' +
          (p && p.telefono ? '<a class="btn small" target="_blank" rel="noopener" href="' + App.wa(p.telefono, t) + '">📲 WhatsApp</a>' : '') +
          (p && p.email ? '<a class="btn small alt" href="mailto:' + encodeURIComponent(p.email) + '?subject=' + encodeURIComponent('Pedido de ' + P.taller.nombre) + '&body=' + encodeURIComponent(t) + '">✉️ Correo</a>' : '') +
          (!p || (!p.telefono && !p.email) ? '<button class="small alt" type="button" data-copiar="' + esc(k) + '">📋 Copiar pedido</button>' : '') +
          '<button class="small okb" type="button" data-llego="' + esc(k) + '">📥 Llegó</button></div></div>';
      }).join('') + '<div class="btns"><button class="ghost" data-cerrar>Cerrar</button></div>');
    d.onclick = async (e) => {
      const c = e.target.closest('[data-copiar]');
      if (c) { navigator.clipboard.writeText(texto(grupos[c.dataset.copiar])).then(() => toast('📋 Pedido copiado')); return; }
      const ll = e.target.closest('[data-llego]'); if (!ll) return;
      const l = grupos[ll.dataset.llego], p = {}; l.forEach((x) => { p[x.id] = cantPedir(x); });
      try { await rpc('taller_stock_sumar', { p }); toast('📥 Stock sumado'); d.close(); await cargarPanel(); verStock(); } catch (err) { toast(err.message); }
    };
  }
  // ---- G59e 🧩 🏷️ Bicis usadas certificadas (informe 50 puntos + fotos + garantía → tu página) + 🔄 Parte de pago
  const INF = () => (window.CFX_FABRICA ? CFX_FABRICA.INFORME : []);
  const INF_SIG = { '': 'ok', ok: 'ajuste', ajuste: 'cambio', cambio: '' };
  const EST_U = { borrador: ['📝 Borrador', ''], publicada: ['🏷️ Publicada', 'ok'], vendida: ['✅ Vendida', 'warn'] };
  const linkUsada = (tk) => App.ROOT + 'u/?t=' + tk;
  const modOfrecer = (k, tit, txt) => '<div class="card"><h2>' + tit + ' <span class="pill pro">🧩 MÓDULO</span></h2><p class="muted">' + txt + '</p>' +
    '<div class="btns"><button type="button" data-sin-atras data-ofrecer="' + k + '">🧩 Ver el módulo</button></div></div>';
  async function verUsadas() {
    body().innerHTML = '<p class="empty">Cargando…</p>';
    let s;
    try { s = await rpc('taller_usadas'); } catch (e) { body().innerHTML = '<p class="err">' + esc(e.message) + '</p>'; return; }
    if (s.bloqueado) { body().innerHTML = modOfrecer('certificadas', '🏷️ Bicis usadas certificadas', 'Revisa la bici en 50 puntos, súbele fotos y garantía, y publícala en tu página. Te escriben por WhatsApp para comprarla u ofertar.'); return; }
    const pub = s.bicis.filter((b) => b.estado === 'publicada').length;
    body().innerHTML = '<div class="card"><h2>🏷️ Bicis usadas <span class="pill">' + s.bicis.length + '</span></h2><p class="sub" style="margin-top:0">Revisa los 50 puntos, sube fotos y publícala: sale en tu página con su informe y garantía.</p>' +
      '<ul class="list" id="uLista">' + (s.bicis.length ? s.bicis.map((b) => '<li class="clic" data-u="' + b.id + '">' +
        (b.mini ? '<img alt="" src="' + esc(b.mini) + '" style="width:48px;height:48px;object-fit:cover;border-radius:10px;flex:none">' : '<span style="font-size:28px;flex:none">🚲</span>') +
        '<div class="grow"><b>' + esc(b.titulo) + '</b><div class="sub">' + (b.precio ? plata(b.precio) + ' · ' : '') + '🔍 ' + b.revisados + '/50</div></div>' +
        '<span class="pill ' + EST_U[b.estado][1] + '">' + EST_U[b.estado][0] + '</span></li>').join('') : '<li class="muted">Toca ＋ para inspeccionar tu primera bici usada.</li>') + '</ul>' +
      '<div class="btns"><button id="uNueva" type="button">＋ Nueva bici usada</button>' + (pub ? '<a class="btn ghost" target="_blank" rel="noopener" href="' + esc(linkReservas()) + '">👀 Ver en mi página</a>' : '') + '</div></div>';
    body().onclick = (e) => {
      const u = e.target.closest('[data-u]'); if (u) { editarUsada(u.dataset.u); return; }
      if (e.target.closest('#uNueva')) editarUsada(null);
    };
  }
  async function editarUsada(id, base) {
    let x;
    try { x = id ? await rpc('taller_usada', { p_id: id }) : Object.assign({ titulo: '', talla: '', anio: null, precio: 0, garantia: 3, nota: '', informe: {}, fotos: [], estado: 'borrador' }, base || {}); }
    catch (e) { toast(e.message); return; }
    const inf = Object.assign({}, x.informe || {}); let fotos = (x.fotos || []).slice(), fotosCambio = false;
    const cuenta = () => Object.values(inf).filter((v) => INF_EST()[v]).length;
    const INF_EST = () => (window.CFX_FABRICA ? CFX_FABRICA.INF_EST : {});
    const d = modal('<h2>' + (id ? '🏷️ ' + esc(x.titulo) : '＋ Nueva bici usada') + '</h2>' +
      '<label for="uT">Marca y modelo</label><input id="uT" maxlength="100" value="' + esc(x.titulo) + '" placeholder="Ej: Trek Marlin 7">' +
      '<div class="row"><div><label for="uTa">Talla</label><input id="uTa" maxlength="20" value="' + esc(x.talla) + '" placeholder="M · 54 · aro 29"></div><div><label for="uA">Año</label><input id="uA" inputmode="numeric" maxlength="4" value="' + (x.anio || '') + '"></div></div>' +
      '<div class="row"><div><label for="uP">Precio de venta</label><input id="uP" inputmode="numeric" value="' + (x.precio || '') + '"></div><div><label for="uG">🛡️ Garantía</label><select id="uG">' +
        [0, 1, 3, 6, 12].map((m) => '<option value="' + m + '"' + (+x.garantia === m ? ' selected' : '') + '>' + (m ? m + (m === 1 ? ' mes' : ' meses') : 'Sin garantía') + '</option>').join('') + '</select></div></div>' +
      '<label for="uN">Detalle (opcional)</label><textarea id="uN" maxlength="600" rows="2" placeholder="Ej: grupo Deore 1x12, frenos hidráulicos">' + esc(x.nota) + '</textarea>' +
      '<h3>📸 Fotos <span class="sub">(hasta 4)</span></h3><p class="sub" style="margin-top:0">De lado completo, con fondo blanco o pared lisa.</p><div id="uFotos" style="display:flex;gap:8px;flex-wrap:wrap"></div><input type="file" accept="image/*" id="uF" class="hidden">' +
      '<h3>🔍 Informe de 50 puntos <span class="pill" id="uCont"></span></h3><p class="sub" style="margin-top:0">Toca cada punto: ⬜ → ✅ Bien → 🔧 Ajustado → 🔁 Cambiado.</p>' +
      '<div id="uInf"></div><div class="btns"><button class="small ghost" id="uTodo" type="button" data-sin-atras>✅ Todo bien en lo que falta</button></div>' +
      '<div class="btns">' + (id && P.dueno ? '<button class="danger" id="uB" type="button">🗑️ Borrar</button>' : '') +
        (x.estado !== 'borrador' && x.token ? '<button class="ghost" id="uC" type="button">📲 Compartir</button>' : '') +
        '<button class="ghost" id="uG2" type="button">💾 Guardar</button>' +
        (x.estado === 'publicada' ? '<button class="okb" id="uV" type="button">✅ Se vendió</button>' : '<button id="uPub" type="button">📣 Publicar</button>') + '</div>');
    const q1 = (s) => d.querySelector(s);
    const pintarFotos = () => {
      q1('#uFotos').innerHTML = fotos.map((f, i) => '<div style="position:relative"><img alt="Foto ' + (i + 1) + '" src="' + esc(f) + '" style="width:72px;height:72px;object-fit:cover;border-radius:10px">' +
        '<button class="small ghost" type="button" data-sin-atras data-fb="' + i + '" aria-label="Borrar foto" style="position:absolute;top:-6px;right:-6px;min-height:0;padding:2px 6px">✕</button></div>').join('') +
        (fotos.length < 4 ? '<button class="ghost" type="button" data-sin-atras id="uFm" style="width:72px;height:72px;min-height:0;font-size:24px" aria-label="Agregar foto">📷</button>' : '');
    };
    const pintarInf = () => {
      const E = INF_EST();
      q1('#uInf').innerHTML = INF().map(([g, ps]) => {
        const n = ps.filter(([k]) => E[inf[k]]).length;
        return '<details data-g="' + esc(g) + '"><summary class="clic" style="font-weight:700;margin:6px 0">' + esc(g) + ' <span class="pill ' + (n === 5 ? 'ok' : '') + '">' + n + '/5</span></summary><ul class="list">' +
          ps.map(([k, t]) => '<li class="clic" data-p="' + k + '"><span style="width:26px;flex:none">' + (E[inf[k]] ? E[inf[k]][0] : '⬜') + '</span><span class="grow">' + esc(t) + '</span><span class="sub">' + (E[inf[k]] ? E[inf[k]][1] : '') + '</span></li>').join('') + '</ul></details>';
      }).join('');
      const c = cuenta(); q1('#uCont').textContent = c + '/50'; q1('#uCont').className = 'pill ' + (c >= 50 ? 'ok' : 'warn');
    };
    pintarFotos(); pintarInf();
    if (window.CFX_FABRICA) CFX_FABRICA.bici(q1('#uT'));
    q1('#uInf').onclick = (e) => {
      const li = e.target.closest('[data-p]'); if (!li) return;
      const k = li.dataset.p, v = INF_SIG[inf[k] || ''];
      if (v) inf[k] = v; else delete inf[k];
      const E = INF_EST(); li.firstChild.textContent = E[v] ? E[v][0] : '⬜'; li.lastChild.textContent = E[v] ? E[v][1] : '';
      const det = li.closest('details'), n = [...det.querySelectorAll('[data-p]')].filter((l) => E[inf[l.dataset.p]]).length;
      det.querySelector('summary .pill').textContent = n + '/5'; det.querySelector('summary .pill').className = 'pill ' + (n === 5 ? 'ok' : '');
      const c = cuenta(); q1('#uCont').textContent = c + '/50'; q1('#uCont').className = 'pill ' + (c >= 50 ? 'ok' : 'warn');
    };
    q1('#uTodo').onclick = () => { INF().forEach(([, ps]) => ps.forEach(([k]) => { if (!INF_EST()[inf[k]]) inf[k] = 'ok'; })); pintarInf(); };
    q1('#uFotos').onclick = (e) => {
      const b = e.target.closest('[data-fb]'); if (b) { fotos.splice(+b.dataset.fb, 1); fotosCambio = true; pintarFotos(); return; }
      if (e.target.closest('#uFm')) q1('#uF').click();
    };
    q1('#uF').onchange = async (e) => {
      const f = e.target.files[0]; e.target.value = ''; if (!f) return;
      try { fotos.push(await App.comprimirFoto(f)); fotosCambio = true; pintarFotos(); } catch (err) { toast(err.message); }
    };
    const guardar = async (estado) => {
      const p = { id: id || null, titulo: q1('#uT').value, talla: q1('#uTa').value, anio: App.numero(q1('#uA').value) || null, precio: App.numero(q1('#uP').value),
        garantia: +q1('#uG').value, nota: q1('#uN').value, informe: inf, estado };
      if (fotosCambio || !id) {
        p.fotos = fotos;
        p.mini = '';
        if (fotos.length && window.CFX_ACHICAR) { try { p.mini = await window.CFX_ACHICAR(fotos[0], 'logo'); } catch (e) { p.mini = ''; } }
      }
      try {
        const nid = await rpc('taller_usada_guardar', { p });
        d.close(); toast(estado === 'publicada' ? '📣 Publicada en tu página' : estado === 'vendida' ? '✅ Marcada como vendida' : '💾 Guardado'); verUsadas();
        return nid;
      } catch (err) { toast(err.message); return null; }
    };
    q1('#uG2').onclick = () => guardar(x.estado || 'borrador');
    const pb = q1('#uPub'); if (pb) pb.onclick = () => guardar('publicada');
    const vb = q1('#uV'); if (vb) vb.onclick = async () => {
      if (!await confirmar('¿Se vendió "' + x.titulo + '"? Sale de tu página.')) return;
      const ok = await guardar('vendida');
      // G59h 🛡️ la garantía de la bici usada pasa al comprador.
      if (ok && tiene('garantias') && x.garantia > 0) editarGarantia(null, { usada: id, bici: x.titulo, cubre: 'bici', meses: x.garantia, detalle: 'Bici usada certificada (informe de 50 puntos)' });
    };
    const cb = q1('#uC'); if (cb) cb.onclick = () => App.compartir(linkUsada(x.token), '🏷️ ' + x.titulo + ' certificada en ' + P.taller.nombre, x.titulo);
    const bb = q1('#uB'); if (bb) bb.onclick = async () => { if (!await confirmar('¿Borrar "' + x.titulo + '"?')) return; try { await rpc('taller_usada_borrar', { p_id: id }); d.close(); verUsadas(); } catch (e) { toast(e.message); } };
  }

  // 🔄 Parte de pago (trade-in): cuánto ofrecer por la bici usada del cliente. No guarda nada; puede pasarla a 🏷️ Usadas.
  const ESTADO_TI = [['1', '✨ Como nueva'], ['0.85', '👍 Buena'], ['0.7', '🙂 Con uso'], ['0.5', '🔧 Para arreglar']];
  const r5 = (v) => Math.max(Math.round(v / 5000) * 5000, 0);
  function tasar(nuevo, anio, estado, arreglos, margen) {
    const edad = Math.max(new Date().getFullYear() - (anio || new Date().getFullYear()), 0);
    const venta = r5(nuevo * Math.max(0.75 * Math.pow(0.88, edad), 0.2) * estado);
    const oferta = r5(venta * (1 - margen / 100) - arreglos);
    return { venta, oferta, gana: venta - oferta - arreglos };
  }
  function verTradein() {
    if (!tiene('tradein')) { body().innerHTML = modOfrecer('tradein', '🔄 Parte de pago', 'El cliente trae su bici usada: la calculadora te dice cuánto ofrecerle para que se lleve una nueva o un arreglo, y cuánto ganas al revenderla.'); return; }
    let mg = 25; try { mg = +localStorage.getItem('cfx_ti_margen') || 25; } catch (e) { /* sin almacenamiento */ }
    const ano = new Date().getFullYear();
    body().innerHTML = '<div class="card"><h2>🔄 Parte de pago</h2><p class="sub" style="margin-top:0">Llena los datos de la bici que trae el cliente y te digo cuánto ofrecerle.</p>' +
      '<label for="tiT">Marca y modelo</label><input id="tiT" maxlength="100" placeholder="Ej: Oxford Mercury">' +
      '<div class="row"><div><label for="tiA">Año</label><input id="tiA" inputmode="numeric" maxlength="4" value="' + (ano - 2) + '"></div><div><label for="tiE">Estado</label><select id="tiE">' +
        ESTADO_TI.map(([v, t]) => '<option value="' + v + '"' + (v === '0.85' ? ' selected' : '') + '>' + t + '</option>').join('') + '</select></div></div>' +
      '<label for="tiN">Precio de una igual nueva hoy</label><input id="tiN" inputmode="numeric" placeholder="Ej: 450000">' +
      '<div class="row"><div><label for="tiR">Arreglos que necesita</label><input id="tiR" inputmode="numeric" placeholder="0"></div><div><label for="tiM">Tu ganancia %</label><input id="tiM" inputmode="numeric" value="' + mg + '"></div></div>' +
      '<div id="tiRes" style="margin-top:12px"></div></div>';
    const b = body(), v = (s) => b.querySelector(s);
    const calc = () => {
      const nuevo = App.numero(v('#tiN').value), m = Math.min(Math.max(App.numero(v('#tiM').value), 0), 90);
      try { localStorage.setItem('cfx_ti_margen', String(m)); } catch (e) { /* sin almacenamiento */ }
      if (!nuevo) { v('#tiRes').innerHTML = '<p class="muted">Pon el precio de una nueva para calcular.</p>'; return; }
      const r = tasar(nuevo, App.numero(v('#tiA').value), +v('#tiE').value, App.numero(v('#tiR').value), m);
      const txt = 'Hola 👋 Por tu ' + (v('#tiT').value.trim() || 'bici') + ' te ofrecemos ' + plata(r.oferta) + ' en parte de pago en ' + P.taller.nombre + ' 🚲';
      v('#tiRes').innerHTML = '<div class="aviso ok"><div class="grow"><div>🏷️ Se vende en <b>' + plata(r.venta) + '</b></div><div style="font-size:1.25em;margin:4px 0">🔄 Ofrécele <b id="tiOf">' + plata(r.oferta) + '</b></div>' +
        '<div class="sub">Ganas ~' + plata(r.gana) + ' al revenderla (ya restados los arreglos).</div></div></div>' +
        '<div class="btns"><button class="ghost" type="button" id="tiCop">📋 Copiar oferta</button>' + (tiene('certificadas') ? '<button type="button" id="tiUs">🏷️ Pasar a usadas</button>' : '') + '</div>';
      v('#tiCop').onclick = () => navigator.clipboard.writeText(txt).then(() => toast('📋 Oferta copiada'));
      const u = v('#tiUs'); if (u) u.onclick = () => editarUsada(null, { titulo: v('#tiT').value.trim(), anio: App.numero(v('#tiA').value) || null, precio: r.venta, nota: 'Recibida en parte de pago.' });
    };
    b.querySelectorAll('input').forEach((i) => { i.oninput = calc; }); v('#tiE').onchange = calc;  // sin onchange en inputs: al salir del campo repintaba y se perdía el toque
    if (window.CFX_FABRICA) CFX_FABRICA.bici(v('#tiT'));
    calc();
  }

  // ---- G59f 🧩 🪪 Pasaporte de la bici: sticker QR en el cuadro (historial, dueño, robo reportado) → ficha pública /p/
  const linkPas = (x, dueno) => App.ROOT + 'p/?t=' + x.token + (dueno ? '&c=' + x.clave : '');
  async function verPasaportes() {
    body().innerHTML = '<p class="empty">Cargando…</p>';
    let s;
    try { s = await rpc('taller_pasaportes'); } catch (e) { body().innerHTML = '<p class="err">' + esc(e.message) + '</p>'; return; }
    if (s.bloqueado) { body().innerHTML = modOfrecer('pasaporte', '🪪 Pasaporte de la bici', 'Pégale un sticker QR al cuadro: guarda el historial de mantenciones y el dueño. Si se la roban, quien la escanee ve “REPORTADA COMO ROBADA”.'); return; }
    const L = s.pasaportes;
    body().innerHTML = '<div class="card"><h2>🪪 Pasaportes <span class="pill">' + L.length + '</span></h2><p class="sub" style="margin-top:0">Cada bici con su sticker QR: historial, dueño y aviso de robo. Créalo desde la orden o aquí.</p>' +
      (L.length > 6 ? '<input id="pBus" type="search" placeholder="🔍 Buscar bici, nº de serie o dueño" aria-label="Buscar pasaporte">' : '') +
      '<ul class="list" id="pLista"></ul><div class="btns"><button id="pNuevo" type="button">＋ Nuevo pasaporte</button></div></div>';
    const pintar = () => {
      const f = (body().querySelector('#pBus') || { value: '' }).value.trim().toLowerCase();
      const l = L.filter((x) => !f || (x.bici + ' ' + x.serie + ' ' + x.dueno + ' ' + x.telefono).toLowerCase().includes(f));
      body().querySelector('#pLista').innerHTML = l.length ? l.map((x) => '<li class="clic" data-pa="' + x.id + '"><span style="font-size:26px;flex:none">' + (x.robada ? '🚨' : '🚲') + '</span>' +
        '<div class="grow"><b>' + esc(x.bici) + '</b><div class="sub">' + esc([x.dueno, x.serie && 'Nº ' + x.serie].filter(Boolean).join(' · ')) + ' · 🔧 ' + x.servicios + '</div></div>' +
        (x.robada ? '<span class="pill bad">' + 'Robada' + (x.visto_at ? ' · vista ' + esc(App.hace(x.visto_at)) : '') + '</span>' : '') + '</li>').join('') : '<li class="muted">' + (L.length ? 'Nada con esa búsqueda.' : 'Toca ＋ o abre una orden → 🪪 Pasaporte.') + '</li>';
    };
    pintar();
    const bus = body().querySelector('#pBus'); if (bus) bus.oninput = pintar;
    body().onclick = (e) => {
      const u = e.target.closest('[data-pa]'); if (u) { editarPasaporte(u.dataset.pa); return; }
      if (e.target.closest('#pNuevo')) editarPasaporte(null);
    };
  }
  // Sticker para imprimir y pegar en el cuadro (2 por si se pierde uno).
  function stickerPas(x) {
    const w = window.open('', '_blank');
    if (!w) { toast('Permite las ventanas emergentes para imprimir'); return; }
    let img = ''; try { const qr = window.qrcode(0, 'M'); qr.addData(linkPas(x)); qr.make(); img = qr.createDataURL(8, 4); } catch (e) { img = ''; }
    const uno = '<div class="s"><b>🪪 PASAPORTE DE LA BICI</b><img alt="QR" src="' + img + '"><span>Escanéame: QR de seguridad de la bici</span><small>' + esc(P.taller.nombre) + '</small></div>';
    w.document.write('<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Sticker ' + esc(x.bici) + '</title><style>body{font-family:system-ui,sans-serif;margin:20px;color:#0f172a}' +
      '.s{display:inline-flex;flex-direction:column;align-items:center;gap:4px;width:5cm;padding:8px;margin:6px;border:2px dashed #94a3b8;border-radius:12px;text-align:center}' +
      '.s b{font-size:11px}.s img{width:4cm;height:4cm;image-rendering:pixelated}.s span{font-size:10px}.s small{font-size:9px;color:#475569}</style></head><body>' + uno + uno +
      '<script>window.onload=function(){setTimeout(function(){window.print()},300)}<\/script></body></html>');
    w.document.close();
  }
  async function editarPasaporte(id, base, alGuardar) {
    let x;
    try { x = id ? await rpc('taller_pasaporte', { p_id: id }) : Object.assign({ bici: '', serie: '', color: '', dueno: '', telefono: '', robada: false, robada_nota: '', historial: [] }, base || {}); }
    catch (e) { toast(e.message); return; }
    const d = modal('<h2>' + (id ? '🪪 ' + esc(x.bici) : '🪪 Nuevo pasaporte') + '</h2>' +
      (x.robada ? '<div class="aviso bad" style="display:block"><b>🚨 Reportada como robada</b>' + (x.robada_at ? ' el ' + App.fCorta(x.robada_at.slice(0, 10)) : '') + (x.robada_nota ? '<div class="sub">' + esc(x.robada_nota) + '</div>' : '') +
        '<div class="sub">' + (x.silencio ? '🕵️ Rastreo silencioso: quien la escanea no ve el aviso.' : '📢 Quien la escanea ve el aviso de robo.') + '</div></div>' : '') +
      (id && (x.robada || (x.rastros || []).length) ? '<h3>📍 Dónde está</h3><div id="paRas">' + App.rastros(x.rastros) + '</div>' +
        '<div class="btns"><button type="button" class="alt" id="paK">📄 Constancia para Carabineros</button>' + (x.robada && x.telefono ? '<button type="button" class="alt" id="paAv">📲 Avisar al dueño</button>' : '') + '</div>' : '') +
      '<label for="paB">Marca y modelo</label><input id="paB" maxlength="120" value="' + esc(x.bici) + '" placeholder="Ej: Trek Marlin 7 aro 29">' +
      '<div class="row"><div><label for="paS">Nº de serie</label><input id="paS" maxlength="60" value="' + esc(x.serie) + '" placeholder="Bajo el pedalier"></div><div><label for="paC">Color</label><input id="paC" maxlength="40" value="' + esc(x.color) + '"></div></div>' +
      '<div class="row"><div><label for="paD">Dueño</label><input id="paD" maxlength="80" value="' + esc(x.dueno) + '"></div><div><label for="paT">Teléfono</label><input id="paT" maxlength="30" inputmode="tel" value="' + esc(x.telefono) + '"></div></div>' +
      (id ? '<h3>🔧 Historial <span class="pill">' + x.historial.length + '</span></h3>' + (x.historial.length ? '<ul class="list">' + x.historial.map((h) => '<li><div class="grow"><b>' + App.fCorta(h.fecha) + '</b> · ' + esc(h.servicio) +
        (h.trabajos.length ? '<div class="sub">' + esc(h.trabajos.join(', ')) + '</div>' : '') + '</div></li>').join('') + '</ul>' : '<p class="sub">Cada orden lista o entregada de esta bici queda aquí.</p>') : '') +
      '<div class="btns">' + (id && P.dueno ? '<button class="danger" id="paX" type="button">🗑️ Borrar</button>' : '') +
        (id ? '<button class="' + (x.robada ? 'okb' : 'danger') + '" id="paR" type="button">' + (x.robada ? '✅ La recuperó' : '🚨 Reportar robo') + '</button>' : '') +
        '<button id="paG" type="button">💾 ' + (id ? 'Guardar' : 'Crear pasaporte') + '</button></div>' +
      (id ? '<div class="btns"><button class="alt" id="paQ" type="button">🖨️ Sticker QR</button>' + (x.telefono ? '<a class="btn alt" id="paW" target="_blank" rel="noopener" href="' + App.wa(x.telefono, 'Hola ' + x.dueno.split(' ')[0] +
        ' 👋 Te escribimos de ' + P.taller.nombre + ': este es el 🪪 pasaporte de tu ' + x.bici + '. Ahí ves su historial y, si te la roban, la reportas en 1 toque 👉 ' + linkPas(x, true)) + '">📲 Enviar al dueño</a>' : '') +
        '<a class="btn ghost" target="_blank" rel="noopener" href="' + esc(linkPas(x)) + '">👀 Ver ficha</a></div>' : ''));
    const q1 = (s) => d.querySelector(s);
    App.mapas(d);  // G91 📍 mapa Leaflet con el recorrido
    const pk = q1('#paK'); if (pk) pk.onclick = () => App.constancia(x, P.taller);  // G91 📄
    const pav = q1('#paAv'); if (pav) pav.onclick = async () => {  // G91 📲 al dueño sin cuenta: la última ubicación y su link para seguirla
      let y = x; try { y = await rpc('taller_pasaporte', { p_id: id }); } catch (e) { /* usa lo que ya tenía */ }
      const u = (y.rastros || []).find((r) => r.lat != null);
      window.open(App.wa(x.telefono, 'Hola ' + String(x.dueno || '').split(' ')[0] + ' 👋 Te escribimos de ' + P.taller.nombre + ' por tu ' + x.bici + ' reportada como robada. ' +
        (u ? '📍 La escanearon ' + App.hace(u.at) + ' aquí: https://www.google.com/maps?q=' + Number(u.lat).toFixed(6) + ',' + Number(u.lng).toFixed(6) + ' . ' : (y.rastros || []).length ? '👀 La escanearon, todavía sin ubicación. ' : 'Todavía nadie la escanea. ') +
        'Síguela en vivo aquí 👉 ' + linkPas(x, true)), '_blank', 'noopener');
    };
    if (window.CFX_FABRICA) CFX_FABRICA.bici(q1('#paB'));
    const datos = (robada, nota, sil) => ({ id: id || null, bici: q1('#paB').value, serie: q1('#paS').value, color: q1('#paC').value, dueno: q1('#paD').value, telefono: q1('#paT').value,
      reserva: x.reserva || null, robada, robada_nota: nota, silencio: sil === undefined ? !!x.silencio : sil });
    // G86 📍 con el pasaporte abierto y la bici robada, la ubicación se actualiza sola cada 15 s
    if (id && x.robada) { const tic = setInterval(async () => { if (!d.open) { clearInterval(tic); return; } if (document.hidden) return;
      try { const y = await rpc('taller_pasaporte', { p_id: id }), c = q1('#paRas'); if (c && d.open) { c.innerHTML = App.rastros(y.rastros); App.mapas(c); } } catch (e) { /* sin señal: reintenta */ } }, 15000); d.addEventListener('close', () => clearInterval(tic)); }
    const guardar = async (robada, nota, msg, sil) => {
      try {
        const nid = await rpc('taller_pasaporte_guardar', { p: datos(robada, nota, sil) });
        d.close(); toast(msg || '💾 Guardado');
        if (alGuardar) alGuardar(nid); else if (subMas === 'pasaporte') verPasaportes();
        if (!id) editarPasaporte(nid, null, alGuardar);
      } catch (err) { toast(err.message); }
    };
    q1('#paG').onclick = () => guardar(!!x.robada, x.robada_nota || '', id ? null : '🪪 Pasaporte creado: imprime el sticker');
    const rb = q1('#paR'); if (rb) rb.onclick = async () => {
      if (x.robada) { if (await confirmar('¿' + (x.dueno.split(' ')[0] || 'El dueño') + ' recuperó la ' + x.bici + '? Se quita el aviso de robo.')) guardar(false, '', '✅ Aviso de robo quitado'); return; }
      const m = modal('<h2>🚨 Reportar robo</h2><label for="rbN">Dónde y cuándo se la robaron</label><input id="rbN" maxlength="300">' +
        '<label style="display:flex;gap:8px;align-items:flex-start;font-weight:400;margin-top:10px"><input type="checkbox" id="rbS" checked style="width:auto;flex:none;margin-top:3px">' +
        '<span>🕵️ Rastreo silencioso: quien la escanee no ve el aviso de robo (así no sospecha) y les llega su ubicación.</span></label>' +
        '<div class="btns"><button class="ghost" type="button" data-cerrar>Cancelar</button><button class="danger" id="rbOk" type="button">🚨 Reportar</button></div>');
      m.querySelector('#rbOk').onclick = () => { const n = m.querySelector('#rbN').value, sil = m.querySelector('#rbS').checked; m.close();
        guardar(true, n, sil ? '🚨 Reportada: rastreo silencioso activo' : '🚨 Reportada como robada', sil); };
    };
    const qb = q1('#paQ'); if (qb) qb.onclick = () => stickerPas(x);
    const xb = q1('#paX'); if (xb) xb.onclick = async () => { if (!await confirmar('¿Borrar el pasaporte de "' + x.bici + '"? El sticker QR deja de funcionar.')) return; try { await rpc('taller_pasaporte_borrar', { p_id: id }); d.close(); verPasaportes(); } catch (e) { toast(e.message); } };
  }

  // ---- G59i 🧩 🔁 Plan de mantención: el cliente paga al mes → N visitas incluidas + % de descuento al usarlo en la orden
  const MEDIOS = { efectivo: '💵 Efectivo', transferencia: '🏦 Transferencia', tarjeta: '💳 Tarjeta' };
  const planTxt = (p) => p.visitas + (p.visitas === 1 ? ' visita' : ' visitas') + ' al mes' + (p.descuento ? ' · ' + p.descuento + '% de descuento' : '');
  const venceSocio = (s) => !s.activa ? 'Pausado' : s.dias < 0 ? 'Venció el ' + App.fCorta(s.hasta) : s.dias === 0 ? 'Vence hoy' : 'Pagado hasta el ' + App.fCorta(s.hasta) + (s.dias <= 5 ? ' (' + s.dias + ' día' + (s.dias === 1 ? '' : 's') + ')' : '');
  const waSocio = (s, txt) => App.wa(s.telefono, 'Hola ' + (s.nombre || '').split(' ')[0] + ' 👋 Te escribimos de ' + P.taller.nombre + ': ' + txt);
  let PL = null;
  async function verPlanes() {
    body().innerHTML = '<p class="empty">Cargando…</p>';
    try { PL = await rpc('taller_planes'); } catch (e) { body().innerHTML = '<p class="err">' + esc(e.message) + '</p>'; return; }
    if (PL.bloqueado) { body().innerHTML = modOfrecer('plan_mant', '🔁 Plan de mantención', 'Tus clientes pagan al mes y tienen visitas incluidas y descuento. Tú tienes plata segura cada mes y ellos vuelven siempre.'); return; }
    const S = PL.socios, pv = S.filter((s) => s.activa && s.dias <= 5 && s.dias >= -7), al = S.filter((s) => s.activa && s.dias > 5), ven = S.filter((s) => !s.activa || s.dias < -7);
    const fila = (s) => '<li class="clic" data-so="' + s.id + '"><span style="font-size:24px;flex:none">' + (!s.vigente ? '⌛' : '🔁') + '</span>' +
      '<div class="grow"><b>' + esc(s.nombre) + '</b><div class="sub">' + esc([s.plan_nombre, s.bici].filter(Boolean).join(' · ')) + '</div><div class="sub">' +
      esc(venceSocio(s)) + (s.vigente ? ' · quedan ' + s.quedan + ' de ' + s.visitas : '') + '</div></div>' +
      (s.activa && s.dias <= 5 && s.dias >= -7 && s.telefono ? '<a class="btn small alt" target="_blank" rel="noopener" data-sin-atras href="' + waSocio(s, s.dias < 0 ? 'tu plan ' + s.plan_nombre + ' venció el ' + App.fCorta(s.hasta) + '. ¿Lo renovamos? 🔁' : 'tu plan ' + s.plan_nombre + ' vence el ' + App.fCorta(s.hasta) + '. ¿Lo renovamos? 🔁') + '">📲 Avisar</a>' : '') + '</li>';
    const sec = (tit, l) => l.length ? '<h3>' + tit + ' <span class="pill">' + l.length + '</span></h3><ul class="list">' + l.map(fila).join('') + '</ul>' : '';
    body().innerHTML = '<div class="card"><h2>🔁 Tus planes</h2><p class="sub" style="margin-top:0">El cliente paga al mes. Cuando trae la bici, en la orden tocas ✅ Usar el plan: gasta 1 visita y baja el total.</p>' +
      (PL.planes.length ? '<ul class="list">' + PL.planes.map((p) => '<li' + (P.dueno ? ' class="clic" data-pl="' + p.id + '"' : '') + '><span style="font-size:24px;flex:none">' + (p.activo ? '🔁' : '⏸️') + '</span><div class="grow"><b>' + esc(p.nombre) + '</b>' +
        (p.precio != null ? '<div><b style="white-space:nowrap">' + plata(p.precio) + '</b> al mes</div>' : '') + '<div class="sub">' + esc(planTxt(p)) + (p.activo ? '' : ' · ya no se vende') + '</div>' + (p.incluye ? '<div class="sub">' + esc(p.incluye) + '</div>' : '') +
        '</div><span class="pill">' + p.socios + ' 👤</span></li>').join('') + '</ul>' : '<p class="sub">' + (P.dueno ? 'Crea tu primer plan: ej. "Rodador" $15.000 al mes · 1 mantención + 10% de descuento.' : 'El dueño todavía no crea planes.') + '</p>') +
      (P.dueno ? '<div class="btns"><button id="plNuevo" type="button" class="' + (PL.planes.length ? 'alt' : '') + '">＋ Nuevo plan</button></div>' : '') + '</div>' +
      '<div class="card"><h2>👤 Clientes con plan <span class="pill">' + S.filter((s) => s.vigente).length + ' al día</span></h2>' +
      (PL.cobrado_mes != null ? '<p class="sub" style="margin-top:0">💰 Cobrado este mes: <b>' + plata(PL.cobrado_mes) + '</b></p>' : '') +
      (S.length ? sec('⏳ Por vencer', pv) + sec('✅ Al día', al) + (ven.length ? '<details><summary class="sub">⌛ Vencidos o pausados (' + ven.length + ')</summary><ul class="list">' + ven.map(fila).join('') + '</ul></details>' : '')
        : '<p class="sub">' + (PL.planes.length ? 'Suma al primer cliente y cóbrale el mes.' : 'Primero crea un plan.') + '</p>') +
      (P.dueno && PL.planes.some((p) => p.activo) ? '<div class="btns"><button id="soNuevo" type="button">＋ Sumar cliente</button></div>' : '') + '</div>';
    body().onclick = (e) => {
      if (e.target.closest('a')) return;
      const pl = e.target.closest('[data-pl]'); if (pl) { editarPlanMant(PL.planes.find((p) => p.id === pl.dataset.pl)); return; }
      const so = e.target.closest('[data-so]'); if (so) { editarSocio(S.find((s) => s.id === so.dataset.so)); return; }
      if (e.target.closest('#plNuevo')) editarPlanMant(null);
      if (e.target.closest('#soNuevo')) editarSocio(null);
    };
  }
  function editarPlanMant(p) {
    const nuevo = !p; p = p || { nombre: '', precio: '', visitas: 1, descuento: 10, incluye: '', activo: true };
    const d = modal('<h2>🔁 ' + (nuevo ? 'Nuevo plan' : esc(p.nombre)) + '</h2>' +
      '<label for="plN">Nombre</label><input id="plN" maxlength="60" value="' + esc(p.nombre) + '" placeholder="Ej: Rodador">' +
      '<div class="row"><div><label for="plP">Precio al mes</label><input id="plP" inputmode="numeric" value="' + esc(p.precio) + '" placeholder="15000"></div>' +
      '<div><label for="plV">Visitas al mes</label><select id="plV">' + [1, 2, 3, 4, 5, 6, 8, 10].map((v) => '<option' + (v === +p.visitas ? ' selected' : '') + '>' + v + '</option>').join('') + '</select></div></div>' +
      '<label for="plD">Descuento al usarlo (en el total de la orden)</label><select id="plD">' + [0, 5, 10, 15, 20, 25, 30, 40, 50].map((v) => '<option value="' + v + '"' + (v === +p.descuento ? ' selected' : '') + '>' + (v ? v + '%' : 'Sin descuento') + '</option>').join('') + '</select>' +
      '<label for="plI">Qué incluye (lo ve el cliente)</label><input id="plI" maxlength="300" value="' + esc(p.incluye) + '" placeholder="Ej: Ajuste de cambios y frenos, lubricación">' +
      (!nuevo ? '<label class="check"><input type="checkbox" id="plA"' + (p.activo ? ' checked' : '') + '> Se vende (sale en tu página)</label>' : '') +
      '<div class="btns">' + (!nuevo ? '<button class="danger" id="plX" type="button">🗑️ Borrar</button>' : '') + '<button id="plG" type="button">💾 Guardar</button></div>');
    const q1 = (s) => d.querySelector(s);
    q1('#plG').onclick = async () => {
      try {
        await rpc('taller_plan_guardar', { p: { id: nuevo ? null : p.id, nombre: q1('#plN').value, precio: App.numero(q1('#plP').value), visitas: +q1('#plV').value, descuento: +q1('#plD').value,
          incluye: q1('#plI').value, activo: q1('#plA') ? q1('#plA').checked : true } });
        d.close(); toast(nuevo ? '🔁 Plan creado: ahora suma clientes' : '💾 Guardado'); verPlanes();
      } catch (e) { toast(e.message); }
    };
    const xb = q1('#plX'); if (xb) xb.onclick = async () => { if (!await confirmar('¿Borrar el plan "' + p.nombre + '"?')) return; try { await rpc('taller_plan_borrar', { p_id: p.id }); d.close(); verPlanes(); } catch (e) { toast(e.message); } };
  }
  async function editarSocio(s, base, alGuardar) {
    if (!PL || !PL.planes) { try { PL = await rpc('taller_planes'); } catch (e) { toast(e.message); return; } }
    if (!P.dueno) { if (s) toast(s.nombre + ': ' + venceSocio(s) + (s.vigente ? ' · quedan ' + s.quedan + ' de ' + s.visitas + ' visitas este mes' : '') + '. Para cobrar, pídele al dueño.'); return; }
    const nuevo = !s; s = s || Object.assign({ nombre: '', telefono: '', bici: '', plan: (PL.planes.find((p) => p.activo) || {}).id, activa: true }, base || {});
    const planes = PL.planes.filter((p) => p.activo || p.id === s.plan);
    const d = modal('<h2>🔁 ' + (nuevo ? 'Sumar cliente al plan' : esc(s.nombre)) + '</h2>' +
      (!nuevo ? '<div class="aviso' + (s.vigente ? '' : ' warn') + '" style="display:block">' + esc(venceSocio(s)) + (s.vigente ? ' · quedan ' + s.quedan + ' de ' + s.visitas + ' visitas este mes' : '') + '</div>' : '') +
      '<label for="soP">Plan</label><select id="soP">' + planes.map((p) => '<option value="' + p.id + '"' + (p.id === s.plan ? ' selected' : '') + '>' + esc(p.nombre) + ' · ' + plata(p.precio) + '/mes</option>').join('') + '</select>' +
      '<div class="row"><div><label for="soN">Cliente</label><input id="soN" maxlength="80" value="' + esc(s.nombre) + '"></div><div><label for="soT">Teléfono</label><input id="soT" maxlength="30" inputmode="tel" value="' + esc(s.telefono) + '"></div></div>' +
      '<label for="soB">Bici</label><input id="soB" maxlength="120" value="' + esc(s.bici) + '">' +
      '<h3>💰 Cobrar</h3><div class="row"><div><select id="soM" aria-label="Meses"><option value="1">1 mes</option><option value="3">3 meses</option><option value="6">6 meses</option><option value="12">12 meses</option></select></div>' +
      '<div><select id="soMe" aria-label="Medio de pago">' + Object.keys(MEDIOS).map((k) => '<option value="' + k + '">' + MEDIOS[k] + '</option>').join('') + '</select></div></div>' +
      '<div class="btns"><button id="soC" type="button">💰 Cobrar y ' + (nuevo ? 'sumar' : 'renovar') + '</button>' + (!nuevo ? '<button class="alt" id="soG" type="button">💾 Solo guardar</button>' : '') + '</div>' +
      (!nuevo ? '<div class="btns">' + (s.telefono ? '<a class="btn alt" target="_blank" rel="noopener" href="' + waSocio(s, 'tu plan ' + s.plan_nombre + ' está ' + (s.vigente ? 'al día hasta el ' + App.fCorta(s.hasta) + '. Te quedan ' + s.quedan + ' visitas este mes 🔁' : 'vencido. ¿Lo renovamos? 🔁')) + '">📲 WhatsApp</a>' : '') +
        '<button class="ghost" id="soPa" type="button">' + (s.activa ? '⏸️ Pausar' : '▶️ Reactivar') + '</button><button class="danger" id="soX" type="button">🗑️ Borrar</button></div>' : ''));
    const q1 = (x) => d.querySelector(x);
    if (window.CFX_FABRICA) CFX_FABRICA.bici(q1('#soB'));
    const fin = () => { if (alGuardar) alGuardar(); else if (subMas === 'planes') verPlanes(); };
    const guardar = async (meses, activa) => {
      try {
        const x = await rpc('taller_socio_guardar', { p: { id: nuevo ? null : s.id, plan: q1('#soP').value, nombre: q1('#soN').value, telefono: q1('#soT').value, bici: q1('#soB').value,
          meses, medio: q1('#soMe').value, activa: activa === undefined ? null : activa } });
        d.close(); toast(meses ? '💰 Cobrado: pagado hasta el ' + App.fCorta(x.hasta) : '💾 Guardado'); fin();
      } catch (e) { toast(e.message); }
    };
    q1('#soC').onclick = () => guardar(+q1('#soM').value);
    const gb = q1('#soG'); if (gb) gb.onclick = () => guardar(0);
    const pa = q1('#soPa'); if (pa) pa.onclick = () => guardar(0, !s.activa);
    const xb = q1('#soX'); if (xb) xb.onclick = async () => { if (!await confirmar('¿Borrar el plan de ' + s.nombre + '? Se pierde su historial de cobros.')) return; try { await rpc('taller_socio_borrar', { p_id: s.id }); d.close(); fin(); } catch (e) { toast(e.message); } };
  }
  // En la orden: ¿el cliente tiene plan? → ✅ Usar el plan (1 visita + descuento) / ↩️ Quitar.
  async function pintarPlan(r) {
    const el = $('dPlan'); if (!el) return;
    if (!tiene('plan_mant') || !r.telefono) { el.innerHTML = ''; return; }
    let s = null; try { s = await rpc('taller_plan_orden', { p_reserva: r.id }); } catch (e) { el.innerHTML = ''; return; }
    if (!detalle || detalle.id !== r.id) return;
    const abierta = r.estado !== 'completada';
    el.innerHTML = !s ? (P.dueno && abierta ? '<p class="sub" style="margin:8px 0 0"><button class="small ghost" type="button" id="dPlanSumar" data-sin-atras>🔁 Ofrecerle un plan</button></p>' : '') :
      '<div class="aviso' + (s.usado ? '' : !s.vigente || !s.quedan ? ' warn' : '') + '" style="margin-top:10px;display:block"><div>🔁 ' +
      (s.usado ? 'Plan <b>' + esc(s.plan_nombre) + '</b> usado en esta orden' + (s.descuento ? ': −' + s.descuento + '% en el total' : '') + '.'
        : !s.vigente ? 'El plan <b>' + esc(s.plan_nombre) + '</b> de ' + esc(s.nombre.split(' ')[0]) + ' ' + (s.activa ? 'venció el ' + App.fCorta(s.hasta) : 'está pausado') + '.'
        : !s.quedan ? esc(s.nombre.split(' ')[0]) + ' ya usó sus ' + s.visitas + ' visitas del plan este mes.'
        : esc(s.nombre.split(' ')[0]) + ' tiene el plan <b>' + esc(s.plan_nombre) + '</b>: quedan ' + s.quedan + ' de ' + s.visitas + ' visitas este mes' + (s.descuento ? ' · −' + s.descuento + '%' : '') + '.') +
      '</div><div class="btns">' + (abierta && !s.usado && s.vigente && s.quedan ? '<button class="small okb" type="button" id="dPlanUsar" data-sin-atras>✅ Usar el plan</button>' : '') +
      (abierta && s.usado ? '<button class="small ghost" type="button" id="dPlanQuitar" data-sin-atras>↩️ Quitar el plan</button>' : '') +
      (!s.vigente && P.dueno ? '<button class="small" type="button" id="dPlanCobrar" data-sin-atras>💰 Cobrar el mes</button>' : '') + '</div></div>';
    const usar = async (si) => {
      try {
        if (si) await guardarTrabajo(true);
        await rpc('taller_plan_usar', { p_reserva: r.id, p_usar: si });
        detalle.plan_desc = si ? s.descuento : 0; totalItems(); pintarPlan(r);
        toast(si ? '🔁 Plan usado' + (s.descuento ? ': −' + s.descuento + '%' : '') : '↩️ Plan quitado');
      } catch (e) { toast(e.message); }
    };
    const u = $('dPlanUsar'); if (u) u.onclick = () => usar(true);
    const qb = $('dPlanQuitar'); if (qb) qb.onclick = () => usar(false);
    const cb = $('dPlanCobrar'); if (cb) cb.onclick = () => editarSocio(s, null, () => pintarPlan(r));
    const sb2 = $('dPlanSumar'); if (sb2) sb2.onclick = async () => {
      try { PL = await rpc('taller_planes'); } catch (e) { toast(e.message); return; }
      if (!PL.planes.some((p) => p.activo)) { toast('Primero crea un plan en Más → 🔁 Planes'); return; }
      editarSocio(null, { nombre: r.nombre, telefono: r.telefono, bici: r.bici }, () => pintarPlan(r));
    };
  }

  // ---- G59h 🧩 🛡️ Garantías: del trabajo, repuestos o bici usada, con vencimiento → link del cliente /g/ (la "usa" en 1 toque)
  const CUBRE = { trabajo: '🔧 El trabajo', repuestos: '📦 Los repuestos', todo: '🔧📦 Trabajo y repuestos', bici: '🚲 La bici' };
  const linkGar = (g) => App.ROOT + 'g/?t=' + g.token;
  const venceTxt = (g) => g.dias < 0 ? 'Venció el ' + App.fCorta(g.hasta) : g.dias === 0 ? 'Vence hoy' : 'Vence el ' + App.fCorta(g.hasta) + (g.dias <= 30 ? ' (' + g.dias + ' día' + (g.dias === 1 ? '' : 's') + ')' : '');
  const waGar = (g, txt) => App.wa(g.telefono, 'Hola ' + (g.nombre || '').split(' ')[0] + ' 👋 Te escribimos de ' + P.taller.nombre + ': ' + txt + ' 👉 ' + linkGar(g));
  async function verGarantias() {
    body().innerHTML = '<p class="empty">Cargando…</p>';
    let s;
    try { s = await rpc('taller_garantias'); } catch (e) { body().innerHTML = '<p class="err">' + esc(e.message) + '</p>'; return; }
    if (s.bloqueado) { body().innerHTML = modOfrecer('garantias', '🛡️ Garantías', 'Al entregar, le das garantía del trabajo, de los repuestos o de la bici usada. El cliente la ve en su link y la usa en 1 toque: tú recibes el aviso.'); return; }
    const L = s.garantias, rec = L.filter((g) => g.reclamo === 'abierto'), pv = L.filter((g) => g.reclamo !== 'abierto' && g.dias >= 0 && g.dias <= 15),
      vig = L.filter((g) => g.reclamo !== 'abierto' && g.dias > 15), ven = L.filter((g) => g.reclamo !== 'abierto' && g.dias < 0);
    const fila = (g) => '<li class="clic" data-ga="' + g.id + '"><span style="font-size:24px;flex:none">' + (g.reclamo === 'abierto' ? '🔔' : g.dias < 0 ? '⌛' : '🛡️') + '</span>' +
      '<div class="grow"><b>' + esc(g.bici || 'Bici') + '</b><div class="sub">' + esc([g.nombre, CUBRE[g.cubre]].filter(Boolean).join(' · ')) + '</div><div class="sub">' +
      (g.reclamo === 'abierto' ? '<b>Usó la garantía:</b> ' + esc(g.reclamo_nota) : esc(venceTxt(g))) + '</div></div>' +
      (g.reclamo !== 'abierto' && g.dias >= 0 && g.dias <= 15 && g.telefono ? '<a class="btn small alt" target="_blank" rel="noopener" data-sin-atras href="' + waGar(g, 'la garantía de tu ' + (g.bici || 'bici') + ' vence el ' + App.fCorta(g.hasta) + '. Si notas algo raro, tráela antes y te la revisamos sin costo') + '">📲 Avisar</a>' : '') + '</li>';
    const sec = (tit, l, vacio) => l.length ? '<h3>' + tit + ' <span class="pill">' + l.length + '</span></h3><ul class="list">' + l.map(fila).join('') + '</ul>' : (vacio ? '<p class="sub">' + vacio + '</p>' : '');
    body().innerHTML = '<div class="card"><h2>🛡️ Garantías <span class="pill">' + (L.length - ven.length) + ' vigente' + (L.length - ven.length === 1 ? '' : 's') + '</span></h2><p class="sub" style="margin-top:0">Dala desde la orden lista o entregada (🛡️ Garantía) o aquí. El cliente la ve en su link y la usa en 1 toque.</p>' +
      sec('🔔 La usaron', rec) + sec('⏳ Por vencer', pv) + sec('✅ Vigentes', vig, L.length ? '' : 'Todavía no das garantías. Abre una orden lista → 🛡️ Garantía.') +
      (ven.length ? '<details><summary class="sub">⌛ Vencidas (' + ven.length + ')</summary><ul class="list">' + ven.map(fila).join('') + '</ul></details>' : '') +
      '<div class="btns"><button id="gNueva" type="button">＋ Nueva garantía</button></div></div>';
    body().onclick = (e) => {
      if (e.target.closest('a')) return;
      const u = e.target.closest('[data-ga]'); if (u) { editarGarantia(u.dataset.ga); return; }
      if (e.target.closest('#gNueva')) editarGarantia(null, {});
    };
  }
  async function editarGarantia(id, base, alGuardar) {
    let g = null;
    try { g = id ? await rpc('taller_garantia', { p_id: id }) : base.reserva ? await rpc('taller_garantia', { p_id: null, p_reserva: base.reserva }) : null; } catch (e) { toast(e.message); return; }
    const nueva = !g;
    if (nueva) g = Object.assign({ nombre: '', telefono: '', bici: '', cubre: 'trabajo', detalle: '', meses: 3, reclamo: '' }, base);
    const ab = g.reclamo === 'abierto';
    const d = modal('<h2>🛡️ ' + (nueva ? 'Dar garantía' : esc(g.bici || 'Garantía')) + '</h2>' +
      (!nueva ? '<div class="aviso' + (g.dias < 0 ? ' warn' : '') + '" style="display:block">' + esc(venceTxt(g)) + ' · desde el ' + App.fCorta(g.desde) + '</div>' : '') +
      (ab ? '<div class="aviso bad" style="display:block;margin-top:8px"><b>🔔 La usó</b>' + (g.reclamo_at ? ' el ' + App.fCorta(g.reclamo_at.slice(0, 10)) : '') + '<div>' + esc(g.reclamo_nota) + '</div>' +
        '<div class="btns"><button class="okb" id="gaOk" type="button">✅ Lo arreglé</button><button class="danger" id="gaNo" type="button">❌ No lo cubre</button>' +
        (g.telefono ? '<a class="btn alt" target="_blank" rel="noopener" href="' + waGar(g, 'vimos tu aviso de garantía de la ' + (g.bici || 'bici') + '. Tráela cuando puedas y la revisamos') + '">📲 WhatsApp</a>' : '') + '</div></div>' : '') +
      (!ab && g.reclamo && g.reclamo !== 'abierto' ? '<p class="sub">' + (g.reclamo === 'resuelto' ? '✅ Reclamo resuelto' : '❌ Reclamo no cubierto') + (g.respuesta ? ': ' + esc(g.respuesta) : '') + '</p>' : '') +
      '<label for="gaQ">¿Qué cubre?</label><select id="gaQ">' + Object.keys(CUBRE).map((k) => '<option value="' + k + '"' + (k === g.cubre ? ' selected' : '') + '>' + CUBRE[k] + '</option>').join('') + '</select>' +
      '<label for="gaM">¿Cuánto dura?</label><select id="gaM">' + [1, 3, 6, 12, 24].concat([1, 3, 6, 12, 24].includes(+g.meses) ? [] : [+g.meses]).map((m) => '<option value="' + m + '"' + (m === +g.meses ? ' selected' : '') + '>' + m + (m === 1 ? ' mes' : ' meses') + '</option>').join('') + '</select>' +
      '<label for="gaD">Detalle (lo ve el cliente)</label><input id="gaD" maxlength="300" value="' + esc(g.detalle) + '" placeholder="Ej: Cambio de cadena y ajuste de cambios">' +
      '<div class="row"><div><label for="gaN">Cliente</label><input id="gaN" maxlength="80" value="' + esc(g.nombre) + '"></div><div><label for="gaT">Teléfono</label><input id="gaT" maxlength="30" inputmode="tel" value="' + esc(g.telefono) + '"></div></div>' +
      '<label for="gaB">Bici</label><input id="gaB" maxlength="120" value="' + esc(g.bici) + '">' +
      '<div class="btns">' + (!nueva && P.dueno ? '<button class="danger" id="gaX" type="button">🗑️ Borrar</button>' : '') + '<button id="gaG" type="button">' + (nueva ? '🛡️ Dar garantía' : '💾 Guardar') + '</button></div>' +
      (!nueva ? '<div class="btns">' + (g.telefono ? '<a class="btn alt" target="_blank" rel="noopener" href="' + waGar(g, 'tu ' + (g.bici || 'bici') + ' tiene 🛡️ garantía hasta el ' + App.fCorta(g.hasta) + '. Si algo falla, la usas desde aquí') + '">📲 Enviar al cliente</a>' : '') +
        '<a class="btn ghost" target="_blank" rel="noopener" href="' + esc(linkGar(g)) + '">👀 Ver</a></div>' : ''));
    const q1 = (sel) => d.querySelector(sel);
    if (window.CFX_FABRICA) CFX_FABRICA.bici(q1('#gaB'));
    const fin = (nid) => { if (alGuardar) alGuardar(nid); else if (subMas === 'garantias') verGarantias(); };
    q1('#gaG').onclick = async () => {
      try {
        const nid = await rpc('taller_garantia_guardar', { p: { id: nueva ? null : g.id, reserva: nueva ? (g.reserva || null) : null, usada: nueva ? (g.usada || null) : null,
          cubre: q1('#gaQ').value, meses: +q1('#gaM').value, detalle: q1('#gaD').value, nombre: q1('#gaN').value, telefono: q1('#gaT').value, bici: q1('#gaB').value } });
        d.close(); toast(nueva ? '🛡️ Garantía lista: envíasela al cliente' : '💾 Guardado');
        fin(nid);
        if (nueva) editarGarantia(nid, null, alGuardar);
      } catch (err) { toast(err.message); }
    };
    const resolver = async (est) => {
      const t = await pedirTexto(est === 'resuelto' ? '✅ Lo arreglé' : '❌ No lo cubre', est === 'resuelto' ? 'Qué hiciste (lo ve el cliente)' : 'Por qué no lo cubre (lo ve el cliente)', '');
      if (t === null) return;
      try { await rpc('taller_garantia_resolver', { p_id: g.id, p_estado: est, p_resp: t }); d.close(); toast(est === 'resuelto' ? '✅ Reclamo resuelto' : '❌ Respondido'); fin(g.id); } catch (e) { toast(e.message); }
    };
    const okb = q1('#gaOk'); if (okb) okb.onclick = () => resolver('resuelto');
    const nob = q1('#gaNo'); if (nob) nob.onclick = () => resolver('rechazado');
    const xb = q1('#gaX'); if (xb) xb.onclick = async () => { if (!await confirmar('¿Borrar la garantía de "' + (g.bici || 'la bici') + '"? El link del cliente deja de funcionar.')) return; try { await rpc('taller_garantia_borrar', { p_id: g.id }); d.close(); fin(null); } catch (e) { toast(e.message); } };
  }

  // ---- G59g 🧩 🚐 Mecánico a domicilio: ruta del día (orden ▲▼, Google Maps) + "Voy en camino"
  const lugar = (x) => [x.direccion, x.comuna].filter(Boolean).join(', ');
  const mapa = (x) => 'https://www.google.com/maps/dir/?api=1&destination=' + encodeURIComponent(lugar(x));
  const waCamino = (x) => App.wa(x.telefono, 'Hola ' + x.nombre.split(' ')[0] + ' 👋 Somos de ' + P.taller.nombre + ': 🚐 vamos en camino a ' + lugar(x) + '. Tu orden: ' + App.ROOT + 'r/?t=' + x.token);
  async function enCamino(x, alListo) {
    try { await rpc('taller_en_camino', { p_id: x.id }); } catch (e) { toast(e.message); return; }
    toast('🚐 Avisado'); if (alListo) alListo();
  }
  let rutaDia = 0;  // 0 = hoy, 1 = mañana
  async function verDomicilio() {
    body().innerHTML = '<p class="empty">Cargando…</p>';
    const hoy = new Date(P.hoy + 'T12:00:00'); hoy.setDate(hoy.getDate() + rutaDia);
    const fecha = hoy.toISOString().slice(0, 10);
    let s;
    try { s = await rpc('taller_ruta', { p_fecha: fecha }); } catch (e) { body().innerHTML = '<p class="err">' + esc(e.message) + '</p>'; return; }
    if (s.bloqueado) { body().innerHTML = modOfrecer('domicilio', '🚐 Mecánico a domicilio', 'Tus clientes reservan con su dirección y pagan la visita. Ves la ruta del día en orden, la abres en Google Maps y les avisas “🚐 Vamos en camino”.'); return; }
    const c = s.config, L = s.paradas;
    const ruta = L.length ? 'https://www.google.com/maps/dir/?api=1' + (s.origen ? '&origin=' + encodeURIComponent(s.origen) : '') + '&destination=' + encodeURIComponent(lugar(L[L.length - 1])) +
      (L.length > 1 ? '&waypoints=' + encodeURIComponent(L.slice(0, -1).map(lugar).join('|')) : '') + '&travelmode=driving' : '';
    body().innerHTML = (!c.activo ? '<div class="aviso warn"><div class="grow">' + (P.dueno ? 'Prende “Ofrecer a domicilio” para que tus clientes lo elijan al reservar.' : 'El dueño aún no ofrece visitas a domicilio en la página de reservas.') + '</div></div>' : '') +
      '<div class="card"><h2>🗺️ Ruta del día</h2><div class="seg" id="rDia"><button type="button" data-d="0" class="' + (rutaDia ? '' : 'on') + '">Hoy</button><button type="button" data-d="1" class="' + (rutaDia ? 'on' : '') + '">Mañana</button></div>' +
      '<p class="sub">' + (L.length ? L.length + ' visita' + (L.length === 1 ? '' : 's') + ' · ordénalas con ▲▼ y abre la ruta.' : 'No hay visitas a domicilio ' + (rutaDia ? 'mañana' : 'hoy') + '. Abre una orden → 🚐 A domicilio para agregar una.') + '</p>' +
      '<ul class="list" id="rLista">' + L.map((x, i) => '<li style="align-items:flex-start"><span class="pill" style="flex:none">' + (i + 1) + '</span><div class="grow"><b>' + esc(x.hora) + ' · ' + esc(x.nombre) + '</b>' +
        '<div class="sub">🏠 ' + esc(lugar(x)) + (x.ref ? ' · ' + esc(x.ref) : '') + '</div><div class="sub">🚲 ' + esc(x.bici || x.servicio) + (x.camino_at ? ' · 🚐 avisado' : '') + '</div>' +
        '<div class="btns" style="margin-top:6px"><a class="btn small ghost" target="_blank" rel="noopener" href="' + esc(mapa(x)) + '">🗺️ Cómo llegar</a>' +
        (x.telefono ? '<button class="small alt" type="button" data-cam="' + i + '">🚐 Voy en camino</button>' : '') + '<button class="small ghost" type="button" data-ord="' + esc(x.id) + '">📋 Orden</button></div></div>' +
        '<div style="display:flex;flex-direction:column;gap:4px;flex:none"><button class="small ghost" type="button" data-sin-atras data-sube="' + i + '" aria-label="Subir"' + (i ? '' : ' disabled') + '>▲</button>' +
        '<button class="small ghost" type="button" data-sin-atras data-baja="' + i + '" aria-label="Bajar"' + (i < L.length - 1 ? '' : ' disabled') + '>▼</button></div></li>').join('') + '</ul>' +
      (L.length ? '<div class="btns"><a class="btn" id="rMaps" target="_blank" rel="noopener" href="' + esc(ruta) + '">🗺️ Abrir la ruta en Google Maps</a></div>' : '') + '</div>' +
      (P.dueno ? '<div class="card"><h2>⚙️ Visitas a domicilio</h2><label class="check"><input type="checkbox" id="dmA"' + (c.activo ? ' checked' : '') + '> Ofrecer a domicilio en mi página de reservas</label>' +
        '<div class="row"><div><label for="dmR">Recargo por visita ($)</label><input id="dmR" type="number" min="0" max="200000" step="500" inputmode="numeric" value="' + (c.recargo || 0) + '"></div>' +
        '<div><label for="dmZ">Zona que atiendes</label><input id="dmZ" maxlength="160" value="' + esc(c.zona) + '" placeholder="Ej: Ñuñoa, Providencia"></div></div>' +
        '<div class="btns"><button id="dmG" type="button">💾 Guardar</button></div></div>' : '');
    const mover = async (i, j) => {
      const ids = L.map((x) => x.id); [ids[i], ids[j]] = [ids[j], ids[i]];
      try { await rpc('taller_ruta_orden', { p_ids: ids }); verDomicilio(); } catch (e) { toast(e.message); }
    };
    body().onclick = async (e) => {
      const d = e.target.closest('[data-d]'); if (d) { rutaDia = +d.dataset.d; verDomicilio(); return; }
      const su = e.target.closest('[data-sube]'); if (su) { mover(+su.dataset.sube, +su.dataset.sube - 1); return; }
      const ba = e.target.closest('[data-baja]'); if (ba) { mover(+ba.dataset.baja, +ba.dataset.baja + 1); return; }
      const ca = e.target.closest('[data-cam]'); if (ca) { const x = L[+ca.dataset.cam]; window.open(waCamino(x), '_blank', 'noopener'); enCamino(x, verDomicilio); return; }
      const o = e.target.closest('[data-ord]'); if (o) { const id = o.dataset.ord; if (hojaMas) hojaMas.h.cerrar(); setTimeout(() => { volverA = 'hoy'; abrirDetalle(id); }, 300); return; }
      if (e.target.closest('#dmG')) {
        try { await rpc('taller_domicilio_config', { p: { activo: body().querySelector('#dmA').checked, recargo: +body().querySelector('#dmR').value || 0, zona: body().querySelector('#dmZ').value } }); toast('💾 Guardado'); verDomicilio(); }
        catch (err) { toast(err.message); }
      }
    };
  }
  // Orden → 🚐 A domicilio: dirección de la visita (suma el recargo como ítem).
  function editarDomicilio(r, alGuardar) {
    const x = r.domicilio || { direccion: '', comuna: '', ref: '' };
    const d = modal('<h2>🚐 Visita a domicilio</h2><p class="sub" style="margin-top:0">' + esc(r.nombre) + ' · ' + App.fCorta(r.fecha) + ' ' + esc(r.hora) + '</p>' +
      '<label for="doD">Dirección (calle y número)</label><input id="doD" maxlength="160" autocomplete="street-address" value="' + esc(x.direccion) + '" placeholder="Ej: Av. Grecia 1234, depto 52">' +
      '<label for="doC">Comuna</label><input id="doC" maxlength="60" value="' + esc(x.comuna) + '">' +
      '<label for="doR">Referencia (opcional)</label><input id="doR" maxlength="160" value="' + esc(x.ref) + '" placeholder="Ej: portón verde, tocar el timbre">' +
      (!r.domicilio ? '<label class="check"><input type="checkbox" id="doX" checked> Sumar el recargo por visita a la orden</label>' : '') +
      '<div class="btns">' + (r.domicilio ? '<button class="danger" id="doQ" type="button">🏪 Ya no es a domicilio</button>' : '') + '<button id="doG" type="button">💾 Guardar</button></div>' +
      (r.domicilio ? '<div class="btns"><a class="btn ghost" target="_blank" rel="noopener" href="' + esc(mapa(x)) + '">🗺️ Cómo llegar</a>' +
        (r.telefono ? '<button class="alt" id="doW" type="button">🚐 Voy en camino</button>' : '') + '</div>' : ''));
    const q1 = (s) => d.querySelector(s);
    const guardar = async (p, msg) => {
      try { await rpc('taller_domicilio', { p_id: r.id, p }); d.close(); toast(msg); if (alGuardar) alGuardar(); } catch (e) { toast(e.message); }
    };
    q1('#doG').onclick = () => guardar({ direccion: q1('#doD').value, comuna: q1('#doC').value, ref: q1('#doR').value, recargo: q1('#doX') ? q1('#doX').checked : undefined }, '🚐 Guardado');
    const qb = q1('#doQ'); if (qb) qb.onclick = async () => { if (await confirmar('¿Ya no es a domicilio? Se quita la dirección y el recargo de la visita.')) guardar(null, '🏪 Ahora es en el taller'); };
    const wb = q1('#doW'); if (wb) wb.onclick = () => { window.open(waCamino(Object.assign({}, r, x)), '_blank', 'noopener'); d.close(); enCamino(r, alGuardar); };
  }
  async function verPlan() {
    const planes = pub.planes || {};
    const t = P.taller, prem = P.premium;
    let cx = null;
    try { cx = await rpc('cfx_pago_estado'); } catch (e) { /* nada */ }
    const pr = (cx && cx.config && cx.config.negocio) || {}, u = cx && cx.ultimo;
    const uso = P.uso, lim = P.plan.limites;
    const barra = (n, m) => '<div class="barra"><i style="width:' + Math.min(100, Math.round(100 * n / Math.max(m, 1))) + '%"></i></div>';
    body().innerHTML = '<div class="card plan' + (prem ? ' premium' : '') + '"><h2>' + (prem ? '⭐ Premium activo' : 'Plan gratis') + '</h2>' +
      (prem ? '<p class="muted" style="margin:0">Hasta el ' + new Date(t.premium_hasta).toLocaleDateString('es-CL') + '.</p>' : '') +
      '<h3>Tu uso</h3><div class="sub">Reservas online este mes: ' + uso.reservas_mes + ' de ' + lim.reservas_mes + barra(uso.reservas_mes, lim.reservas_mes) + '</div>' +
      '<div class="sub" style="margin-top:6px">Servicios: ' + uso.servicios + ' de ' + lim.servicios + barra(uso.servicios, lim.servicios) + '</div>' +
      '<div class="sub" style="margin-top:6px">Equipo: ' + uso.equipo + ' de ' + lim.equipo + ' · Promociones activas: ' + uso.promos + ' de ' + lim.promos + ' · Clientes con cuenta: ' + uso.clientes_cuenta + ' de ' + lim.clientes_cuenta + '</div></div>' +
      ['taller_free', 'taller_premium'].map((c) => planes[c] ? '<div class="card plan' + (c === 'taller_premium' ? ' premium' : '') + '"><h2>' + (c === 'taller_premium' ? '⭐ ' : '') + esc(planes[c].nombre) +
        (c === 'taller_premium' && pr.mensual ? '<span class="sub" style="font-weight:600">' + [plata(pr.mensual) + '/mes', pr.anual && plata(pr.anual) + '/año'].filter(Boolean).join(' · ') + '</span>' : '') + '</h2>' +
        '<p class="muted" style="margin:0">' + esc(planes[c].descripcion) + '</p><ul>' + planes[c].beneficios.map((b) => '<li>' + esc(b) + '</li>').join('') + '</ul></div>' : '').join('') +
      '<div class="card"><h2>' + (prem ? '🔁 Renovar Premium' : '⭐ Activar Premium') + '</h2>' +
      (u && u.estado === 'pendiente' ? '<div class="aviso"><div class="grow">🧾 Tu comprobante de ' + plata(u.monto) + ' está en revisión. Te avisamos apenas se apruebe.</div></div>'
        : (u && u.estado === 'rechazado' ? '<div class="aviso bad"><div class="grow">Tu último comprobante fue rechazado' + (u.motivo ? ': ' + esc(u.motivo) : '') + '.</div></div>' : '') +
          (P.dueno ? '<button class="block gold" id="plPagar">💳 Pagar con link o transferencia</button>' : '<p class="sub">Pídele al dueño del taller que active Premium.</p>')) + '</div>';
    if ($('plPagar')) $('plPagar').onclick = () => CFX_PAGOS.abrir({ rpc, alPagar: verPlan });
  }

  // ---- Equipo
  function verEquipo() {
    const lim = P.plan.limites.equipo;
    body().innerHTML = '<div class="card"><h2>👥 Equipo</h2><p class="muted" style="margin-top:0">Tus mecánicos o recepción con su propia cuenta: ven la agenda, revisan comprobantes y trabajan las reservas. ' +
      'No pueden cambiar tu perfil, horario, precios, links ni tu plan.</p><ul class="list">' +
      P.equipo.map((p) => '<li><div class="grow"><b>' + esc(p.nombre) + '</b> <span class="pill">' + (p.rol === 'taller' ? '👑 Dueño' : '🔧 Equipo') + '</span>' + (p.suspendido ? ' <span class="pill bad">Suspendido</span>' : '') +
        '<div class="sub">' + esc(p.email) + ' · visto ' + App.hace(p.visto_at) + '</div></div>' +
        (P.dueno && p.rol === 'equipo' ? '<button class="small ' + (p.suspendido ? 'okb' : 'danger') + '" data-q="' + p.id + '" data-s="' + (p.suspendido ? 0 : 1) + '">' + (p.suspendido ? 'Reactivar' : 'Suspender') + '</button>' : '') + '</li>').join('') + '</ul>' +
      (P.dueno ? (lim > 0 ? '<h3>＋ Agregar persona <span class="sub">(' + P.uso.equipo + ' de ' + lim + ')</span></h3><div class="row"><div><label for="qN">Nombre</label><input id="qN" maxlength="80"></div>' +
        '<div><label for="qE">Correo</label><input id="qE" type="email" autocomplete="off"></div></div><label for="qT">WhatsApp (para mandarle el acceso)</label><input id="qT" inputmode="tel">' +
        '<div class="btns"><button id="qCrear">Crear cuenta</button></div><p class="err" id="qErr"></p>'
        : '<div class="aviso"><div class="grow">⭐ El equipo es una función Premium.</div><button class="small gold" data-m="plan">Ver Premium</button></div>') : '') + '</div>';
    body().onclick = async (e) => {
      const m = e.target.closest('[data-m]'); if (m && !m.closest('#mSeg')) { verMas(m.dataset.m); return; }
      const b = e.target.closest('[data-q]'); if (!b) return;
      try { await rpc('taller_equipo_suspender', { p_id: b.dataset.q, p_suspender: b.dataset.s === '1' }); await cargarPanel(); verEquipo(); } catch (err) { toast(err.message); }
    };
    const bc = $('qCrear');
    if (bc) bc.onclick = async () => {
      const d = { nombre: $('qN').value.trim(), email: $('qE').value.trim(), telefono: $('qT').value.trim(), password: App.clave(), rol: 'equipo' };
      if (!d.nombre || !d.email) { $('qErr').textContent = 'Escribe el nombre y el correo'; return; }
      bc.disabled = true; bc.textContent = 'Creando…';
      try {
        await App.crearCuenta(d);
        const msg = App.mensajeAcceso({ nombre: d.nombre.split(' ')[0], email: d.email, password: d.password, lugar: P.taller.nombre });
        await cargarPanel(); verEquipo();
        modal('<h2>✅ Cuenta creada</h2><p class="muted">Envíale sus datos de acceso:</p><pre class="link" style="white-space:pre-wrap;font:inherit">' + esc(msg) + '</pre>' +
          '<div class="btns"><button class="ghost" data-cerrar>Cerrar</button>' + (d.telefono ? '<a class="btn" target="_blank" rel="noopener" href="' + App.wa(d.telefono, msg) + '">📲 Enviar por WhatsApp</a>' : '') + '</div>');
      } catch (e) { $('qErr').textContent = e.message; bc.disabled = false; bc.textContent = 'Crear cuenta'; }
    };
  }

  // ---- Estadísticas (Premium)
  // Gráficos simples (sin librerías): barras verticales, barras horizontales y barras dobles.
  const barras = (l, val, etq, fmt) => {
    const max = Math.max(1, ...l.map((x) => +val(x) || 0));
    return '<div class="chart">' + l.map((x) => '<div><b>' + (fmt ? fmt(val(x)) : (+val(x) || 0)) + '</b><i style="height:' + Math.round(100 * (+val(x) || 0) / max) + '%"></i>' + esc(etq(x)) + '</div>').join('') + '</div>';
  };
  const hbarras = (l, total) => {
    const max = Math.max(1, ...l.map((x) => x[1]));
    return l.map((x) => '<div class="hbar"><span>' + esc(x[0]) + '</span><div><i style="width:' + Math.round(100 * x[1] / max) + '%"></i></div><b>' + x[1] +
      (total ? ' <span class="sub">(' + Math.round(100 * x[1] / Math.max(total, 1)) + '%)</span>' : '') + '</b></div>').join('');
  };
  const mesCorto = (m) => new Date(+m.slice(0, 4), +m.slice(5, 7) - 1, 1).toLocaleDateString('es-CL', { month: 'short' });
  async function verStats() {
    body().innerHTML = '<p class="empty">Cargando…</p>';
    let s;
    try { s = await rpc('taller_estadisticas'); } catch (e) { body().innerHTML = '<p class="err">' + esc(e.message) + '</p>'; return; }
    if (s.bloqueado) {
      body().innerHTML = (s.mes_reservas != null ? '<div class="stats"><div class="card"><span>📅 Reservas este mes</span><b>' + s.mes_reservas + '</b></div>' +
        '<div class="card"><span>💰 Ingresos este mes</span><b>' + plata(s.mes_ingresos) + '</b></div></div>' : '') +
        bloqueadoPremium('📊 Gráficos y estadísticas', 'Ingresos por mes, días con más trabajo, servicios más pedidos, clientes nuevos y los que vuelven, de dónde llegan tus reservas, ticket promedio y tus estrellas.');
      return;
    }
    const tot = s.meses.reduce((a, m) => a + (+m.ingresos || 0), 0), trab = s.meses.reduce((a, m) => a + (+m.trabajos || 0), 0);
    const o = s.origen || {}, oTot = (+o.online || 0) + (+o.cuenta || 0) + (+o.taller || 0);
    const est = s.estrellas || [], eTot = est.reduce((a, x) => a + x.n, 0);
    const k = (n) => n >= 1e6 ? '$' + (n / 1e6).toFixed(1).replace('.', ',') + 'M' : n >= 1000 ? '$' + Math.round(n / 1000) + 'k' : plata(n);
    body().innerHTML = '<div class="stats">' +
      '<div class="card"><span>💰 Ingresos (6 meses)</span><b>' + plata(tot) + '</b></div><div class="card"><span>🔧 Trabajos (6 meses)</span><b>' + trab + '</b></div>' +
      '<div class="card"><span>🧾 Ticket promedio</span><b>' + plata(s.ticket || 0) + '</b></div><div class="card"><span>🌐 Reservas online (90 días)</span><b>' + s.online + '</b></div>' +
      '<div class="card"><span>🚫 Faltas (90 días)</span><b>' + s.faltas + '</b></div><div class="card"><span>❌ Cancelaciones (90 días)</span><b>' + s.canceladas + '</b></div>' +
      '<div class="card"><span>💸 Abonos que te quedaste</span><b>' + plata(s.abonos_perdidos) + '</b></div></div>' +
      '<div class="card"><h2>💰 Ingresos por mes</h2>' + (s.meses.length ? barras(s.meses, (m) => m.ingresos, (m) => mesCorto(m.mes), k) : '<p class="muted">Aún sin trabajos completados.</p>') + '</div>' +
      '<div class="card"><h2>📅 Próximos 7 días</h2>' + barras(s.proximos || [], (d) => d.n, (d) => App.DIAS[App.fechaDe(d.fecha).getDay()] + ' ' + App.fechaDe(d.fecha).getDate()) +
        '<p class="sub">Bicis agendadas por día' + (P.taller.max_dia ? ' (tu máximo: ' + P.taller.max_dia + ' por día)' : '') + '.</p></div>' +
      '<div class="card"><h2>🗓️ Días con más trabajo (90 días)</h2>' + barras([1, 2, 3, 4, 5, 6, 0].map((d) => (s.semana || []).find((x) => x.dia === d) || { dia: d, n: 0 }), (x) => x.n, (x) => App.DIAS[x.dia]) + '</div>' +
      '<div class="card"><h2>👥 Clientes nuevos y los que vuelven</h2>' + ((s.clientes_mes || []).length ?
        '<div class="chart">' + (() => { const cm = s.clientes_mes, mx = Math.max(1, ...cm.map((x) => x.nuevos + x.vuelven));
          return cm.map((x) => '<div><b>' + (x.nuevos + x.vuelven) + '</b><i class="b2" style="height:' + Math.round(100 * x.vuelven / mx) + '%;border-radius:7px 7px 0 0"></i>' +
            '<i style="height:' + Math.round(100 * x.nuevos / mx) + '%;border-radius:0"></i>' + esc(mesCorto(x.mes)) + '</div>').join(''); })() + '</div>' +
        '<div class="leyenda"><span><i style="background:var(--brand)"></i>Nuevos</span><span><i style="background:color-mix(in srgb, var(--brand) 40%, var(--line))"></i>Vuelven</span></div>'
        : '<p class="muted">Aún sin datos.</p>') + '</div>' +
      '<div class="card"><h2>🛠️ Servicios más pedidos (90 días)</h2>' + (s.servicios.length ? hbarras(s.servicios.map((x) => [x.nombre, +x.n])) : '<p class="muted">Sin datos.</p>') + '</div>' +
      '<div class="card"><h2>📲 ¿De dónde llegan tus reservas? (90 días)</h2>' + (oTot ? hbarras([['🌐 Online sin cuenta', +o.online || 0], ['📱 Clientes con cuenta', +o.cuenta || 0], ['🏪 En el taller / teléfono', +o.taller || 0]], oTot) +
        '<p class="sub">💡 Comparte tu QR: los clientes con cuenta vuelven más y reciben recordatorios.</p>' : '<p class="muted">Sin reservas todavía.</p>') + '</div>' +
      '<div class="card"><h2>⭐ Tus estrellas</h2>' + (eTot ? hbarras(est.map((x) => ['★'.repeat(x.e), x.n]), eTot) : '<p class="muted">Aún sin calificaciones.</p>') + '</div>';
  }
  function bloqueadoPremium(t, d, mod) {
    return '<div class="card plan premium"><h2>' + t + ' <span class="pill pro">PREMIUM</span></h2><p class="muted">' + esc(d) + '</p><div class="btns">' +
      (P.dueno ? '<button class="gold" onclick="location.hash=\'plan\'">⭐ Activar Premium</button>' +
        (mod && P.venta ? '<button class="alt" type="button" data-sin-atras data-ofrecer="' + mod + '">🧩 O activa solo esta función</button>' : '')
        : '<p class="sub">Pídele al dueño del taller que active Premium.</p>') + '</div></div>';
  }

  // ---- Recordatorios de mantención (Premium)
  async function verRecordar() {
    body().innerHTML = '<p class="empty">Cargando…</p>';
    let s;
    try { s = await rpc('taller_recordatorios'); } catch (e) { body().innerHTML = '<p class="err">' + esc(e.message) + '</p>'; return; }
    if (s.bloqueado) { body().innerHTML = bloqueadoPremium('🔔 Recordatorios de mantención', 'Ve qué clientes ya deberían volver y escríbeles con un toque. Con cuenta, les avisamos solos.', 'mantencion'); return; }
    body().innerHTML = '<div class="card"><h2>🔔 Les toca mantención</h2><p class="muted" style="margin-top:0">Clientes cuya próxima mantención es en los próximos 15 días o ya pasó, y que no han vuelto a reservar.</p><ul class="list">' +
      (s.lista.map((c) => '<li><div class="grow"><b>' + esc(c.nombre) + '</b><div class="sub">' + esc(c.bici || '') + ' · le toca ' + App.fCorta(c.proxima) + ' · última visita ' + App.fCorta(c.ultima) + '</div></div>' +
        (c.telefono ? '<a class="btn small" target="_blank" rel="noopener" href="' + App.wa(c.telefono, 'Hola ' + c.nombre.split(' ')[0] + ' 👋 Te escribimos de ' + P.taller.nombre + '. A tu bici ya le toca su mantención 🔧 Reserva aquí: ' + linkReservas()) + '">📲 Recordar</a>' : '') + '</li>').join('')
        || '<li class="muted">Nadie por recordar 🎉</li>') + '</ul></div>';
  }

  // ---- Mi cuenta
  function verCuenta() {
    // Nombre, WhatsApp, modo, contraseña y notificaciones: en Configuración del menú Más (perfil común del núcleo).
    body().innerHTML = '<div class="card"><p class="muted" style="margin-top:0">' + esc(yo.email) + ' · ' + (yo.rol === 'taller' ? 'Dueño del taller' : 'Equipo') + '</p>' +
      '<div id="uSop"></div>' +
      (P.dueno ? '<h3>🧹 Comprobantes</h3><p class="sub" style="margin:0">Se borran solos a los ' + ((pub.config || {}).dias_comprobantes || 30) + ' días. Descarga los que quieras guardar antes de limpiar.</p>' +
        '<div class="btns"><button class="ghost" id="uLimpiar">Borrar comprobantes ya revisados</button></div>' +
        '<h3>🪪 Identidad</h3><div class="btns"><button class="ghost" id="uVerif">🪪 Verificar mi identidad</button></div>' +
        '<h3>💾 Respaldo</h3><p class="sub" style="margin:0">Descarga en Excel tus reservas, clientes, servicios, promociones y calificaciones. Los avisos y mensajes se borran solos a los 30 días (te avisamos antes).</p>' +
        '<div class="btns"><button class="ghost" id="uRespaldo">⬇️ Descargar respaldo (Excel)</button></div>' : '') +
      '<div class="btns"><button class="danger" id="uSalir">Cerrar sesión</button></div></div>';
    const sop = (pub.config || {}).soporte_whatsapp;
    if (sop) $('uSop').innerHTML = '<a class="btn alt block" target="_blank" rel="noopener" href="' + App.wa(sop, 'Hola 👋 Soy ' + yo.nombre + ' de ' + P.taller.nombre + ' (BiciTaller).') + '">📲 Escribir al soporte por WhatsApp</a>';
    $('uSalir').onclick = () => App.salir();
    if ($('uVerif')) $('uVerif').onclick = () => CFX_VERIFICAR.abrir({ rpc });
    const ur = $('uRespaldo');
    if (ur) ur.onclick = async () => { try { CFX_RESPALDO.excel('respaldo-' + P.taller.nombre, await rpc('mi_respaldo')); toast('💾 Respaldo descargado'); } catch (e) { toast(e.message); } };
    const ul = $('uLimpiar');
    if (ul) ul.onclick = async () => { if (!await confirmar('¿Borrar todos los comprobantes ya revisados? No se puede deshacer.')) return; try { const n = await rpc('taller_limpiar_comprobantes'); toast('🧹 ' + n + ' borrados'); } catch (e) { toast(e.message); } };
  }

  /* ---------- Inicio ---------- */
  try { await Promise.all([cargarPanel(), cargarCatalogo()]); }
  catch (e) { $('cargando').textContent = '⚠️ ' + e.message; return; }
  $('cargando').classList.add('hidden');
  App.campana($('campana'));
  App.chatBoton($('chatBtn'));
  App.pie();
  // Guardar de dónde venimos para el botón "Volver" del detalle.
  const showOrig = show;
  document.querySelectorAll('nav.tabs button').forEach((b) => b.addEventListener('click', () => { if (b.dataset.v !== 'detalle') volverA = b.dataset.v; }));
  const h = location.hash.slice(1);
  const hm = /^mas\/(\w+)$/.exec(h);
  if (h === 'plan') { subMas = 'plan'; showOrig('mas'); }
  else if (hm) { subMas = hm[1]; showOrig('mas'); }
  else showOrig(['hoy', 'agenda', 'reservas', 'clientes', 'mas'].includes(h) ? h : 'hoy');
})();
