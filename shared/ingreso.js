/* G142 b · 📋 CFX_INGRESO (núcleo): recibir algo (bici, auto, equipo) con CASILLAS, fotos, N° de serie, firma y notas.
   const f = CFX_INGRESO.montar(el, { rpc, datos, ficha: [{ k, t, lista }], accesorios: [...], zonas: [...], serie: true, firma: true, fotos: 4 });
     f.datos()  → { ficha:{k:valor}, accesorios:[...], estado:{zona:'ok'|'rev'|'mal'}, serie, notas, firma:'data:image/png…' | '' }
     f.fotos()  → fotos nuevas ya achicadas (data:image/jpeg, ≤ 150 KB c/u) para que la app las suba a lo suyo.
     f.valido() → '' o el texto de lo que falta (p. ej. firma pedida y vacía si o.firmaObligatoria).
   CFX_INGRESO.acta(datos, { titulo, negocio, cliente, fecha, extra }) → HTML (escapado) del acta para imprimir / PDF / compartir.
   CFX_INGRESO.leerSerie(file) → texto leído con OCR en el teléfono (Tesseract.js 5.1.1, la foto no se sube).
   📷 Escanear usa BarcodeDetector (Android/Chrome); si el teléfono no lo tiene, queda 📸 Leer con foto (OCR) y escribirlo.
   CFX_INGRESO.nfc(url) → 📲 graba el link en una etiqueta NFC (Chrome Android).
   📳 Vibra al marcar. 🎙️ El dictado lo pone voz.js en las notas (si la app lo carga). Requiere CFX_CATALOGO para el autocompletar. */
(function () {
  if (window.CFX_INGRESO) return;
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const vibrar = (ms) => { if (navigator.vibrate) try { navigator.vibrate(ms || 10); } catch (x) { /* sin vibración */ } };
  const aviso = (t) => window.CFX_DIALOGO ? window.CFX_DIALOGO.avisar(t) : (window.CFX_AVISO ? window.CFX_AVISO(t) : console.warn(t));
  const ESTADOS = { '': ['⬜', 'Sin revisar'], ok: ['✅', 'Bien'], rev: ['🔧', 'Revisar'], mal: ['⚠️', 'Dañado'] };
  const CICLO = ['', 'ok', 'rev', 'mal'];
  const css = document.createElement('style');
  css.textContent =
    '.cfxi{display:grid;gap:12px}.cfxi h3{margin:6px 0 0;font-size:15px}.cfxi .cfxi-sub{margin:0;font-size:13px;color:var(--cfx-texto-2,#5b6472)}' +
    '.cfxi-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(130px,1fr));gap:8px}.cfxi-grid label{margin:0;font-size:13px}.cfxi-grid input{width:100%;box-sizing:border-box}' +
    '.cfxi-ch{display:flex;flex-wrap:wrap;gap:6px}.cfxi-ch button{font:inherit;font-size:14px;min-height:40px;padding:6px 12px;border-radius:99px;cursor:pointer;' +
    'border:1px solid var(--cfx-borde,rgba(100,116,139,.35));background:transparent;color:inherit}.cfxi-ch button[aria-pressed=true]{background:var(--brand,#2563eb);border-color:var(--brand,#2563eb);color:#fff;font-weight:700}' +
    '.cfxi-z{display:grid;grid-template-columns:repeat(auto-fill,minmax(140px,1fr));gap:6px}.cfxi-z button{display:flex;align-items:center;justify-content:flex-start;gap:8px;font:inherit;font-size:14px;min-height:44px;padding:6px 10px;border-radius:12px;cursor:pointer;text-align:left;' +
    'border:1px solid var(--cfx-borde,rgba(100,116,139,.35));background:var(--cfx-tarjeta,transparent);color:inherit}.cfxi-z button span:first-child{font-size:18px}.cfxi-z button small{display:block;opacity:.7;font-size:12px}' +
    '.cfxi-row{display:flex;gap:6px;flex-wrap:wrap;align-items:center}.cfxi-row input{flex:1 1 150px;min-width:0}.cfxi-row button,.cfxi-row label.cfxi-b{flex:0 0 auto;margin:0}' +
    '.cfxi-b{display:inline-flex;align-items:center;justify-content:center;font:inherit;font-size:14px;min-height:42px;padding:6px 12px;border-radius:12px;cursor:pointer;border:1px solid var(--brand,#2563eb);background:transparent;color:var(--brand,#2563eb);font-weight:700}' +
    '.cfxi-fotos{display:flex;gap:6px;flex-wrap:wrap}.cfxi-fotos figure{position:relative;margin:0;width:72px;height:72px;border-radius:10px;overflow:hidden;background:var(--cfx-fondo-2,rgba(100,116,139,.14))}' +
    '.cfxi-fotos img{width:100%;height:100%;object-fit:cover}.cfxi-fotos button{position:absolute;top:2px;right:2px;width:26px;height:26px;border-radius:50%;border:0;background:rgba(0,0,0,.6);color:#fff;cursor:pointer}' +
    '.cfxi-firma{position:relative;border:1px dashed var(--cfx-borde,rgba(100,116,139,.6));border-radius:12px;background:#fff;touch-action:none;height:150px}.cfxi-firma canvas{width:100%;height:100%;display:block;border-radius:12px}' +
    '.cfxi-firma span{position:absolute;left:10px;bottom:6px;font-size:12px;color:#94a3b8;pointer-events:none}.cfxi-firma img{width:100%;height:100%;object-fit:contain}' +
    '.cfxi-scan{position:fixed;inset:0;z-index:2147483000;background:#000;display:flex;flex-direction:column}.cfxi-scan video{flex:1;width:100%;object-fit:cover}' +
    '.cfxi-scan p{margin:0;padding:10px 14px;color:#fff;text-align:center}.cfxi-scan button{margin:10px 14px calc(14px + env(safe-area-inset-bottom));min-height:48px;border-radius:12px;border:0;font:inherit;font-weight:800}' +
    '.cfxi-err{color:var(--cfx-error,#dc2626);font-size:13px;margin:0}';
  document.head.appendChild(css);

  // Foto → JPEG achicado que entra en el límite (las bases guardan ≤ 160.000 caracteres).
  async function achicar(file, max, limite) {
    const url = URL.createObjectURL(file);
    try {
      const img = await new Promise((ok, no) => { const i = new Image(); i.onload = () => ok(i); i.onerror = () => no(new Error('Esa imagen no se pudo abrir')); i.src = url; });
      let lado = max || 1000, q = 0.72, out = '';
      for (let i = 0; i < 6; i++) {
        const k = Math.min(1, lado / Math.max(img.width, img.height, 1)), c = document.createElement('canvas');
        c.width = Math.round(img.width * k); c.height = Math.round(img.height * k);
        const g = c.getContext('2d'); g.fillStyle = '#fff'; g.fillRect(0, 0, c.width, c.height); g.drawImage(img, 0, 0, c.width, c.height);
        out = c.toDataURL('image/jpeg', q); if (out.length <= (limite || 150000)) return out;
        lado = Math.round(lado * 0.8); q = Math.max(0.45, q - 0.07);
      }
      return out;
    } finally { URL.revokeObjectURL(url); }
  }
  // 📸 N° de serie con OCR en el teléfono. Devuelve los candidatos (letras y números, con al menos un dígito).
  let tess;
  const cargarTess = () => tess || (tess = new Promise((ok, no) => {
    if (window.Tesseract) return ok(window.Tesseract);
    const s = document.createElement('script'); s.src = 'https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js'; s.crossOrigin = 'anonymous';
    s.onload = () => ok(window.Tesseract); s.onerror = () => { tess = null; no(new Error('No se pudo cargar el lector. Revisa tu conexión o escribe el número.')); };
    document.head.appendChild(s);
  }));
  const candidatos = (texto) => {
    const t = String(texto || '').toUpperCase().replace(/[^A-Z0-9\-\s]/g, ' ');
    const v = (t.match(/[A-Z0-9][A-Z0-9-]{4,22}[A-Z0-9]/g) || []).filter((x) => /\d/.test(x) && /[A-Z0-9]{2}/.test(x));
    return Array.from(new Set(v)).sort((a, b) => b.length - a.length).slice(0, 5);
  };
  async function leerSerie(file) {
    const T = await cargarTess();
    const url = URL.createObjectURL(file);
    try {
      const img = await new Promise((ok, no) => { const i = new Image(); i.onload = () => ok(i); i.onerror = () => no(new Error('Esa imagen no se pudo abrir')); i.src = url; });
      const k = Math.min(1, 1600 / Math.max(img.width, 1)), c = document.createElement('canvas');
      c.width = Math.round(img.width * k); c.height = Math.round(img.height * k);
      const g = c.getContext('2d'); g.filter = 'grayscale(1) contrast(1.4)'; g.drawImage(img, 0, 0, c.width, c.height);
      const w = await T.createWorker('eng', 1);
      try {
        await w.setParameters({ tessedit_char_whitelist: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-' });
        const { data } = await w.recognize(c); return { texto: data.text, candidatos: candidatos(data.text) };
      } finally { w.terminate(); }
    } finally { URL.revokeObjectURL(url); }
  }
  // 📷 Escanear código de barras / QR con la cámara (BarcodeDetector). Devuelve el texto o null.
  const puedeEscanear = () => 'BarcodeDetector' in window && !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia);
  async function escanear() {
    const det = new window.BarcodeDetector({ formats: ['code_128', 'code_39', 'qr_code', 'data_matrix', 'ean_13', 'upc_a', 'itf'] });
    const cap = document.createElement('div'); cap.className = 'cfxi-scan';
    cap.innerHTML = '<p>Apunta al código de barras o QR del marco (bajo el pedalier)</p><video playsinline muted></video><button type="button">Cancelar</button>';
    document.body.appendChild(cap);
    const v = cap.querySelector('video'); let st = null, fin = false;
    return new Promise(async (ok) => {
      const cerrar = (r) => { if (fin) return; fin = true; if (st) st.getTracks().forEach((t) => t.stop()); cap.remove(); ok(r); };
      cap.querySelector('button').onclick = () => cerrar(null);
      try { st = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } }); v.srcObject = st; await v.play(); }
      catch (e) { cerrar(null); aviso('No se pudo abrir la cámara. Revisa el permiso o escribe el número.'); return; }
      const paso = async () => {
        if (fin) return;
        try { const r = await det.detect(v); if (r && r[0] && r[0].rawValue) { vibrar(40); return cerrar(String(r[0].rawValue).trim().slice(0, 60)); } } catch (e) { /* sigue */ }
        setTimeout(paso, 250);
      };
      paso();
    });
  }

  function montar(el, o) {
    o = o || {};
    const d0 = o.datos || {};
    const D = { ficha: Object.assign({}, d0.ficha || {}), accesorios: (d0.accesorios || []).slice(), estado: Object.assign({}, d0.estado || {}),
      serie: d0.serie || '', notas: d0.notas || '', firma: d0.firma || '' };
    const fotos = [];
    const acc = Array.from(new Set((o.accesorios || []).concat(D.accesorios)));
    const ficha = o.ficha || [];
    el.innerHTML = '<div class="cfxi">' +
      (ficha.length ? '<div class="cfxi-grid">' + ficha.map((c, i) => '<div' + (c.ancho ? ' style="grid-column:1/-1"' : '') + '><label for="cfxiF' + i + '">' + esc(c.t) + '</label><input id="cfxiF' + i + '" data-f="' + esc(c.k) + '" maxlength="60" value="' + esc(D.ficha[c.k] || '') + '" placeholder="' + esc(c.ph || '') + '"></div>').join('') + '</div>' : '') +
      (o.serie ? '<div><h3>🔢 N° de serie</h3><div class="cfxi-row"><input data-serie maxlength="60" autocapitalize="characters" placeholder="Bajo el pedalier" value="' + esc(D.serie) + '">' +
        (puedeEscanear() ? '<button type="button" class="cfxi-b" data-scan>📷 Escanear</button>' : '') +
        '<label class="cfxi-b">📸 Leer con foto<input type="file" accept="image/*" capture="environment" hidden data-ocr></label></div><p class="cfxi-sub" data-ocr-txt></p></div>' : '') +
      (acc.length ? '<div><h3>🎒 Trae</h3><p class="cfxi-sub">Marca lo que deja con la bici.</p><div class="cfxi-ch" data-acc>' + acc.map((a) => '<button type="button" aria-pressed="' + (D.accesorios.includes(a)) + '" data-a="' + esc(a) + '">' + esc(a) + '</button>').join('') +
        '<button type="button" data-otro-acc>＋ Otro</button></div></div>' : '') +
      ((o.zonas || []).length ? '<div><h3>🔍 Cómo llega</h3><p class="cfxi-sub">Toca cada parte: ⬜ → ✅ bien → 🔧 revisar → ⚠️ dañado.</p><div class="cfxi-z">' +
        o.zonas.map((z) => '<button type="button" data-z="' + esc(z) + '"></button>').join('') + '</div></div>' : '') +
      (o.fotos ? '<div><h3>📸 Fotos al recibir</h3><div class="cfxi-fotos" data-fotos></div><div class="cfxi-row" style="margin-top:6px"><label class="cfxi-b">📷 Sacar foto<input type="file" accept="image/*" capture="environment" hidden data-foto></label>' +
        '<label class="cfxi-b">🖼️ De la galería<input type="file" accept="image/*" multiple hidden data-foto></label></div></div>' : '') +
      '<div><label for="cfxiN"><b>📝 Notas</b> <span class="cfxi-sub">(rayones, detalles, lo que pidió)</span></label><textarea id="cfxiN" data-notas maxlength="600" rows="2">' + esc(D.notas) + '</textarea></div>' +
      (o.firma ? '<div><h3>✍️ Firma del cliente</h3><p class="cfxi-sub">' + esc(o.textoFirma || 'Firma con el dedo: deja la bici con lo marcado arriba.') + '</p><div class="cfxi-firma" data-firma></div>' +
        '<div class="cfxi-row" style="margin-top:6px"><button type="button" class="cfxi-b" data-borrar-firma>↺ Borrar firma</button></div></div>' : '') +
      '<p class="cfxi-err" data-err></p></div>';
    const q = (s) => el.querySelector(s);
    // 📚 autocompletar
    ficha.forEach((c, i) => { const inp = q('#cfxiF' + i); if (c.lista && window.CFX_CATALOGO) window.CFX_CATALOGO.campo(inp, c.lista, { rpc: o.rpc }); inp.addEventListener('change', () => { D.ficha[c.k] = inp.value.trim(); }); inp.addEventListener('input', () => { D.ficha[c.k] = inp.value.trim(); }); });
    // 🔍 zonas
    const pintaZ = (b) => { const s = ESTADOS[D.estado[b.dataset.z] || ''] || ESTADOS['']; b.innerHTML = '<span>' + s[0] + '</span><span>' + esc(b.dataset.z) + '<small>' + s[1] + '</small></span>'; b.setAttribute('aria-label', b.dataset.z + ': ' + s[1]); };
    el.querySelectorAll('[data-z]').forEach(pintaZ);
    el.addEventListener('click', async (ev) => {
      const z = ev.target.closest('[data-z]');
      if (z) { const k = z.dataset.z, i = CICLO.indexOf(D.estado[k] || ''); const n = CICLO[(i + 1) % CICLO.length]; if (n) D.estado[k] = n; else delete D.estado[k]; pintaZ(z); vibrar(n === 'mal' ? 30 : 10); return; }
      const a = ev.target.closest('[data-a]');
      if (a) { const on = a.getAttribute('aria-pressed') !== 'true'; a.setAttribute('aria-pressed', on); const v = a.dataset.a; D.accesorios = D.accesorios.filter((x) => x !== v); if (on) D.accesorios.push(v); vibrar(); return; }
      if (ev.target.closest('[data-otro-acc]')) {
        const t = window.CFX_DIALOGO ? await window.CFX_DIALOGO.pedir('¿Qué otra cosa trae?', '', { si: 'Agregar' }) : null;
        const v = String(t || '').trim().slice(0, 40); if (!v || D.accesorios.includes(v)) return;
        D.accesorios.push(v); const b = document.createElement('button'); b.type = 'button'; b.dataset.a = v; b.textContent = v; b.setAttribute('aria-pressed', 'true');
        ev.target.closest('[data-otro-acc]').before(b); vibrar(); return;
      }
      if (ev.target.closest('[data-scan]')) { const r = await escanear(); if (r) { q('[data-serie]').value = r; D.serie = r; } return; }
      const fx = ev.target.closest('[data-quitar]');
      if (fx) { fotos.splice(+fx.dataset.quitar, 1); pintaF(); return; }
      if (ev.target.closest('[data-borrar-firma]')) { D.firma = ''; firmaLimpia(); }
    });
    const se = q('[data-serie]'); if (se) se.addEventListener('input', () => { D.serie = se.value.trim().toUpperCase(); });
    const no = q('[data-notas]'); no.addEventListener('input', () => { D.notas = no.value; });
    const ocr = q('[data-ocr]');
    if (ocr) ocr.addEventListener('change', async () => {
      const f = ocr.files && ocr.files[0]; ocr.value = ''; if (!f) return;
      const t = q('[data-ocr-txt]'); t.textContent = '⏳ Leyendo el número… (la 1.ª vez demora un poco)';
      try {
        const r = await leerSerie(f);
        if (!r.candidatos.length) { t.textContent = 'No encontré un número claro. Saca la foto más de cerca y con luz, o escríbelo.'; return; }
        se.value = r.candidatos[0]; D.serie = r.candidatos[0];
        t.innerHTML = '¿Es este? Revisa letra por letra.' + (r.candidatos.length > 1 ? ' Otros: ' + r.candidatos.slice(1).map((x) => '<button type="button" class="cfxi-b" data-cand="' + esc(x) + '">' + esc(x) + '</button>').join(' ') : '');
        t.querySelectorAll('[data-cand]').forEach((b) => { b.onclick = () => { se.value = b.dataset.cand; D.serie = b.dataset.cand; }; });
        vibrar(20);
      } catch (e) { t.textContent = (e && e.message) || 'No se pudo leer'; }
    });
    // 📸 fotos
    const maxF = +o.fotos || 0;
    const pintaF = () => { const z = q('[data-fotos]'); if (!z) return; z.innerHTML = fotos.map((f, i) => '<figure><img alt="Foto ' + (i + 1) + '" src="' + f + '"><button type="button" data-quitar="' + i + '" aria-label="Quitar foto">✕</button></figure>').join(''); };
    el.querySelectorAll('[data-foto]').forEach((inp) => inp.addEventListener('change', async () => {
      const fs = Array.from(inp.files || []); inp.value = '';
      for (const f of fs) {
        if (fotos.length >= maxF) { aviso('Máximo ' + maxF + ' fotos al recibir.'); break; }
        try { fotos.push(await achicar(f, 1000, o.limiteFoto || 150000)); } catch (e) { aviso((e && e.message) || 'Esa foto no se pudo usar'); }
      }
      pintaF(); vibrar();
    }));
    // ✍️ firma
    let firmaLimpia = () => {};
    const fz = q('[data-firma]');
    if (fz) {
      const dibujar = () => {
        fz.innerHTML = '<canvas aria-label="Firma"></canvas><span>Firma aquí</span>';
        const c = fz.querySelector('canvas'), r = fz.getBoundingClientRect(), k = Math.min(2, window.devicePixelRatio || 1);
        c.width = Math.max(200, Math.round(r.width * k)); c.height = Math.round(150 * k);
        const g = c.getContext('2d'); g.lineWidth = 2.4 * k; g.lineCap = 'round'; g.lineJoin = 'round'; g.strokeStyle = '#111827';
        let ab = false, hay = false, px = 0, py = 0;
        const pos = (e) => { const b = c.getBoundingClientRect(); return [(e.clientX - b.left) * c.width / b.width, (e.clientY - b.top) * c.height / b.height]; };
        c.addEventListener('pointerdown', (e) => { ab = true; [px, py] = pos(e); try { c.setPointerCapture(e.pointerId); } catch (x) { /* sin captura */ } e.preventDefault(); });
        c.addEventListener('pointermove', (e) => { if (!ab) return; const [x, y] = pos(e); g.beginPath(); g.moveTo(px, py); g.lineTo(x, y); g.stroke(); px = x; py = y; hay = true; e.preventDefault(); });
        const fin = () => { if (!ab) return; ab = false; if (hay) { fz.querySelector('span').textContent = ''; D.firma = recortar(c); } };
        c.addEventListener('pointerup', fin); c.addEventListener('pointercancel', fin); c.addEventListener('pointerleave', fin);
      };
      firmaLimpia = dibujar;
      if (D.firma) { fz.innerHTML = '<img alt="Firma guardada" src="' + esc(D.firma) + '">'; } else requestAnimationFrame(dibujar);
    }
    return {
      datos: () => {
        const f = {}; Object.keys(D.ficha).forEach((k) => { const v = String(D.ficha[k] || '').trim().slice(0, 60); if (v) f[k] = v; });
        return { ficha: f, accesorios: D.accesorios.slice(0, 30).map((x) => String(x).slice(0, 40)), estado: D.estado, serie: String(D.serie || '').slice(0, 60), notas: String(D.notas || '').slice(0, 600), firma: D.firma || '' };
      },
      fotos: () => fotos.slice(),
      valido: () => { const t = o.firmaObligatoria && !D.firma ? 'Falta la firma del cliente' : ''; q('[data-err]').textContent = t; return t; }
    };
  }
  // Firma → PNG chico (recortado a lo dibujado, máx. 600 px de ancho).
  function recortar(c) {
    const g = c.getContext('2d'), w = c.width, h = c.height, px = g.getImageData(0, 0, w, h).data;
    let x0 = w, y0 = h, x1 = 0, y1 = 0;
    for (let y = 0; y < h; y += 2) for (let x = 0; x < w; x += 2) if (px[(y * w + x) * 4 + 3] > 0) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
    if (x1 <= x0) return '';
    const m = 8, cw = Math.min(w, x1 - x0 + 2 * m), ch = Math.min(h, y1 - y0 + 2 * m), k = Math.min(1, 600 / cw);
    const o = document.createElement('canvas'); o.width = Math.round(cw * k); o.height = Math.round(ch * k);
    o.getContext('2d').drawImage(c, Math.max(0, x0 - m), Math.max(0, y0 - m), cw, ch, 0, 0, o.width, o.height);
    return o.toDataURL('image/png');
  }
  // 🧾 Acta del ingreso (HTML para mostrar / imprimir). Todo escapado.
  function acta(d, o) {
    d = d || {}; o = o || {};
    const fi = d.ficha || {}, et = o.etiquetas || {};
    const filas = Object.keys(fi).map((k) => '<tr><th>' + esc(et[k] || k) + '</th><td>' + esc(fi[k]) + '</td></tr>').join('') + (d.serie ? '<tr><th>N° de serie</th><td><b>' + esc(d.serie) + '</b></td></tr>' : '');
    const est = Object.keys(d.estado || {});
    return '<div class="cfxi-acta">' + (o.titulo ? '<h3>' + esc(o.titulo) + '</h3>' : '') +
      (filas ? '<table>' + filas + '</table>' : '') +
      ((d.accesorios || []).length ? '<p><b>Trae:</b> ' + d.accesorios.map(esc).join(' · ') + '</p>' : '') +
      (est.length ? '<p><b>Cómo llega:</b> ' + est.map((z) => (ESTADOS[d.estado[z]] || ESTADOS[''])[0] + ' ' + esc(z) + ' (' + (ESTADOS[d.estado[z]] || ESTADOS[''])[1].toLowerCase() + ')').join(' · ') + '</p>' : '') +
      (d.notas ? '<p><b>Notas:</b> ' + esc(d.notas) + '</p>' : '') +
      (d.firma && /^data:image\/png;base64,[A-Za-z0-9+/=]+$/.test(d.firma) ? '<p><b>Firma del cliente:</b><br><img class="cfxi-fir" alt="Firma" src="' + d.firma + '"></p>' : '') +
      '</div>';
  }
  // G142 d 📲 NFC (Chrome de Android): graba un link en una etiqueta NFC (p. ej. el pasaporte de la bici). true si quedó grabado.
  const puedeNFC = () => 'NDEFReader' in window;
  async function nfc(url) {
    if (!puedeNFC()) { aviso('Tu teléfono no graba NFC desde el navegador (solo Chrome en Android).'); return false; }
    try { const w = new window.NDEFReader(); aviso('📲 Acerca la etiqueta NFC a la parte de atrás del teléfono…'); await w.write({ records: [{ recordType: 'url', data: String(url) }] }); vibrar(60); return true; }
    catch (e) { aviso('No se pudo grabar: ' + ((e && e.message) || 'acerca la etiqueta y prueba otra vez')); return false; }
  }
  window.CFX_INGRESO = { montar, acta, leerSerie, candidatos, achicar, escanear, puedeEscanear, nfc, puedeNFC, ESTADOS };
})();
