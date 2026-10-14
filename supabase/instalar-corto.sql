-- BiciTaller · Instalación/actualización corta (v1.1): descarga y ejecuta supabase/instalar.sql.
create extension if not exists http with schema extensions;
do $$ begin
  execute (select content from extensions.http_get('https://raw.githubusercontent.com/CodeFixService/Taller/058be8ebe50b0fc5891d4d686655b41ea5b3c775/supabase/instalar.sql'));
end $$;
