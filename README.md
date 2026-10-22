# BiciTaller

App web instalable (PWA) para talleres de bicicletas que todavía no tienen sistema propio:
reservas online con abono y comprobante, agenda con bloqueos, órdenes de trabajo, clientes,
calificaciones, promociones, planes Gratis/Premium y un panel de administración general.
Servidor: **Supabase** (plan gratis). Publicación: **Cloudflare Pages**.

➡️ Configuración paso a paso: [`docs/CONFIGURAR.md`](docs/CONFIGURAR.md)

## Perfiles
| Perfil | Quién lo crea | Qué hace |
|---|---|---|
| **Administrador** | — (correo fijo) | Crea talleres, ve todo (actividad, clientes, reservas, uso del servidor), da/quita Premium y días, aprueba pagos, edita precios, links, planes, reglas y textos, envía avisos, borra calificaciones y limpia el servidor. |
| **Taller** (dueño) | El administrador, o él mismo y gratis desde el link/QR de registro (`n/`) | Perfil (logo, colores, ícono), horario, servicios, link del abono, promociones, equipo, agenda, reservas, trabajos, clientes, estadísticas y recordatorios. |
| **Equipo** (mecánico / recepción) | El dueño del taller | Agenda, revisar comprobantes, trabajar reservas y clientes. No cambia perfil, precios, links ni plan. |
| **Cliente con cuenta** | Él mismo, desde la página de su taller | Queda asociado a ese taller: sus reservas, historial de la bici, avisos y Premium. |
| **Cliente sin cuenta** | — | Reserva con nombre y WhatsApp, paga el abono y sube el comprobante desde el enlace de su reserva. |

## Registro abierto, directorio y referidos (v1.6)
- **Link y QR de registro** (`n/`): el administrador lo comparte o imprime como afiche (Talleres → 📣 Invita talleres).
  Cualquier taller crea su cuenta **gratis** con los días de Premium de regalo; los ciclistas usan el mismo link para buscar taller.
  Se abre o cierra en **Ajustes → Reglas**. Al admin le llega un aviso por cada taller nuevo (filtro "🆕 Se registraron solos").
- **Directorio** (`d/`): talleres activos con al menos un servicio, por comuna. Los Premium salen primero ("⭐ Destacado").
  El taller puede salir del directorio desde su Perfil.
- **Referidos**: cada taller tiene su link `n/?ref=<su-taller>`. Cuando el taller invitado paga su primer Premium,
  el que invitó gana 30 días de Premium (editable; 0 = sin premio).

## Reserva y abono
1. El cliente elige servicio, día y hora (respeta duración del servicio, cupos, colación y bloqueos).
2. La hora queda **retenida 30 minutos** mientras paga el abono con el link del taller.
3. Sube la foto del comprobante → la reserva queda **en revisión** y la hora sigue apartada.
4. El taller aprueba (queda **confirmada**) o rechaza (la hora se libera). Si no sube nada en 30 min, se libera sola.

**Cancelaciones**: dentro de los primeros 10 minutos → se devuelve el abono (el taller lo marca como devuelto).
Después, con 24 h o más de anticipación → queda como **saldo a favor** para reagendar (90 días, todas las veces
que cumpla los plazos). Con menos de 24 h o si no llega → pierde el abono. El abono se descuenta del total.
Todos estos tiempos los cambia el administrador en **Ajustes → Reglas**.

## Pagos
Todo por **link de pago** (Mercado Pago) + foto del comprobante, dentro de la app:
- **Premium del taller y del cliente** → al administrador (2 links por plan, uno activo; precio editable).
- **Abono de la reserva** → al taller (2 links propios, uno activo; solo el taller los ve).
- **Plan anual** (talleres y clientes): link aparte; se sugiere el precio de 10 meses y se activan 365 días.

## Gratis vs Premium (todo editable en Ajustes → Planes)
| | Taller gratis | Taller Premium |
|---|---|---|
| Reservas online al mes | 30 | 1000 |
| Servicios / promociones activas | 5 / 1 | 60 / 15 |
| Equipo con cuenta | — | 10 |
| Clientes con cuenta | 30 | 2000 |
| Estadísticas y recordatorios de mantención | — | ✅ |
| Fotos antes/después en la orden de trabajo | — | ✅ |
| Orden en el directorio | Normal | Primero (⭐ Destacado) |

| | Cliente gratis | Cliente Premium |
|---|---|---|
| Historial de la bici | Últimas 3 visitas | Completo |
| Reservar con anticipación extra | — | +15 días |
| Aviso cuando le toca mantención | — | ✅ |
| Horas exclusivas Premium del taller | — | ✅ |
| Reservar con su cuenta en cualquier taller | Solo en su taller | ✅ |
| Fotos antes/después en el historial | 7 días | Siempre |

**Horas exclusivas Premium**: el taller marca en Horario las horas que solo pueden tomar clientes Premium (los demás las ven
con 🔒). Si nadie Premium la toma, se abre a todos 24 horas antes (editable en Reglas).

Cuando vence el Premium, el taller queda en gratis: no pierde nada, pero no puede agregar más de lo que permite
el plan hasta renovar. Se avisa 3 días antes con el botón para pagar.

## Calificaciones
El cliente califica al taller y el taller al cliente (una vez por visita). Solo se muestra el **promedio de estrellas**;
los comentarios los ve el calificado y el administrador.

## Avisos
Campanita dentro de la app, en vivo, y notificación push al celular (función `servidor` + cron).
El correo queda preparado para una etapa siguiente.

## Estructura
```
index.html            Inicio de sesión
admin/                Panel del administrador
taller/               Panel del taller y su equipo
cliente/              App del cliente con cuenta
t/?s=<taller>         Página pública del taller: reservar y crear cuenta
n/                    Registro: crear la cuenta de un taller gratis (?ref=<taller> para referidos) o ir al directorio
d/                    Directorio de talleres
r/?t=<token>          Página de la reserva: pagar, comprobante, cancelar, reagendar, seguir la bici, calificar
shared/               Estilos, núcleo (sesión, campanita, push, imágenes) y librerías
supabase/schema.sql   Base de datos completa (tablas, reglas de seguridad y funciones)
supabase/cron.sql     Tareas automáticas
supabase/functions/servidor/index.ts   Crear cuentas y enviar push
```

© CodeFix · Josué Castillo.
