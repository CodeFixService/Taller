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

select cron.schedule('bt-push', '* * * * *', $$
  select net.http_post(
    url := 'https://iwvjthcmufirbnotgixi.supabase.co/functions/v1/servidor',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml3dmp0aGNtdWZpcmJub3RnaXhpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIwMDU1MjMsImV4cCI6MjEwNzU4MTUyM30.54Hc89HlUejofX3knvL4nXDNCphsrZeQG7m50jEIlfw"}'::jsonb,
    body := '{}'::jsonb)
$$);
