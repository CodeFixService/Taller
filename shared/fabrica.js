// G65 🏭 Datos de fábrica de BiciTaller: bicis para elegir, repuestos con precio y notas de un toque.
// Todo es sugerencia: se puede escribir otra cosa y los precios se cambian en la orden.
(function () {
  const M = {
    Trek: ['Marlin 4', 'Marlin 5', 'Marlin 6', 'Marlin 7', 'Roscoe', 'X-Caliber', 'Procaliber', 'Fuel EX', 'Top Fuel', 'Slash', 'Domane', 'Émonda', 'Madone', 'Checkpoint', 'FX', 'Dual Sport', 'Verve', 'Allant+', 'Rail', 'Powerfly', 'Precaliber'],
    Specialized: ['Rockhopper', 'Chisel', 'Epic', 'Stumpjumper', 'Enduro', 'Fuse', 'Allez', 'Tarmac', 'Roubaix', 'Aethos', 'Diverge', 'Sirrus', 'Turbo Vado', 'Turbo Levo', 'Riprock', 'Hotrock'],
    Giant: ['Talon', 'ATX', 'Fathom', 'XTC', 'Trance', 'Reign', 'Anthem', 'Contend', 'TCR', 'Defy', 'Propel', 'Revolt', 'Escape', 'Roam', 'FastRoad', 'Talon E+', 'Explore E+'],
    Scott: ['Aspect', 'Scale', 'Spark', 'Genius', 'Ransom', 'Addict', 'Foil', 'Speedster', 'Speedster Gravel', 'Sub Cross', 'Strike eRIDE', 'Roxter'],
    Cannondale: ['Trail', 'Trail SE', 'F-Si', 'Scalpel', 'Habit', 'Jekyll', 'CAAD Optimo', 'CAAD13', 'SuperSix EVO', 'Synapse', 'Topstone', 'Quick', 'Treadwell', 'Moterra'],
    Merida: ['Big.Nine', 'Big.Seven', 'One-Twenty', 'One-Forty', 'Ninety-Six', 'Scultura', 'Reacto', 'Silex', 'Crossway', 'eOne-Sixty'],
    Oxford: ['Merak 1', 'Merak 2', 'Orion 3', 'Orion 4', 'Venus', 'Hurricane', 'Vulcano', 'Luna', 'Pulse', 'Cosmo', 'Mercurio', 'Spirit', 'Aro 20 infantil', 'Aro 16 infantil'],
    Bianchi: ['Magma', 'Methanol', 'Nitron', 'Via Nirone 7', 'Sprint', 'Oltre', 'Infinito', 'Specialissima', 'Impulso', 'C-Sport'],
    Trinx: ['M100', 'M116', 'M136', 'M500', 'M1000', 'X1', 'Climber', 'Tempo', 'Free'],
    Orbea: ['MX', 'Onna', 'Alma', 'Oiz', 'Occam', 'Rallon', 'Orca', 'Avant', 'Terra', 'Vector', 'Rise', 'Wild'],
    Cube: ['Aim', 'Attention', 'Analog', 'Reaction', 'Stereo', 'AMS', 'Attain', 'Agree', 'Nuroad', 'Nature', 'Stereo Hybrid'],
    Polygon: ['Cascade', 'Xtrada', 'Syncline', 'Siskiu', 'Strattos', 'Path'],
    GT: ['Aggressor', 'Avalanche', 'Zaskar', 'Force', 'Grade', 'Performer', 'Mach One'],
    'Santa Cruz': ['Chameleon', 'Tallboy', 'Hightower', 'Bronson', '5010', 'Megatower', 'Nomad', 'Blur', 'Heckler'],
    BMC: ['Twostroke', 'Fourstroke', 'Teamelite', 'Roadmachine', 'Teammachine', 'URS'],
    Bergamont: ['Revox', 'Trailster', 'Contrail', 'Grandurance', 'Sweep'],
    Mongoose: ['Legion', 'Switchback', 'Tyax', 'Dolomite'],
    Haro: ['Downtown', 'Leucadia', 'Flightline', 'Double Peak'],
    Lahsen: ['Aro 29', 'Aro 27.5', 'Aro 26', 'Urbana', 'Infantil'],
    Bimex: ['Aro 29', 'Aro 26', 'Paseo', 'Infantil'],
    Brompton: ['C Line', 'P Line', 'T Line', 'Electric'],
    Xiaomi: ['Scooter / bici eléctrica'],
    Otra: ['Aro 29', 'Aro 27.5', 'Aro 26', 'Aro 700c (ruta)', 'Urbana', 'Plegable', 'BMX', 'Eléctrica', 'Infantil', 'Tándem', 'Fixie']
  };
  const BICIS = [];
  Object.keys(M).forEach((m) => M[m].forEach((x) => BICIS.push(m === 'Otra' ? x : m + ' ' + x)));
  Object.keys(M).forEach((m) => { if (m !== 'Otra') BICIS.push(m); });

  const REPUESTOS = [
    ['Cámara aro 29', 6000], ['Cámara aro 27.5', 6000], ['Cámara aro 26', 5000], ['Cámara 700c (ruta)', 6000], ['Cámara aro 20', 4500],
    ['Neumático MTB aro 29', 25000], ['Neumático MTB aro 27.5', 24000], ['Neumático ruta 700c', 28000], ['Neumático urbano', 15000],
    ['Cadena 8 velocidades', 12000], ['Cadena 9 velocidades', 15000], ['Cadena 10 velocidades', 20000], ['Cadena 11 velocidades', 25000], ['Cadena 12 velocidades', 35000],
    ['Cassette / piñón', 35000], ['Plato / bielas', 40000], ['Pata de cambio', 12000], ['Cambio trasero', 40000], ['Cambio delantero', 25000], ['Mando de cambio', 25000],
    ['Pastillas de freno (par)', 9000], ['Disco de freno', 18000], ['Zapatas V-brake (par)', 5000], ['Líquido de frenos', 6000],
    ['Cable de freno', 3000], ['Cable de cambio', 3000], ['Funda (metro)', 2500],
    ['Rodamiento de dirección', 15000], ['Eje de pedalier', 25000], ['Rodamientos de maza', 12000], ['Rayo', 1000],
    ['Líquido tubeless', 8000], ['Cinta tubeless', 6000], ['Válvula tubeless (par)', 7000],
    ['Pedales', 15000], ['Puños', 8000], ['Sillín', 20000], ['Cinta de manubrio', 12000], ['Luz delantera', 12000], ['Luz trasera', 8000], ['Grasa / lubricante', 5000]
  ];
  const NOTAS = ['Frena poco', 'El cambio salta', 'Pinchazo', 'Ruido raro', 'Mantención general', 'Rueda descentrada', 'Se sale la cadena', 'Suspensión dura', 'Dirección suelta', 'Bici nueva para armar'];

  const lista = (id, valores) => {
    if (document.getElementById(id)) return id;
    const d = document.createElement('datalist'); d.id = id;
    d.innerHTML = valores.map((v) => '<option value="' + String(v).replace(/[&"<>]/g, (c) => ({ '&': '&amp;', '"': '&quot;', '<': '&lt;', '>': '&gt;' })[c]) + '">').join('');
    document.body.appendChild(d); return id;
  };
  // G59e 🏷️ Informe de inspección de 50 puntos de la bici usada certificada (10 grupos × 5). Las claves no se cambian: quedan guardadas.
  const INFORME = [
    ['🚲 Cuadro y horquilla', [['cu1', 'Cuadro sin fisuras ni golpes'], ['cu2', 'Horquilla derecha'], ['cu3', 'Uniones y soldaduras'], ['cu4', 'Pintura'], ['cu5', 'Nº de serie visible']]],
    ['🧭 Dirección', [['di1', 'Juego de dirección'], ['di2', 'Manubrio'], ['di3', 'Potencia'], ['di4', 'Puños'], ['di5', 'Alineación']]],
    ['🛑 Frenos', [['fr1', 'Manillas'], ['fr2', 'Pastillas o zapatas'], ['fr3', 'Discos o llantas de freno'], ['fr4', 'Cables o hidráulico'], ['fr5', 'Frenado parejo']]],
    ['⛓️ Transmisión', [['tr1', 'Desgaste de la cadena'], ['tr2', 'Cassette o piñones'], ['tr3', 'Platos'], ['tr4', 'Desviador trasero'], ['tr5', 'Desviador delantero']]],
    ['🔀 Cambios', [['ca1', 'Mandos de cambio'], ['ca2', 'Cables y fundas'], ['ca3', 'Ajuste de cambios'], ['ca4', 'Pata de cambio derecha'], ['ca5', 'Entran todas las marchas']]],
    ['🛞 Ruedas', [['ru1', 'Rueda delantera centrada'], ['ru2', 'Rueda trasera centrada'], ['ru3', 'Rayos tensos'], ['ru4', 'Mazas sin juego'], ['ru5', 'Ejes y cierres']]],
    ['⚫ Neumáticos', [['ne1', 'Neumático delantero'], ['ne2', 'Neumático trasero'], ['ne3', 'Válvulas'], ['ne4', 'Cámaras o tubeless'], ['ne5', 'Presión']]],
    ['⚙️ Pedalier y bielas', [['pe1', 'Pedalier sin juego'], ['pe2', 'Bielas'], ['pe3', 'Pedales'], ['pe4', 'Rodamientos'], ['pe5', 'Sin ruidos al pedalear']]],
    ['🪑 Suspensión y asiento', [['su1', 'Suspensión delantera'], ['su2', 'Suspensión trasera'], ['su3', 'Tija'], ['su4', 'Sillín'], ['su5', 'Abrazadera']]],
    ['🏁 Prueba final', [['pf1', 'Prueba en ruta'], ['pf2', 'Sin ruidos'], ['pf3', 'Luces, timbre y reflectantes'], ['pf4', 'Limpieza'], ['pf5', 'Pernos al torque']]]
  ];
  const INF_EST = { ok: ['✅', 'Bien'], ajuste: ['🔧', 'Ajustado'], cambio: ['🔁', 'Cambiado'] };
  window.CFX_FABRICA = {
    BICIS, REPUESTOS, NOTAS, INFORME, INF_EST,
    // 🚲 Campo de bici: marca y modelo para elegir (o escribir otra).
    bici(inp) { if (inp) { inp.setAttribute('list', lista('fabBicis', BICIS)); inp.setAttribute('autocomplete', 'off'); } },
    // 📦 Nombre de repuesto: lista para elegir.
    repuestos(inp) { if (inp) { inp.setAttribute('list', lista('fabRep', REPUESTOS.map((r) => r[0]))); inp.setAttribute('autocomplete', 'off'); } },
    precio(nombre) { const r = REPUESTOS.find((x) => x[0].toLowerCase() === String(nombre || '').trim().toLowerCase()); return r ? r[1] : null; },
    // 📝 Notas de un toque debajo del campo: suman la frase (separada por coma).
    notas(campo) {
      if (!campo || campo.nextElementSibling && campo.nextElementSibling.classList.contains('fab-notas')) return;
      const w = document.createElement('div'); w.className = 'fab-notas';
      w.innerHTML = NOTAS.map((n) => '<button type="button" class="chip" data-sin-atras>' + n + '</button>').join('');
      w.onclick = (e) => {
        const b = e.target.closest('button'); if (!b) return;
        const v = campo.value.trim();
        if (v.toLowerCase().includes(b.textContent.toLowerCase())) return;
        campo.value = (v ? v.replace(/[.,\s]+$/, '') + ', ' : '') + b.textContent;
        campo.dispatchEvent(new Event('input', { bubbles: true }));
      };
      campo.after(w);
    }
  };
  const st = document.createElement('style');
  st.textContent = '.fab-notas{display:flex;flex-wrap:nowrap;overflow-x:auto;gap:6px;margin:6px 0 4px;padding-bottom:4px;scrollbar-width:none;max-width:100%}.fab-notas::-webkit-scrollbar{display:none}.fab-notas .chip{flex:0 0 auto;width:auto;white-space:nowrap;font-size:.8rem;padding:5px 10px;border-radius:999px;min-height:0;' +
    'background:var(--cfx-tarjeta,transparent);color:var(--cfx-texto,inherit);border:1px solid var(--cfx-borde,rgba(127,127,127,.35));box-shadow:none;font-weight:500}';
  document.head.appendChild(st);
})();
