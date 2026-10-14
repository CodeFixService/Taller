-- BiciTaller · Instalación/actualización corta (v1.2): descarga y ejecuta supabase/instalar.sql.
create extension if not exists http with schema extensions;
do $$ begin
  execute (select content from extensions.http_get('https://raw.githubusercontent.com/CodeFixService/Taller/e8e4a1f5853ff9d84ea2d8642e2155b153a4a175/supabase/instalar.sql'));
end $$;
