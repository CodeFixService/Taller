// BiciTaller · Función "servidor" (Supabase → Edge Functions → nombre: servidor)
//  1) { accion: 'crear_cuenta' }  El administrador crea talleres y socios; el dueño crea a su equipo.
//  2) { accion: 'borrar' }        Administrador (o socio con motivo): borra un usuario o un taller completo.
//  3) { accion: 'actualizar_bd' } Solo el administrador: instala la base de datos que viene con esta versión de la función.
//  4) { accion: 'ping' }          Diagnóstico.
//  3) sin acción (cada minuto, pg_cron): envía por push los avisos nuevos de la campanita.
import webpush from 'npm:web-push@3.6.7';
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import postgres from 'npm:postgres@3.4.4';
import { INSTALAR, DB_VERSION } from './instalar.ts';

const VERSION = '1.9';
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (o: unknown, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

const db = () => createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
  auth: { persistSession: false, autoRefreshToken: false },
});

type Cuenta = { email?: string; password?: string; nombre?: string; telefono?: string; rol?: string; taller_nombre?: string; taller_id?: string };

async function crearCuenta(jwt: string, b: Cuenta) {
  const s = db();
  const { data: who, error: e0 } = await s.auth.getUser(jwt);
  if (e0 || !who?.user) return { ok: false, error: 'Inicia sesión de nuevo' };
  const email = String(b.email || '').trim().toLowerCase();
  const password = String(b.password || '');
  if (password.length < 6) return { ok: false, error: 'La contraseña debe tener al menos 6 caracteres' };
  const { data: prep, error: e1 } = await s.rpc('preparar_cuenta', {
    p_caller: who.user.id, p_email: email, p_nombre: String(b.nombre || ''), p_telefono: String(b.telefono || ''),
    p_rol: ['socio', 'taller', 'equipo', 'cliente'].includes(String(b.rol)) ? b.rol : 'equipo', p_taller_nombre: String(b.taller_nombre || ''),
    p_taller: /^[0-9a-f-]{36}$/i.test(String(b.taller_id || '')) ? b.taller_id : null,
  });
  if (e1) return { ok: false, error: e1.message };
  if (!prep?.ok) return prep;
  const { data: nu, error: e2 } = await s.auth.admin.createUser({
    email, password, email_confirm: true, user_metadata: { nombre: String(b.nombre || '').trim() },
  });
  if (e2 || !nu?.user) {
    await s.rpc('cancelar_invitacion', { p_email: email });
    const m = (e2 && e2.message) || 'No se pudo crear la cuenta';
    return { ok: false, error: /already|registered|exists/i.test(m) ? 'Ese correo ya tiene cuenta' : m };
  }
  return { ok: true, id: nu.user.id };
}

async function borrar(jwt: string, b: { tipo?: string; id?: string; motivo?: string }) {
  const s = db();
  const { data: who, error: e0 } = await s.auth.getUser(jwt);
  if (e0 || !who?.user) return { ok: false, error: 'Inicia sesión de nuevo' };
  if (!/^[0-9a-f-]{36}$/i.test(String(b.id || ''))) return { ok: false, error: 'Dato no válido' };
  const { data: prep, error: e1 } = await s.rpc('preparar_borrado', { p_caller: who.user.id, p_tipo: b.tipo === 'taller' ? 'taller' : 'perfil', p_id: b.id,
    p_motivo: String(b.motivo || '').slice(0, 200) || null });
  if (e1) return { ok: false, error: e1.message };
  if (!prep?.ok) return prep;
  let n = 0;
  for (const id of prep.ids as string[]) {
    const { error } = await s.auth.admin.deleteUser(id);
    if (!error) n++;
  }
  if (prep.taller) await s.rpc('borrar_taller', { p_id: prep.taller });
  return { ok: true, borrados: n };
}

// Botón "Actualizar base de datos": ejecuta supabase/instalar.sql, que viaja DENTRO de esta función
// (queda fijo al publicarla; no se descarga nada al momento). Se puede repetir: no borra datos.
async function actualizarBd(jwt: string) {
  const s = db();
  const { data: who, error: e0 } = await s.auth.getUser(jwt);
  if (e0 || !who?.user) return { ok: false, error: 'Inicia sesión de nuevo' };
  const { data: adminEmail } = await s.rpc('admin_email');
  const { data: yo } = await s.from('perfiles').select('rol, suspendido').eq('id', who.user.id).maybeSingle();
  if (!yo || yo.rol !== 'admin' || yo.suspendido || !who.user.email_confirmed_at ||
      String(who.user.email || '').toLowerCase() !== String(adminEmail || '').toLowerCase()) {
    return { ok: false, error: 'Solo el administrador actualiza la base de datos' };
  }
  const dbUrl = Deno.env.get('SUPABASE_DB_URL');
  if (!dbUrl) return { ok: false, error: 'La función no tiene acceso a la base de datos (falta SUPABASE_DB_URL)' };
  const { data: antes } = await s.rpc('db_version');
  const sql = postgres(dbUrl, { prepare: false, max: 1, idle_timeout: 5, connect_timeout: 20 });
  try {
    await sql.unsafe(INSTALAR);
    const r = await sql`select public.db_version() as v`;
    return { ok: true, antes: antes || '?', ahora: r[0]?.v || DB_VERSION };
  } catch (e) {
    return { ok: false, error: 'La base de datos rechazó la actualización: ' + String((e as Error).message || e).slice(0, 300) };
  } finally {
    await sql.end({ timeout: 5 }).catch(() => {});
  }
}

async function enviarPush() {
  const s = db();
  const { data, error } = await s.rpc('push_pendientes');
  if (error) throw error;
  const envios = (data?.envios || []) as { endpoint: string; p256dh: string; auth: string; titulo: string; cuerpo: string; url: string; id: string }[];
  const claves = data?.claves || {};
  if (!envios.length) return { enviados: 0 };
  if (!claves.publica || !claves.privada) return { enviados: 0, error: 'Faltan las claves push (Admin → Ajustes → Notificaciones)' };
  webpush.setVapidDetails('mailto:soporte@bicitaller.app', claves.publica, claves.privada);
  let ok = 0, malos = 0;
  for (let i = 0; i < envios.length; i += 50) {
    const lote = envios.slice(i, i + 50);
    const res = await Promise.allSettled(lote.map((e) => webpush.sendNotification(
      { endpoint: e.endpoint, keys: { p256dh: e.p256dh, auth: e.auth } },
      JSON.stringify({ title: e.titulo, body: e.cuerpo, url: e.url || '/', tag: e.id }), { TTL: 86400 })));
    for (let j = 0; j < res.length; j++) {
      const r = res[j];
      if (r.status === 'fulfilled') ok++;
      else {
        malos++;
        const code = (r.reason as { statusCode?: number })?.statusCode;
        if (code === 404 || code === 410) await s.rpc('push_borrar_endpoint', { p_endpoint: lote[j].endpoint });
      }
    }
  }
  return { enviados: ok, fallidos: malos };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = req.method === 'POST' ? await req.json().catch(() => ({})) : {};
    if (body?.accion === 'ping') return json({ ok: true, version: VERSION, db_version: DB_VERSION, servicio: !!Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'), bd: !!Deno.env.get('SUPABASE_DB_URL') });
    if (body?.accion === 'actualizar_bd') {
      const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
      try { return json(await actualizarBd(jwt)); }
      catch (e) { return json({ ok: false, error: 'Error del servidor: ' + String((e as Error).message || e) }); }
    }
    if (body?.accion === 'crear_cuenta') {
      const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
      try { return json(await crearCuenta(jwt, body)); }
      catch (e) { return json({ ok: false, error: 'Error del servidor: ' + String((e as Error).message || e) }); }
    }
    if (body?.accion === 'borrar') {
      const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
      try { return json(await borrar(jwt, body)); }
      catch (e) { return json({ ok: false, error: 'Error del servidor: ' + String((e as Error).message || e) }); }
    }
    return json(await enviarPush());
  } catch (e) {
    return json({ error: String((e as Error).message || e) }, 500);
  }
});
