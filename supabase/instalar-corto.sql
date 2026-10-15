-- BiciTaller · Instalación/actualización corta (v1.3): descarga y ejecuta supabase/instalar.sql.
create extension if not exists http with schema extensions;
do $$ begin
  execute (select content from extensions.http_get('https://raw.githubusercontent.com/CodeFixService/Taller/94a59b6ea900a1e9bea606e3594c153a2b16ad1e/supabase/instalar.sql'));
end $$;
