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
- Siguiente: aviso lista → recordatorio km/meses → repuestos+stock → certificadas+trade-in → pasaporte QR → domicilio. (Fotos del daño por ítem: pendiente, hoy usa 📸 Llegada.)

## 🏭 G65 · De fábrica (2.87, bd 2.30) — prueba SaaS/pruebas/g65_fabrica.js
- SQL (final de schema.sql): taller_fabrica_agregar(tid) (lista de 23; agrega lo que falta por nombre hasta el límite) · trigger talleres_fabrica (taller nuevo) · RPC taller_servicios_fabrica() (solo dueño; botón ✨ en Más → Servicios) · FREE servicios 40.
- shared/fabrica.js (propio, en FILES de sw.js; lo cargan taller/ y t/): CFX_FABRICA.bici(input) → datalist fabBicis · repuestos(input) → fabRep + precio(nombre) (la orden pone el precio si estaba en 0) · notas(campo) → fila .fab-notas (botones data-sin-atras). Para sumar marcas/repuestos/notas: editar ese archivo.
