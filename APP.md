# APP.md

(Mapa completo pendiente: G42j.)

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
