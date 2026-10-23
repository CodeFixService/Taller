# Puesta en marcha de BiciTaller (una sola vez)

Proyecto de Supabase: `https://iwvjthcmufirbnotgixi.supabase.co` (ya está puesto en `shared/config.js`).
Administrador: `juanjosuecastilloloyola@gmail.com` (el usuario que ya creaste en Supabase).

---

## 1. Base de datos (y tareas automáticas)
1. Supabase → **SQL Editor** → **New query**.
2. Pega el contenido de [`supabase/instalar-corto.sql`](../supabase/instalar-corto.sql) (5 líneas: descarga e instala la versión
   correcta de [`supabase/instalar.sql`](../supabase/instalar.sql)) → **Run**. Debe decir "Success".
3. Para actualizar a una versión nueva: lo mismo, con el `instalar-corto.sql` nuevo. No borra datos.

> Si tu repositorio es privado, el atajo no puede descargar el archivo: en ese caso pega el `instalar.sql` completo.
>
> Tu usuario administrador queda reconocido solo. Revisa en **Authentication → Users** que tu correo
> diga "Confirmed". Si no, ábrelo y toca **Confirm email**.

## 2. Inicio de sesión (Authentication)
En **Authentication → Sign In / Providers**:
- **Email**: activado.
- **Allow new users to sign up**: **activado**. Los clientes se crean su cuenta desde la página de su taller y los
  talleres desde el link de registro (`n/`, se cierra en Ajustes → Reglas). El equipo solo lo crea el dueño del taller.
  La base de datos rechaza cualquier otra cuenta.
- **Confirm email**: recomendado **desactivado**, así el cliente entra al tiro. Si lo dejas activado, el
  cliente tendrá que confirmar su correo antes de entrar.

En **Authentication → URL Configuration** (sirve para "olvidé mi contraseña"):
- **Site URL**: la dirección donde está la app. Para probar en GitHub Pages: `https://codefixservice.github.io/Taller/`
  (después, la de Cloudflare: `https://TU-DOMINIO.pages.dev/`).
- **Redirect URLs**: agrega `https://codefixservice.github.io/Taller/**` y, cuando la tengas, `https://TU-DOMINIO.pages.dev/**`.

## 3. Tareas automáticas
Ya quedan creadas con el paso 1 (cada 5 minutos: libera horas sin pago, recordatorios, vencimientos y limpieza diaria;
cada minuto: notificaciones al celular). Si alguna vez quieres reinstalarlas solas, usa [`supabase/cron.sql`](../supabase/cron.sql).

## 4. Función "servidor" (crear cuentas y enviar notificaciones)
1. Supabase → **Edge Functions** → **Deploy a new function** → **Via Editor**.
2. Nombre: **`servidor`** (exacto, en minúscula).
3. Borra el ejemplo y pega la línea de [`supabase/functions/servidor/corto.ts`](../supabase/functions/servidor/corto.ts)
   (carga la versión correcta de `index.ts` desde GitHub) → **Deploy**. Si el repositorio es privado, pega el `index.ts` completo.
4. Deja **Verify JWT** como viene (activado).

## 5. Activar las notificaciones al celular
1. Entra a la app con tu correo de administrador.
2. **Ajustes → 🔔 Notificaciones → Crear claves**.
3. Toca **Probar función servidor**: debe decir "✅ Funciona".
4. En cada celular, la persona toca la campanita → **Activar**. En iPhone primero hay que instalar la app
   (Compartir → "Agregar a inicio") y abrirla desde ese ícono.

## 6. Precios y links (mensual, anual y promociones)
**Ajustes → 💳 Precios y links**: para el Premium de talleres y el de clientes pon el precio y el link de Mercado Pago
del **mensual** y del **anual**. Los dos se ofrecen al mismo tiempo (si un link queda vacío, ese período no se ofrece).
Cada uno tiene una **🔥 Promoción** opcional: precio promo, su link y fecha de término. Mientras esté activa se cobra
la promo y el precio normal se ve tachado; al pasar la fecha vuelve solo al normal.

El **abono** de las reservas lo configura cada taller en **Más → 💳 Abono** con su propio link:
ese dinero le llega directo al taller.

## 7. Publicar en Cloudflare Pages
1. Cloudflare → **Workers & Pages** → **Create** → pestaña **Pages** → **Connect to Git**.
2. Elige el repositorio **CodeFixService/Taller** y la rama **main**.
3. **Framework preset**: None · **Build command**: (vacío) · **Build output directory**: `/`
4. **Save and Deploy**. Te da una dirección tipo `https://bicitaller.pages.dev`.
5. Vuelve al paso 2 y pon esa dirección en **Site URL** y **Redirect URLs**.

Cada cambio que se suba a `main` se publica solo.

## 8. Primer taller
La forma fácil: **Talleres → 📣 Invita talleres** → comparte el link o imprime el **QR y afiche**. Cada taller crea su
cuenta solo y gratis (con los días de Premium de regalo) y te llega un aviso.

También puedes crearlo tú en **Talleres → ➕ Crear un taller yo mismo**: nombre del taller, dueño, correo y WhatsApp. La app arma el mensaje con su
acceso para mandárselo por WhatsApp. El taller parte con 30 días de Premium de regalo (lo cambias en
**Ajustes → Reglas**).

El taller, al entrar, ve una lista de lo que le falta: logo y colores, servicios, **link del abono**
(sin eso no recibe reservas online) y dirección. Su enlace para compartir es
`https://TU-DOMINIO/t/?s=nombre-del-taller` (también tiene QR).

---

## 9. Socios (v1.7)
**Ajustes → 👥 Socios → Crear socio**: nombre, correo y contraseña inicial (la app arma el mensaje para WhatsApp).
El socio entra con su correo al mismo panel de administración. No puede crear ni eliminar nada; cada cambio que hace
te llega como aviso con su motivo. Para crear socios la función "servidor" debe ser la versión 1.7 (paso 4).

## 10. Plan anual
**Ajustes → 💳 Precios y links** → "Premium de talleres · anual" y "Premium de clientes · anual": pon el precio
(sugerido: 10 meses) y el link de Mercado Pago. Mientras el link anual esté vacío solo se ofrece el mensual.

## Límites del plan gratis de Supabase
- Base de datos: 500 MB. El panel **Resumen → Servidor** muestra cuánto se usa (🟢 / 🟡 70% / 🔴 90%).
- Los comprobantes se achican antes de subirse (~100-300 KB) y se borran solos a los 30 días.
- Las fotos antes/después (~60-150 KB, máximo 4 por trabajo) se borran solas al año (Ajustes → Reglas).
- Cuando se acerque al límite: limpia desde el panel o pasa a Supabase Pro.

## Si algo falla
- **"No se pudo conectar con la función servidor"** → falta el paso 4 (o el nombre no es `servidor`).
- **"La base de datos es la versión X"** en el Resumen → vuelve a correr el paso 1.
- **El cliente no puede crear cuenta** → revisa el paso 2 ("Allow new users to sign up" activado) y que el
  taller no haya llegado a su límite de clientes con cuenta.
- **No llegan notificaciones al celular** → pasos 3, 4 y 5, y que la persona haya tocado "Activar".

## Versiones y actualizaciones (todo desde la app)
- Al pie de cada pantalla está **🔄 Actualizar** (para todos): descarga la última versión de la app.
- Admin: **Ajustes → 🔄 Actualizar** muestra la función, la base de datos y la app, en ese orden:
  1. **Función "servidor"** (casi nunca cambia): **📋 Copiar línea y abrir Supabase** → servidor → Code → pega → **Deploy**.
     Es el único paso a mano: Supabase no deja que una app cambie sus funciones.
  2. **Base de datos**: **🧾 Abrir el editor con la consulta** abre el SQL Editor de tu proyecto con la consulta ya pegada
     (y copiada) → **Run** → vuelve y toca **Ya la corrí: revisar**. Si la función trae la misma versión, aparece además
     **⬆️ Actualizar con un toque**. Nunca borra datos.
  3. **App**: **🔄 Actualizar app**.
- Cuando falta algo, el **Resumen** muestra un aviso que lleva directo a Ajustes → Actualizar.
- Para programadores: después de cambiar `schema.sql` o `cron.sql`, corre `node supabase/generar.mjs`.
