-- BiciTaller · Instalación/actualización corta (v1.4): descarga y ejecuta supabase/instalar.sql.
create extension if not exists http with schema extensions;
do $$ begin
  execute (select content from extensions.http_get('https://raw.githubusercontent.com/CodeFixService/Taller/4689491f895a357464ebcfb2c4080463abf29a4b/supabase/instalar.sql'));
end $$;
