/* G142 b · 📚 CFX_CATALOGO (núcleo): listas de TEXTO con autocompletar ("tre ma" → Trek Marlin). Sin fotos, liviano.
   CFX_CATALOGO.campo(input, 'bici', { rpc, alElegir })  → sugerencias bajo el campo (tocar = elegir). Lo que se escribe y no existe
                                                         se suma a la lista PROPIA del negocio (cfx_catalogo_sumar; nucleo/sql/catalogo.sql).
   CFX_CATALOGO.buscar('bici', 'tre ma', 8)            → ['Trek Marlin 4', …]
   CFX_CATALOGO.lista('color')                          → la lista de fábrica (sin las propias).
   CFX_CATALOGO.registrar('mi_lista', [...])            → otra app suma su lista.
   Listas: bici (marca + modelo) · bici_marca · bici_tipo · aro · talla · grupo · frenos · color · auto (marca + modelo) · auto_marca. */
(function () {
  if (window.CFX_CATALOGO) return;
  const BICIS = {
    Trek: 'Marlin 4|Marlin 5|Marlin 6|Marlin 7|Marlin 8|Roscoe|X-Caliber|Procaliber|Supercaliber|Fuel EX|Top Fuel|Slash|Remedy|Domane|Émonda|Madone|Checkpoint|FX|Dual Sport|Verve|Allant+|Rail|Powerfly|Precaliber|Wahoo',
    Specialized: 'Rockhopper|Chisel|Epic|Stumpjumper|Enduro|Status|Fuse|Allez|Tarmac|Roubaix|Aethos|Diverge|Crux|Sirrus|Turbo Vado|Turbo Levo|Turbo Como|Riprock|Hotrock|Jett',
    Giant: 'Talon|ATX|Fathom|XTC|Trance|Reign|Stance|Anthem|Contend|TCR|Defy|Propel|Revolt|Escape|Roam|FastRoad|Talon E+|Explore E+|ARX',
    Scott: 'Aspect|Scale|Spark|Genius|Ransom|Contessa|Addict|Foil|Speedster|Speedster Gravel|Sub Cross|Sub Cargo|Strike eRIDE|Roxter',
    Cannondale: 'Trail|Trail SE|F-Si|Scalpel|Habit|Jekyll|CAAD Optimo|CAAD13|SuperSix EVO|Synapse|Topstone|Quick|Treadwell|Moterra|Cujo',
    Merida: 'Big.Nine|Big.Seven|Big.Trail|One-Twenty|One-Forty|Ninety-Six|Scultura|Reacto|Silex|Crossway|eOne-Sixty|Matts',
    Oxford: 'Merak 1|Merak 2|Orion 3|Orion 4|Orion 5|Venus|Hurricane|Vulcano|Luna|Pulse|Cosmo|Mercurio|Spirit|Sport|Infantil aro 20|Infantil aro 16',
    Bianchi: 'Magma|Methanol|Nitron|Via Nirone 7|Sprint|Oltre|Infinito|Specialissima|Impulso|C-Sport|Arcadex',
    Trinx: 'M100|M116|M136|M500|M600|M1000|X1|Climber|Tempo|Free|Majestic',
    Orbea: 'MX|Onna|Alma|Oiz|Occam|Laufey|Rallon|Orca|Avant|Terra|Vector|Carpe|Rise|Wild|Katu',
    Cube: 'Aim|Attention|Analog|Acid|Reaction|Stereo|AMS|Attain|Agree|Nuroad|Nature|Kathmandu|Stereo Hybrid|Reaction Hybrid',
    Polygon: 'Cascade|Monarch|Xtrada|Syncline|Siskiu|Collosus|Strattos|Path|Heist',
    GT: 'Aggressor|Avalanche|Zaskar|Sensor|Force|Grade|Performer|Mach One|Slammer',
    'Santa Cruz': 'Chameleon|Tallboy|Hightower|Bronson|5010|Megatower|Nomad|Blur|Heckler|Stigmata',
    BMC: 'Twostroke|Fourstroke|Speedfox|Teamelite|Roadmachine|Teammachine|Kaius|URS|Alpenchallenge',
    Canyon: 'Grand Canyon|Neuron|Spectral|Strive|Lux|Exceed|Endurace|Ultimate|Aeroad|Grizl|Grail|Pathlite|Roadlite|Commuter',
    Kona: 'Lana\'i|Fire Mountain|Mahuna|Kahuna|Honzo|Process|Remote|Rove|Sutra|Dew|Unit',
    Marin: 'Bolinas Ridge|Wildcat Trail|Bobcat Trail|Palisades Trail|San Quentin|Rift Zone|Alpine Trail|Nicasio|Gestalt|Fairfax|Larkspur|DSX',
    Focus: 'Whistler|Raven|Jam|Thron|Sam|Izalco|Cayo|Paralane|Atlas|Jarifa|Aventura',
    Haro: 'Downtown|Leucadia|Flightline|Double Peak|Shift|Annex|Midway',
    Mongoose: 'Legion|Switchback|Tyax|Dolomite|Status|Title',
    Bergamont: 'Revox|Trailster|Contrail|Grandurance|Sweep|E-Horizon',
    Jeep: 'Aro 29|Aro 27.5|Aro 26|Eléctrica plegable|Infantil',
    GW: 'Zebra|Lynx|Hyena|Raptor|Jaguar|Alligator|Cougar|Fenix|Panther',
    Lahsen: 'Aro 29|Aro 27.5|Aro 26|Urbana|Paseo|Infantil',
    Bimex: 'Aro 29|Aro 26|Paseo|Infantil',
    Brompton: 'C Line|P Line|T Line|Electric',
    Benotto: 'Aro 29|Aro 26|Ruta|Urbana',
    Cervélo: 'R5|S5|Caledonia|Áspero|Soloist',
    Pinarello: 'Dogma|Prince|F5|Grevil',
    Colnago: 'V4Rs|C68|G3-X',
    Ghost: 'Kato|Lanao|Lector|Riot|Asket',
    Lapierre: 'Edge|Prorace|XRM|Zesty|Xelius|Pulsium',
    Commencal: 'Meta|Clash|Absolut|Supreme|Ramones',
    Xiaomi: 'Himo|Qicycle|Scooter / bici eléctrica',
    Otra: 'Aro 29|Aro 27.5|Aro 26|Aro 700c (ruta)|Urbana|Plegable|BMX|Eléctrica|Infantil|Tándem|Fixie|Cargo'
  };
  const AUTOS = {
    Chevrolet: 'Spark|Sail|Onix|Prisma|Tracker|Captiva|Groove|Equinox|Silverado|Colorado|N400|D-Max',
    Suzuki: 'Swift|Baleno|Dzire|Celerio|Alto|S-Presso|Ignis|Vitara|Grand Vitara|Jimny|Ertiga|XL7|Fronx',
    Hyundai: 'Accent|Grand i10|i20|Elantra|Creta|Tucson|Santa Fe|Kona|Venue|H-1|Porter',
    Kia: 'Morning|Rio|Soluto|Cerato|Sonet|Seltos|Sportage|Sorento|Carnival|Frontier',
    Toyota: 'Yaris|Corolla|Corolla Cross|RAV4|Hilux|Fortuner|Rush|Raize|Land Cruiser Prado|4Runner',
    Nissan: 'March|Versa|Sentra|Kicks|Qashqai|X-Trail|Navara|NP300|Terrano',
    Peugeot: '208|2008|301|308|3008|5008|Partner|Rifter|Landtrek|Boxer',
    Mazda: '2|3|CX-3|CX-30|CX-5|CX-9|BT-50',
    Mitsubishi: 'Mirage|ASX|Outlander|Eclipse Cross|Montero|L200',
    Chery: 'Tiggo 2|Tiggo 3|Tiggo 4|Tiggo 7|Tiggo 8|Arrizo 5',
    MG: 'MG3|ZS|ZX|HS|GT|MG5|RX5',
    Great_Wall: 'Poer|Wingle',
    Haval: 'Jolion|H6|Dargo',
    Changan: 'Alsvin|CS15|CS35|CS55|Hunter|Uni-T',
    Ford: 'Fiesta|Focus|EcoSport|Territory|Escape|Explorer|Ranger|F-150|Transit',
    Volkswagen: 'Gol|Polo|Virtus|Jetta|T-Cross|Nivus|Taos|Tiguan|Amarok|Saveiro',
    Renault: 'Kwid|Clio|Logan|Symbol|Stepway|Duster|Koleos|Oroch|Alaskan|Kangoo',
    Citroën: 'C3|C4|C-Elysée|C5 Aircross|Berlingo|Jumpy',
    Fiat: 'Mobi|Uno|Argo|Cronos|Pulse|Fastback|Strada|Toro|Fiorino',
    Honda: 'City|Civic|Fit|HR-V|CR-V|WR-V|Pilot',
    Subaru: 'Impreza|XV|Crosstrek|Forester|Outback',
    JAC: 'S2|S3|JS4|T6|T8',
    BYD: 'Dolphin|Seal|Yuan Plus|Song Plus|Tang|Han',
    Jeep_: 'Renegade|Compass|Cherokee|Grand Cherokee|Wrangler|Gladiator',
    Ssangyong: 'Tivoli|Korando|Rexton|Musso|Actyon',
    Mercedes_Benz: 'Clase A|Clase C|GLA|GLC|Sprinter',
    BMW: 'Serie 1|Serie 3|X1|X3|X5',
    Audi: 'A3|A4|Q2|Q3|Q5',
    Otra: 'Moto|Camioneta|Furgón|Camión|SUV|Sedán|Hatchback'
  };
  const nom = (k) => k.replace(/_$/, '').replace(/_/g, ' ');
  const plano = (o) => { const r = []; Object.keys(o).forEach((m) => { const mm = nom(m); if (m !== 'Otra') r.push(mm); o[m].split('|').forEach((x) => r.push(m === 'Otra' ? x : mm + ' ' + x)); }); return r; };
  const L = {
    bici: plano(BICIS), bici_marca: Object.keys(BICIS).filter((m) => m !== 'Otra').map(nom),
    bici_tipo: ['MTB (montaña)', 'Ruta', 'Gravel', 'Urbana', 'Paseo', 'BMX', 'Eléctrica (e-bike)', 'Infantil', 'Plegable', 'Fixie', 'Tándem', 'Cargo', 'Enduro', 'Downhill', 'Triatlón'],
    aro: ['12', '14', '16', '20', '24', '26', '27.5', '29', '700c', '650b'],
    talla: ['XS', 'S', 'M', 'L', 'XL', 'XXL', '13"', '15"', '16"', '17"', '18"', '19"', '20"', '21"', '22"', '48 cm', '50 cm', '52 cm', '54 cm', '56 cm', '58 cm', '60 cm'],
    grupo: ['Shimano Tourney', 'Shimano Altus', 'Shimano Acera', 'Shimano Alivio', 'Shimano Cues', 'Shimano Deore', 'Shimano SLX', 'Shimano XT', 'Shimano XTR',
      'Shimano Claris', 'Shimano Sora', 'Shimano Tiagra', 'Shimano 105', 'Shimano 105 Di2', 'Shimano Ultegra', 'Shimano Ultegra Di2', 'Shimano Dura-Ace', 'Shimano GRX',
      'SRAM SX Eagle', 'SRAM NX Eagle', 'SRAM GX Eagle', 'SRAM X01 Eagle', 'SRAM XX1 Eagle', 'SRAM Eagle Transmission', 'SRAM Apex', 'SRAM Rival', 'SRAM Force', 'SRAM Red',
      'microSHIFT Advent', 'microSHIFT Advent X', 'microSHIFT Acolyte', 'microSHIFT Mezzo', 'Sunrace', 'Ltwoo', 'Campagnolo', 'Monovelocidad', 'Cambio interno (maza)'],
    frenos: ['Disco hidráulico', 'Disco mecánico', 'V-brake', 'Caliper (ruta)', 'Contrapedal', 'Cantilever', 'Tambor'],
    color: ['Negro', 'Blanco', 'Gris', 'Plateado', 'Rojo', 'Azul', 'Celeste', 'Verde', 'Amarillo', 'Naranjo', 'Morado', 'Rosado', 'Café', 'Dorado', 'Turquesa', 'Calipso',
      'Negro mate', 'Negro con rojo', 'Negro con verde', 'Negro con azul', 'Blanco con negro', 'Gris con naranjo', 'Multicolor'],
    auto: plano(AUTOS), auto_marca: Object.keys(AUTOS).filter((m) => m !== 'Otra').map(nom)
  };
  const norm = (t) => String(t || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9.+"]+/g, ' ').trim();
  const IDX = {};
  const idx = (k) => IDX[k] || (IDX[k] = (L[k] || []).map((x) => [x, norm(x), norm(x).split(' ')]));
  const PROPIAS = {}, CARGANDO = {};
  // Cada palabra escrita es el comienzo de alguna palabra del ítem (en cualquier orden). Primero lo que empieza igual y lo más corto.
  function buscar(k, texto, n) {
    const q = norm(texto).split(' ').filter(Boolean); if (!q.length) return [];
    const base = (PROPIAS[k] || []).map((x) => [x, norm(x), norm(x).split(' '), 1]).concat(idx(k));
    const vistos = new Set(), r = [];
    for (const [x, t, ws, propia] of base) {
      if (vistos.has(t)) continue;
      if (!q.every((w) => ws.some((p) => p.startsWith(w)) || (w.length > 2 && t.includes(w)))) continue;
      vistos.add(t);
      r.push([x, (t.startsWith(q[0]) ? 0 : 10) + (propia ? -5 : 0) + t.length / 100]);
    }
    return r.sort((a, b) => a[1] - b[1]).slice(0, n || 8).map((x) => x[0]);
  }
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const css = document.createElement('style');
  css.textContent = '.cfx-cat{position:relative}.cfx-cat-l{position:absolute;left:0;right:0;top:100%;z-index:60;margin:2px 0 0;padding:4px;list-style:none;border-radius:12px;' +
    'background:var(--cfx-tarjeta,#fff);color:var(--cfx-texto,#111827);border:1px solid var(--cfx-borde,rgba(100,116,139,.35));box-shadow:0 8px 24px rgba(0,0,0,.18);max-height:260px;overflow:auto}' +
    '.cfx-cat-l button{display:block;width:100%;text-align:left;font:inherit;padding:10px;min-height:44px;border:0;border-radius:8px;background:transparent;color:inherit;cursor:pointer}' +
    '.cfx-cat-l button:hover,.cfx-cat-l button:focus{background:var(--cfx-fondo-2,rgba(100,116,139,.14));outline:0}.cfx-cat-l b{color:var(--brand,#2563eb)}.cfx-cat-l small{opacity:.65}';
  document.head.appendChild(css);
  async function propias(k, rpc) {
    if (!rpc || PROPIAS[k]) return;
    if (!CARGANDO[k]) CARGANDO[k] = Promise.resolve(rpc('cfx_catalogo_mio', { p_lista: k })).then((r) => { PROPIAS[k] = Array.isArray(r) ? r : []; }).catch(() => { PROPIAS[k] = []; });
    return CARGANDO[k];
  }
  // Marca en negrita lo escrito (sin innerHTML con datos crudos).
  const resaltar = (x, q) => { const ws = norm(q).split(' ').filter(Boolean); return x.split(' ').map((p) => { const n = norm(p); const w = ws.find((y) => n.startsWith(y)); return w ? '<b>' + esc(p.slice(0, w.length)) + '</b>' + esc(p.slice(w.length)) : esc(p); }).join(' '); };
  function campo(input, k, o) {
    if (!input || input.dataset.cfxCat) return; input.dataset.cfxCat = k; o = o || {};
    input.setAttribute('autocomplete', 'off'); input.removeAttribute('list');
    const caja = document.createElement('div'); caja.className = 'cfx-cat'; input.parentNode.insertBefore(caja, input); caja.appendChild(input);
    const ul = document.createElement('div'); ul.className = 'cfx-cat-l'; ul.hidden = true; ul.setAttribute('role', 'listbox'); caja.appendChild(ul);
    propias(k, o.rpc);
    let elegido = false;
    const pintar = () => {
      const v = input.value; const r = buscar(k, v, 8);
      if (!v.trim() || !r.length || (r.length === 1 && norm(r[0]) === norm(v))) { ul.hidden = true; return; }
      ul.innerHTML = r.map((x) => '<button type="button" role="option" data-v="' + esc(x) + '">' + resaltar(x, v) + '</button>').join('');
      ul.hidden = false;
    };
    input.addEventListener('input', () => { elegido = false; pintar(); });
    input.addEventListener('focus', () => { propias(k, o.rpc); if (input.value) pintar(); });
    ul.addEventListener('mousedown', (e) => e.preventDefault());  // que el campo no pierda el foco antes del toque
    ul.addEventListener('click', (e) => {
      const b = e.target.closest('[data-v]'); if (!b) return;
      input.value = b.dataset.v; elegido = true; ul.hidden = true;
      input.dispatchEvent(new Event('change', { bubbles: true }));
      if (navigator.vibrate) try { navigator.vibrate(8); } catch (x) { /* sin vibración */ }
      if (o.alElegir) o.alElegir(input.value);
    });
    input.addEventListener('blur', () => setTimeout(() => { ul.hidden = true; if (!elegido) sumar(k, input.value, o.rpc); }, 150));
  }
  // Lo que el negocio escribe y no está → a SU lista (servidor). Silencioso: nunca molesta si falla.
  function sumar(k, v, rpc) {
    v = String(v || '').trim().replace(/\s+/g, ' ');
    if (!rpc || v.length < 2 || v.length > 60) return;
    const n = norm(v); if (idx(k).some((x) => x[1] === n) || (PROPIAS[k] || []).some((x) => norm(x) === n)) return;
    (PROPIAS[k] = PROPIAS[k] || []).unshift(v);
    Promise.resolve(rpc('cfx_catalogo_sumar', { p_lista: k, p_valor: v })).catch(() => {});
  }
  window.CFX_CATALOGO = { campo, buscar, sumar, norm, lista: (k) => (L[k] || []).slice(), registrar: (k, a) => { L[k] = (a || []).slice(); delete IDX[k]; }, LISTAS: Object.keys(L) };
})();
