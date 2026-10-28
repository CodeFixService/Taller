-- =====================================================================
--  BiciTaller · Tareas automáticas (pégalo en Supabase → SQL Editor → Run,
--  DESPUÉS de schema.sql y de crear la función "servidor").
--   · Cada 5 minutos: libera horas sin pago, recordatorios, avisos de vencimiento, limpieza diaria.
--   · Cada minuto: envía por push los avisos nuevos de la campanita.
-- =====================================================================
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

select cron.unschedule(jobid) from cron.job where jobname in ('bt-tareas', 'bt-push');

select cron.schedule('bt-tareas', '*/5 * * * *', $$ select public.tareas_periodicas(); $$);

-- v2.0: la app ya no se actualiza apenas se publica: llega a los usuarios cuando la liberas (Admin → Actualizar, o Centro de Mando → Apps).
insert into public.config (clave, valor) values ('version_liberada', '"2.7"') on conflict (clave) do nothing;

-- =====================================================================
-- Actualización automática (núcleo CodeFix): cada 10 minutos la base revisa GitHub (rama main).
--   · Si hay una base nueva (version.json), descarga y ejecuta este mismo instalar.sql (no borra datos).
--   · Si solo cambió la app, la libera para que los celulares se actualicen solos.
--   Si algo falla no cambia nada y lo reintenta en la siguiente vuelta. Hay que correr este archivo UNA vez.
-- =====================================================================
create or replace function public.auto_actualizar() returns text
language plpgsql security definer set search_path = '' as $f$
declare
  base constant text := 'https://raw.githubusercontent.com/CodeFixService/Taller/main/';
  marca text := '?t=' || extract(epoch from now())::bigint; j jsonb; v_bd text; v_app text; codigo text; lib text;
  re constant text := '^[0-9]+(\.[0-9]+)*$';
begin
  execute 'select content from extensions.http_get($1)' into codigo using base || 'version.json' || marca;
  j := codigo::jsonb; v_bd := j ->> 'bd'; v_app := j ->> 'version';
  if v_bd ~ re and coalesce((public.db_version())::text, '0') ~ re and string_to_array(v_bd, '.')::int[] > string_to_array(coalesce((public.db_version())::text, '0'), '.')::int[] then
    execute 'select content from extensions.http_get($1)' into codigo using base || 'supabase/instalar.sql' || marca;
    if codigo is null or length(codigo) < 1000 then return 'instalar.sql no disponible'; end if;
    execute codigo;
    return 'base actualizada a ' || (public.db_version())::text;
  end if;
  return 'al día';
exception when others then
  return 'sin cambios: ' || sqlerrm;
end $f$;
revoke execute on function public.auto_actualizar() from public, anon, authenticated;
do $$
begin
  create extension if not exists http with schema extensions;
  perform cron.unschedule(jobid) from cron.job where jobname = 'cfx-auto';
  perform cron.schedule('cfx-auto', '*/10 * * * *', 'select public.auto_actualizar()');
exception when others then
  raise notice 'Actualización automática no activada (%). Activa pg_cron en Supabase y vuelve a correr este archivo.', sqlerrm;
end $$;

select cron.schedule('bt-push', '* * * * *', $$
  select net.http_post(
    url := 'https://iwvjthcmufirbnotgixi.supabase.co/functions/v1/servidor',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml3dmp0aGNtdWZpcmJub3RnaXhpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIwMDU1MjMsImV4cCI6MjEwNzU4MTUyM30.54Hc89HlUejofX3knvL4nXDNCphsrZeQG7m50jEIlfw"}'::jsonb,
    body := '{}'::jsonb)
$$);
