-- BiciTaller · Instalación/actualización corta (v1.7): descarga y ejecuta supabase/instalar.sql.
create extension if not exists http with schema extensions;
do $$ begin
  execute (select content from extensions.http_get('https://raw.githubusercontent.com/CodeFixService/Taller/0725ac5e5f51ca4b98c651e5a54c26273f297e61/supabase/instalar.sql'));
end $$;
