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
    $('hPlan').textContent = P.premium ? 'PREMIUM' : 'GRATIS';
    $('hPlan').className = 'pill ' + (P.premium ? 'pro' : '');
    $('tabRev').textContent = P.por_revisar; $('tabRev').classList.toggle('hidden', !P.por_revisar);
    document.querySelectorAll('#mSeg .dueno').forEach((b) => b.classList.toggle('hidden', !P.dueno));
  }
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
  window.addEventListener('hashchange', () => { if (location.hash === '#mas') { subMas = null; show('mas'); return; } const m = /^#(?:mas\/)?(plan|perfil|horario|servicios|abono|promos|equipo|stats|recordar|cuenta|compartir)$/.exec(location.hash); if (m && (m[1] === 'plan' || /^#mas\//.test(location.hash))) { subMas = m[1]; show('mas'); } });
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
      esc(App.txt('bienvenida_taller')) + '</p><ul class="list">' + falta.map((f) => '<li class="clic" data-m="' + f[0] + '"><span class="grow">◻️ ' + esc(f[1]) + '</span><span>›</span></li>').join('') + '</ul></div>' : '';
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
  $('v-hoy').addEventListener('click', async (e) => {
    const ir = e.target.closest('[data-ir]');
    if (ir) { const [v, f] = ir.dataset.ir.split(':'); if (f) filtroR = f; show(v); return; }
    const m = e.target.closest('[data-m]');
    if (m) { subMas = m.dataset.m; show('mas'); return; }
    if (await accionesComunes(e)) return;
    const c = e.target.closest('[data-r]'); if (c) abrirDetalle(c.dataset.r);
  });
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
      '<label for="mB">Bici</label><input id="mB" maxlength="120"><label for="mO">Nota</label><input id="mO" maxlength="500">' +
      '<label class="check"><input type="checkbox" id="mSc"> Agendar aunque no haya cupo (sobrecupo)</label>' +
      '<div class="btns"><button class="ghost" data-cerrar>Cancelar</button><button id="mOk">Guardar</button></div><p class="err" id="mErr"></p>');
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
    detalle = r; items = JSON.parse(JSON.stringify(r.items || []));
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
      (r.bici ? '<div>🚲 ' + esc(r.bici) + '</div>' : '') + (r.nota ? '<div class="sub">📝 ' + esc(r.nota) + '</div>' : '') +
      '<div class="sub">📞 ' + esc(r.telefono) + (r.email ? ' · ' + esc(r.email) : '') + ' · ' + (r.origen === 'taller' ? 'Reserva del taller' : r.origen === 'cliente' ? 'Cliente con cuenta' : 'Reserva online') + '</div>' +
      '<div class="sub">💳 ' + ABONO[r.abono_estado] + (r.abono_monto ? ' · ' + plata(r.abono_monto) : '') + (r.reagendada ? ' · reagendada ' + r.reagendada + ' vez/veces' : '') + '</div>' +
      (r.motivo ? '<div class="sub">Motivo: ' + esc(r.motivo) + '</div>' : '') +
      '<div class="btns">' + (r.telefono ? '<a class="btn small alt" target="_blank" rel="noopener" href="' + App.wa(r.telefono, 'Hola ' + r.nombre.split(' ')[0] + ' 👋 Te escribimos de ' + P.taller.nombre + ': ' +
        (msgCliente || '') + '\nTu reserva: ' + link) + '">📲 WhatsApp</a>' : '') +
      '<button class="small ghost" id="dLink">🔗 Enlace del cliente</button>' + (r.tiene_comprobante ? '<button class="small ghost" data-comp="' + r.id + '">👁️ Comprobante</button>' : '') + '</div>' +
      (r.estado === 'en_revision' ? botonesRevisar(r) : '') +
      (r.abono_estado === 'devolver' ? '<div class="aviso warn" style="margin-top:12px"><div class="grow">Devuelve el abono de ' + plata(r.abono_monto) + ' al cliente.</div><button class="small okb" data-devuelto="' + r.id + '">✓ Ya lo devolví</button></div>' : '') +
      '</div>' +
      (trabajando ? '<div class="card"><h2>🔧 Estado del trabajo</h2><div class="btns" style="margin-top:0">' + (sig ? '<button id="dSig" data-e="' + sig[0] + '">' + sig[1] + '</button>' : '') +
        (['recibida', 'en_reparacion'].includes(r.estado) ? '<button class="alt" data-e="esperando_repuesto">📦 Esperando repuesto</button>' : '') +
        (r.estado === 'confirmada' ? '<button class="danger" data-e="no_asistio">🚫 No llegó</button><button class="danger" data-e="cancelada">Cancelar (devolver abono)</button>' : '') + '</div></div>' +
        '<div class="card"><h2>🧾 Servicios y repuestos</h2><div class="items" id="dItems"></div>' +
        '<div class="row" style="margin-top:6px"><select id="dAddS" aria-label="Agregar servicio"><option value="">＋ Agregar servicio…</option>' +
          servicios.map((s) => '<option value="' + s.id + '">' + esc(s.nombre) + ' · ' + plata(s.precio) + '</option>').join('') + '</select>' +
          '<button class="alt" id="dAddR" type="button" style="flex:0 0 auto">＋ Repuesto</button></div>' +
        '<p style="margin:12px 0 0">Total: <b class="precio" id="dTotal"></b><span class="sub" id="dSaldo"></span></p>' +
        '<label for="dDiag">Diagnóstico (lo ve el cliente)</label><textarea id="dDiag" maxlength="1000">' + esc(r.diagnostico) + '</textarea>' +
        '<label for="dNotas">Notas internas (solo el taller)</label><textarea id="dNotas" maxlength="1000">' + esc(r.notas_internas) + '</textarea>' +
        '<div class="row"><div><label for="dMec">Mecánico</label><select id="dMec"><option value="">Sin asignar</option>' + equipo.map((p) => '<option value="' + p.id + '"' + (p.id === r.mecanico_id ? ' selected' : '') + '>' + esc(p.nombre) + '</option>').join('') + '</select></div>' +
        '<div><label for="dProx">Próxima mantención</label><input type="date" id="dProx" value="' + (r.proxima_mantencion || '') + '"></div></div>' +
        '<div class="btns"><button id="dGuardar">💾 Guardar</button><button class="ghost" onclick="window.print()">🖨️ Imprimir</button></div></div>' +
        '<div class="card"><h2>📷 Fotos antes / después</h2><div id="dFotos"></div></div>' : '') +
      (['completada', 'lista', 'no_asistio'].includes(r.estado) ? '<div class="card"><h2>⭐ Califica al cliente</h2><p class="sub" style="margin-top:0">Los otros talleres y clientes solo ven el promedio de estrellas.</p>' +
        (r.calificado ? '<p class="muted">✅ Ya lo calificaste.</p>' : '<div class="row"><select id="dEst"><option value="5">★★★★★ Excelente</option><option value="4">★★★★ Bueno</option><option value="3">★★★ Regular</option>' +
          '<option value="2">★★ Llegó tarde / mal trato</option><option value="1">★ No llegó / problemas</option></select><button id="dCal" style="flex:0 0 auto">Calificar</button></div>' +
          '<input id="dCalTxt" maxlength="300" placeholder="Comentario privado (opcional)" style="margin-top:8px">') + '</div>' : '');
    show('detalle');
    $('dVolver').onclick = () => history.length > 1 ? show(volverA) : show('reservas');
    $('dLink').onclick = () => { navigator.clipboard.writeText(link).then(() => toast('🔗 Enlace copiado')); };
    $('v-detalle').onclick = async (ev) => {
      if (await accionesComunes(ev)) return;
      const be = ev.target.closest('[data-e]'); if (!be) return;
      const est = be.dataset.e;
      if (['no_asistio', 'cancelada'].includes(est) && !await confirmar(est === 'no_asistio' ? 'El cliente no llegó: pierde el abono. ¿Confirmar?' : 'Cancelar la reserva: tendrás que devolver el abono. ¿Confirmar?')) return;
      try {
        if (est === 'completada' || est === 'lista') await guardarTrabajo(true);
        await rpc('taller_estado', { p_id: r.id, p_estado: est });
        sb.functions.invoke('servidor').catch(() => {});
        toast((ESTADOS[est] || [est])[0]); abrirDetalle(r.id);
      } catch (err) { toast(err.message); }
    };
    if (trabajando) {
      pintarItems();
      $('dItems').oninput = (ev) => { const i = ev.target.dataset.i; if (i === undefined) return; items[i][ev.target.dataset.k] = ev.target.dataset.k === 'nombre' ? ev.target.value : App.numero(ev.target.value); totalItems(); };
      $('dItems').onclick = (ev) => { const x = ev.target.closest('[data-x]'); if (x) { items.splice(+x.dataset.x, 1); pintarItems(); } };
      $('dAddS').onchange = () => { const s = servicios.find((x) => x.id === $('dAddS').value); if (s) items.push({ nombre: s.nombre, cant: 1, precio: s.precio }); $('dAddS').value = ''; pintarItems(); };
      $('dAddR').onclick = () => { items.push({ nombre: '', cant: 1, precio: 0 }); pintarItems(); const ins = $('dItems').querySelectorAll('[data-k=nombre]'); ins[ins.length - 1].focus(); };
      $('dGuardar').onclick = () => guardarTrabajo(false);
      pintarFotos(r.id);
    }
    const bc = $('dCal');
    if (bc) bc.onclick = async () => {
      try { await rpc('taller_calificar', { p_id: r.id, p_estrellas: +$('dEst').value, p_comentario: $('dCalTxt').value }); toast('⭐ Cliente calificado'); abrirDetalle(r.id); }
      catch (err) { toast(err.message); }
    };
  }
  let volverA = 'reservas';
  // Fotos antes/después (Premium): el cliente las ve en el enlace de su reserva y, si es Premium, siempre en su historial.
  async function pintarFotos(id) {
    const el = $('dFotos');
    if (!P.plan.limites.fotos) {
      el.innerHTML = '<p class="muted" style="margin-top:0">Muestra el antes y el después: tu taller se ve más profesional y el cliente confía más. Es una función ⭐ Premium.</p>' +
        (P.dueno ? '<div class="btns"><button class="gold" type="button" data-plan>⭐ Activar Premium</button></div>' : '');
      const bp = el.querySelector('[data-plan]'); if (bp) bp.onclick = () => { subMas = 'plan'; show('mas'); };
      return;
    }
    let fotos = [];
    try { fotos = await rpc('taller_fotos', { p_reserva: id }); } catch (e) { el.innerHTML = '<p class="err">' + esc(e.message) + '</p>'; return; }
    const n = (t) => fotos.filter((f) => f.tipo === t).length;
    el.innerHTML = '<p class="sub" style="margin-top:0">Hasta 2 de cada una. El cliente las ve en el enlace de su reserva.</p>' +
      (fotos.length ? '<div class="fotos">' + fotos.map((f) => '<figure><img alt="Foto ' + f.tipo + '" src="' + f.imagen + '"><figcaption>' + (f.tipo === 'antes' ? 'Antes' : 'Después') + '</figcaption>' +
        '<button class="small danger" type="button" data-fx="' + f.id + '" aria-label="Borrar foto">✕</button></figure>').join('') + '</div>' : '') +
      '<div class="btns">' + ['antes', 'despues'].map((t) => n(t) < 2 ? '<label class="btn alt" style="margin:0;color:var(--brand)">📷 ' + (t === 'antes' ? 'Antes' : 'Después') +
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
  function pintarItems() {
    $('dItems').innerHTML = items.length ? items.map((it, i) => '<div class="it"><input data-i="' + i + '" data-k="nombre" value="' + esc(it.nombre) + '" placeholder="Descripción" aria-label="Descripción">' +
      '<input data-i="' + i + '" data-k="cant" value="' + it.cant + '" inputmode="numeric" aria-label="Cantidad"><input data-i="' + i + '" data-k="precio" value="' + it.precio + '" inputmode="numeric" aria-label="Precio">' +
      '<button class="danger" data-x="' + i + '" aria-label="Quitar">✕</button></div>').join('') : '<p class="sub" style="margin:0">Agrega lo que se hizo y los repuestos.</p>';
    totalItems();
  }
  function totalItems() {
    const tot = items.reduce((s, it) => s + Math.max(+it.cant || 0, 0) * Math.max(+it.precio || 0, 0), 0);
    const ab = ['pagado', 'aplicado'].includes(detalle.abono_estado) ? detalle.abono_monto : 0;
    $('dTotal').textContent = plata(tot);
    $('dSaldo').textContent = ab ? ' · menos abono ' + plata(ab) + ' = a pagar ' + plata(Math.max(tot - ab, 0)) : '';
  }
  async function guardarTrabajo(callado) {
    const limpios = items.filter((it) => String(it.nombre || '').trim()).map((it) => ({ nombre: String(it.nombre).trim().slice(0, 100), cant: Math.max(+it.cant || 1, 0), precio: Math.max(Math.round(+it.precio || 0), 0) }));
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
  function verMas(m) {
    // Sin sección: menú en cuadrícula (igual en todas las apps). Con sección: la tira de secciones arriba.
    if (!m || ($('mSeg').querySelector('[data-m="' + m + '"]') || {}).classList?.contains('hidden')) {
      subMas = null; $('mSeg').classList.add('hidden');
      body().innerHTML = '<div class="cfx-grilla">' + [...$('mSeg').querySelectorAll('button[data-m]:not(.hidden)')].map((b) => '<button type="button" data-m="' + b.dataset.m + '">' + b.innerHTML + '</button>').join('') + '</div>';
      body().querySelectorAll('[data-m]').forEach((b) => { b.onclick = () => { history.pushState(null, '', '#mas/' + b.dataset.m); verMas(b.dataset.m); }; });
      return;
    }
    $('mSeg').classList.remove('hidden');
    subMas = m;
    $('mSeg').querySelectorAll('button').forEach((b) => b.classList.toggle('on', b.dataset.m === m));
    const on = $('mSeg').querySelector('.on'); if (on) on.scrollIntoView({ inline: 'center', block: 'nearest' });
    ({ perfil: verPerfil, horario: verHorario, servicios: verServicios, abono: verAbono, promos: verPromos, plan: verPlan,
      equipo: verEquipo, stats: verStats, recordar: verRecordar, cuenta: verCuenta, compartir: verCompartir })[m]();
  }
  const body = () => $('mBody');

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
      '<div class="btns"><button id="pGuardar">💾 Guardar perfil</button></div><p class="err" id="pErr"></p></div>';
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
    body().innerHTML = '<div class="card"><h2>⏰ Horario y reservas</h2><label>Días y horario (cada día con su propio horario)</label><div id="hDias">' +
      [1, 2, 3, 4, 5, 6, 0].map((i) => '<div class="row" style="align-items:center;flex-wrap:nowrap;margin-bottom:6px"><label class="check" style="margin:0;flex:0 0 76px"><input type="checkbox" data-d="' + i + '"' +
        (t.dias.includes(i) ? ' checked' : '') + '> ' + App.DIAS[i] + '</label><input type="time" data-a="' + i + '" value="' + String(hd(i).abre).slice(0, 5) + '" aria-label="Abre ' + App.DIAS[i] + '">' +
        '<input type="time" data-c="' + i + '" value="' + String(hd(i).cierra).slice(0, 5) + '" aria-label="Cierra ' + App.DIAS[i] + '"></div>').join('') + '</div>' +
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
      '<p class="sub">Para bloquear un feriado o unas horas usa ⛔ Bloquear en la Agenda.</p>' +
      '<div class="btns"><button id="hGuardar">💾 Guardar horario</button></div><p class="err" id="hErr"></p></div>';
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

  // ---- Servicios
  function verServicios() {
    const lim = P.plan.limites.servicios;
    body().innerHTML = '<div class="card"><h2>🛠️ Servicios <span class="pill">' + servicios.length + ' de ' + lim + '</span></h2><ul class="list" id="sLista"></ul>' +
      '<div class="btns"><button id="sNuevo">＋ Nuevo servicio</button>' + (servicios.length ? '' : '<button class="alt" id="sTipicos">✨ Cargar servicios típicos</button>') + '</div></div>';
    $('sLista').innerHTML = servicios.length ? servicios.map((s) => '<li' + (s.activo ? '' : ' style="opacity:.55"') + '><div class="grow"><b>' + esc(s.nombre) + '</b> <span class="precio">' + plata(s.precio) + '</span>' +
      (s.adicional ? ' <span class="pill info">Adicional</span>' : '') + '<div class="sub">' + (s.adicional ? '' : '⏱️ ' + s.duracion_min + ' min') + (s.descripcion ? ' · ' + esc(s.descripcion) : '') + (s.activo ? '' : ' · pausado') + '</div></div>' +
      '<button class="small ghost" data-e="' + s.id + '">✏️</button></li>').join('') : '<li class="muted">Agrega lo que ofreces: mantención, pinchazo, ajuste de frenos…</li>';
    $('sNuevo').onclick = () => editarServicio(null);
    $('sLista').onclick = (e) => { const b = e.target.closest('[data-e]'); if (b) editarServicio(servicios.find((s) => s.id === b.dataset.e)); };
    const st = $('sTipicos');
    if (st) st.onclick = async () => {
      const tip = [['Mantención básica', 20000, 60, 'Ajuste de frenos y cambios, lubricación y revisión general.'],
        ['Mantención completa', 40000, 120, 'Lavado, engrase de rodamientos, ajuste completo de frenos y cambios.'],
        ['Reparación de pinchazo', 5000, 30, 'Parche o cambio de cámara (cámara aparte).'], ['Ajuste de frenos', 8000, 30, ''], ['Ajuste de cambios', 8000, 30, '']]
        .slice(0, lim);
      try { await q(sb.from('servicios').insert(tip.map((x, i) => ({ taller_id: T, nombre: x[0], precio: x[1], duracion_min: x[2], descripcion: x[3], orden: i })))); await cargarCatalogo(); toast('✨ Listo: ajusta tus precios'); verServicios(); }
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
  function bloqueadoPremium(t, d) {
    return '<div class="card plan premium"><h2>' + t + ' <span class="pill pro">PREMIUM</span></h2><p class="muted">' + esc(d) + '</p><div class="btns">' +
      (P.dueno ? '<button class="gold" onclick="location.hash=\'plan\'">⭐ Activar Premium</button>' : '<p class="sub">Pídele al dueño del taller que active Premium.</p>') + '</div></div>';
  }

  // ---- Recordatorios de mantención (Premium)
  async function verRecordar() {
    body().innerHTML = '<p class="empty">Cargando…</p>';
    let s;
    try { s = await rpc('taller_recordatorios'); } catch (e) { body().innerHTML = '<p class="err">' + esc(e.message) + '</p>'; return; }
    if (s.bloqueado) { body().innerHTML = bloqueadoPremium('🔔 Recordatorios de mantención', 'Ve qué clientes ya deberían volver y escríbeles con un toque.'); return; }
    body().innerHTML = '<div class="card"><h2>🔔 Les toca mantención</h2><p class="muted" style="margin-top:0">Clientes cuya próxima mantención es en los próximos 15 días o ya pasó, y que no han vuelto a reservar.</p><ul class="list">' +
      (s.lista.map((c) => '<li><div class="grow"><b>' + esc(c.nombre) + '</b><div class="sub">' + esc(c.bici || '') + ' · le toca ' + App.fCorta(c.proxima) + ' · última visita ' + App.fCorta(c.ultima) + '</div></div>' +
        (c.telefono ? '<a class="btn small" target="_blank" rel="noopener" href="' + App.wa(c.telefono, 'Hola ' + c.nombre.split(' ')[0] + ' 👋 Te escribimos de ' + P.taller.nombre + '. A tu bici ya le toca su mantención 🔧 Reserva aquí: ' + linkReservas()) + '">📲 Recordar</a>' : '') + '</li>').join('')
        || '<li class="muted">Nadie por recordar 🎉</li>') + '</ul></div>';
  }

  // ---- Mi cuenta
  function verCuenta() {
    body().innerHTML = '<div class="card"><h2>👤 Mi cuenta</h2><p class="muted" style="margin-top:0">' + esc(yo.email) + ' · ' + (yo.rol === 'taller' ? 'Dueño del taller' : 'Equipo') + '</p>' +
      '<div class="row"><div><label for="uN">Nombre</label><input id="uN" maxlength="80" value="' + esc(yo.nombre) + '"></div><div><label for="uT">Teléfono</label><input id="uT" maxlength="30" value="' + esc(yo.telefono) + '"></div></div>' +
      '<div class="btns"><button id="uG">💾 Guardar</button></div>' +
      '<label for="uP">Contraseña nueva</label><input id="uP" type="password" autocomplete="new-password"><div class="btns"><button class="alt" id="uPG">Cambiar contraseña</button></div>' +
      '<div id="uPush"></div><div id="uModo" style="margin-top:12px"></div><div id="uSop" style="margin-top:12px"></div>' +
      (P.dueno ? '<h3>🧹 Comprobantes</h3><p class="sub" style="margin:0">Se borran solos a los ' + ((pub.config || {}).dias_comprobantes || 30) + ' días. Descarga los que quieras guardar antes de limpiar.</p>' +
        '<div class="btns"><button class="ghost" id="uLimpiar">Borrar comprobantes ya revisados</button></div>' +
        '<h3>🪪 Identidad</h3><div class="btns"><button class="ghost" id="uVerif">🪪 Verificar mi identidad</button></div>' +
        '<h3>💾 Respaldo</h3><p class="sub" style="margin:0">Descarga en Excel tus reservas, clientes, servicios, promociones y calificaciones. Los avisos y mensajes se borran solos a los 30 días (te avisamos antes).</p>' +
        '<div class="btns"><button class="ghost" id="uRespaldo">⬇️ Descargar respaldo (Excel)</button></div>' : '') +
      '<div class="btns"><button class="danger" id="uSalir">Cerrar sesión</button></div></div>';
    App.ofrecerPush($('uPush'));
    App.selectorModo($('uModo'));
    const sop = (pub.config || {}).soporte_whatsapp;
    if (sop) $('uSop').innerHTML = '<a class="btn alt block" target="_blank" rel="noopener" href="' + App.wa(sop, 'Hola 👋 Soy ' + yo.nombre + ' de ' + P.taller.nombre + ' (BiciTaller).') + '">📲 Escribir al soporte por WhatsApp</a>';
    $('uG').onclick = async () => { try { await rpc('mi_perfil_guardar', { p_nombre: $('uN').value, p_telefono: $('uT').value }); toast('💾 Guardado'); } catch (e) { toast(e.message); } };
    $('uPG').onclick = async () => { const { error } = await sb.auth.updateUser({ password: $('uP').value }); toast(error ? App.friendly(error) : '🔑 Contraseña cambiada'); };
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
