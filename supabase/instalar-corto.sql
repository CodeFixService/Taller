-- BiciTaller · Instalación/actualización corta (v1.6): descarga y ejecuta supabase/instalar.sql.
create extension if not exists http with schema extensions;
do $$ begin
  execute (select content from extensions.http_get('https://raw.githubusercontent.com/CodeFixService/Taller/fdd496d8acd2f2d198b3b2007c3275d49947ddf8/supabase/instalar.sql'));
end $$;
