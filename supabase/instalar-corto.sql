-- BiciTaller · Instalación/actualización corta (v1.9): descarga y ejecuta supabase/instalar.sql.
create extension if not exists http with schema extensions;
do $$ begin
  execute (select content from extensions.http_get('https://raw.githubusercontent.com/CodeFixService/Taller/1eff206f3a866a93d77aeb35a4586755b410a0e5/supabase/instalar.sql'));
end $$;
