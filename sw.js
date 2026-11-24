/* BiciTaller · Service worker: app instalable, funciona con mala señal y recibe notificaciones.
   Siempre intenta traer la versión nueva de internet (así nunca queda una versión vieja);
   si no hay señal, usa la copia guardada. */
const CACHE = 'bt-v2.75';
const BASE = ['./', 'index.html', 'manifest.webmanifest', 'icons/icon-192.png', 'icons/icon-512.png',
  'shared/app.css', 'shared/app.js', 'shared/filtro.js', 'shared/vendor/letras/inter.woff2', 'shared/vendor/letras/roboto.woff2', 'shared/vendor/letras/open-sans.woff2', 'shared/vendor/letras/montserrat.woff2', 'shared/vendor/letras/nunito.woff2', 'shared/ui.js', 'shared/vendor/bootstrap-utilities.min.css', 'shared/seguro.js', 'shared/vitrina.js', 'shared/datos.js', 'shared/carga.js', 'shared/ayuda.js', 'shared/est-motor.js', 'shared/est-importador.js', 'shared/est-links.js', 'shared/estudio.js', 'shared/qr.js', 'shared/comprobante.js', 'shared/tap.js', 'shared/boleta.js', 'shared/modulos.js', 'shared/premium.js', 'shared/humano.js', 'shared/verificar.js', 'shared/pagos.js', 'shared/respaldo.js', 'shared/voz.js', 'shared/fotos.js', 'shared/fabrica.js', 'shared/catalogo.js', 'shared/ingreso.js', 'shared/auto.js', 'shared/barra.js', 'shared/tema.css', 'shared/iconos.js', 'shared/instalar.js', 'shared/config.js', 'shared/vendor/supabase.js', 'shared/vendor/qrcode.js', 'shared/vendor/leaflet.js', 'shared/vendor/leaflet.css',
  'admin/', 'admin/admin.js', 'taller/', 'taller/taller.js', 'cliente/', 't/', 'r/', 'n/', 'd/', 'u/', 'p/', 'g/'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(BASE.map((u) => new Request(u, { cache: 'reload' })))).catch(() => {}).then(() => self.skipWaiting()));
});
self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((k) => Promise.all(k.filter((x) => x !== CACHE).map((x) => caches.delete(x)))).then(() => self.clients.claim()));
});
// Cloudflare redirige ".../index.html" a ".../" (p. ej. el enlace de recuperar contraseña): una respuesta con marca de redirección
// no se puede entregar a una página (Chrome muestra ERR_FAILED), así que se entrega una copia limpia.
async function limpia(res) {
  if (!res || !res.redirected) return res;
  return new Response(await res.blob(), { status: res.status, statusText: res.statusText, headers: res.headers });
}
self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET' || url.origin !== location.origin) return;
  const fresco = e.request.mode === 'navigate' ? fetch(e.request.url, { cache: 'no-cache', credentials: 'same-origin' }) : fetch(e.request, { cache: 'no-cache' });
  e.respondWith(fresco.then(limpia).then((res) => {
    if (res.ok) { const copia = res.clone(); caches.open(CACHE).then((c) => c.put(e.request, copia)); }
    return res;
  }).catch(() => caches.match(e.request, { ignoreSearch: true }).then((r) => r || caches.match('index.html')).then(limpia)));
});
// G61 a 📲 Confirma al servidor que el aviso llegó (así deja de reenviarlo). Sin red: el servidor reintenta.
function cfxAck(e, d) {
  if (!d || !d.ack || !/^https:\/\//.test(d.ackUrl || '')) return;
  e.waitUntil(fetch(d.ackUrl, { method: 'POST', headers: { 'Content-Type': 'application/json', apikey: d.ackKey || '', Authorization: 'Bearer ' + (d.ackKey || '') }, body: JSON.stringify({ p_grupo: d.ack }) }).catch(() => {}));
}
self.addEventListener('push', (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (err) { d = { title: e.data && e.data.text() }; }
  cfxAck(e, d);
  e.waitUntil(self.registration.showNotification(d.title || 'BiciTaller', {
    body: d.body || '', icon: 'icons/icon-192.png', badge: 'icons/badge.png', tag: d.tag, data: { url: d.url || '/' }, renotify: !!d.tag, vibrate: [200, 100, 200]
  }));
});
self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const url = new URL((e.notification.data && e.notification.data.url || '/').replace(/^\//, ''), self.registration.scope).href;
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((l) => {
    for (const c of l) { if (c.url.split('#')[0] === url.split('#')[0] && 'focus' in c) { c.navigate(url); return c.focus(); } }
    return self.clients.openWindow(url);
  }));
});
