# APP.md

(Mapa completo pendiente: G42j.)

- G95 (3.11 · bd 2.51): el taller parte FREE (premium_hasta null; dias_regalo_taller ya no se usa) · registro_info.prueba · 🎁 Probar Premium en la hoja de pago (núcleo) · talleres de antes anotados 1 vez (cfx_config g95_pruebas). Prueba: SaaS/pruebas/g95.js.

## 🧠 Del núcleo: falta aplicar aquí
- G42e (núcleo 2.78): utilidades Bootstrap 5.3.8 ya usan los colores CodeFix (--bs-* → --cfx-*). Al revisar esta app: si quiere Bootstrap, enlazar vendor/bootstrap-utilities.min.css ANTES de su CSS (nunca el Bootstrap completo: choca con .btn/.card/.modal/.row/.toast).
- G48 (núcleo 2.77): revisar en el celular ✋ mover secciones desde el título y 🎨 Color y modo → Colores a tu gusto (fondo, texto, íconos y +); si la app pinta íconos o fondo con colores fijos, pasarlos a var(--cfx-icono)/var(--cfx-fondo).
- G37 (núcleo 2.76): 🧾 comprobante.js + 🖨️ impresora.js son del núcleo (OPCIONAL). Aplicar: sumar "taller" a OPCIONAL en sincronizar.py + <script> + FILES de sw.js; definir window.CFX_COMPROBANTE_DATOS = async (c) => ({ logo, firma }) y abrir CFX_COMPROBANTE.abrir({...}) en orden de trabajo entregada. 🧾 Boleta SII: hoy solo Despega (SQL boleta_*); si esta app la necesita, pasarla primero a nucleo/sql/boleta.sql. · 🔑 Entrar con QR: la función ya atiende qr_entrar (servidor 2.0); falta en la app: <script qr.js> + #lQR en el ingreso (como CM/Barbería) + ?qr=.
- G42 (núcleo 2.75, ya activo solo): ⬆️ subir, 🪟 ventanas del núcleo (✕+Cerrar / ← Volver), 📌 títulos fijos y ✋ ordenar en CFX_AJUSTES/CFX_MENU. Falta aquí: ✋ marcar otras listas propias con data-cfx-orden si sirve; 🪟 revisar ventanas propias (dialog) que no usan la hoja del núcleo; 🔐 usar CFX_TAPAR en avisos de enlace/validación y CFX_URL en links que pone el negocio (boleta, pago).
- G43: su lista "Para empezar" (#bienvenida, marcada data-cfx-guia-propia) aún lleva al menú → que cada fila use CFX_AYUDA.ir({ ir, campo }) + ✕ / "No mostrar más" (CFX_AYUDA.guiaEstado/guiaOcultar), como Despega. Su ventana propia "Activa las notificaciones" sale aunque estén bloqueadas → dejar solo la del núcleo (instalar.js).

## 🚲 G59 · Taller FREE (2.85, bd 2.28) — prueba SaaS/pruebas/g59_taller.js
- 🚦 Tablero del taller: Hoy → tarjeta "Tablero del taller" (#hTablero, pintarTablero en taller.js). Columnas = EN_TALLER (Recibida, En reparación, Esperando repuesto, Lista). ‹ › llaman taller_estado (avisa al cliente); en Lista: 🎉 Entregar (pide confirmar). Botones con data-sin-atras (si no, el "‹" del núcleo hace history.back). Tocar la tarjeta abre la orden.
- 📸 Fotos de llegada y entrega: GRATIS (taller_foto_subir ya no mira limites.fotos). En la base siguen siendo tipo 'antes'/'despues'; en pantalla dicen Llegada/Entrega (taller y /r/).
- 🧾 Checklist de revisión: reservas.checklist jsonb { frenos|cambios|ruedas|neumaticos|cadena|pedalier|direccion|suspension|cuadro|luces: ok|ajuste|cambio }. RPC taller_checklist(p_id, p_check). En la orden: card "Revisión de la bici" (#dCheck, toque = ⬜→✅→🔧→🔁→⬜, guarda al tiro). El cliente la ve en /r/ (#cCheck) vía reserva_ver.checklist. taller_reservas trae checklist y mecanico (nombre).

## 🧩 G59b · Módulos (2.86, bd 2.29) — prueba SaaS/pruebas/g59b_presupuesto.js
- Ganchos del núcleo (schema.sql, después de taller_checklist): cfx_negocio_de_cuenta(u) = owner_id del taller · cfx_es_premium(n) = taller_es_premium · cfx_modulos_app() = ['presupuesto'] (sumar aquí los próximos; catálogo + demo en SaaS/nucleo: sql/modulos_venta.sql y modulos.js). NO vienen en Premium (G39). Packs del núcleo se vacían (al final de schema.sql, solo si siguen los de fábrica).
- taller_tiene(clave) en la base · taller_panel trae modulos (cfx_modulos()) y venta → JS tiene(k) / ofrecer(k) (demo ▶️ + Comprar; equipo: "pídele al dueño"). Más → 🧩 Módulos (data-m=modulos, solo dueño y con la venta prendida) = CFX_MODULOS_TIENDA.montar.
- ✅ Presupuesto por link: reservas.presupuesto {estado enviado|respondido, enviado_at, respondido_at} + items[i].aprob pend|si|no. taller_presupuesto(id) (marca ⏳ lo no respondido, avisa al cliente) · reserva_presupuesto(token, {"0":"si","1":"no"}) (anon, responde todos, avisa al taller). Total sin lo rechazado (taller_trabajo y JS). Editar un ítem le borra aprob. Taller: #dPres en la orden (✅ Pedir aprobación + 📲 WhatsApp); cliente: #cPres en /r/.
- Siguiente: ⭐ reseñas Google (✅ plan mensual, aviso lista, recordatorio, stock, certificadas+trade-in, pasaporte, domicilio, garantías). (Fotos del daño por ítem: pendiente, hoy usa 📸 Llegada.)

## 🏭 G65 · De fábrica (2.87, bd 2.30) — prueba SaaS/pruebas/g65_fabrica.js
- SQL (final de schema.sql): taller_fabrica_agregar(tid) (lista de 23; agrega lo que falta por nombre hasta el límite) · trigger talleres_fabrica (taller nuevo) · RPC taller_servicios_fabrica() (solo dueño; botón ✨ en Más → Servicios) · FREE servicios 40.
- shared/fabrica.js (propio, en FILES de sw.js; lo cargan taller/ y t/): CFX_FABRICA.bici(input) → datalist fabBicis · repuestos(input) → fabRep + precio(nombre) (la orden pone el precio si estaba en 0) · notas(campo) → fila .fab-notas (botones data-sin-atras). Para sumar marcas/repuestos/notas: editar ese archivo.

## 🔔⏰ G59c · Módulos aviso lista y mantención (2.88, bd 2.31 · núcleo 2.85) — prueba SaaS/pruebas/g59c_modulos.js
- cfx_modulos_app() = ['presupuesto', 'aviso_lista', 'mantencion', 'stock'].
- 🔔 aviso_lista: reservas.lista_at + lista_recordada (taller_estado los arma al pasar a Lista). JS avisoLista(r): al pasar a Lista (tablero › o botón de la orden) ventana con 📲 WhatsApp (total + link /r/). Tablero: "⏳ Lista hace N días". Sin módulo: aviso en la orden con data-ofrecer (listener global → ofrecer). tareas_periodicas 3b: a los 2 días avisa al cliente (con cuenta) y al taller, 1 vez. El push de cada estado al cliente sigue GRATIS.
- ⏰ mantencion: taller_recordatorios = Premium (como antes) O módulo; tareas_periodicas 3: cliente Premium O taller con módulo (cfx_modulo_de('mantencion', owner_id)). bloqueadoPremium(t, d, mod) muestra "🧩 O activa solo esta función". Km: NO (no hay de dónde sacar los km; va por meses de Configuración).

## 📦🛒 G59d · Módulo Repuestos y stock + pedido a proveedor (2.89, bd 2.32) — prueba SaaS/pruebas/g59d_stock.js
- Tablas repuestos (nombre único por taller, precio, stock, minimo, proveedor_id) y proveedores (nombre, telefono, email, nota). reservas.stock_at = ya descontó.
- RPC: taller_stock() ({bloqueado} sin módulo) · taller_repuesto_guardar/borrar, taller_proveedor_guardar/borrar, taller_repuestos_fabrica(lista de fabrica.js) = solo dueño · taller_stock_sumar({id: n}) = todo el equipo (➖➕ y 📥 Llegó).
- Al entregar (taller_estado → completada) taller_stock_descontar: baja por NOMBRE igual al ítem (sin los rechazados), una sola vez; si cruza el mínimo → push al taller "📦 Se está acabando" (/taller/#mas/stock).
- Pantalla: Más → 📦 Repuestos (verStock; equipo solo si el taller lo tiene) · 🛒 Armar pedido (stock ≤ mínimo, agrupado por proveedor, pide mínimo×2 − stock; 📲 WhatsApp / ✉️ correo / 📋 copiar; 📥 Llegó suma) · Hoy #hStock "N repuestos por pedir" (panel.stock_bajo) · Orden: datalist stRep (mis repuestos + fábrica), precio del stock y "📦 Quedan N en stock".
- Ojo: dentro de las hojas de Más usar body().querySelector (puede quedar otra hoja con el mismo id).

## 🏷️🔄 G59e · Módulos Bicis usadas certificadas + Parte de pago (2.90, bd 2.33 · núcleo 2.86) — prueba SaaS/pruebas/g59e_usadas.js
- cfx_modulos_app() suma 'certificadas', 'tradein'. Catálogo + demo en el núcleo.
- Tabla bicis_usadas (titulo, talla, anio, precio, garantia meses, nota, informe {clave: ok|ajuste|cambio}, fotos jsonb ≤4 dataURL ≤160000, mini ≤60000, estado borrador|publicada|vendida, token).
- Los 50 puntos: CFX_FABRICA.INFORME en shared/fabrica.js (10 grupos × 5; las claves NO se cambian) + INF_EST (✅🔧🔁).
- RPC: taller_usadas() ({bloqueado} sin módulo) · taller_usada(id) con fotos · taller_usada_guardar(p) = todo el equipo (publicar exige 50 revisados + 1 foto + precio) · taller_usada_borrar = solo dueño · públicas (anon): usadas_publicas(slug) y usada_ver(token) (solo si el taller tiene el módulo; plpgsql porque cfx_modulo_de está más abajo).
- Pantalla: Más → 🏷️ Bicis usadas (verUsadas/editarUsada: fotos, informe tocando ⬜→✅→🔧→🔁, ✅ Todo bien en lo que falta, 📣 Publicar, ✅ Se vendió, 📲 Compartir). /t/ muestra #usadas; ficha pública nueva u/?t=token (📲 Me interesa / 💬 Hacer una oferta por WhatsApp al taller). u/ en FILES de sw.js.
- 🔄 Más → Parte de pago (verTradein, solo pantalla): venta = nueva × máx(0,75·0,88^años; 0,2) × estado (1/0,85/0,7/0,5), oferta = venta × (1 − ganancia%) − arreglos, redondeo a $5.000; margen en localStorage. 🏷️ Pasar a usadas = borrador con modelo/año/precio.
- Error visto: inputs con onchange repintaban el resultado al salir del campo y se perdía el toque del botón → solo oninput (categoría UI).

## 🪪 G59f · Módulo Pasaporte de la bici (2.91, bd 2.34 · núcleo 2.87) — prueba SaaS/pruebas/g59f_pasaporte.js
- cfx_modulos_app() suma 'pasaporte'. Catálogo + demo en el núcleo.
- Tabla pasaportes (bici, serie única por taller, color, dueño, teléfono/tel_norm, robada/robada_at/robada_nota, token = QR público, clave = del dueño). reservas.pasaporte_id (sin FK) = historial; trigger zz_pasaporte_enlazar enlaza solas las órdenes nuevas del mismo teléfono + bici.
- RPC: taller_pasaportes() ({bloqueado} sin módulo) · taller_pasaporte(id) con historial (lista/completada, sin ítems rechazados) · taller_pasaporte_guardar(p) = todo el equipo (p.reserva enlaza la orden + las de ese teléfono y bici) · taller_pasaporte_borrar = solo dueño · públicas: pasaporte_ver(token, clave) (serie tapada salvo 4 últimos; con clave = es_dueno) y pasaporte_reportar(token, clave, robada, nota) → avisa al dueño del taller.
- Pantalla: Más → 🪪 Pasaporte de la bici (lista, 🚨 robadas primero, buscar) y orden → 🪪 Pasaporte (crea con bici/dueño/teléfono de la orden). En el pasaporte: 🚨 Reportar robo / ✅ La recuperó, 🖨️ Sticker QR (2 de 5 cm), 📲 Enviar al dueño (link con clave), 👀 Ver ficha.
- Público: p/?t=token (&c=clave del dueño: 🚨 Me la robaron / ✅ La recuperé). r/ muestra "🪪 Ver mi pasaporte" con la clave. p/ en FILES de sw.js.
- 📍 G86 Rastreo (3.03, bd 2.43 — prueba SaaS/pruebas/g86.js): pasaportes.silencio + rastro_aviso_at · tabla pasaporte_rastros (sesion hex, lat/lng/prec; RLS sin políticas, sin permisos; 30 días) · pública pasaporte_rastro(token, sesion, lat, lng, prec) (siempre {ok}; solo guarda si robada; frenos 4 s / 900 puntos-h / 30 teléfonos-h) · pasaporte_rastros_json (60 últimos) va en taller_pasaporte y en pasaporte_ver SOLO con clave · pasaporte_avisar = taller + cliente con cuenta + admin · pasaporte_reportar suma p_silencio (default true; se hace drop de la firma vieja) · taller_pasaporte_guardar lee p.silencio.
- Pantallas G86: p/ → #cUbi (quien escanea: watchPosition, sesión en sessionStorage 'bt-ras'), #cSil (casilla del dueño), #cRas (dueño: App.rastros, refresco 15 s) · taller: pasaporte → "📍 Dónde está" (#paRas, refresco 15 s) y 🚨 Reportar robo = cuadro con #rbN + casilla #rbS. App.rastros(L) en shared/app.js (mapa OSM iframe + link Google Maps).

## 🚐 G59g · Módulo Mecánico a domicilio (2.92, bd 2.35 · núcleo 2.88) — prueba SaaS/pruebas/g59g_domicilio.js
- cfx_modulos_app() suma 'domicilio'. Catálogo + demo en el núcleo.
- talleres.domicilio { activo, recargo, zona } (solo dueño: taller_domicilio_config) · reservas.domicilio { direccion, comuna, ref, orden, camino_at }.
- domicilio_aplicar pone/saca el ítem "🚐 Visita a domicilio" (recargo) una sola vez y ajusta total/precio. taller_domicilio(id, p): p sin "recargo" = deja el que tenía; p null = ya no es a domicilio.
- Públicas: domicilio_info(taller) (null si no tiene módulo o no está prendido) · reserva_domicilio(token, p) (por_pagar/en_revision/confirmada; avisa al taller la 1ª vez). /t/ #fDom "🏠 Que vengan a mi casa (+$X)" → después de reservar llama reserva_domicilio. /r/ #cDom + "🚐 ¡Vamos en camino!".
- Taller: Más → 🚐 A domicilio (verDomicilio): Ruta del día Hoy/Mañana (taller_ruta), ▲▼ (taller_ruta_orden), 🗺️ Cómo llegar / Abrir la ruta en Google Maps (origen = dirección del taller, waypoints), 🚐 Voy en camino (WhatsApp + taller_en_camino → push al cliente con cuenta), ⚙️ configuración. Orden: #dDom (editarDomicilio) + #dDomTxt. Hoy: #hDom "N visitas a domicilio hoy".
- Error visto: al volver a guardar la dirección se borraba el recargo (el JS mandaba recargo:false) → sin "recargo" queda el que tenía (categoría DATOS).

## 🛡️ G59h · Módulo Garantías (2.93, bd 2.36 · núcleo 2.89) — prueba SaaS/pruebas/g59h_garantias.js
- cfx_modulos_app() suma 'garantias'. Catálogo + demo en el núcleo. Ícono 🛡️ (🛠️ = Servicios).
- Tabla garantias (reserva_id única o usada_id, cliente_id, nombre, telefono, bici, cubre trabajo|repuestos|todo|bici, detalle, meses 1-36, desde, hasta, token, reclamo ''|abierto|resuelto|rechazado, reclamo_nota/at, respuesta, resuelto_at).
- RPC: taller_garantias() ({bloqueado} sin módulo; reclamos abiertos primero, luego por vencimiento) · taller_garantia(id, reserva) · taller_garantia_guardar(p) = todo el equipo (con reserva: solo lista/completada; si ya tiene, la edita) · taller_garantia_resolver(id, resuelto|rechazado, texto) → push al cliente con cuenta · taller_garantia_borrar = solo dueño · públicas: garantia_ver(token) y garantia_reclamar(token, nota) (vigente y sin otro abierto → avisar_taller). reserva_ver.garantia · taller_panel.garantia_reclamos.
- Pantalla: orden lista/entregada → 🛡️ Garantía (editarGarantia) · Más → 🛡️ Garantías (verGarantias: 🔔 La usaron · ⏳ Por vencer ≤15 días + 📲 Avisar · ✅ Vigentes · ⌛ Vencidas) · Hoy #hGar · 🏷️ usada ✅ Se vendió → ofrece la garantía al comprador (cubre bici, meses de la usada).
- Público: g/?t=token (VIGENTE/VENCIÓ, 🛡️ Usar mi garantía con CFX_DIALOGO.pedir, respuesta del taller). r/ #cGar enlaza. g/ en FILES de sw.js.

## 🔁 G59i · Módulo Plan de mantención (2.94, bd 2.37 · núcleo 2.90) — prueba SaaS/pruebas/g59i_planes.js
- cfx_modulos_app() suma 'plan_mant' (no 'membresia': esa clave/demo es de Barbería). Catálogo + demo en el núcleo.
- Tablas planes_mant (nombre, precio/mes, visitas 1-10, descuento 0-50, incluye, activo; máx. 10) · plan_socios (plan, nombre, telefono/tel_norm único activo, bici, hasta, activa, cliente_id por la última orden con cuenta) · plan_cobros (meses, monto, medio) · plan_usos (reserva_id única). reservas.plan_desc.
- orden_total(items, %) = suma sin rechazados − floor(suma·%/100): la usan taller_trabajo, reserva_presupuesto y domicilio_aplicar (JS totalItems y /r/ presTot igual).
- RPC: taller_planes() ({bloqueado}; equipo sin precios ni cobrado_mes) · taller_plan_guardar/borrar, taller_socio_guardar (meses = cobrar)/borrar = solo dueño · taller_plan_orden(reserva) · taller_plan_usar(reserva, bool) = todo el equipo (vigente y con visitas; orden abierta) · pública planes_publicos(taller). reserva_ver.plan + plan_desc · taller_panel.planes_vencen.
- Pantalla: Más → 🔁 Planes de mantención (verPlanes, editarPlanMant, editarSocio) · orden #dPlan (pintarPlan) · Hoy #hPlanes · /r/ #cPlan · /t/ #planes.

## 🧾 G74a · Orden rápida, presupuesto y 💵 Caja (2.96, bd 2.38, FREE) — prueba SaaS/pruebas/g74a_caja.js
- Hoy #cAcc: ＋ Nueva orden (#hOrden) · 🧾 Presupuesto (#hPres) · 💵 Caja (data-m=caja). ordenNueva(pres) → taller_orden_nueva(nombre, tel, bici, nota, pres) = reserva origen 'taller', estado 'recibida', sin abono, hora = ahora (no ocupa agenda), servicio_nombre 'Orden de trabajo'|'Presupuesto' → abre la orden.
- Orden: sin módulo presupuesto → #dPresWa "📲 Enviar presupuesto" (WhatsApp con ítems y total, gratis) · lista → #dCobrar 💵 Cobrar y entregar · recibida/en reparación sin abono → ❌ Anular (cancelada).
- Tabla caja (taller, fecha, medio efectivo|transferencia|tarjeta, total, items, nombre, reserva_id único, stock). RPC: taller_caja_vender(items, medio, nombre) (baja stock si tiene 📦) · taller_caja_cobrar(reserva, medio) (a pagar = total − abono; lista → completada; no cobra 2 veces) · taller_caja(fecha) {cobros, medios, por_cobrar (lista o entregadas ≤3 días sin cobro)} · taller_caja_anular(id) (solo dueño; devuelve stock).
- Pantalla: Más → 💵 Caja (verCaja, ventaMostrador, elegirMedio, cobrarOrden; constante CAJA_M porque MEDIOS ya existe).
- G32 e (3.26): elegirMedio(titulo, fn, monto) suma "📲 Tarjeta (celular)" (data-medio=tap) → núcleo shared/tap.js a pedido (cargarTap) → aprobado = medio 'tarjeta'. Prueba: SaaS/pruebas/g32e.js.

## ⭐ G74c · Módulo Reseñas en Google (2.99, bd 2.40 · núcleo 2.94) — prueba SaaS/pruebas/g74c_resenas.js
- cfx_modulos_app() suma 'resenas' (misma clave, catálogo y demo que Barbería; la demo ahora dice "calificó su atención").
- talleres.google_resenas (https://, ≤300) · RPC taller_google_guardar(p_link) = solo dueño (se puede guardar sin módulo, pero solo se usa con él).
- reserva_calificar devuelve { ok, google }: google = link solo si 4-5 ★ y cfx_modulo_de('resenas', owner_id).
- Pantalla: Más → 🏪 Perfil → card #pGoo (#pGLink + #pGGuardar; sin módulo: data-ofrecer="resenas") · orden completada con teléfono → #dGoo ⭐ Pedir reseña (WhatsApp con el link) · /r/ pedirGoogle(link): ventana con #bGoogle.

## 🚲 G91 · BLOQUE BICITALLER (3.07, bd 2.47) — pruebas SaaS/pruebas/g91a…h_*.js (ANCHO=320)
- 📸 a) Foto del daño por ítem: fotos_trabajo.tipo 'dano' (máx. 12 por orden) · items[i].foto = id · taller_trabajo borra la foto del ítem que ya no está · reserva_fotos devuelve id. Taller: "📷 Foto del daño" en cada ítem (#dItems [data-fi]); /r/: foto dentro del presupuesto (img.fdi[data-foto]) y en la galería como "🔍 Daño".
- 🧑‍🔧 b) Carga por mecánico: Hoy → Tablero → #hMecs (Todos · cada mecánico · Sin asignar, con cuántas bicis) filtra el tablero; se recuerda en localStorage 'bt-mec'. Solo pantalla.
- 📍 c) Rastreo v2 (G87 B): pasaportes.cliente_id · cliente_bicis() / cliente_bici_guardar(p) (app del cliente → 🚲 Mis bicis, GRATIS, máx. 5, con 🖨️ QR) · pasaporte_ver: historial SOLO dueño con clave + módulo; 'rastrear' = robada (sin reporte el QR NO pide ubicación) · reportar y rastrear YA NO dependen del módulo (seguridad siempre) · mapa = Leaflet + OSM (shared/vendor/leaflet.js/.css, copiados de Estaciona; App.mapas(raíz) dibuja los .bt-mapa de App.rastros: recorrido, último punto, precisión).
- 🗓️ d) Agenda (G87 F): talleres.horarios[dow] acepta bloque (15…240), cupos (1-20), max (0-200) → horas_libres los usa; taller_guardar los valida. Más → ⏰ Horario: Lunes a viernes + tarjetas Sábado y Domingo ([data-finde]) + ⛔ Días cerrados (rango ≤62 días, tabla bloqueos, ✅ Abrir).
- 📄 e) G86 extras: App.constancia(x, taller) = hoja para imprimir/PDF (bici, reporte, cada escaneo con hora y coordenadas) en el pasaporte (#paK) y en p/ (#bConst) · #paAv 📲 Avisar al dueño por WhatsApp (última ubicación + su link con clave).
- 🧾 f) Boleta en Caja: caja.boleta (folio SII, solo dígitos ≤10) · taller_caja_boleta(id, folio) (todo el equipo) · Caja → 🧾 en cada cobro ([data-bol]): N° de boleta + 🧾 Comprobante (núcleo comprobante.js a pedido; CFX_COMPROBANTE_DATOS = logo/nombre del taller). ✅ G92 (3.08 · bd 2.48): boleta del núcleo (boleta.js a pedido + boleta.sql) · gancho cfx_boleta_negocio_app (taller_de; p_dueno = es_dueno) · taller_caja_boleta_sii(p_id, p_folio) · trigger caja_boleta_auto (⚡ OpenFactura + auto) · caja.boleta_url · Más → 🧾 Boleta SII (verBoleta, ruta #mas/boleta).
- 🛒 g) Tienda (va con el módulo 📦 stock): repuestos.tienda/tipo (repuesto|accesorio|bici)/descripcion/foto (≤120000) · máx. 40 publicados · taller_repuesto_foto(id) · tienda_publica(slug) (anon, solo con módulo). ✏️ repuesto → 🛒 Mostrar en mi tienda; /t/ #tienda: tarjetas 2 columnas + carrito → 📲 Pedir por WhatsApp (#tPedir).
- 📊 h) Reportes (Premium): taller_estadisticas suma mecanicos (90 días, horas recibida→lista del historial), caja_mes, vendidos · taller_reporte(desde, hasta) (≤1 año; grant en la lista después del revoke general) → 📥 CSV para Excel (BOM, ';', anti-fórmulas).
- G96 b (3.13 · bd 2.53): 📣 Promo destacada (módulo 'promos'; Más → 📣 data-m=promoapp, ≠ 🏷️ Promociones de siempre) · gancho cfx_promo_negocios_app = perfiles.taller_id. Prueba: SaaS/pruebas/g96b.js.
- G100 a (3.16 · bd 2.56 · servidor 2.3): ⚡ abono SIN link si el taller tiene MP: link_activo (plpgsql) acepta url vacía con cfx_mp_neg_activo(owner) · link_guardar lo permite solo con MP · taller_panel.abono_ok · guía 'Cobro del abono' · /r/ sin botón de link vacío. Prueba: SaaS/pruebas/g100.js.
- G99 a (3.15 · bd 2.55 · servidor 2.2): ⚡ aviso instantáneo de Mercado Pago (núcleo): cfx_mp_aviso_url_app en cron.sql · servidor atiende ?cfx_mp=. Prueba: SaaS/pruebas/g99.js.
- G98 (3.14 · bd 2.54): ⚡ abono con el Mercado Pago del taller (núcleo mp_negocio.sql): reserva_mp_pagar/reserva_mp_revisar(token) · reserva_ver.mp · gancho cfx_mp_neg_pagado_app → confirmada / abono 'devolver' si ya venció · reserva_estado_vencido y tareas_periodicas preguntan a MP antes de liberar · r/ botón #bMp · dueño: Más → 💳 Abono (#aMp). Prueba: SaaS/pruebas/g98.js.
- G107 (3.24 · bd 2.63): 💳 abono con el Flow (Webpay) del taller: reserva_mp_pagar(token, volver, p_medio) · reserva_ver.medios · r/ botones [data-mp="mp"|"flow"] (ya no #bMp) · dueño: Más → 💳 Abono (#aMp + tarjeta Flow debajo). Prueba: SaaS/pruebas/g107.js.

- 🧩 G112 b · Packs 🌱 Básico · ⭐ Normal (clave `crecer`, destacado) · 💎 Completo, iguales en las 6; precios y módulos: SaaS/LANZAMIENTO.md (Módulos, paso 3). Solo cambian si siguen de fábrica.
- 🎬 G112 d · Estudio de contenido = 🧩 módulo 'estudio' (núcleo estudio.sql/estudio.js; ayuda.js lo carga al abrir: CFX_ESTUDIO.montar(zona, { rpc, probar, nombre })). Datos en cfx_estudio (solo el dueño por funciones). Entra en ⭐ Normal (si sigue de fábrica) y 💎 Completo. Dónde: Más → 🎬 Estudio de contenido (data-m="estudio").
- G113 (núcleo 3.21): ☰ Más en páginas que se deslizan de lado (pestañas + ⇅ ordenar/renombrar por persona), ≥ 900 px opciones en grilla pareja, 🗂️ CFX_CAJA y CFX_DIALOGO { lista } disponibles para elegir entre muchas opciones / mostrar listas.
- 📊 G118 (3.36): Más → Servicios → 📊 Cargar o actualizar muchos (núcleo CFX_RESPALDO.planilla; insert/update en servicios con RLS + limites_catalogo).
- 🖼️ G122 (3.37 · bd 2.68): fotos de bicis usadas → Storage (núcleo CFX_NUBE; taller_usada_guardar acepta la URL; la que se quita se borra). Miniatura sigue en base64. Viejas pasan solas (cfx_fotos_viejas/cfx_foto_pasar sobre bicis_usadas.fotos).
- 💬 G128 b (3.41): orden con cliente con cuenta → #dChat abre App.abrirChat(T, cliente_id). Aviso sin medios: ya estaba en Hoy → Para empezar. Prueba: SaaS/pruebas/g128b.js.
