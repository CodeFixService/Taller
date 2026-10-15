-- BiciTaller · Instalación/actualización corta (v1.5): descarga y ejecuta supabase/instalar.sql.
create extension if not exists http with schema extensions;
do $$ begin
  execute (select content from extensions.http_get('https://raw.githubusercontent.com/CodeFixService/Taller/090cdd11910cc7e259d6eb7f53d88b00333e2c6a/supabase/instalar.sql'));
end $$;
