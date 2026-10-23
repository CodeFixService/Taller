-- BiciTaller · Instalación/actualización corta (v1.8): descarga y ejecuta supabase/instalar.sql.
create extension if not exists http with schema extensions;
do $$ begin
  execute (select content from extensions.http_get('https://raw.githubusercontent.com/CodeFixService/Taller/b7ae7e022c48d3b50b3f1160b1d0a1e7fc9bbe27/supabase/instalar.sql'));
end $$;
