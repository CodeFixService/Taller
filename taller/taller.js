/* BiciTaller · Panel del taller (dueño y equipo). */
(async function () {
  'use strict';
  const { $, esc, plata, rpc, q, sb, toast, modal, confirmar } = App;
  App.registrarSW();
  const yo = await App.requerir(['taller', 'equipo']);
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
  window.addEventListener('hashchange', () => { if (location.hash === '#plan') { subMas = 'plan'; show('mas'); } });
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
      if (!servicios.length) falta.push(['servicios', 'Agrega tus servicios y precios']);
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
  $('hQR').onclick = () => verQR(linkReservas());
  async function compartir(url, texto) {
    if (navigator.share) { try { await navigator.share({ title: P.taller.nombre, text: texto, url }); return; } catch (e) { /* cancelado */ } }
    window.open('https://wa.me/?text=' + encodeURIComponent(texto + ': ' + url), '_blank');
  }
  function verQR(url) {
    let img = '';
    try { const qr = qrcode(0, 'M'); qr.addData(url); qr.make(); img = qr.createDataURL(8, 8); } catch (e) { /* nada */ }
    const d = modal('<h2>📱 QR de tu página de reservas</h2><div class="qr" style="text-align:center"><img alt="QR" src="' + img + '"></div><p class="sub" style="text-align:center">' + esc(url) +
      '</p><div class="btns"><button class="ghost" data-cerrar>Cerrar</button><button data-bajar>⬇️ Descargar</button></div>');
    d.querySelector('[data-bajar]').onclick = () => App.descargar(img, 'qr-' + P.taller.slug + '.gif');
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
        '<div class="btns"><button id="dGuardar">💾 Guardar</button><button class="ghost" onclick="window.print()">🖨️ Imprimir</button></div></div>' : '') +
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
    }
    const bc = $('dCal');
    if (bc) bc.onclick = async () => {
      try { await rpc('taller_calificar', { p_id: r.id, p_estrellas: +$('dEst').value, p_comentario: $('dCalTxt').value }); toast('⭐ Cliente calificado'); abrirDetalle(r.id); }
      catch (err) { toast(err.message); }
    };
  }
  let volverA = 'reservas';
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
  $('mSeg').onclick = (e) => { const b = e.target.closest('[data-m]'); if (b) verMas(b.dataset.m); };
  function verMas(m) {
    if (!m || ($('mSeg').querySelector('[data-m="' + m + '"]') || {}).classList?.contains('hidden')) m = P.dueno ? 'perfil' : 'equipo';
    subMas = m;
    $('mSeg').querySelectorAll('button').forEach((b) => b.classList.toggle('on', b.dataset.m === m));
    const on = $('mSeg').querySelector('.on'); if (on) on.scrollIntoView({ inline: 'center', block: 'nearest' });
    ({ perfil: verPerfil, horario: verHorario, servicios: verServicios, abono: verAbono, promos: verPromos, plan: verPlan,
      equipo: verEquipo, stats: verStats, recordar: verRecordar, cuenta: verCuenta })[m]();
  }
  const body = () => $('mBody');

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
          comuna: $('pCom').value, telefono: $('pTel').value, instagram: $('pIg').value, logo, color, icono } });
        await cargarPanel(); toast('💾 Perfil guardado'); verPerfil();
      } catch (e) { $('pErr').textContent = e.message; }
    };
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
          meses_mantencion: Math.min(Math.max(App.numero($('hMe').value) || 4, 1), 24), reservas_online: $('hOn').checked } });
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
  async function verPlan() {
    const planes = pub.planes || {}, link = pub.premium_taller;
    const t = P.taller, prem = P.premium;
    let pend = null;
    try { pend = await rpc('mi_pago_pendiente'); } catch (e) { /* nada */ }
    const uso = P.uso, lim = P.plan.limites;
    const barra = (n, m) => '<div class="barra"><i style="width:' + Math.min(100, Math.round(100 * n / Math.max(m, 1))) + '%"></i></div>';
    body().innerHTML = '<div class="card plan' + (prem ? ' premium' : '') + '"><h2>' + (prem ? '⭐ Premium activo' : 'Plan gratis') + '</h2>' +
      (prem ? '<p class="muted" style="margin:0">Hasta el ' + new Date(t.premium_hasta).toLocaleDateString('es-CL') + '.</p>' : '') +
      '<h3>Tu uso</h3><div class="sub">Reservas online este mes: ' + uso.reservas_mes + ' de ' + lim.reservas_mes + barra(uso.reservas_mes, lim.reservas_mes) + '</div>' +
      '<div class="sub" style="margin-top:6px">Servicios: ' + uso.servicios + ' de ' + lim.servicios + barra(uso.servicios, lim.servicios) + '</div>' +
      '<div class="sub" style="margin-top:6px">Equipo: ' + uso.equipo + ' de ' + lim.equipo + ' · Promociones activas: ' + uso.promos + ' de ' + lim.promos + ' · Clientes con cuenta: ' + uso.clientes_cuenta + ' de ' + lim.clientes_cuenta + '</div></div>' +
      ['taller_free', 'taller_premium'].map((c) => planes[c] ? '<div class="card plan' + (c === 'taller_premium' ? ' premium' : '') + '"><h2>' + (c === 'taller_premium' ? '⭐ ' : '') + esc(planes[c].nombre) +
        (c === 'taller_premium' && link ? ' · <span class="precio">' + plata(link.monto) + '</span> <span class="sub">cada ' + planes[c].duracion_dias + ' días</span>' : '') + '</h2>' +
        '<p class="muted" style="margin:0">' + esc(planes[c].descripcion) + '</p><ul>' + planes[c].beneficios.map((b) => '<li>' + esc(b) + '</li>').join('') + '</ul></div>' : '').join('') +
      '<div class="card"><h2>' + (prem ? '🔁 Renovar Premium' : '⭐ Activar Premium') + '</h2>' +
      (pend && pend.estado === 'en_revision' ? '<div class="aviso"><div class="grow">🧾 Tu comprobante de ' + plata(pend.monto) + ' está en revisión. Te avisamos apenas se apruebe.</div></div>'
        : !link ? '<p class="muted">El pago aún no está disponible. Escríbele al administrador.</p>'
        : (pend && pend.estado === 'rechazado' ? '<div class="aviso bad"><div class="grow">Tu último comprobante fue rechazado' + (pend.nota ? ': ' + esc(pend.nota) : '') + '.</div></div>' : '') +
          '<p class="muted" style="margin-top:0">' + esc(App.txt('pago_instrucciones')) + '</p>' + (link.texto ? '<p class="sub">' + esc(link.texto) + '</p>' : '') +
          '<a class="btn block gold" target="_blank" rel="noopener" href="' + esc(link.url) + '">1️⃣ Pagar ' + plata(link.monto) + '</a>' +
          '<label for="plFile" class="btn block alt" style="margin-top:10px;color:var(--brand)">2️⃣ Subir comprobante</label><input type="file" id="plFile" accept="image/*" class="hidden">' +
          '<div id="plPrev" style="text-align:center"></div><button class="block hidden" id="plEnviar" style="margin-top:10px">Enviar comprobante</button><p class="err" id="plErr"></p>') + '</div>';
    const f = $('plFile');
    if (f) {
      let img = null;
      f.onchange = async (e) => { const x = e.target.files[0]; if (!x) return; try { img = await App.comprimirComprobante(x); $('plPrev').innerHTML = '<img alt="Comprobante" src="' + img + '" style="max-height:240px;border-radius:12px;margin-top:10px">'; $('plEnviar').classList.remove('hidden'); } catch (err) { $('plErr').textContent = err.message; } };
      $('plEnviar').onclick = async () => {
        try { const r = await rpc('premium_pagar', { p_tipo: 'premium_taller', p_imagen: img }); if (!r.ok) throw new Error(r.error); sb.functions.invoke('servidor').catch(() => {}); toast('🧾 Comprobante enviado'); verPlan(); }
        catch (err) { $('plErr').textContent = err.message; }
      };
    }
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
  async function verStats() {
    body().innerHTML = '<p class="empty">Cargando…</p>';
    let s;
    try { s = await rpc('taller_estadisticas'); } catch (e) { body().innerHTML = '<p class="err">' + esc(e.message) + '</p>'; return; }
    if (s.bloqueado) { body().innerHTML = bloqueadoPremium('📊 Estadísticas', 'Ingresos por mes, servicios más pedidos, faltas y abonos perdidos.'); return; }
    const max = Math.max(1, ...s.meses.map((m) => +m.ingresos || 0));
    body().innerHTML = '<div class="stats"><div class="card"><span>Reservas online (90 días)</span><b>' + s.online + '</b></div><div class="card"><span>Faltas (90 días)</span><b>' + s.faltas + '</b></div>' +
      '<div class="card"><span>Cancelaciones (90 días)</span><b>' + s.canceladas + '</b></div><div class="card"><span>Abonos que te quedaste</span><b>' + plata(s.abonos_perdidos) + '</b></div></div>' +
      '<div class="card"><h2>💰 Ingresos por mes</h2>' + (s.meses.length ? '<div class="bar-mes">' + s.meses.map((m) => '<div><b style="color:var(--text)">' + plata(m.ingresos) + '</b><span style="height:' +
        Math.round(100 * (m.ingresos || 0) / max) + '%"></span>' + m.mes.slice(5) + '/' + m.mes.slice(2, 4) + '</div>').join('') + '</div>' : '<p class="muted">Aún sin trabajos completados.</p>') + '</div>' +
      '<div class="card"><h2>🛠️ Servicios más pedidos (90 días)</h2><ul class="list">' + (s.servicios.map((x) => '<li><span class="grow">' + esc(x.nombre) + '</span><b>' + x.n + '</b></li>').join('') || '<li class="muted">Sin datos.</li>') + '</ul></div>';
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
      '<div id="uPush"></div>' +
      (P.dueno ? '<h3>🧹 Comprobantes</h3><p class="sub" style="margin:0">Se borran solos a los ' + ((pub.config || {}).dias_comprobantes || 30) + ' días. Descarga los que quieras guardar antes de limpiar.</p>' +
        '<div class="btns"><button class="ghost" id="uLimpiar">Borrar comprobantes ya revisados</button></div>' : '') +
      '<div class="btns"><button class="danger" id="uSalir">Cerrar sesión</button></div></div>';
    App.ofrecerPush($('uPush'));
    $('uG').onclick = async () => { try { await rpc('mi_perfil_guardar', { p_nombre: $('uN').value, p_telefono: $('uT').value }); toast('💾 Guardado'); } catch (e) { toast(e.message); } };
    $('uPG').onclick = async () => { const { error } = await sb.auth.updateUser({ password: $('uP').value }); toast(error ? App.friendly(error) : '🔑 Contraseña cambiada'); };
    $('uSalir').onclick = () => App.salir();
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
  if (h === 'plan') { subMas = 'plan'; showOrig('mas'); }
  else showOrig(['hoy', 'agenda', 'reservas', 'clientes', 'mas'].includes(h) ? h : 'hoy');
})();
