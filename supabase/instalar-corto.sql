-- BiciTaller · Instalación/actualización corta (v1.7): descarga y ejecuta supabase/instalar.sql.
create extension if not exists http with schema extensions;
do $$ begin
  execute (select content from extensions.http_get('https://raw.githubusercontent.com/CodeFixService/Taller/6b77326ee7c65bf6a45ee726c0d2830f6a5e8dea/supabase/instalar.sql'));
end $$;
