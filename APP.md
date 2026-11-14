# APP.md

(Mapa completo pendiente: G42j.)

## 🧠 Del núcleo: falta aplicar aquí
- G37 (núcleo 2.76): 🧾 comprobante.js + 🖨️ impresora.js son del núcleo (OPCIONAL). Aplicar: sumar "taller" a OPCIONAL en sincronizar.py + <script> + FILES de sw.js; definir window.CFX_COMPROBANTE_DATOS = async (c) => ({ logo, firma }) y abrir CFX_COMPROBANTE.abrir({...}) en orden de trabajo entregada. 🧾 Boleta SII: hoy solo Despega (SQL boleta_*); si esta app la necesita, pasarla primero a nucleo/sql/boleta.sql. · 🔑 Entrar con QR: la función ya atiende qr_entrar (servidor 2.0); falta en la app: <script qr.js> + #lQR en el ingreso (como CM/Barbería) + ?qr=.
- G42 (núcleo 2.75, ya activo solo): ⬆️ subir, 🪟 ventanas del núcleo (✕+Cerrar / ← Volver), 📌 títulos fijos y ✋ ordenar en CFX_AJUSTES/CFX_MENU. Falta aquí: ✋ marcar otras listas propias con data-cfx-orden si sirve; 🪟 revisar ventanas propias (dialog) que no usan la hoja del núcleo; 🔐 usar CFX_TAPAR en avisos de enlace/validación y CFX_URL en links que pone el negocio (boleta, pago).
- G43: su lista "Para empezar" (#bienvenida, marcada data-cfx-guia-propia) aún lleva al menú → que cada fila use CFX_AYUDA.ir({ ir, campo }) + ✕ / "No mostrar más" (CFX_AYUDA.guiaEstado/guiaOcultar), como Despega. Su ventana propia "Activa las notificaciones" sale aunque estén bloqueadas → dejar solo la del núcleo (instalar.js).
