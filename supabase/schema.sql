-- =====================================================================
--  BiciTaller · Base de datos (Supabase)
--  Supabase → SQL Editor → New query → pega TODO este archivo → Run.
--  Se puede volver a ejecutar sin perder datos (sirve para actualizar).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Ajustes generales
-- ---------------------------------------------------------------------
-- El único administrador general (se reconoce por su correo confirmado).
create or replace function public.admin_email() returns text
language sql immutable as $$ select 'juanjosuecastilloloyola@gmail.com'::text $$;

create or replace function public.db_version() returns text
language sql immutable as $$ select '2.7'::text $$;

-- Teléfono normalizado (solo números; celulares chilenos con 56 adelante).
create or replace function public.tel_norm(t text) returns text
language plpgsql immutable as $$
declare d text := regexp_replace(coalesce(t, ''), '\D', '', 'g');
begin
  if length(d) = 9 and left(d, 1) = '9' then return '56' || d; end if;
  if length(d) = 8 then return '569' || d; end if;
  return d;
end $$;

-- Configuración que el administrador cambia desde su panel.
create table if not exists public.config (
  clave  text primary key,
  valor  jsonb not null
);
insert into public.config (clave, valor) values
  ('minutos_pago', '30'),            -- tiempo para pagar el abono y subir el comprobante
  ('minutos_devolucion', '10'),      -- cancelar dentro de este tiempo: se devuelve el abono
  ('horas_cancelacion', '24'),       -- anticipación mínima para cancelar/reagendar con saldo a favor
  ('dias_saldo', '90'),              -- días que dura el saldo a favor
  ('dias_regalo_taller', '30'),      -- Premium de regalo al crear un taller
  ('dias_aviso_vencimiento', '3'),   -- aviso antes de que venza el Premium
  ('dias_comprobantes', '30'),       -- los comprobantes se borran solos después de estos días
  ('soporte_whatsapp', '""'),
  ('vapid_publica', '""'),
  ('registro_talleres', '1'),        -- 1 = cualquiera crea su taller gratis desde /n/ (0 = cerrado)
  ('dias_referido', '30'),           -- Premium de regalo al taller que invitó, cuando el invitado paga su primer Premium
  ('horas_libera_premium', '24'),    -- las horas exclusivas Premium se abren a todos con esta anticipación
  ('dias_fotos', '365'),             -- las fotos antes/después se borran solas después de estos días
  ('color_app', '"#16a34a"')         -- color de la app (inicio, registro, directorio y panel del administrador)
on conflict (clave) do nothing;
alter table public.config enable row level security;

-- Textos de la app (el administrador los edita).
create table if not exists public.textos (
  clave  text primary key,
  valor  text not null default ''
);
insert into public.textos (clave, valor) values
  ('app_nombre', 'BiciTaller'),
  ('app_lema', 'Reserva tu hora en el taller de bicicletas'),
  ('reserva_pago', 'Para confirmar tu hora paga el abono con el botón "Pagar abono" y sube la foto o captura del comprobante. Tienes {minutos} minutos; si no, la hora se libera.'),
  ('reserva_politica', 'Puedes cancelar sin costo dentro de los primeros {devolucion} minutos (se te devuelve el abono). Después, si cancelas con {horas} horas o más de anticipación, el abono queda como saldo a favor para reagendar. Si cancelas con menos de {horas} horas o no llegas, pierdes el abono. El abono se descuenta del total del servicio.'),
  ('premium_taller_titulo', 'BiciTaller Premium'),
  ('premium_taller_texto', 'Más reservas, tu equipo de mecánicos, estadísticas y recordatorios de mantención para que tus clientes vuelvan.'),
  ('premium_cliente_titulo', 'Cliente Premium'),
  ('premium_cliente_texto', 'Historial completo de tu bici, recordatorios de mantención y reserva con más anticipación.'),
  ('pago_instrucciones', 'Toca "Pagar", paga en Mercado Pago, toma una captura del comprobante y súbela aquí. Te avisamos apenas se apruebe.'),
  ('bienvenida_taller', '¡Bienvenido! Completa tu perfil, tu horario, tus servicios y el link de pago del abono para empezar a recibir reservas.'),
  ('terminos', 'Al usar BiciTaller aceptas que tus datos (nombre, teléfono y correo) se usen solo para gestionar tus reservas con el taller.')
on conflict (clave) do nothing;
alter table public.textos enable row level security;

-- Planes: límites y beneficios (todo editable por el administrador).
create table if not exists public.planes (
  codigo        text primary key check (codigo in ('taller_free', 'taller_premium', 'cliente_free', 'cliente_premium')),
  nombre        text not null,
  descripcion   text not null default '',
  limites       jsonb not null default '{}',
  beneficios    jsonb not null default '[]',
  duracion_dias int not null default 30 check (duracion_dias between 1 and 3650)
);
insert into public.planes (codigo, nombre, descripcion, limites, beneficios) values
  ('taller_free', 'Gratis', 'Lo básico para recibir reservas online.',
   '{"reservas_mes": 30, "servicios": 5, "promos": 1, "equipo": 0, "clientes_cuenta": 30, "estadisticas": false, "recordatorios": false}',
   '["Página de reservas con tu logo y colores", "Hasta 30 reservas online al mes", "5 servicios y 1 promoción", "Abono con comprobante y agenda con bloqueos", "Órdenes de trabajo y calificaciones"]'),
  ('taller_premium', 'Premium', 'Todo para hacer crecer tu taller.',
   '{"reservas_mes": 1000, "servicios": 60, "promos": 15, "equipo": 10, "clientes_cuenta": 2000, "estadisticas": true, "recordatorios": true}',
   '["Reservas online casi ilimitadas (1000 al mes)", "Hasta 10 mecánicos o recepción con su propia cuenta", "60 servicios y 15 promociones", "Estadísticas de ingresos, servicios y clientes", "Recordatorios de mantención para que tus clientes vuelvan", "Hasta 2000 clientes con cuenta"]'),
  ('cliente_free', 'Gratis', 'Reserva y sigue tu bici.',
   '{"historial": 3, "anticipacion_extra": 0, "recordatorios": false}',
   '["Reserva tu hora", "Sigue el estado de tu bici", "Tus últimas 3 visitas"]'),
  ('cliente_premium', 'Premium', 'Para ciclistas que cuidan su bici.',
   '{"historial": 1000, "anticipacion_extra": 15, "recordatorios": true}',
   '["Historial completo de tu bici", "Recordatorio cuando le toca mantención", "Reserva hasta 15 días antes que el resto", "Insignia de cliente Premium"]')
on conflict (codigo) do nothing;
alter table public.planes enable row level security;
-- v1.6: fotos antes/después (taller Premium) y beneficios nuevos (solo si el administrador no cambió la lista).
update public.planes set limites = limites || '{"fotos": false}' where codigo = 'taller_free' and not limites ? 'fotos';
update public.planes set limites = limites || '{"fotos": true}' where codigo = 'taller_premium' and not limites ? 'fotos';
update public.planes set beneficios = beneficios || '["Fotos antes/después en tus órdenes de trabajo", "Apareces primero en el directorio de talleres"]'::jsonb
where codigo = 'taller_premium' and beneficios = '["Reservas online casi ilimitadas (1000 al mes)", "Hasta 10 mecánicos o recepción con su propia cuenta", "60 servicios y 15 promociones", "Estadísticas de ingresos, servicios y clientes", "Recordatorios de mantención para que tus clientes vuelvan", "Hasta 2000 clientes con cuenta"]'::jsonb;
update public.planes set beneficios = '["Horas exclusivas para clientes Premium", "Reserva con tu cuenta en cualquier taller del directorio", "Historial completo de tu bici, con fotos antes/después", "Recordatorio cuando le toca mantención", "Reserva hasta 15 días antes que el resto", "Insignia de cliente Premium"]'::jsonb
where codigo = 'cliente_premium' and beneficios = '["Historial completo de tu bici", "Recordatorio cuando le toca mantención", "Reserva hasta 15 días antes que el resto", "Insignia de cliente Premium"]'::jsonb;

-- Secretos (claves push): solo los lee el servidor.
create table if not exists public.secretos (
  clave  text primary key,
  valor  text not null
);
alter table public.secretos enable row level security;

-- ---------------------------------------------------------------------
-- 1. Talleres y perfiles
-- ---------------------------------------------------------------------
create table if not exists public.talleres (
  id                uuid primary key default gen_random_uuid(),
  owner_id          uuid unique,
  nombre            text not null check (length(trim(nombre)) between 1 and 80),
  slug              text not null unique check (slug ~ '^[a-z0-9-]{3,60}$'),
  descripcion       text not null default '' check (length(descripcion) <= 500),
  direccion         text not null default '' check (length(direccion) <= 160),
  comuna            text not null default '' check (length(comuna) <= 60),
  telefono          text not null default '' check (length(telefono) <= 30),
  instagram         text not null default '' check (length(instagram) <= 60),
  logo              text check (logo is null or (logo ~ '^data:image/(jpeg|png|webp);base64,' and length(logo) <= 120000)),
  color             text not null default '#16a34a' check (color ~ '^#[0-9a-fA-F]{6}$'),
  icono             text not null default '🚲' check (length(icono) <= 8),
  -- Horario y agenda
  zona              text not null default 'America/Santiago',
  dias              int[] not null default '{1,2,3,4,5,6}',
  abre              time not null default '10:00',
  cierra            time not null default '19:00',
  colacion_desde    time,
  colacion_hasta    time,
  bloque_min        int not null default 60,
  cupos             int not null default 2 check (cupos between 1 and 20),
  anticipacion_dias int not null default 21 check (anticipacion_dias between 1 and 120),
  meses_mantencion  int not null default 4 check (meses_mantencion between 1 and 24),
  reservas_online   boolean not null default true,
  -- Plan
  premium_hasta     timestamptz,
  aviso_venc_para   timestamptz,
  aviso_vencido_para timestamptz,
  activo            boolean not null default true,
  suspendido        boolean not null default false,
  created_at        timestamptz not null default now(),
  check (cierra > abre),
  check ((colacion_desde is null) = (colacion_hasta is null) and (colacion_hasta is null or colacion_hasta > colacion_desde))
);
alter table public.talleres enable row level security;
alter table public.talleres add column if not exists horarios jsonb not null default '{}';   -- {"6": {"abre": "10:00", "cierra": "14:00"}}
alter table public.talleres add column if not exists max_dia int not null default 0;         -- 0 = sin límite de bicis por día
alter table public.talleres add column if not exists capacidad_dia int not null default 0;   -- mantenciones que se terminan por día (0 = no calcular entrega)
alter table public.talleres add column if not exists max_espera_dias int not null default 14; -- tope de días hasta la entrega
alter table public.talleres drop constraint if exists talleres_bloque_min_check;
alter table public.talleres add constraint talleres_bloque_min_check check (bloque_min in (15, 20, 30, 45, 60, 90, 120, 180, 240));
-- v1.6: registro abierto, referidos, directorio y horas exclusivas Premium.
alter table public.talleres add column if not exists autoregistro boolean not null default false;     -- se registró solo (link/QR)
alter table public.talleres add column if not exists referido_por uuid references public.talleres (id) on delete set null;
alter table public.talleres add column if not exists referido_premiado boolean not null default false;
alter table public.talleres add column if not exists en_directorio boolean not null default true;
alter table public.talleres add column if not exists horas_premium text[] not null default '{}';     -- {"10:00"}: solo clientes Premium

create table if not exists public.perfiles (
  id               uuid primary key references auth.users (id) on delete cascade,
  email            text not null,
  nombre           text not null default '' check (length(nombre) <= 80),
  telefono         text not null default '' check (length(telefono) <= 30),
  rol              text not null check (rol in ('admin', 'taller', 'equipo', 'cliente')),
  taller_id        uuid references public.talleres (id) on delete cascade,
  premium_hasta    timestamptz,          -- Premium del cliente
  aviso_venc_para  timestamptz,
  aviso_vencido_para timestamptz,
  suspendido       boolean not null default false,
  visto_at         timestamptz,
  created_by       uuid,
  created_at       timestamptz not null default now()
);
create index if not exists perfiles_taller_idx on public.perfiles (taller_id, rol);
alter table public.perfiles enable row level security;
-- v1.7: socio = administra junto al administrador (ve todo; no crea ni elimina; cada cambio con motivo).
alter table public.perfiles drop constraint if exists perfiles_rol_check;
alter table public.perfiles add constraint perfiles_rol_check check (rol in ('admin', 'socio', 'taller', 'equipo', 'cliente'));

alter table public.talleres drop constraint if exists talleres_owner_fk;
alter table public.talleres add constraint talleres_owner_fk foreign key (owner_id) references public.perfiles (id) on delete set null
  deferrable initially deferred;

-- Invitaciones: las crea el servidor (función "servidor") antes de crear la cuenta.
create table if not exists public.invitaciones (
  email        text primary key,
  rol          text not null check (rol in ('taller', 'equipo', 'cliente')),
  nombre       text not null default '',
  telefono     text not null default '',
  taller_id    uuid references public.talleres (id) on delete cascade,
  taller_nombre text not null default '',
  created_by   uuid,
  created_at   timestamptz not null default now()
);
alter table public.invitaciones enable row level security;
alter table public.invitaciones drop constraint if exists invitaciones_rol_check;
alter table public.invitaciones add constraint invitaciones_rol_check check (rol in ('socio', 'taller', 'equipo', 'cliente'));

-- ---------------------------------------------------------------------
-- 2. Quién soy
-- ---------------------------------------------------------------------
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.perfiles p join auth.users u on u.id = p.id
    where p.id = auth.uid() and p.rol = 'admin' and not p.suspendido
      and lower(u.email) = public.admin_email() and u.email_confirmed_at is not null)
$$;

-- Socio del administrador (lo crea solo el administrador).
create or replace function public.es_socio() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.perfiles p where p.id = auth.uid() and p.rol = 'socio' and not p.suspendido)
$$;

-- Taller donde trabaja la persona (dueño o equipo), si ambos están activos.
create or replace function public.taller_de(uid uuid) returns uuid
language sql stable security definer set search_path = '' as $$
  select p.taller_id from public.perfiles p join public.talleres t on t.id = p.taller_id
  where p.id = uid and p.rol in ('taller', 'equipo') and not p.suspendido and not t.suspendido
$$;

-- Taller al que pertenece la persona (cualquier rol).
create or replace function public.mi_taller() returns uuid
language sql stable security definer set search_path = '' as $$
  select taller_id from public.perfiles where id = auth.uid() and not suspendido
$$;

create or replace function public.es_dueno(t uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.perfiles p join public.talleres x on x.id = p.taller_id
                 where p.id = auth.uid() and p.rol = 'taller' and p.taller_id = t and not p.suspendido and not x.suspendido)
$$;

create or replace function public.taller_es_premium(t uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select premium_hasta > now() from public.talleres where id = t), false)
$$;

create or replace function public.cliente_es_premium(uid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select premium_hasta > now() from public.perfiles where id = uid), false)
$$;

-- Límite de un plan (número o verdadero/falso), según si el taller/cliente es Premium.
create or replace function public.limite_taller(t uuid, clave text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select limites -> clave from public.planes
  where codigo = case when public.taller_es_premium(t) then 'taller_premium' else 'taller_free' end
$$;
create or replace function public.limite_cliente(uid uuid, clave text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select limites -> clave from public.planes
  where codigo = case when public.cliente_es_premium(uid) then 'cliente_premium' else 'cliente_free' end
$$;

create or replace function public.cfg_int(c text) returns int
language sql stable security definer set search_path = '' as $$
  select (valor #>> '{}')::int from public.config where clave = c
$$;

-- ---------------------------------------------------------------------
-- 3. Cuentas nuevas
--   · Admin: por correo.  · Equipo: solo con invitación (servidor).
--   · Taller: lo crea el administrador o se registra solo y gratis desde /n/ (link y QR).
--   · Cliente: se registra desde la página de SU taller y queda asociado a él.
-- ---------------------------------------------------------------------
create or replace function public.slug_de(txt text) returns text
language plpgsql immutable as $$
declare s text;
begin
  s := lower(translate(coalesce(txt, ''), 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun'));
  s := regexp_replace(s, '[^a-z0-9]+', '-', 'g');
  s := trim(both '-' from s);
  if length(s) < 3 then s := s || '-taller'; end if;
  return left(s, 50);
end $$;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  inv public.invitaciones;
  em text := lower(new.email);
  t public.talleres;
  sl text;
  tid uuid;
  nom text;
  ref public.talleres;
begin
  if em = public.admin_email() then
    insert into public.perfiles (id, email, nombre, rol) values (new.id, em, 'Administrador', 'admin')
    on conflict (id) do nothing;
    return new;
  end if;

  select * into inv from public.invitaciones where email = em and created_at > now() - interval '1 day';
  if inv.email is not null then
    if inv.rol = 'taller' then
      sl := public.slug_de(inv.taller_nombre);
      while exists (select 1 from public.talleres where slug = sl) loop
        sl := left(public.slug_de(inv.taller_nombre), 44) || '-' || substr(md5(random()::text), 1, 5);
      end loop;
      insert into public.talleres (owner_id, nombre, slug, telefono, premium_hasta)
      values (new.id, left(inv.taller_nombre, 80), sl, inv.telefono,
              now() + make_interval(days => coalesce(public.cfg_int('dias_regalo_taller'), 30)))
      returning id into tid;
      insert into public.perfiles (id, email, nombre, telefono, rol, taller_id, created_by)
      values (new.id, em, left(inv.nombre, 80), inv.telefono, 'taller', tid, inv.created_by);
    else
      insert into public.perfiles (id, email, nombre, telefono, rol, taller_id, created_by)
      values (new.id, em, left(inv.nombre, 80), inv.telefono, inv.rol, inv.taller_id, inv.created_by);
    end if;
    delete from public.invitaciones where email = em;
    return new;
  end if;

  -- Taller que se registra solo desde /n/ (plan gratis + días de Premium de regalo).
  if meta ->> 'rol' = 'taller' then
    if coalesce(public.cfg_int('registro_talleres'), 1) <= 0 then raise exception 'El registro de talleres está cerrado'; end if;
    nom := left(trim(coalesce(meta ->> 'taller_nombre', '')), 80);
    if nom = '' then raise exception 'Escribe el nombre de tu taller'; end if;
    if (select count(*) from public.talleres where autoregistro and created_at > now() - interval '1 hour') >= 20 then
      raise exception 'Muchos registros seguidos. Intenta en un rato.';
    end if;
    select * into ref from public.talleres where slug = lower(trim(coalesce(meta ->> 'ref', ''))) and activo and not suspendido;
    sl := public.slug_de(nom);
    while exists (select 1 from public.talleres where slug = sl) loop
      sl := left(public.slug_de(nom), 44) || '-' || substr(md5(random()::text), 1, 5);
    end loop;
    insert into public.talleres (owner_id, nombre, slug, telefono, comuna, premium_hasta, autoregistro, referido_por)
    values (new.id, nom, sl, left(trim(coalesce(meta ->> 'telefono', '')), 30), left(trim(coalesce(meta ->> 'comuna', '')), 60),
            now() + make_interval(days => coalesce(public.cfg_int('dias_regalo_taller'), 30)), true, ref.id)
    returning id into tid;
    insert into public.perfiles (id, email, nombre, telefono, rol, taller_id)
    values (new.id, em, left(trim(coalesce(meta ->> 'nombre', '')), 80), left(trim(coalesce(meta ->> 'telefono', '')), 30), 'taller', tid);
    perform public.avisar_admin('🚲 Nuevo taller: ' || nom, concat_ws(' · ', nullif(trim(meta ->> 'comuna'), ''), em, 'se registró solo',
      'invitado por ' || ref.nombre), '/admin/#talleres');
    if ref.id is not null then
      perform public.avisar_taller(ref.id, '🤝 Se sumó un taller con tu invitación', nom || ' · Cuando active su Premium te regalamos ' ||
        coalesce(public.cfg_int('dias_referido'), 30) || ' días de Premium.', '/taller/#hoy');
    end if;
    return new;
  end if;

  -- Cliente que se registra desde la página de su taller.
  if meta ->> 'rol' = 'cliente' and (meta ->> 'taller') ~ '^[0-9a-f-]{36}$' then
    select * into t from public.talleres where id = (meta ->> 'taller')::uuid and activo and not suspendido;
    if t.id is null then raise exception 'Este taller no está recibiendo clientes nuevos'; end if;
    if (select count(*) from public.perfiles where taller_id = t.id and rol = 'cliente')
       >= coalesce((public.limite_taller(t.id, 'clientes_cuenta'))::int, 30) then
      raise exception 'Este taller llegó a su límite de clientes con cuenta';
    end if;
    insert into public.perfiles (id, email, nombre, telefono, rol, taller_id)
    values (new.id, em, left(trim(coalesce(meta ->> 'nombre', '')), 80), left(trim(coalesce(meta ->> 'telefono', '')), 30), 'cliente', t.id);
    return new;
  end if;

  raise exception 'Para crear tu cuenta entra al link de tu taller o al registro de talleres.';
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Si el administrador ya había creado su usuario antes de correr este archivo.
insert into public.perfiles (id, email, nombre, rol)
select u.id, lower(u.email), 'Administrador', 'admin' from auth.users u
where lower(u.email) = public.admin_email()
on conflict (id) do nothing;

-- Lo llama SOLO el servidor antes de crear una cuenta de taller o de equipo.
drop function if exists public.preparar_cuenta(uuid, text, text, text, text, text);
create or replace function public.preparar_cuenta(p_caller uuid, p_email text, p_nombre text, p_telefono text,
  p_rol text, p_taller_nombre text, p_taller uuid default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  c public.perfiles;
  em text := lower(trim(coalesce(p_email, '')));
  admin boolean;
  tid uuid;
begin
  select * into c from public.perfiles where id = p_caller and not suspendido;
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'Sin permiso'); end if;
  admin := c.rol = 'admin' and c.email = public.admin_email();
  if em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return jsonb_build_object('ok', false, 'error', 'Correo no válido'); end if;
  if trim(coalesce(p_nombre, '')) = '' then return jsonb_build_object('ok', false, 'error', 'Escribe el nombre'); end if;
  if exists (select 1 from auth.users where lower(email) = em) then
    return jsonb_build_object('ok', false, 'error', 'Ese correo ya tiene cuenta');
  end if;
  if p_rol = 'taller' then
    if not admin then return jsonb_build_object('ok', false, 'error', 'Solo el administrador crea talleres'); end if;
    if trim(coalesce(p_taller_nombre, '')) = '' then return jsonb_build_object('ok', false, 'error', 'Escribe el nombre del taller'); end if;
    insert into public.invitaciones (email, rol, nombre, telefono, taller_nombre, created_by)
    values (em, 'taller', trim(p_nombre), trim(coalesce(p_telefono, '')), trim(p_taller_nombre), c.id)
    on conflict (email) do update set rol = excluded.rol, nombre = excluded.nombre, telefono = excluded.telefono,
      taller_nombre = excluded.taller_nombre, taller_id = null, created_by = excluded.created_by, created_at = now();
    return jsonb_build_object('ok', true);
  end if;
  if p_rol = 'socio' then
    if not admin then return jsonb_build_object('ok', false, 'error', 'Solo el administrador crea socios'); end if;
    insert into public.invitaciones (email, rol, nombre, telefono, created_by)
    values (em, 'socio', trim(p_nombre), trim(coalesce(p_telefono, '')), c.id)
    on conflict (email) do update set rol = excluded.rol, nombre = excluded.nombre, telefono = excluded.telefono,
      taller_id = null, taller_nombre = '', created_by = excluded.created_by, created_at = now();
    return jsonb_build_object('ok', true);
  end if;
  if p_rol not in ('equipo', 'cliente') then return jsonb_build_object('ok', false, 'error', 'Tipo de cuenta no válido'); end if;
  -- Equipo y clientes: el admin elige el taller; el dueño, el suyo.
  tid := case when admin then p_taller when c.rol = 'taller' then public.taller_de(c.id) end;
  if tid is null or not exists (select 1 from public.talleres where id = tid) then
    return jsonb_build_object('ok', false, 'error', case when admin then 'Elige el taller' else 'Sin permiso' end);
  end if;
  if not admin and p_rol = 'equipo' and (select count(*) from public.perfiles where taller_id = tid and rol = 'equipo')
     >= coalesce((public.limite_taller(tid, 'equipo'))::int, 0) then
    return jsonb_build_object('ok', false, 'error', case when public.taller_es_premium(tid)
      then 'Llegaste al máximo de personas en tu equipo' else 'Tu equipo es una función Premium. Activa Premium para agregar mecánicos.' end);
  end if;
  insert into public.invitaciones (email, rol, nombre, telefono, taller_id, created_by)
  values (em, p_rol, trim(p_nombre), trim(coalesce(p_telefono, '')), tid, c.id)
  on conflict (email) do update set rol = excluded.rol, nombre = excluded.nombre, telefono = excluded.telefono,
    taller_id = excluded.taller_id, taller_nombre = '', created_by = excluded.created_by, created_at = now();
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.cancelar_invitacion(p_email text) returns void
language sql security definer set search_path = '' as $$
  delete from public.invitaciones where email = lower(trim(p_email))
$$;

-- ---------------------------------------------------------------------
-- 4. Servicios, promociones y bloqueos de agenda
-- ---------------------------------------------------------------------
create table if not exists public.servicios (
  id            uuid primary key default gen_random_uuid(),
  taller_id     uuid not null references public.talleres (id) on delete cascade,
  nombre        text not null check (length(trim(nombre)) between 1 and 80),
  descripcion   text not null default '' check (length(descripcion) <= 300),
  precio        int not null default 0 check (precio >= 0),
  duracion_min  int not null default 60 check (duracion_min between 10 and 480),
  activo        boolean not null default true,
  orden         int not null default 0,
  created_at    timestamptz not null default now()
);
create index if not exists servicios_t_idx on public.servicios (taller_id);
alter table public.servicios enable row level security;
alter table public.servicios add column if not exists adicional boolean not null default false;  -- se suma a un servicio principal

create table if not exists public.promos (
  id            uuid primary key default gen_random_uuid(),
  taller_id     uuid not null references public.talleres (id) on delete cascade,
  titulo        text not null check (length(trim(titulo)) between 1 and 80),
  texto         text not null default '' check (length(texto) <= 400),
  precio        int check (precio >= 0),
  precio_antes  int check (precio_antes >= 0),
  hasta         date,
  activa        boolean not null default true,
  created_at    timestamptz not null default now()
);
create index if not exists promos_t_idx on public.promos (taller_id);
alter table public.promos enable row level security;

-- Bloqueos: un día completo (desde/hasta vacíos) o un tramo de horas.
create table if not exists public.bloqueos (
  id         uuid primary key default gen_random_uuid(),
  taller_id  uuid not null references public.talleres (id) on delete cascade,
  fecha      date not null,
  desde      time,
  hasta      time,
  motivo     text not null default '' check (length(motivo) <= 80),
  created_at timestamptz not null default now(),
  check ((desde is null) = (hasta is null) and (hasta is null or hasta > desde))
);
create index if not exists bloqueos_f_idx on public.bloqueos (taller_id, fecha);
alter table public.bloqueos enable row level security;

-- Límites del plan al crear servicios y promociones.
create or replace function public.limites_catalogo() returns trigger
language plpgsql security definer set search_path = '' as $$
declare n int; lim int;
begin
  if tg_table_name = 'servicios' then
    if tg_op = 'INSERT' then
      select count(*) into n from public.servicios where taller_id = new.taller_id;
      lim := coalesce((public.limite_taller(new.taller_id, 'servicios'))::int, 5);
      if n >= lim then raise exception 'Tu plan permite % servicios. Activa Premium para tener más.', lim; end if;
    end if;
  elsif tg_table_name = 'promos' then
    if (to_jsonb(new) ->> 'activa')::boolean and (tg_op = 'INSERT' or not (to_jsonb(old) ->> 'activa')::boolean) then
      select count(*) into n from public.promos where taller_id = new.taller_id and activa and id <> new.id;
      lim := coalesce((public.limite_taller(new.taller_id, 'promos'))::int, 1);
      if n >= lim then raise exception 'Tu plan permite % promociones activas. Activa Premium para tener más.', lim; end if;
    end if;
  end if;
  if tg_op = 'UPDATE' and new.taller_id <> old.taller_id then raise exception 'No se puede cambiar de taller'; end if;
  return new;
end $$;
drop trigger if exists servicios_lim on public.servicios;
create trigger servicios_lim before insert or update on public.servicios for each row execute function public.limites_catalogo();
drop trigger if exists promos_lim on public.promos;
create trigger promos_lim before insert or update on public.promos for each row execute function public.limites_catalogo();

-- ---------------------------------------------------------------------
-- 5. Links de pago (2 por tipo; solo uno activo a la vez)
--   abono           → del taller (le llega al taller). Solo lo ve el taller.
--   premium_taller  → del administrador (el taller paga su Premium).
--   premium_cliente → del administrador (el cliente paga su Premium).
--   premium_taller_anual / premium_cliente_anual → lo mismo, pagando el año (v1.6).
-- ---------------------------------------------------------------------
create table if not exists public.links_pago (
  id         uuid primary key default gen_random_uuid(),
  taller_id  uuid references public.talleres (id) on delete cascade,  -- null = del administrador
  tipo       text not null check (tipo in ('abono', 'premium_taller', 'premium_cliente')),
  slot       smallint not null check (slot in (1, 2)),
  monto      int not null default 0 check (monto >= 0),
  url        text not null default '' check (url = '' or url ~ '^https://'),
  texto      text not null default '' check (length(texto) <= 300),
  activo     boolean not null default false,
  updated_at timestamptz not null default now(),
  check ((tipo = 'abono') = (taller_id is not null))
);
create unique index if not exists links_pago_uni on public.links_pago (coalesce(taller_id, '00000000-0000-0000-0000-000000000000'::uuid), tipo, slot);
alter table public.links_pago enable row level security;
-- v1.8: en los Premium el espacio 1 es el precio normal y el 2 la promoción (con fecha de término opcional).
alter table public.links_pago add column if not exists hasta date;
alter table public.links_pago drop constraint if exists links_pago_tipo_check;
alter table public.links_pago add constraint links_pago_tipo_check
  check (tipo in ('abono', 'premium_taller', 'premium_cliente', 'premium_taller_anual', 'premium_cliente_anual'));

-- Plan anual: precio sugerido = 10 meses (paga 10, lleva 12). Se activa al poner el link.
insert into public.links_pago (taller_id, tipo, slot, monto, texto, activo)
select null, x.tipo, x.slot, case when x.tipo like '%anual' then 49900 else 4990 end,
       case when x.tipo like '%anual' then 'Pago anual: pagas 10 meses y te llevas 12' else '' end, x.slot = 1
from (values ('premium_taller', 1::smallint), ('premium_taller', 2::smallint),
             ('premium_cliente', 1::smallint), ('premium_cliente', 2::smallint),
             ('premium_taller_anual', 1::smallint), ('premium_taller_anual', 2::smallint),
             ('premium_cliente_anual', 1::smallint), ('premium_cliente_anual', 2::smallint)) x(tipo, slot)
where not exists (select 1 from public.links_pago l where l.taller_id is null and l.tipo = x.tipo and l.slot = x.slot);

-- Abono del taller: el espacio activo. Premium (admin): la promoción vigente (espacio 2) o, si no, el precio normal (espacio 1).
create or replace function public.link_activo(p_taller uuid, p_tipo text) returns public.links_pago
language sql stable security definer set search_path = '' as $$
  select * from public.links_pago
  where tipo = p_tipo and taller_id is not distinct from p_taller and activo and url <> '' and monto > 0
    and (hasta is null or hasta >= (now() at time zone 'America/Santiago')::date)
  order by case when p_taller is null then -slot else slot end limit 1
$$;

-- Lo que ve la gente de un precio Premium (con el precio normal tachado si hay promoción).
create or replace function public.link_publico(p_tipo text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('monto', l.monto, 'url', l.url, 'texto', l.texto, 'promo', l.slot = 2, 'hasta', l.hasta,
    'antes', case when l.slot = 2 then (select n.monto from public.links_pago n where n.taller_id is null and n.tipo = p_tipo
                                         and n.slot = 1 and n.activo and n.url <> '' and n.monto > l.monto) end)
  from public.link_activo(null, p_tipo) l where l.id is not null
$$;

-- ---------------------------------------------------------------------
-- 6. Reservas (también son la orden de trabajo de la bici)
-- ---------------------------------------------------------------------
create table if not exists public.reservas (
  id                 uuid primary key default gen_random_uuid(),
  taller_id          uuid not null references public.talleres (id) on delete cascade,
  servicio_id        uuid references public.servicios (id) on delete set null,
  servicio_nombre    text not null default '',
  precio             int not null default 0,
  fecha              date not null,
  hora               time not null,
  hora_fin           time not null,
  nombre             text not null check (length(trim(nombre)) between 1 and 80),
  telefono           text not null default '' check (length(telefono) <= 30),
  tel_norm           text not null default '',
  email              text not null default '' check (length(email) <= 120),
  bici               text not null default '' check (length(bici) <= 120),
  nota               text not null default '' check (length(nota) <= 500),
  cliente_id         uuid references public.perfiles (id) on delete set null,
  origen             text not null default 'online' check (origen in ('online', 'cliente', 'taller')),
  estado             text not null default 'por_pagar' check (estado in (
                       'por_pagar', 'en_revision', 'confirmada', 'recibida', 'en_reparacion', 'esperando_repuesto',
                       'lista', 'completada', 'no_asistio', 'rechazada', 'expirada', 'cancelada')),
  expira_at          timestamptz,
  abono_monto        int not null default 0,
  abono_estado       text not null default 'pendiente' check (abono_estado in (
                       'pendiente', 'en_revision', 'pagado', 'rechazado', 'devolver', 'devuelto', 'saldo', 'perdido',
                       'aplicado', 'sin_abono', 'no_pagado')),
  saldo_hasta        timestamptz,
  motivo             text not null default '' check (length(motivo) <= 300),
  -- Trabajo
  mecanico_id        uuid references public.perfiles (id) on delete set null,
  items              jsonb not null default '[]' check (jsonb_typeof(items) = 'array' and jsonb_array_length(items) <= 60),
  total              int not null default 0,
  diagnostico        text not null default '' check (length(diagnostico) <= 1000),
  notas_internas     text not null default '' check (length(notas_internas) <= 1000),
  proxima_mantencion date,
  historial          jsonb not null default '[]',
  reagendada         int not null default 0,
  recordado          boolean not null default false,
  mantencion_avisada boolean not null default false,
  token              text not null unique default replace(gen_random_uuid()::text, '-', ''),
  comprobante_at     timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  completada_at      timestamptz
);
create index if not exists reservas_f_idx on public.reservas (taller_id, fecha);
create index if not exists reservas_e_idx on public.reservas (taller_id, estado);
create index if not exists reservas_tel_idx on public.reservas (tel_norm);
create index if not exists reservas_cli_idx on public.reservas (cliente_id);
alter table public.reservas enable row level security;
alter table public.reservas add column if not exists entrega_estimada date;

-- Fotos antes/después del trabajo (v1.6, taller Premium). Livianas y se borran solas después de N días.
create table if not exists public.fotos_trabajo (
  id          uuid primary key default gen_random_uuid(),
  reserva_id  uuid not null references public.reservas (id) on delete cascade,
  tipo        text not null check (tipo in ('antes', 'despues')),
  imagen      text not null check (imagen ~ '^data:image/(jpeg|png|webp);base64,' and length(imagen) <= 160000),
  created_at  timestamptz not null default now()
);
create index if not exists fotos_r_idx on public.fotos_trabajo (reserva_id);
alter table public.fotos_trabajo enable row level security;

-- Comprobantes (imagen liviana). Se borran solos después de N días.
create table if not exists public.comprobantes (
  id          uuid primary key default gen_random_uuid(),
  reserva_id  uuid references public.reservas (id) on delete cascade,
  pago_id     uuid,
  imagen      text not null check (imagen ~ '^data:image/(jpeg|png|webp);base64,' and length(imagen) <= 600000),
  created_at  timestamptz not null default now(),
  check ((reserva_id is null) <> (pago_id is null))
);
create index if not exists comprobantes_r_idx on public.comprobantes (reserva_id);
create index if not exists comprobantes_p_idx on public.comprobantes (pago_id);
alter table public.comprobantes enable row level security;

-- Pagos de Premium (taller o cliente → administrador).
create table if not exists public.pagos (
  id           uuid primary key default gen_random_uuid(),
  perfil_id    uuid not null references public.perfiles (id) on delete cascade,
  taller_id    uuid references public.talleres (id) on delete cascade,
  tipo         text not null check (tipo in ('premium_taller', 'premium_cliente')),
  monto        int not null default 0,
  estado       text not null default 'en_revision' check (estado in ('en_revision', 'aprobado', 'rechazado')),
  nota         text not null default '' check (length(nota) <= 300),
  created_at   timestamptz not null default now(),
  resuelto_at  timestamptz
);
create index if not exists pagos_e_idx on public.pagos (estado, created_at);
alter table public.pagos enable row level security;
alter table public.pagos add column if not exists anual boolean not null default false;   -- v1.6: pagó el año
alter table public.comprobantes drop constraint if exists comprobantes_pago_fk;
alter table public.comprobantes add constraint comprobantes_pago_fk foreign key (pago_id) references public.pagos (id) on delete cascade;

-- Calificaciones: el cliente califica al taller y el taller al cliente (una vez por visita).
create table if not exists public.calificaciones (
  id          uuid primary key default gen_random_uuid(),
  reserva_id  uuid not null references public.reservas (id) on delete cascade,
  taller_id   uuid not null references public.talleres (id) on delete cascade,
  autor       text not null check (autor in ('cliente', 'taller')),
  tel_norm    text not null default '',          -- cliente calificado (cuando autor = taller)
  estrellas   int not null check (estrellas between 1 and 5),
  comentario  text not null default '' check (length(comentario) <= 300),
  created_at  timestamptz not null default now(),
  unique (reserva_id, autor)
);
create index if not exists calif_t_idx on public.calificaciones (taller_id, autor);
create index if not exists calif_tel_idx on public.calificaciones (tel_norm, autor);
alter table public.calificaciones enable row level security;

-- Notificaciones dentro de la app (campanita) y push.
create table if not exists public.notificaciones (
  id            uuid primary key default gen_random_uuid(),
  para          uuid not null references public.perfiles (id) on delete cascade,
  titulo        text not null,
  cuerpo        text not null default '',
  url           text not null default '',
  leida         boolean not null default false,
  push_enviado  boolean not null default false,
  created_at    timestamptz not null default now()
);
create index if not exists notif_para_idx on public.notificaciones (para, created_at desc);
create index if not exists notif_push_idx on public.notificaciones (push_enviado, created_at) where not push_enviado;
alter table public.notificaciones enable row level security;

create table if not exists public.push_subs (
  endpoint    text primary key,
  perfil_id   uuid not null references public.perfiles (id) on delete cascade,
  p256dh      text not null,
  auth        text not null,
  created_at  timestamptz not null default now()
);
alter table public.push_subs enable row level security;

-- Registro de acciones del administrador.
create table if not exists public.auditoria (
  id          bigserial primary key,
  quien       uuid,
  accion      text not null,
  detalle     text not null default '',
  created_at  timestamptz not null default now()
);
alter table public.auditoria enable row level security;

-- ---------------------------------------------------------------------
-- 7. Avisos (campanita)
-- ---------------------------------------------------------------------
create or replace function public.avisar(p_para uuid, p_titulo text, p_cuerpo text, p_url text) returns void
language sql security definer set search_path = '' as $$
  insert into public.notificaciones (para, titulo, cuerpo, url)
  select p_para, left(p_titulo, 90), left(coalesce(p_cuerpo, ''), 240), coalesce(p_url, '')
  where p_para is not null
$$;

-- A todo el taller (dueño y equipo activos).
create or replace function public.avisar_taller(p_taller uuid, p_titulo text, p_cuerpo text, p_url text) returns void
language sql security definer set search_path = '' as $$
  insert into public.notificaciones (para, titulo, cuerpo, url)
  select p.id, left(p_titulo, 90), left(coalesce(p_cuerpo, ''), 240), coalesce(p_url, '')
  from public.perfiles p where p.taller_id = p_taller and p.rol in ('taller', 'equipo') and not p.suspendido
$$;

create or replace function public.avisar_admin(p_titulo text, p_cuerpo text, p_url text) returns void
language sql security definer set search_path = '' as $$
  insert into public.notificaciones (para, titulo, cuerpo, url)
  select p.id, left(p_titulo, 90), left(coalesce(p_cuerpo, ''), 240), coalesce(p_url, '')
  from public.perfiles p where (p.rol = 'admin' and p.email = public.admin_email()) or (p.rol = 'socio' and not p.suspendido)
$$;

-- Registro de cambios. Si el cambio lo hace un socio, guarda su motivo y avisa al administrador.
create or replace function public.auditar(p_accion text, p_detalle text) returns void
language plpgsql security definer set search_path = '' as $$
declare m text := nullif(current_setting('bt.motivo', true), ''); quien text;
begin
  insert into public.auditoria (quien, accion, detalle)
  values (auth.uid(), p_accion, left(coalesce(p_detalle, '') || coalesce(' · Motivo: ' || m, ''), 500));
  select coalesce(nullif(nombre, ''), email) into quien from public.perfiles where id = auth.uid() and rol = 'socio';
  if quien is not null then
    insert into public.notificaciones (para, titulo, cuerpo, url)
    select p.id, left('👥 ' || quien || ': ' || p_accion, 90), left(coalesce(p_detalle, '') || coalesce(' · Motivo: ' || m, ''), 240), '/admin/#ajustes'
    from public.perfiles p where p.rol = 'admin' and p.email = public.admin_email();
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 8. Políticas de lectura (las escrituras pasan por funciones)
-- ---------------------------------------------------------------------
drop policy if exists "ver perfiles" on public.perfiles;
create policy "ver perfiles" on public.perfiles for select to authenticated
  using (id = auth.uid() or public.is_admin() or (taller_id is not null and taller_id = public.taller_de(auth.uid())));

drop policy if exists "ver taller" on public.talleres;
create policy "ver taller" on public.talleres for select to authenticated
  using (public.is_admin() or id = public.mi_taller());

drop policy if exists "ver servicios" on public.servicios;
create policy "ver servicios" on public.servicios for select to authenticated using (taller_id = public.mi_taller() or public.is_admin());
drop policy if exists "dueño servicios" on public.servicios;
create policy "dueño servicios" on public.servicios for all to authenticated
  using (public.es_dueno(taller_id)) with check (public.es_dueno(taller_id));

drop policy if exists "ver promos" on public.promos;
create policy "ver promos" on public.promos for select to authenticated using (taller_id = public.mi_taller() or public.is_admin());
drop policy if exists "dueño promos" on public.promos;
create policy "dueño promos" on public.promos for all to authenticated
  using (public.es_dueno(taller_id)) with check (public.es_dueno(taller_id));

drop policy if exists "ver bloqueos" on public.bloqueos;
create policy "ver bloqueos" on public.bloqueos for select to authenticated using (taller_id = public.taller_de(auth.uid()));
drop policy if exists "taller bloqueos" on public.bloqueos;
create policy "taller bloqueos" on public.bloqueos for all to authenticated
  using (taller_id = public.taller_de(auth.uid())) with check (taller_id = public.taller_de(auth.uid()));

drop policy if exists "ver reservas" on public.reservas;
create policy "ver reservas" on public.reservas for select to authenticated
  using (taller_id = public.taller_de(auth.uid()) or cliente_id = auth.uid());

drop policy if exists "mis avisos" on public.notificaciones;
create policy "mis avisos" on public.notificaciones for select to authenticated using (para = auth.uid());
drop policy if exists "leer mis avisos" on public.notificaciones;
create policy "leer mis avisos" on public.notificaciones for update to authenticated
  using (para = auth.uid()) with check (para = auth.uid());
drop policy if exists "borrar mis avisos" on public.notificaciones;
create policy "borrar mis avisos" on public.notificaciones for delete to authenticated using (para = auth.uid());

drop policy if exists "ver textos" on public.textos;
create policy "ver textos" on public.textos for select to anon, authenticated using (true);
drop policy if exists "ver planes" on public.planes;
create policy "ver planes" on public.planes for select to anon, authenticated using (true);

revoke all on all tables in schema public from anon;
revoke insert, update, delete, truncate on all tables in schema public from authenticated;
grant select on public.perfiles, public.talleres, public.servicios, public.promos, public.bloqueos, public.reservas,
  public.notificaciones, public.textos, public.planes to authenticated;
grant select on public.textos, public.planes to anon;
grant insert, update, delete on public.servicios, public.promos, public.bloqueos to authenticated;
grant update (leida), delete on public.notificaciones to authenticated;

-- En vivo (Realtime): avisos y reservas.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'notificaciones') then
      alter publication supabase_realtime add table public.notificaciones;
    end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'reservas') then
      alter publication supabase_realtime add table public.reservas;
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 9. Cuenta y datos públicos
-- ---------------------------------------------------------------------
create or replace function public.config_publica() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'config', (select jsonb_object_agg(clave, valor) from public.config),
    'textos', (select jsonb_object_agg(clave, valor) from public.textos),
    'planes', (select jsonb_object_agg(codigo, jsonb_build_object('nombre', nombre, 'descripcion', descripcion,
                 'limites', limites, 'beneficios', beneficios, 'duracion_dias', duracion_dias)) from public.planes),
    'premium_taller', public.link_publico('premium_taller'),
    'premium_cliente', public.link_publico('premium_cliente'),
    'premium_taller_anual', public.link_publico('premium_taller_anual'),
    'premium_cliente_anual', public.link_publico('premium_cliente_anual'))
$$;

create or replace function public.mi_cuenta() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', p.id, 'email', p.email, 'nombre', p.nombre, 'telefono', p.telefono, 'rol', p.rol,
    'suspendido', p.suspendido or coalesce(t.suspendido, false),
    'is_admin', public.is_admin(),
    'taller_id', p.taller_id,
    'taller', case when t.id is null then null else jsonb_build_object(
       'id', t.id, 'nombre', t.nombre, 'slug', t.slug, 'logo', t.logo, 'color', t.color, 'icono', t.icono,
       'telefono', t.telefono, 'premium', public.taller_es_premium(t.id), 'premium_hasta', t.premium_hasta) end,
    'premium', case when p.rol = 'cliente' then public.cliente_es_premium(p.id)
                    when p.rol in ('taller', 'equipo') then public.taller_es_premium(p.taller_id)
                    else true end,
    'premium_hasta', case when p.rol = 'cliente' then p.premium_hasta else t.premium_hasta end)
  from public.perfiles p left join public.talleres t on t.id = p.taller_id
  where p.id = auth.uid()
$$;

create or replace function public.registrar_visto() returns void
language sql security definer set search_path = '' as $$
  update public.perfiles set visto_at = now()
  where id = auth.uid() and (visto_at is null or visto_at < now() - interval '5 minutes')
$$;

create or replace function public.mi_perfil_guardar(p_nombre text, p_telefono text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if trim(coalesce(p_nombre, '')) = '' then raise exception 'Escribe tu nombre'; end if;
  update public.perfiles set nombre = left(trim(p_nombre), 80), telefono = left(trim(coalesce(p_telefono, '')), 30)
  where id = auth.uid();
end $$;

-- Promedio de estrellas.
create or replace function public.nota_taller(t uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('promedio', round(avg(estrellas)::numeric, 1), 'total', count(*))
  from public.calificaciones where taller_id = t and autor = 'cliente'
$$;
create or replace function public.nota_cliente(tel text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('promedio', round(avg(estrellas)::numeric, 1), 'total', count(*))
  from public.calificaciones where tel_norm = public.tel_norm(tel) and autor = 'taller' and public.tel_norm(tel) <> ''
$$;

-- Página pública del taller (por su enlace).
create or replace function public.taller_publico(p_slug text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', t.id, 'nombre', t.nombre, 'slug', t.slug, 'descripcion', t.descripcion, 'direccion', t.direccion,
    'comuna', t.comuna, 'telefono', t.telefono, 'instagram', t.instagram, 'logo', t.logo, 'color', t.color, 'icono', t.icono,
    'dias', t.dias, 'abre', to_char(t.abre, 'HH24:MI'), 'cierra', to_char(t.cierra, 'HH24:MI'),
    'horarios', t.horarios, 'max_dia', t.max_dia, 'capacidad_dia', t.capacidad_dia,
    'colacion_desde', to_char(t.colacion_desde, 'HH24:MI'), 'colacion_hasta', to_char(t.colacion_hasta, 'HH24:MI'),
    'anticipacion_dias', t.anticipacion_dias, 'hoy', (now() at time zone t.zona)::date,
    'premium', public.taller_es_premium(t.id), 'horas_premium', t.horas_premium,
    'horas_libera_premium', coalesce(public.cfg_int('horas_libera_premium'), 24),
    'reservas_online', t.reservas_online and (public.link_activo(t.id, 'abono')).id is not null,
    'abono', (public.link_activo(t.id, 'abono')).monto,
    'nota', public.nota_taller(t.id),
    'acepta_cuentas', (select count(*) from public.perfiles where taller_id = t.id and rol = 'cliente')
                      < coalesce((public.limite_taller(t.id, 'clientes_cuenta'))::int, 30),
    'servicios', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'nombre', s.nombre, 'descripcion', s.descripcion,
                    'precio', s.precio, 'duracion_min', s.duracion_min, 'adicional', s.adicional) order by s.adicional, s.orden, s.nombre), '[]')
                  from public.servicios s where s.taller_id = t.id and s.activo),
    'promos', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'titulo', o.titulo, 'texto', o.texto, 'precio', o.precio,
                 'precio_antes', o.precio_antes, 'hasta', o.hasta) order by o.created_at desc), '[]')
               from public.promos o where o.taller_id = t.id and o.activa and (o.hasta is null or o.hasta >= (now() at time zone t.zona)::date)))
  from public.talleres t
  where (t.slug = lower(p_slug) or t.id::text = p_slug) and t.activo and not t.suspendido
$$;

-- ---------------------------------------------------------------------
-- 10. Agenda: horas libres (considera duración, cupos, colación,
--     bloqueos y las horas retenidas mientras pagan)
-- ---------------------------------------------------------------------
create or replace function public.ocupa_hora(r public.reservas) returns boolean
language sql stable as $$
  select r.estado not in ('rechazada', 'expirada', 'cancelada')
     and not (r.estado = 'por_pagar' and r.expira_at <= now())
$$;

create or replace function public.horas_libres(p_taller uuid, p_fecha date, p_min int, p_excluir uuid default null)
returns setof text
language plpgsql stable security definer set search_path = '' as $$
declare
  c public.talleres;
  paso int; dur int; ini int; fin int; m int; k int; x int;
  c_ini int; c_fin int; ahora timestamp; ok boolean; n int;
begin
  select * into c from public.talleres where id = p_taller;
  if c.id is null or not c.activo or c.suspendido then return; end if;
  if not (extract(dow from p_fecha)::int = any (c.dias)) then return; end if;
  if exists (select 1 from public.bloqueos b where b.taller_id = p_taller and b.fecha = p_fecha and b.desde is null) then return; end if;
  ahora := now() at time zone c.zona;
  paso := c.bloque_min;
  dur := (ceil(greatest(coalesce(p_min, paso), 1)::numeric / paso) * paso)::int;
  -- Horario propio del día (si tiene) y cupo máximo de bicis por día.
  ini := (extract(epoch from coalesce((c.horarios -> (extract(dow from p_fecha)::int)::text ->> 'abre')::time, c.abre)) / 60)::int;
  fin := (extract(epoch from coalesce((c.horarios -> (extract(dow from p_fecha)::int)::text ->> 'cierra')::time, c.cierra)) / 60)::int;
  if c.max_dia > 0 and (select count(*) from public.reservas r where r.taller_id = p_taller and r.fecha = p_fecha
      and public.ocupa_hora(r) and (p_excluir is null or r.id <> p_excluir)) >= c.max_dia then return; end if;
  c_ini := (extract(epoch from c.colacion_desde) / 60)::int;
  c_fin := (extract(epoch from c.colacion_hasta) / 60)::int;
  m := ini;
  while m + dur <= fin loop
    ok := true;
    if p_fecha + make_interval(mins => m) <= ahora + interval '30 minutes' then ok := false; end if;
    if ok and c_ini is not null and m < c_fin and m + dur > c_ini then ok := false; end if;
    if ok and exists (select 1 from public.bloqueos b where b.taller_id = p_taller and b.fecha = p_fecha and b.desde is not null
                      and m < (extract(epoch from b.hasta) / 60)::int and m + dur > (extract(epoch from b.desde) / 60)::int) then
      ok := false;
    end if;
    k := 0;
    while ok and k * paso < dur loop
      x := m + k * paso;
      select count(*) into n from public.reservas r
      where r.taller_id = p_taller and r.fecha = p_fecha and public.ocupa_hora(r)
        and (p_excluir is null or r.id <> p_excluir)
        and x < (extract(epoch from r.hora_fin) / 60)::int and x + paso > (extract(epoch from r.hora) / 60)::int;
      if n >= c.cupos then ok := false; end if;
      k := k + 1;
    end loop;
    if ok then return next to_char(make_time(m / 60, m % 60, 0), 'HH24:MI'); end if;
    m := m + paso;
  end loop;
end $$;

-- Hora exclusiva Premium que todavía no se abre a todos (y quien reserva no es cliente Premium).
create or replace function public.hora_premium_cerrada(p_taller uuid, p_fecha date, p_hora text, p_cliente uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select left(p_hora, 5) = any (t.horas_premium)
                     and (p_fecha + left(p_hora, 5)::time) at time zone t.zona
                         > now() + make_interval(hours => coalesce(public.cfg_int('horas_libera_premium'), 24))
                   from public.talleres t where t.id = p_taller), false)
     and not public.cliente_es_premium(p_cliente)
$$;

-- Días con horas libres (para pintar el calendario de reserva).
create or replace function public.dias_libres(p_taller uuid, p_min int) returns setof date
language plpgsql stable security definer set search_path = '' as $$
declare c public.talleres; d date; hoy date; extra int := 0; me public.perfiles;
begin
  select * into c from public.talleres where id = p_taller and activo and not suspendido;
  if c.id is null then return; end if;
  select * into me from public.perfiles where id = auth.uid();
  if me.rol = 'cliente' and (me.taller_id = p_taller or public.cliente_es_premium(me.id)) then
    extra := coalesce((public.limite_cliente(me.id, 'anticipacion_extra'))::int, 0);
  end if;
  hoy := (now() at time zone c.zona)::date;
  for d in select generate_series(hoy, hoy + c.anticipacion_dias + extra, interval '1 day')::date loop
    if exists (select 1 from public.horas_libres(p_taller, d, p_min)) then return next d; end if;
  end loop;
end $$;

create or replace function public.minutos_servicio(p_taller uuid, p_servicio uuid) returns int
language sql stable security definer set search_path = '' as $$
  select coalesce((select duracion_min from public.servicios where id = p_servicio and taller_id = p_taller),
                  (select bloque_min from public.talleres where id = p_taller))
$$;

create or replace function public.historial_mas(h jsonb, e text) returns jsonb
language sql stable as $$
  select coalesce(h, '[]'::jsonb) || jsonb_build_object('estado', e, 'at', now(), 'por', auth.uid())
$$;

-- ---------------------------------------------------------------------
-- 11. Reservar (sin cuenta o con cuenta de cliente)
-- ---------------------------------------------------------------------
drop function if exists public.reservar(uuid, uuid, date, text, text, text, text, text, text);
create or replace function public.reservar(p_taller uuid, p_servicio uuid, p_fecha date, p_hora text,
  p_nombre text, p_telefono text, p_email text, p_bici text, p_nota text, p_extras uuid[] default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  ex jsonb; ex_nombres text; ex_precio int; ent date;
  c public.talleres; s public.servicios; me public.perfiles; l public.links_pago;
  hoy date; extra int := 0; mins int; nom text; tel text; r public.reservas; n int;
begin
  select * into c from public.talleres where id = p_taller and activo and not suspendido;
  if c.id is null or not c.reservas_online then return jsonb_build_object('ok', false, 'error', 'Este taller no está recibiendo reservas online'); end if;
  l := public.link_activo(p_taller, 'abono');
  if l.id is null then return jsonb_build_object('ok', false, 'error', 'El taller aún no configura el pago del abono'); end if;
  select * into me from public.perfiles where id = auth.uid();
  -- Con cuenta: en su taller, o en cualquier taller si es cliente Premium.
  if me.id is not null and (me.rol <> 'cliente' or (me.taller_id <> p_taller and not public.cliente_es_premium(me.id))) then me := null; end if;
  if me.id is not null then extra := coalesce((public.limite_cliente(me.id, 'anticipacion_extra'))::int, 0); end if;
  nom := left(trim(coalesce(nullif(trim(p_nombre), ''), me.nombre, '')), 80);
  tel := left(trim(coalesce(nullif(trim(p_telefono), ''), me.telefono, '')), 30);
  if nom = '' then return jsonb_build_object('ok', false, 'error', 'Escribe tu nombre'); end if;
  if length(public.tel_norm(tel)) < 9 then return jsonb_build_object('ok', false, 'error', 'Escribe tu WhatsApp'); end if;
  if p_servicio is not null then
    select * into s from public.servicios where id = p_servicio and taller_id = p_taller and activo and not adicional;
    if s.id is null then return jsonb_build_object('ok', false, 'error', 'Elige un servicio'); end if;
  end if;
  hoy := (now() at time zone c.zona)::date;
  if p_fecha < hoy or p_fecha > hoy + c.anticipacion_dias + extra then
    return jsonb_build_object('ok', false, 'error', 'Esa fecha no está disponible');
  end if;
  -- Límite del plan del taller (reservas online del mes).
  select count(*) into n from public.reservas
  where taller_id = p_taller and origen <> 'taller' and estado not in ('expirada', 'rechazada')
    and created_at >= date_trunc('month', now());
  if n >= coalesce((public.limite_taller(p_taller, 'reservas_mes'))::int, 30) then
    return jsonb_build_object('ok', false, 'error', 'El taller no tiene más cupos online este mes. Escríbele por WhatsApp.');
  end if;
  -- Anti-abuso: máximo 2 reservas activas por teléfono en el taller.
  select count(*) into n from public.reservas z
  where z.taller_id = p_taller and z.tel_norm = public.tel_norm(tel) and z.fecha >= hoy
    and z.estado in ('por_pagar', 'en_revision', 'confirmada') and public.ocupa_hora(z);
  if n >= 2 then return jsonb_build_object('ok', false, 'error', 'Ya tienes 2 reservas activas en este taller'); end if;

  perform pg_advisory_xact_lock(hashtext('reserva:' || p_taller::text || p_fecha::text));
  mins := coalesce(s.duracion_min, c.bloque_min);
  if not exists (select 1 from public.horas_libres(p_taller, p_fecha, mins) h where h = p_hora) then
    return jsonb_build_object('ok', false, 'error', 'Esa hora ya no está disponible. Elige otra.');
  end if;
  if public.hora_premium_cerrada(p_taller, p_fecha, p_hora, me.id) then
    return jsonb_build_object('ok', false, 'error', 'Esa hora es exclusiva para clientes Premium. Elige otra o hazte Premium.');
  end if;
  mins := (ceil(mins::numeric / c.bloque_min) * c.bloque_min)::int;
  -- Entrega estimada según la cola del taller (si calcula capacidad diaria).
  ent := public.estimar_entrega(p_taller, p_fecha, p_hora::time, null);
  if ent is not null and ent > p_fecha + c.max_espera_dias then
    return jsonb_build_object('ok', false, 'error', 'Ese día el taller ya tiene la cola llena. Elige otro día.');
  end if;
  -- Servicios adicionales (suman precio, no tiempo de agenda).
  select coalesce(jsonb_agg(jsonb_build_object('nombre', x.nombre, 'cant', 1, 'precio', x.precio) order by x.nombre), '[]'),
         string_agg(x.nombre, ' + ' order by x.nombre), coalesce(sum(x.precio), 0)
    into ex, ex_nombres, ex_precio
  from public.servicios x where x.taller_id = p_taller and x.activo and x.adicional and x.id = any (coalesce(p_extras, '{}'));
  insert into public.reservas (taller_id, servicio_id, servicio_nombre, precio, fecha, hora, hora_fin, nombre, telefono, tel_norm,
    email, bici, nota, cliente_id, origen, estado, expira_at, abono_monto, abono_estado, historial, items, total, entrega_estimada)
  values (p_taller, s.id, left(coalesce(s.nombre, 'Revisión general') || coalesce(' + ' || ex_nombres, ''), 300), coalesce(s.precio, 0) + ex_precio, p_fecha, p_hora::time,
    p_hora::time + make_interval(mins => mins), nom, tel, public.tel_norm(tel),
    left(lower(trim(coalesce(nullif(p_email, ''), me.email, ''))), 120), left(trim(coalesce(p_bici, '')), 120),
    left(trim(coalesce(p_nota, '')), 500), me.id, case when me.id is null then 'online' else 'cliente' end,
    'por_pagar', now() + make_interval(mins => coalesce(public.cfg_int('minutos_pago'), 30)), l.monto, 'pendiente',
    public.historial_mas('[]', 'por_pagar'),
    case when s.id is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('nombre', s.nombre, 'cant', 1, 'precio', s.precio)) end || ex,
    coalesce(s.precio, 0) + ex_precio, ent)
  returning * into r;
  perform public.avisar_taller(p_taller, '📅 Nueva reserva', nom || ' · ' || to_char(p_fecha, 'DD/MM') || ' ' || p_hora ||
    ' · esperando abono', '/taller/#reservas');
  return jsonb_build_object('ok', true, 'token', r.token);
end $$;

-- ¿Quien tiene el enlace de la reserva puede ver sus fotos antes/después?
create or replace function public.fotos_visibles(r public.reservas) returns boolean
language sql stable security definer set search_path = '' as $$
  select r.estado <> 'completada' or r.completada_at > now() - interval '7 days' or public.cliente_es_premium(r.cliente_id)
$$;

-- Detalle de la reserva por su enlace (sin cuenta).
create or replace function public.reserva_estado_vencido(r public.reservas) returns public.reservas
language plpgsql security definer set search_path = '' as $$
begin
  if r.estado = 'por_pagar' and r.expira_at <= now() then
    update public.reservas set estado = 'expirada', abono_estado = 'no_pagado', historial = public.historial_mas(historial, 'expirada'),
      updated_at = now() where id = r.id returning * into r;
  end if;
  return r;
end $$;

create or replace function public.reserva_ver(p_token text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r public.reservas; c public.talleres; l public.links_pago; cita timestamptz; dev int; hrs int; tipo text;
begin
  select * into r from public.reservas where token = p_token and length(p_token) >= 20;
  if r.id is null then return null; end if;
  r := public.reserva_estado_vencido(r);
  select * into c from public.talleres where id = r.taller_id;
  l := public.link_activo(r.taller_id, 'abono');
  cita := (r.fecha + r.hora) at time zone c.zona;
  dev := coalesce(public.cfg_int('minutos_devolucion'), 10);
  hrs := coalesce(public.cfg_int('horas_cancelacion'), 24);
  tipo := case
    when r.estado = 'por_pagar' then 'libre'
    when r.estado not in ('en_revision', 'confirmada') then null
    when now() - r.created_at <= make_interval(mins => dev) and r.reagendada = 0 then 'devolucion'
    when cita - now() >= make_interval(hours => hrs) then 'saldo'
    else 'pierde' end;
  return jsonb_build_object(
    'token', r.token, 'estado', r.estado, 'abono_estado', r.abono_estado, 'abono_monto', r.abono_monto,
    'expira_at', r.expira_at, 'fecha', r.fecha, 'hora', to_char(r.hora, 'HH24:MI'), 'servicio', r.servicio_nombre,
    'servicio_id', r.servicio_id, 'minutos', (extract(epoch from (r.hora_fin - r.hora)) / 60)::int, 'precio', r.precio, 'nombre', r.nombre, 'telefono', r.telefono, 'bici', r.bici,
    'motivo', r.motivo, 'items', r.items, 'total', r.total, 'diagnostico', r.diagnostico,
    'proxima_mantencion', r.proxima_mantencion, 'saldo_hasta', r.saldo_hasta, 'created_at', r.created_at, 'entrega_estimada', r.entrega_estimada,
    'historial', (select coalesce(jsonb_agg(jsonb_build_object('estado', h ->> 'estado', 'at', h ->> 'at')), '[]') from jsonb_array_elements(r.historial) h),
    'cita', cita, 'cancelar', tipo,
    'reagendar', (r.estado = 'confirmada' and cita - now() >= make_interval(hours => hrs))
              or (r.estado = 'cancelada' and r.abono_estado = 'saldo' and r.saldo_hasta > now()),
    'pagar_url', case when r.estado = 'por_pagar' then l.url end,
    'calificada', exists (select 1 from public.calificaciones where reserva_id = r.id and autor = 'cliente'),
    -- Fotos antes/después: se ven durante el trabajo y una semana después; luego, solo el cliente Premium.
    'fotos_n', (select count(*) from public.fotos_trabajo f where f.reserva_id = r.id),
    'fotos_visibles', public.fotos_visibles(r),
    'taller', jsonb_build_object('id', c.id, 'nombre', c.nombre, 'slug', c.slug, 'telefono', c.telefono, 'logo', c.logo,
      'color', c.color, 'icono', c.icono, 'direccion', c.direccion, 'comuna', c.comuna),
    'minutos_devolucion', dev, 'horas_cancelacion', hrs);
end $$;

-- El cliente sube la foto del comprobante del abono.
create or replace function public.reserva_comprobante(p_token text, p_imagen text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r public.reservas;
begin
  select * into r from public.reservas where token = p_token and length(p_token) >= 20 for update;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'Reserva no encontrada'); end if;
  r := public.reserva_estado_vencido(r);
  if r.estado = 'expirada' then return jsonb_build_object('ok', false, 'error', 'Se acabó el tiempo para pagar y la hora se liberó. Reserva de nuevo.'); end if;
  if r.estado <> 'por_pagar' then return jsonb_build_object('ok', false, 'error', 'Esta reserva ya tiene comprobante'); end if;
  if p_imagen !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$' or length(p_imagen) > 600000 then
    return jsonb_build_object('ok', false, 'error', 'Imagen no válida o muy pesada');
  end if;
  delete from public.comprobantes where reserva_id = r.id;
  insert into public.comprobantes (reserva_id, imagen) values (r.id, p_imagen);
  update public.reservas set estado = 'en_revision', abono_estado = 'en_revision', comprobante_at = now(), expira_at = null,
    historial = public.historial_mas(historial, 'en_revision'), updated_at = now() where id = r.id;
  perform public.avisar_taller(r.taller_id, '🧾 Comprobante por revisar', r.nombre || ' · ' || to_char(r.fecha, 'DD/MM') || ' ' ||
    to_char(r.hora, 'HH24:MI') || ' · $' || r.abono_monto, '/taller/#reservas');
  return jsonb_build_object('ok', true);
end $$;

-- Cancelar según las reglas (10 minutos: se devuelve · 24 h: saldo a favor · después: se pierde).
create or replace function public.reserva_cancelar(p_token text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v jsonb; r public.reservas; ab text; msg text;
begin
  v := public.reserva_ver(p_token);
  if v is null then return jsonb_build_object('ok', false, 'error', 'Reserva no encontrada'); end if;
  if v ->> 'cancelar' is null then return jsonb_build_object('ok', false, 'error', 'Esta reserva ya no se puede cancelar'); end if;
  select * into r from public.reservas where token = p_token for update;
  ab := case v ->> 'cancelar'
          when 'libre' then 'no_pagado'
          when 'devolucion' then case when r.estado = 'en_revision' or r.estado = 'confirmada' then 'devolver' else 'no_pagado' end
          when 'saldo' then 'saldo'
          else 'perdido' end;
  update public.reservas set estado = 'cancelada', abono_estado = ab, expira_at = null,
    saldo_hasta = case when ab = 'saldo' then now() + make_interval(days => coalesce(public.cfg_int('dias_saldo'), 90)) end,
    historial = public.historial_mas(historial, 'cancelada'), updated_at = now()
  where id = r.id;
  msg := case ab when 'devolver' then 'Devuelve el abono de $' || r.abono_monto || ' a ' || r.nombre || ' (' || r.telefono || ')'
                 when 'saldo' then 'Queda con saldo a favor de $' || r.abono_monto || ' para reagendar'
                 when 'perdido' then 'Canceló tarde: pierde el abono'
                 else 'Canceló antes de pagar' end;
  perform public.avisar_taller(r.taller_id, case when ab = 'devolver' then '💸 Cancelación: devolver abono' else '❌ Reserva cancelada' end,
    r.nombre || ' · ' || to_char(r.fecha, 'DD/MM') || ' ' || to_char(r.hora, 'HH24:MI') || ' · ' || msg, '/taller/#reservas');
  return jsonb_build_object('ok', true, 'abono', ab);
end $$;

-- Reagendar (con 24 h de anticipación, o usando el saldo a favor).
create or replace function public.reserva_reagendar(p_token text, p_fecha date, p_hora text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v jsonb; r public.reservas; c public.talleres; hoy date; mins int; extra int := 0;
begin
  v := public.reserva_ver(p_token);
  if v is null then return jsonb_build_object('ok', false, 'error', 'Reserva no encontrada'); end if;
  if not (v ->> 'reagendar')::boolean then
    return jsonb_build_object('ok', false, 'error', 'Ya no se puede reagendar (faltan menos de ' || (v ->> 'horas_cancelacion') || ' horas o venció el saldo)');
  end if;
  select * into r from public.reservas where token = p_token for update;
  select * into c from public.talleres where id = r.taller_id and activo and not suspendido;
  if c.id is null then return jsonb_build_object('ok', false, 'error', 'El taller no está recibiendo reservas'); end if;
  if r.cliente_id is not null then extra := coalesce((public.limite_cliente(r.cliente_id, 'anticipacion_extra'))::int, 0); end if;
  hoy := (now() at time zone c.zona)::date;
  if p_fecha < hoy or p_fecha > hoy + c.anticipacion_dias + extra then return jsonb_build_object('ok', false, 'error', 'Esa fecha no está disponible'); end if;
  perform pg_advisory_xact_lock(hashtext('reserva:' || r.taller_id::text || p_fecha::text));
  mins := (extract(epoch from (r.hora_fin - r.hora)) / 60)::int;
  if not exists (select 1 from public.horas_libres(r.taller_id, p_fecha, mins, r.id) h where h = p_hora) then
    return jsonb_build_object('ok', false, 'error', 'Esa hora ya no está disponible. Elige otra.');
  end if;
  if public.hora_premium_cerrada(r.taller_id, p_fecha, p_hora, r.cliente_id) then
    return jsonb_build_object('ok', false, 'error', 'Esa hora es exclusiva para clientes Premium. Elige otra.');
  end if;
  update public.reservas set fecha = p_fecha, hora = p_hora::time, hora_fin = p_hora::time + make_interval(mins => mins),
    estado = 'confirmada', abono_estado = 'pagado', saldo_hasta = null, recordado = false, reagendada = reagendada + 1,
    entrega_estimada = public.estimar_entrega(r.taller_id, p_fecha, p_hora::time, r.id),
    historial = public.historial_mas(historial, 'reagendada'), updated_at = now()
  where id = r.id;
  perform public.avisar_taller(r.taller_id, '🔁 Reserva reagendada', r.nombre || ' · ahora el ' || to_char(p_fecha, 'DD/MM') || ' ' || p_hora,
    '/taller/#agenda');
  return jsonb_build_object('ok', true);
end $$;

-- El cliente califica al taller (después de la visita).
create or replace function public.reserva_calificar(p_token text, p_estrellas int, p_comentario text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r public.reservas;
begin
  select * into r from public.reservas where token = p_token and length(p_token) >= 20;
  if r.id is null or r.estado not in ('completada', 'lista') then
    return jsonb_build_object('ok', false, 'error', 'Podrás calificar cuando el taller termine tu servicio');
  end if;
  if p_estrellas not between 1 and 5 then return jsonb_build_object('ok', false, 'error', 'Elige de 1 a 5 estrellas'); end if;
  insert into public.calificaciones (reserva_id, taller_id, autor, estrellas, comentario)
  values (r.id, r.taller_id, 'cliente', p_estrellas, left(trim(coalesce(p_comentario, '')), 300))
  on conflict (reserva_id, autor) do update set estrellas = excluded.estrellas, comentario = excluded.comentario, created_at = now();
  perform public.avisar_taller(r.taller_id, '⭐ Nueva calificación', r.nombre || ' te calificó con ' || p_estrellas || ' estrellas', '/taller/#mas');
  return jsonb_build_object('ok', true);
end $$;

-- App del cliente con cuenta.
create or replace function public.cliente_inicio() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare me public.perfiles; t public.talleres; lim int;
begin
  select * into me from public.perfiles where id = auth.uid() and rol = 'cliente';
  if me.id is null then return null; end if;
  select * into t from public.talleres where id = me.taller_id;
  lim := coalesce((public.limite_cliente(me.id, 'historial'))::int, 3);
  return jsonb_build_object(
    'taller', public.taller_publico(t.slug),
    'premium', public.cliente_es_premium(me.id), 'premium_hasta', me.premium_hasta,
    'mi_nota', public.nota_cliente(me.telefono),
    'activas', (select coalesce(jsonb_agg(jsonb_build_object('token', r.token, 'estado', r.estado, 'fecha', r.fecha,
                  'hora', to_char(r.hora, 'HH24:MI'), 'servicio', r.servicio_nombre, 'abono_estado', r.abono_estado,
                  'saldo_hasta', r.saldo_hasta, 'otro_taller', case when r.taller_id <> me.taller_id
                    then (select nombre from public.talleres where id = r.taller_id) end) order by r.fecha, r.hora), '[]')
                from public.reservas r where r.cliente_id = me.id
                  and ((r.estado in ('por_pagar', 'en_revision', 'confirmada', 'recibida', 'en_reparacion', 'esperando_repuesto', 'lista')
                        and public.ocupa_hora(r))
                       or (r.estado = 'cancelada' and r.abono_estado = 'saldo' and r.saldo_hasta > now()))),
    'historial', (select coalesce(jsonb_agg(x order by x.fecha desc), '[]') from (
                  select r.token, r.estado, r.fecha, to_char(r.hora, 'HH24:MI') as hora, r.servicio_nombre as servicio, r.total,
                         r.bici, r.diagnostico, r.items, r.proxima_mantencion,
                         (select t2.nombre from public.talleres t2 where t2.id = r.taller_id) as taller,
                         (select count(*) from public.fotos_trabajo f where f.reserva_id = r.id) as fotos,
                         exists (select 1 from public.calificaciones q where q.reserva_id = r.id and q.autor = 'cliente') as calificada
                  from public.reservas r where r.cliente_id = me.id and r.estado in ('completada', 'no_asistio')
                  order by r.fecha desc limit lim) x),
    'limite_historial', lim);
end $$;

-- ---------------------------------------------------------------------
-- 12. Panel del taller (dueño y equipo)
-- ---------------------------------------------------------------------
create or replace function public.taller_panel() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare t public.talleres; tid uuid := public.taller_de(auth.uid()); hoy date; dueno boolean;
begin
  if tid is null then raise exception 'Sin acceso al taller'; end if;
  select * into t from public.talleres where id = tid;
  hoy := (now() at time zone t.zona)::date;
  dueno := public.es_dueno(tid);
  return jsonb_build_object(
    'taller', to_jsonb(t) - 'aviso_venc_para' - 'aviso_vencido_para',
    'dueno', dueno, 'hoy', hoy, 'premium', public.taller_es_premium(tid),
    'plan', (select jsonb_build_object('codigo', codigo, 'nombre', nombre, 'limites', limites) from public.planes
             where codigo = case when public.taller_es_premium(tid) then 'taller_premium' else 'taller_free' end),
    'nota', public.nota_taller(tid),
    'uso', jsonb_build_object(
      'reservas_mes', (select count(*) from public.reservas where taller_id = tid and origen <> 'taller'
                        and estado not in ('expirada', 'rechazada') and created_at >= date_trunc('month', now())),
      'servicios', (select count(*) from public.servicios where taller_id = tid),
      'promos', (select count(*) from public.promos where taller_id = tid and activa),
      'equipo', (select count(*) from public.perfiles where taller_id = tid and rol = 'equipo'),
      'clientes_cuenta', (select count(*) from public.perfiles where taller_id = tid and rol = 'cliente')),
    'equipo', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nombre', coalesce(nullif(p.nombre, ''), p.email), 'email', p.email,
                 'rol', p.rol, 'suspendido', p.suspendido, 'visto_at', p.visto_at) order by p.rol desc, p.created_at), '[]')
               from public.perfiles p where p.taller_id = tid and p.rol in ('taller', 'equipo')),
    'links', case when dueno then (select coalesce(jsonb_agg(jsonb_build_object('slot', l.slot, 'monto', l.monto, 'url', l.url,
                 'texto', l.texto, 'activo', l.activo) order by l.slot), '[]') from public.links_pago l where l.taller_id = tid and l.tipo = 'abono') end,
    'pago_pendiente', (select jsonb_build_object('id', id, 'monto', monto, 'created_at', created_at) from public.pagos
                       where taller_id = tid and tipo = 'premium_taller' and estado = 'en_revision' order by created_at desc limit 1),
    'por_revisar', (select count(*) from public.reservas where taller_id = tid and estado = 'en_revision'),
    'por_devolver', (select count(*) from public.reservas where taller_id = tid and abono_estado = 'devolver'));
end $$;

create or replace function public.taller_guardar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); sl text;
begin
  if tid is null or not public.es_dueno(tid) then raise exception 'Solo el dueño del taller puede cambiar esto'; end if;
  if p ? 'slug' then
    sl := public.slug_de(p ->> 'slug');
    if exists (select 1 from public.talleres where slug = sl and id <> tid) then raise exception 'Ese enlace ya lo usa otro taller'; end if;
  end if;
  update public.talleres set
    nombre = coalesce(nullif(trim(p ->> 'nombre'), ''), nombre),
    slug = coalesce(sl, slug),
    descripcion = coalesce(p ->> 'descripcion', descripcion),
    direccion = coalesce(p ->> 'direccion', direccion),
    comuna = coalesce(p ->> 'comuna', comuna),
    telefono = coalesce(p ->> 'telefono', telefono),
    instagram = coalesce(p ->> 'instagram', instagram),
    logo = case when p ? 'logo' then nullif(p ->> 'logo', '') else logo end,
    color = coalesce(p ->> 'color', color),
    icono = coalesce(nullif(p ->> 'icono', ''), icono),
    dias = coalesce((select array_agg(x::int) from jsonb_array_elements_text(p -> 'dias') x), dias),
    abre = coalesce((p ->> 'abre')::time, abre),
    cierra = coalesce((p ->> 'cierra')::time, cierra),
    colacion_desde = case when p ? 'colacion_desde' then nullif(p ->> 'colacion_desde', '')::time else colacion_desde end,
    colacion_hasta = case when p ? 'colacion_hasta' then nullif(p ->> 'colacion_hasta', '')::time else colacion_hasta end,
    bloque_min = coalesce((p ->> 'bloque_min')::int, bloque_min),
    cupos = coalesce((p ->> 'cupos')::int, cupos),
    anticipacion_dias = coalesce((p ->> 'anticipacion_dias')::int, anticipacion_dias),
    meses_mantencion = coalesce((p ->> 'meses_mantencion')::int, meses_mantencion),
    reservas_online = coalesce((p ->> 'reservas_online')::boolean, reservas_online),
    horarios = case when p ? 'horarios' and jsonb_typeof(p -> 'horarios') = 'object' then p -> 'horarios' else horarios end,
    max_dia = coalesce(least(greatest((p ->> 'max_dia')::int, 0), 200), max_dia),
    capacidad_dia = coalesce(least(greatest((p ->> 'capacidad_dia')::int, 0), 100), capacidad_dia),
    max_espera_dias = coalesce(least(greatest((p ->> 'max_espera_dias')::int, 1), 120), max_espera_dias),
    en_directorio = coalesce((p ->> 'en_directorio')::boolean, en_directorio),
    horas_premium = case when jsonb_typeof(p -> 'horas_premium') = 'array' then
      (select coalesce(array_agg(distinct left(x, 5) order by left(x, 5)), '{}') from jsonb_array_elements_text(p -> 'horas_premium') x
       where x ~ '^([01][0-9]|2[0-3]):[0-5][0-9]') else horas_premium end
  where id = tid;
  if cardinality((select horas_premium from public.talleres where id = tid)) > 12 then
    raise exception 'Máximo 12 horas exclusivas Premium';
  end if;
  if exists (select 1 from public.talleres t, jsonb_each(t.horarios) h where t.id = tid
             and (h.value ->> 'cierra')::time <= (h.value ->> 'abre')::time) then
    raise exception 'Revisa el horario: el cierre debe ser después de la apertura';
  end if;
  return public.taller_panel();
end $$;

-- Links de pago del abono (2 espacios, uno activo).
drop function if exists public.link_guardar(text, int, int, text, text, boolean);
create or replace function public.link_guardar(p_tipo text, p_slot int, p_monto int, p_url text, p_texto text, p_activar boolean,
  p_hasta date default null)
returns void
language plpgsql security definer set search_path = '' as $$
declare tid uuid;
begin
  if p_tipo = 'abono' then
    tid := public.taller_de(auth.uid());
    if tid is null or not public.es_dueno(tid) then raise exception 'Solo el dueño del taller'; end if;
  elsif p_tipo in ('premium_taller', 'premium_cliente', 'premium_taller_anual', 'premium_cliente_anual') then
    if not public.is_admin() then raise exception 'Solo el administrador'; end if;
    tid := null;
  else raise exception 'Tipo no válido'; end if;
  if p_slot not in (1, 2) then raise exception 'Espacio no válido'; end if;
  if coalesce(p_url, '') <> '' and p_url !~ '^https://' then raise exception 'El link debe empezar con https://'; end if;
  if p_activar and (coalesce(p_url, '') = '' or coalesce(p_monto, 0) <= 0) then raise exception 'Para activarlo pon el monto y el link'; end if;
  insert into public.links_pago (taller_id, tipo, slot, monto, url, texto, activo, hasta)
  values (tid, p_tipo, p_slot, greatest(coalesce(p_monto, 0), 0), coalesce(p_url, ''), left(coalesce(p_texto, ''), 300), coalesce(p_activar, false),
          case when tid is null and p_slot = 2 then p_hasta end)
  on conflict (coalesce(taller_id, '00000000-0000-0000-0000-000000000000'::uuid), tipo, slot)
  do update set monto = excluded.monto, url = excluded.url, texto = excluded.texto, activo = excluded.activo, hasta = excluded.hasta, updated_at = now();
  -- Abono: un solo espacio activo. Premium: el normal y la promoción conviven (gana la promoción vigente).
  if p_activar and tid is not null then
    update public.links_pago set activo = false where tipo = p_tipo and taller_id is not distinct from tid and slot <> p_slot;
  end if;
  if tid is null then perform public.auditar('link', p_tipo || case when p_slot = 2 then ' promoción' else ' normal' end || ' $' || p_monto ||
    case when p_activar then ' (activo' || coalesce(' hasta ' || to_char(p_hasta, 'DD/MM/YYYY'), '') || ')' else ' (apagado)' end); end if;
end $$;

-- Reservas del taller en un rango de fechas (con la nota del cliente).
drop function if exists public.taller_reservas(date, date, text[]);
create or replace function public.taller_reservas(p_desde date, p_hasta date, p_estados text[] default null, p_id uuid default null) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(x order by x.fecha, x.hora), '[]') from (
    select r.id, r.fecha, to_char(r.hora, 'HH24:MI') as hora, to_char(r.hora_fin, 'HH24:MI') as hora_fin, r.nombre, r.telefono,
      r.email, r.bici, r.nota, r.servicio_id, r.servicio_nombre, r.precio, r.estado, r.abono_monto, r.abono_estado, r.expira_at,
      r.origen, r.cliente_id, r.mecanico_id, r.items, r.total, r.diagnostico, r.notas_internas, r.proxima_mantencion,
      r.token, r.motivo, r.reagendada, r.created_at, r.comprobante_at, r.saldo_hasta, r.entrega_estimada,
      exists (select 1 from public.comprobantes k where k.reserva_id = r.id) as tiene_comprobante,
      public.nota_cliente(r.telefono) as nota_cliente,
      exists (select 1 from public.calificaciones q where q.reserva_id = r.id and q.autor = 'taller') as calificado,
      (select count(*) from public.reservas z where z.taller_id = r.taller_id and z.tel_norm = r.tel_norm and z.estado = 'no_asistio') as faltas
    from public.reservas r
    where r.taller_id = public.taller_de(auth.uid())
      and ((p_id is not null and r.id = p_id) or (p_id is null
        and ((r.fecha between p_desde and p_hasta) or (p_estados is not null and r.estado = any (p_estados)))
        and (p_estados is null or r.estado = any (p_estados))
        and not (r.estado = 'por_pagar' and r.expira_at <= now())))
  ) x
$$;

create or replace function public.taller_comprobante(p_id uuid) returns text
language sql stable security definer set search_path = '' as $$
  select k.imagen from public.comprobantes k join public.reservas r on r.id = k.reserva_id
  where k.reserva_id = p_id and r.taller_id = public.taller_de(auth.uid())
  order by k.created_at desc limit 1
$$;

-- Aprobar o rechazar el comprobante del abono.
create or replace function public.taller_revisar(p_id uuid, p_aprobar boolean, p_motivo text) returns void
language plpgsql security definer set search_path = '' as $$
declare r public.reservas;
begin
  select * into r from public.reservas where id = p_id and taller_id = public.taller_de(auth.uid()) for update;
  if r.id is null then raise exception 'Reserva no encontrada'; end if;
  if r.estado <> 'en_revision' then raise exception 'Esta reserva no está en revisión'; end if;
  update public.reservas set
    estado = case when p_aprobar then 'confirmada' else 'rechazada' end,
    abono_estado = case when p_aprobar then 'pagado' else 'rechazado' end,
    motivo = case when p_aprobar then '' else left(coalesce(p_motivo, ''), 300) end,
    historial = public.historial_mas(historial, case when p_aprobar then 'confirmada' else 'rechazada' end), updated_at = now()
  where id = r.id;
  perform public.avisar(r.cliente_id, case when p_aprobar then '✅ Reserva confirmada' else '❌ Comprobante rechazado' end,
    to_char(r.fecha, 'DD/MM') || ' ' || to_char(r.hora, 'HH24:MI') || case when p_aprobar then ' · ¡Te esperamos!' else ' · ' || coalesce(p_motivo, '') end,
    '/r/?t=' || r.token);
end $$;

-- Cambiar el estado del trabajo (recibida → reparación → lista → completada, no llegó, cancelar).
create or replace function public.taller_estado(p_id uuid, p_estado text) returns void
language plpgsql security definer set search_path = '' as $$
declare r public.reservas; c public.talleres; ab text;
begin
  select * into r from public.reservas where id = p_id and taller_id = public.taller_de(auth.uid()) for update;
  if r.id is null then raise exception 'Reserva no encontrada'; end if;
  if p_estado not in ('confirmada', 'recibida', 'en_reparacion', 'esperando_repuesto', 'lista', 'completada', 'no_asistio', 'cancelada') then
    raise exception 'Estado no válido';
  end if;
  if r.estado in ('por_pagar', 'en_revision', 'rechazada', 'expirada', 'cancelada') then
    raise exception 'Primero confirma la reserva (revisa el comprobante)';
  end if;
  select * into c from public.talleres where id = r.taller_id;
  ab := r.abono_estado;
  if p_estado = 'completada' and ab = 'pagado' then ab := 'aplicado'; end if;
  if p_estado = 'no_asistio' and ab = 'pagado' then ab := 'perdido'; end if;
  if p_estado = 'cancelada' and ab = 'pagado' then ab := 'devolver'; end if;
  update public.reservas set estado = p_estado, abono_estado = ab,
    completada_at = case when p_estado = 'completada' then now() else completada_at end,
    proxima_mantencion = case when p_estado = 'completada' and proxima_mantencion is null
                              then (current_date + make_interval(months => c.meses_mantencion))::date else proxima_mantencion end,
    historial = public.historial_mas(historial, p_estado), updated_at = now()
  where id = r.id;
  perform public.avisar(r.cliente_id,
    case p_estado when 'recibida' then '🚲 Recibimos tu bici' when 'en_reparacion' then '🔧 Tu bici está en reparación'
      when 'esperando_repuesto' then '📦 Esperando un repuesto' when 'lista' then '✅ ¡Tu bici está lista!'
      when 'completada' then '🎉 ¡Gracias por venir!' when 'no_asistio' then '🚫 No llegaste a tu hora'
      when 'cancelada' then '❌ El taller canceló tu reserva' else '📅 Reserva actualizada' end,
    c.nombre || ' · ' || to_char(r.fecha, 'DD/MM'), '/r/?t=' || r.token);
end $$;

-- Detalle del trabajo: servicios y repuestos, diagnóstico, mecánico.
create or replace function public.taller_trabajo(p_id uuid, p_items jsonb, p_diagnostico text, p_notas text,
  p_mecanico uuid, p_proxima date) returns void
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); tot int;
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  if jsonb_typeof(p_items) <> 'array' then raise exception 'Ítems no válidos'; end if;
  if p_mecanico is not null and not exists (select 1 from public.perfiles where id = p_mecanico and taller_id = tid and rol in ('taller', 'equipo')) then
    raise exception 'Mecánico no válido';
  end if;
  select coalesce(sum(greatest(coalesce((i ->> 'cant')::numeric, 1), 0) * greatest(coalesce((i ->> 'precio')::numeric, 0), 0)), 0)::int
    into tot from jsonb_array_elements(p_items) i;
  update public.reservas set items = p_items, total = tot, diagnostico = left(coalesce(p_diagnostico, ''), 1000),
    notas_internas = left(coalesce(p_notas, ''), 1000), mecanico_id = p_mecanico, proxima_mantencion = p_proxima, updated_at = now()
  where id = p_id and taller_id = tid;
  if not found then raise exception 'Reserva no encontrada'; end if;
end $$;

-- Reserva hecha por el taller (teléfono, mesón): sin abono.
create or replace function public.taller_reserva_manual(p_fecha date, p_hora text, p_servicio uuid, p_nombre text,
  p_telefono text, p_bici text, p_nota text, p_sobrecupo boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); c public.talleres; s public.servicios; mins int;
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  select * into c from public.talleres where id = tid;
  if trim(coalesce(p_nombre, '')) = '' then raise exception 'Escribe el nombre del cliente'; end if;
  if p_servicio is not null then select * into s from public.servicios where id = p_servicio and taller_id = tid; end if;
  mins := coalesce(s.duracion_min, c.bloque_min);
  perform pg_advisory_xact_lock(hashtext('reserva:' || tid::text || p_fecha::text));
  if not coalesce(p_sobrecupo, false) and not exists (select 1 from public.horas_libres(tid, p_fecha, mins) h where h = p_hora) then
    raise exception 'Esa hora no está libre (marca "sobrecupo" para agendar igual)';
  end if;
  mins := (ceil(mins::numeric / c.bloque_min) * c.bloque_min)::int;
  insert into public.reservas (taller_id, servicio_id, servicio_nombre, precio, fecha, hora, hora_fin, nombre, telefono, tel_norm,
    bici, nota, origen, estado, abono_monto, abono_estado, historial, items, total, entrega_estimada)
  values (tid, s.id, coalesce(s.nombre, 'Revisión general'), coalesce(s.precio, 0), p_fecha, p_hora::time, p_hora::time + make_interval(mins => mins),
    left(trim(p_nombre), 80), left(trim(coalesce(p_telefono, '')), 30), public.tel_norm(p_telefono), left(trim(coalesce(p_bici, '')), 120),
    left(trim(coalesce(p_nota, '')), 500), 'taller', 'confirmada', 0, 'sin_abono', public.historial_mas('[]', 'confirmada'),
    case when s.id is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('nombre', s.nombre, 'cant', 1, 'precio', s.precio)) end,
    coalesce(s.precio, 0), public.estimar_entrega(tid, p_fecha, p_hora::time, null));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.taller_devuelto(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.reservas set abono_estado = 'devuelto', historial = public.historial_mas(historial, 'abono_devuelto'), updated_at = now()
  where id = p_id and taller_id = public.taller_de(auth.uid()) and abono_estado = 'devolver';
  if not found then raise exception 'No hay abono por devolver'; end if;
end $$;

-- El taller califica al cliente.
create or replace function public.taller_calificar(p_id uuid, p_estrellas int, p_comentario text) returns void
language plpgsql security definer set search_path = '' as $$
declare r public.reservas;
begin
  select * into r from public.reservas where id = p_id and taller_id = public.taller_de(auth.uid());
  if r.id is null then raise exception 'Reserva no encontrada'; end if;
  if r.estado not in ('completada', 'lista', 'no_asistio') then raise exception 'Califica al cliente después de la visita'; end if;
  if p_estrellas not between 1 and 5 then raise exception 'Elige de 1 a 5 estrellas'; end if;
  if r.tel_norm = '' then raise exception 'La reserva no tiene teléfono'; end if;
  insert into public.calificaciones (reserva_id, taller_id, autor, tel_norm, estrellas, comentario)
  values (r.id, r.taller_id, 'taller', r.tel_norm, p_estrellas, left(trim(coalesce(p_comentario, '')), 300))
  on conflict (reserva_id, autor) do update set estrellas = excluded.estrellas, comentario = excluded.comentario, created_at = now();
end $$;

-- Clientes del taller (por teléfono), con su nota y su historial.
create or replace function public.taller_clientes() returns jsonb
language sql stable security definer set search_path = '' as $$
  with tid as (select public.taller_de(auth.uid()) as id),
  r as (
    select r.tel_norm, max(r.nombre) as nombre, max(r.telefono) as telefono, max(r.email) as email,
      count(*) filter (where r.estado = 'completada') as visitas, count(*) filter (where r.estado = 'no_asistio') as faltas,
      max(r.fecha) filter (where r.estado = 'completada') as ultima, coalesce(sum(r.total) filter (where r.estado = 'completada'), 0) as gastado,
      max(r.proxima_mantencion) as proxima
    from public.reservas r, tid where r.taller_id = tid.id and r.tel_norm <> '' and r.estado not in ('expirada')
    group by r.tel_norm),
  c as (select p.id, p.nombre, p.telefono, p.email, public.tel_norm(p.telefono) as tel_norm, public.cliente_es_premium(p.id) as premium
        from public.perfiles p, tid where p.taller_id = tid.id and p.rol = 'cliente')
  select coalesce(jsonb_agg(jsonb_build_object(
    'tel_norm', coalesce(r.tel_norm, c.tel_norm), 'nombre', coalesce(c.nombre, r.nombre), 'telefono', coalesce(r.telefono, c.telefono),
    'email', coalesce(c.email, r.email), 'cuenta', c.id is not null, 'cliente_id', c.id, 'premium', coalesce(c.premium, false),
    'visitas', coalesce(r.visitas, 0), 'faltas', coalesce(r.faltas, 0), 'ultima', r.ultima, 'gastado', coalesce(r.gastado, 0),
    'proxima', r.proxima, 'nota', public.nota_cliente(coalesce(r.telefono, c.telefono))) order by coalesce(c.nombre, r.nombre)), '[]')
  from r full join c on c.tel_norm = r.tel_norm
  where (select id from tid) is not null
$$;

create or replace function public.taller_equipo_suspender(p_id uuid, p_suspender boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.perfiles set suspendido = p_suspender
  where id = p_id and rol = 'equipo' and public.es_dueno(taller_id);
  if not found then raise exception 'Sin permiso'; end if;
end $$;

-- Estadísticas (Premium).
create or replace function public.taller_estadisticas() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid());
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  -- Gratis: un adelanto del mes (para que vean lo que tendrían con Premium).
  if not coalesce((public.limite_taller(tid, 'estadisticas'))::boolean, false) then
    return jsonb_build_object('bloqueado', true,
      'mes_reservas', (select count(*) from public.reservas where taller_id = tid and created_at >= date_trunc('month', now()) and estado not in ('expirada', 'rechazada')),
      'mes_ingresos', (select coalesce(sum(total), 0) from public.reservas where taller_id = tid and estado = 'completada' and completada_at >= date_trunc('month', now())));
  end if;
  return jsonb_build_object(
    -- v1.9: datos para los gráficos.
    'semana', (select coalesce(jsonb_agg(jsonb_build_object('dia', d, 'n', (select count(*) from public.reservas r where r.taller_id = tid
                 and extract(dow from r.fecha) = d and r.fecha > current_date - 90 and r.estado not in ('expirada', 'rechazada', 'cancelada')))
                 order by d), '[]') from generate_series(0, 6) d),
    'origen', (select jsonb_build_object('online', count(*) filter (where origen = 'online'), 'cuenta', count(*) filter (where origen = 'cliente'),
                 'taller', count(*) filter (where origen = 'taller'))
               from public.reservas where taller_id = tid and created_at > now() - interval '90 days' and estado not in ('expirada', 'rechazada')),
    'clientes_mes', (select coalesce(jsonb_agg(x order by x.mes), '[]') from (
       select to_char(date_trunc('month', r.fecha), 'YYYY-MM') as mes,
         count(distinct r.tel_norm) filter (where not exists (select 1 from public.reservas z where z.taller_id = tid and z.tel_norm = r.tel_norm
           and z.estado = 'completada' and z.fecha < date_trunc('month', r.fecha))) as nuevos,
         count(distinct r.tel_norm) filter (where exists (select 1 from public.reservas z where z.taller_id = tid and z.tel_norm = r.tel_norm
           and z.estado = 'completada' and z.fecha < date_trunc('month', r.fecha))) as vuelven
       from public.reservas r where r.taller_id = tid and r.estado = 'completada' and r.tel_norm <> '' and r.fecha > current_date - 180
       group by 1) x),
    'proximos', (select coalesce(jsonb_agg(jsonb_build_object('fecha', d::date, 'n', (select count(*) from public.reservas r where r.taller_id = tid
                   and r.fecha = d::date and public.ocupa_hora(r))) order by d), '[]')
                 from generate_series((now() at time zone 'America/Santiago')::date, (now() at time zone 'America/Santiago')::date + 6, interval '1 day') d),
    'ticket', (select coalesce(round(avg(total)), 0) from public.reservas where taller_id = tid and estado = 'completada' and total > 0
               and completada_at > now() - interval '90 days'),
    'estrellas', (select coalesce(jsonb_agg(jsonb_build_object('e', e, 'n', (select count(*) from public.calificaciones q where q.taller_id = tid
                    and q.autor = 'cliente' and q.estrellas = e)) order by e desc), '[]') from generate_series(1, 5) e),
    'meses', (select coalesce(jsonb_agg(x order by x.mes), '[]') from (
       select to_char(date_trunc('month', completada_at), 'YYYY-MM') as mes, count(*) as trabajos, sum(total) as ingresos
       from public.reservas where taller_id = tid and estado = 'completada' and completada_at > now() - interval '6 months'
       group by 1) x),
    'servicios', (select coalesce(jsonb_agg(x order by x.n desc), '[]') from (
       select servicio_nombre as nombre, count(*) as n from public.reservas where taller_id = tid and estado = 'completada'
         and completada_at > now() - interval '90 days' group by 1 order by 2 desc limit 8) x),
    'faltas', (select count(*) from public.reservas where taller_id = tid and estado = 'no_asistio' and fecha > current_date - 90),
    'abonos_perdidos', (select coalesce(sum(abono_monto), 0) from public.reservas where taller_id = tid and abono_estado = 'perdido'
                        and updated_at > now() - interval '90 days'),
    'canceladas', (select count(*) from public.reservas where taller_id = tid and estado = 'cancelada' and updated_at > now() - interval '90 days'),
    'online', (select count(*) from public.reservas where taller_id = tid and origen <> 'taller' and created_at > now() - interval '90 days'
               and estado not in ('expirada', 'rechazada')));
end $$;

-- Mantenciones por recordar (Premium).
create or replace function public.taller_recordatorios() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid());
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  if not coalesce((public.limite_taller(tid, 'recordatorios'))::boolean, false) then return jsonb_build_object('bloqueado', true); end if;
  return jsonb_build_object('lista', (select coalesce(jsonb_agg(x order by x.proxima), '[]') from (
    select distinct on (r.tel_norm) r.nombre, r.telefono, r.bici, r.proxima_mantencion as proxima, r.fecha as ultima
    from public.reservas r where r.taller_id = tid and r.estado = 'completada' and r.proxima_mantencion <= current_date + 15
      and not exists (select 1 from public.reservas z where z.taller_id = tid and z.tel_norm = r.tel_norm and z.fecha > r.fecha
                      and z.estado not in ('expirada', 'rechazada', 'cancelada'))
    order by r.tel_norm, r.fecha desc) x));
end $$;

-- Limpiar comprobantes ya revisados (botón del taller).
create or replace function public.taller_limpiar_comprobantes() returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  delete from public.comprobantes k using public.reservas r
  where k.reserva_id = r.id and r.taller_id = public.taller_de(auth.uid()) and public.es_dueno(r.taller_id)
    and r.estado <> 'en_revision';
  get diagnostics n = row_count;
  return n;
end $$;

-- ---------------------------------------------------------------------
-- 13. Premium: pagar con link y subir el comprobante (taller o cliente → admin)
--     Mensual (duración del plan) o anual (365 días, con el link anual).
-- ---------------------------------------------------------------------
drop function if exists public.premium_pagar(text, text);
create or replace function public.premium_pagar(p_tipo text, p_imagen text, p_anual boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare me public.perfiles; l public.links_pago; pg public.pagos; quien text;
begin
  select * into me from public.perfiles where id = auth.uid() and not suspendido;
  if me.id is null then return jsonb_build_object('ok', false, 'error', 'Inicia sesión'); end if;
  if p_tipo = 'premium_taller' and not (me.rol = 'taller' and public.es_dueno(me.taller_id)) then
    return jsonb_build_object('ok', false, 'error', 'Solo el dueño del taller');
  end if;
  if p_tipo = 'premium_cliente' and me.rol <> 'cliente' then return jsonb_build_object('ok', false, 'error', 'Solo clientes'); end if;
  if p_tipo not in ('premium_taller', 'premium_cliente') then return jsonb_build_object('ok', false, 'error', 'Tipo no válido'); end if;
  l := public.link_activo(null, p_tipo || case when coalesce(p_anual, false) then '_anual' else '' end);
  if l.id is null then return jsonb_build_object('ok', false, 'error', 'El pago aún no está disponible'); end if;
  if p_imagen !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$' or length(p_imagen) > 600000 then
    return jsonb_build_object('ok', false, 'error', 'Imagen no válida o muy pesada');
  end if;
  if exists (select 1 from public.pagos where perfil_id = me.id and estado = 'en_revision') then
    return jsonb_build_object('ok', false, 'error', 'Ya tienes un comprobante en revisión');
  end if;
  insert into public.pagos (perfil_id, taller_id, tipo, monto, anual)
  values (me.id, case when p_tipo = 'premium_taller' then me.taller_id end, p_tipo, l.monto, coalesce(p_anual, false))
  returning * into pg;
  insert into public.comprobantes (pago_id, imagen) values (pg.id, p_imagen);
  quien := case when p_tipo = 'premium_taller' then (select nombre from public.talleres where id = me.taller_id)
                else coalesce(nullif(me.nombre, ''), me.email) || ' (cliente)' end;
  perform public.avisar_admin('💰 Pago Premium por revisar', quien || ' · $' || l.monto || case when p_anual then ' · anual' else '' end, '/admin/#pagos');
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.mi_pago_pendiente() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', id, 'monto', monto, 'estado', estado, 'created_at', created_at, 'nota', nota, 'anual', anual)
  from public.pagos where perfil_id = auth.uid() order by created_at desc limit 1
$$;

-- ---------------------------------------------------------------------
-- 14. Panel del administrador
-- ---------------------------------------------------------------------
create or replace function public.admin_check() returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Solo el administrador'; end if;
end $$;

-- Ver el panel: administrador o socio.
create or replace function public.admin_ver() returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if not (public.is_admin() or public.es_socio()) then raise exception 'Solo el administrador'; end if;
end $$;

-- Editar: el administrador libre; el socio solo con un motivo (queda en el registro y le llega al administrador).
create or replace function public.admin_editar(p_motivo text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if public.is_admin() then perform set_config('bt.motivo', coalesce(trim(p_motivo), ''), true); return; end if;
  if not public.es_socio() then raise exception 'Solo el administrador'; end if;
  if length(trim(coalesce(p_motivo, ''))) < 5 then raise exception 'Escribe el motivo del cambio (mínimo 5 letras)'; end if;
  perform set_config('bt.motivo', left(trim(p_motivo), 200), true);
end $$;

create or replace function public.admin_resumen() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare tablas jsonb;
begin
  perform public.admin_ver();
  select jsonb_object_agg(t, pg_total_relation_size(('public.' || t)::regclass)) into tablas
  from unnest(array['perfiles', 'talleres', 'servicios', 'promos', 'reservas', 'comprobantes', 'fotos_trabajo', 'pagos', 'calificaciones',
                    'notificaciones', 'push_subs', 'auditoria', 'mensajes']) t;
  return jsonb_build_object(
    'talleres', (select count(*) from public.talleres),
    'talleres_premium', (select count(*) from public.talleres where premium_hasta > now()),
    'talleres_activos_7d', (select count(distinct p.taller_id) from public.perfiles p where p.rol in ('taller', 'equipo') and p.visto_at > now() - interval '7 days'),
    'talleres_nuevos_7d', (select count(*) from public.talleres where created_at > now() - interval '7 days'),
    'registro_abierto', coalesce(public.cfg_int('registro_talleres'), 1) > 0,
    'clientes', (select count(*) from public.perfiles where rol = 'cliente'),
    'clientes_premium', (select count(*) from public.perfiles where rol = 'cliente' and premium_hasta > now()),
    'equipo', (select count(*) from public.perfiles where rol = 'equipo'),
    'reservas_mes', (select count(*) from public.reservas where created_at >= date_trunc('month', now()) and estado not in ('expirada', 'rechazada')),
    'reservas_hoy', (select count(*) from public.reservas where created_at >= current_date),
    'pagos_por_revisar', (select count(*) from public.pagos where estado = 'en_revision'),
    'ingresos_mes', (select coalesce(sum(monto), 0) from public.pagos where estado = 'aprobado' and resuelto_at >= date_trunc('month', now())),
    'por_vencer', (select count(*) from public.talleres where premium_hasta between now() and now() + interval '7 days'),
    'uso', jsonb_build_object('db_bytes', pg_database_size(current_database()), 'db_limite', 500 * 1024 * 1024, 'tablas', tablas,
      'comprobantes', (select count(*) from public.comprobantes), 'comprobantes_bytes', (select coalesce(sum(length(imagen)), 0) from public.comprobantes),
      'logos_bytes', (select coalesce(sum(length(logo)), 0) from public.talleres),
      'fotos', (select count(*) from public.fotos_trabajo), 'fotos_bytes', (select coalesce(sum(length(imagen)), 0) from public.fotos_trabajo),
      'notificaciones', (select count(*) from public.notificaciones), 'reservas', (select count(*) from public.reservas)),
    'version', public.db_version());
end $$;

create or replace function public.admin_talleres() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_ver();
  return (select coalesce(jsonb_agg(x order by x.created_at desc), '[]') from (
    select t.id, t.nombre, t.slug, t.telefono, t.comuna, t.logo, t.color, t.icono, t.premium_hasta, t.premium_hasta > now() as premium,
      t.activo, t.suspendido, t.created_at, t.reservas_online, t.autoregistro, t.en_directorio,
      (select x.nombre from public.talleres x where x.id = t.referido_por) as referido_por,
      (select count(*) from public.talleres x where x.referido_por = t.id) as invitados,
      o.email, o.nombre as dueno, o.visto_at as dueno_visto,
      (select max(p.visto_at) from public.perfiles p where p.taller_id = t.id and p.rol in ('taller', 'equipo')) as visto_at,
      (select count(*) from public.perfiles p where p.taller_id = t.id and p.rol = 'cliente') as clientes_cuenta,
      (select count(*) from public.perfiles p where p.taller_id = t.id and p.rol = 'equipo') as equipo,
      (select count(distinct r.tel_norm) from public.reservas r where r.taller_id = t.id and r.tel_norm <> '') as clientes,
      (select count(*) from public.reservas r where r.taller_id = t.id and r.created_at >= date_trunc('month', now())
         and r.estado not in ('expirada', 'rechazada')) as reservas_mes,
      (select count(*) from public.reservas r where r.taller_id = t.id and r.estado not in ('expirada', 'rechazada')) as reservas_total,
      (select count(*) from public.servicios s where s.taller_id = t.id) as servicios,
      (select count(*) from public.promos s where s.taller_id = t.id and s.activa) as promos,
      (public.link_activo(t.id, 'abono')).id is not null as cobra_abono,
      public.nota_taller(t.id) as nota
    from public.talleres t left join public.perfiles o on o.id = t.owner_id) x);
end $$;

create or replace function public.admin_clientes() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_ver();
  return (select coalesce(jsonb_agg(x order by x.created_at desc), '[]') from (
    select p.id, p.rol, p.nombre, p.email, p.telefono, p.premium_hasta, p.premium_hasta > now() as premium, p.suspendido, p.visto_at,
      p.created_at, t.nombre as taller, t.id as taller_id, public.nota_cliente(p.telefono) as nota,
      (select count(*) from public.reservas r where r.cliente_id = p.id and r.estado = 'completada') as visitas
    from public.perfiles p left join public.talleres t on t.id = p.taller_id where p.rol in ('cliente', 'equipo') limit 5000) x);
end $$;

-- Dar o quitar Premium (días; 0 = quitar).
drop function if exists public.admin_premium(text, uuid, int);
create or replace function public.admin_premium(p_tipo text, p_id uuid, p_dias int, p_motivo text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare h timestamptz; owner uuid; nom text;
begin
  perform public.admin_editar(p_motivo);
  if p_tipo = 'taller' then
    update public.talleres set premium_hasta = case when coalesce(p_dias, 0) <= 0 then now()
      else greatest(coalesce(premium_hasta, now()), now()) + make_interval(days => p_dias) end
    where id = p_id returning premium_hasta, owner_id, nombre into h, owner, nom;
    if not found then raise exception 'Taller no encontrado'; end if;
    perform public.avisar_taller(p_id, case when p_dias > 0 then '⭐ Premium activado' else 'Tu Premium terminó' end,
      case when p_dias > 0 then 'Tu Premium está activo hasta el ' || to_char(h at time zone 'America/Santiago', 'DD/MM/YYYY') else 'Tu taller volvió a la versión gratis.' end,
      '/taller/#mas');
  elsif p_tipo = 'cliente' then
    update public.perfiles set premium_hasta = case when coalesce(p_dias, 0) <= 0 then now()
      else greatest(coalesce(premium_hasta, now()), now()) + make_interval(days => p_dias) end
    where id = p_id and rol = 'cliente' returning premium_hasta, nombre into h, nom;
    if not found then raise exception 'Cliente no encontrado'; end if;
    perform public.avisar(p_id, case when p_dias > 0 then '⭐ Premium activado' else 'Tu Premium terminó' end,
      case when p_dias > 0 then 'Activo hasta el ' || to_char(h at time zone 'America/Santiago', 'DD/MM/YYYY') else 'Volviste a la versión gratis.' end, '/cliente/');
  else raise exception 'Tipo no válido'; end if;
  perform public.auditar('premium', p_tipo || ' ' || coalesce(nom, '') || ': ' || case when p_dias > 0 then '+' || p_dias || ' días' else 'quitado' end);
end $$;

drop function if exists public.admin_suspender(text, uuid, boolean);
create or replace function public.admin_suspender(p_tipo text, p_id uuid, p_suspender boolean, p_motivo text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_editar(p_motivo);
  if p_tipo = 'taller' then
    update public.talleres set suspendido = p_suspender where id = p_id;
  else
    if not public.is_admin() and exists (select 1 from public.perfiles where id = p_id and rol = 'socio') then
      raise exception 'Solo el administrador suspende socios';
    end if;
    update public.perfiles set suspendido = p_suspender where id = p_id and rol <> 'admin';
  end if;
  perform public.auditar(case when p_suspender then 'suspender' else 'reactivar' end, p_tipo || ' ' || p_id);
end $$;

create or replace function public.admin_pagos(p_estado text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_ver();
  return (select coalesce(jsonb_agg(x order by x.created_at desc), '[]') from (
    select g.id, g.tipo, g.monto, g.estado, g.nota, g.created_at, g.resuelto_at, g.anual,
      coalesce(t.nombre, nullif(p.nombre, ''), p.email) as quien, p.email, p.telefono,
      case when g.tipo = 'premium_taller' then t.premium_hasta else p.premium_hasta end as premium_hasta,
      exists (select 1 from public.comprobantes k where k.pago_id = g.id) as tiene_comprobante
    from public.pagos g join public.perfiles p on p.id = g.perfil_id left join public.talleres t on t.id = g.taller_id
    where p_estado is null or g.estado = p_estado limit 300) x);
end $$;

create or replace function public.admin_pago_comprobante(p_id uuid) returns text
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_ver();
  return (select imagen from public.comprobantes where pago_id = p_id order by created_at desc limit 1);
end $$;

create or replace function public.admin_pago_resolver(p_id uuid, p_aprobar boolean, p_nota text) returns void
language plpgsql security definer set search_path = '' as $$
declare g public.pagos; dias int; t public.talleres; regalo int := coalesce(public.cfg_int('dias_referido'), 30);
begin
  perform public.admin_editar(case when p_aprobar then 'Pago aprobado tras revisar el comprobante' else p_nota end);
  select * into g from public.pagos where id = p_id for update;
  if g.id is null or g.estado <> 'en_revision' then raise exception 'Este pago ya fue revisado'; end if;
  update public.pagos set estado = case when p_aprobar then 'aprobado' else 'rechazado' end, nota = left(coalesce(p_nota, ''), 300),
    resuelto_at = now() where id = g.id;
  if p_aprobar then
    select duracion_dias into dias from public.planes where codigo = case when g.tipo = 'premium_taller' then 'taller_premium' else 'cliente_premium' end;
    if g.anual then dias := 365; end if;
    if g.tipo = 'premium_taller' then perform public.admin_premium('taller', g.taller_id, coalesce(dias, 30), 'Pago aprobado tras revisar el comprobante');
    else perform public.admin_premium('cliente', g.perfil_id, coalesce(dias, 30), 'Pago aprobado tras revisar el comprobante'); end if;
    -- Referidos: el primer Premium pagado del taller invitado le regala días al taller que lo invitó.
    select * into t from public.talleres where id = g.taller_id and g.tipo = 'premium_taller' and referido_por is not null and not referido_premiado for update;
    if t.id is not null and regalo > 0 then
      update public.talleres set referido_premiado = true where id = t.id;
      update public.talleres set premium_hasta = greatest(coalesce(premium_hasta, now()), now()) + make_interval(days => regalo) where id = t.referido_por;
      perform public.avisar_taller(t.referido_por, '🤝 ¡Ganaste ' || regalo || ' días de Premium!', t.nombre || ' activó su Premium con tu invitación. ¡Gracias por recomendarnos!', '/taller/#plan');
      perform public.auditar('referido', t.nombre || ' → +' || regalo || ' días al taller que lo invitó');
    end if;
  else
    perform public.avisar(g.perfil_id, '❌ Pago rechazado', coalesce(nullif(p_nota, ''), 'Revisa el comprobante e inténtalo de nuevo.'),
      case when g.tipo = 'premium_taller' then '/taller/#mas' else '/cliente/' end);
  end if;
  perform public.auditar('pago', g.tipo || ' $' || g.monto || ' ' || case when p_aprobar then 'aprobado' else 'rechazado' end);
end $$;

create or replace function public.admin_links() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_ver();
  return (select coalesce(jsonb_agg(jsonb_build_object('tipo', tipo, 'slot', slot, 'monto', monto, 'url', url, 'texto', texto,
    'activo', activo, 'hasta', hasta) order by tipo, slot), '[]') from public.links_pago where taller_id is null);
end $$;

drop function if exists public.admin_plan_guardar(text, text, text, jsonb, jsonb, int);
create or replace function public.admin_plan_guardar(p_codigo text, p_nombre text, p_descripcion text, p_limites jsonb,
  p_beneficios jsonb, p_duracion int, p_motivo text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_editar(p_motivo);
  if jsonb_typeof(p_limites) <> 'object' or jsonb_typeof(p_beneficios) <> 'array' then raise exception 'Datos no válidos'; end if;
  update public.planes set nombre = left(trim(p_nombre), 40), descripcion = left(coalesce(p_descripcion, ''), 300),
    limites = p_limites, beneficios = p_beneficios, duracion_dias = greatest(1, least(coalesce(p_duracion, 30), 3650))
  where codigo = p_codigo;
  if not found then raise exception 'Plan no encontrado'; end if;
  perform public.auditar('plan', p_codigo);
end $$;

drop function if exists public.admin_config_guardar(text, jsonb);
create or replace function public.admin_config_guardar(p_clave text, p_valor jsonb, p_motivo text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_editar(p_motivo);
  if p_clave not in ('minutos_pago', 'minutos_devolucion', 'horas_cancelacion', 'dias_saldo', 'dias_regalo_taller',
                     'dias_aviso_vencimiento', 'dias_comprobantes', 'soporte_whatsapp', 'vapid_publica',
                     'registro_talleres', 'dias_referido', 'horas_libera_premium', 'dias_fotos', 'color_app', 'version_liberada') then
    raise exception 'Ajuste no válido';
  end if;
  if p_clave = 'vapid_publica' and not public.is_admin() then raise exception 'Solo el administrador'; end if;
  if p_clave = 'color_app' and (p_valor #>> '{}') !~ '^#[0-9a-fA-F]{6}$' then raise exception 'Color no válido'; end if;
  insert into public.config (clave, valor) values (p_clave, p_valor) on conflict (clave) do update set valor = excluded.valor;
  perform public.auditar('ajuste', p_clave || ' = ' || p_valor::text);
end $$;

drop function if exists public.admin_texto_guardar(text, text);
create or replace function public.admin_texto_guardar(p_clave text, p_valor text, p_motivo text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_editar(p_motivo);
  update public.textos set valor = left(coalesce(p_valor, ''), 2000) where clave = p_clave;
  if not found then raise exception 'Texto no encontrado'; end if;
  perform public.auditar('texto', p_clave);
end $$;

create or replace function public.admin_calificaciones() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_ver();
  return (select coalesce(jsonb_agg(x order by x.created_at desc), '[]') from (
    select q.id, q.autor, q.estrellas, q.comentario, q.created_at, t.nombre as taller, r.nombre as cliente
    from public.calificaciones q join public.talleres t on t.id = q.taller_id join public.reservas r on r.id = q.reserva_id
    order by q.created_at desc limit 300) x);
end $$;

drop function if exists public.admin_calificacion_borrar(uuid);
create or replace function public.admin_calificacion_borrar(p_id uuid, p_motivo text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_editar(p_motivo);
  delete from public.calificaciones where id = p_id;
  perform public.auditar('calificacion_borrada', p_id::text);
end $$;

-- Aviso masivo a la campanita.
create or replace function public.admin_aviso(p_destino text, p_titulo text, p_cuerpo text) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  perform public.admin_check();
  if trim(coalesce(p_titulo, '')) = '' then raise exception 'Escribe el título'; end if;
  insert into public.notificaciones (para, titulo, cuerpo, url)
  select p.id, left(p_titulo, 90), left(coalesce(p_cuerpo, ''), 240), ''
  from public.perfiles p where not p.suspendido and p.rol <> 'admin'
    and (p_destino = 'todos' or (p_destino = 'talleres' and p.rol = 'taller') or (p_destino = 'equipos' and p.rol in ('taller', 'equipo'))
         or (p_destino = 'clientes' and p.rol = 'cliente'));
  get diagnostics n = row_count;
  perform public.auditar('aviso', p_destino || ': ' || p_titulo);
  return n;
end $$;

create or replace function public.admin_auditoria() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_ver();
  return (select coalesce(jsonb_agg(x order by x.id desc), '[]') from (
    select a.*, coalesce(nullif(p.nombre, ''), p.email) as quien_nombre, p.rol as quien_rol
    from public.auditoria a left join public.perfiles p on p.id = a.quien order by a.id desc limit 200) x);
end $$;

-- Limpieza del servidor.
create or replace function public.limpiar(p_que text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a int := 0; b int := 0; c int := 0; d int := 0; f int := 0; dias int := coalesce(public.cfg_int('dias_comprobantes'), 30);
begin
  if auth.uid() is not null then perform public.admin_check(); end if;
  if p_que in ('comprobantes', 'todo', 'auto') then
    delete from public.comprobantes k where k.created_at < now() - make_interval(days => case when p_que = 'comprobantes' then 0 else dias end)
      and not exists (select 1 from public.reservas r where r.id = k.reserva_id and r.estado = 'en_revision')
      and not exists (select 1 from public.pagos g where g.id = k.pago_id and g.estado = 'en_revision');
    get diagnostics a = row_count;
  end if;
  if p_que in ('notificaciones', 'todo', 'auto') then
    delete from public.notificaciones where (leida and created_at < now() - interval '30 days') or created_at < now() - interval '120 days';
    get diagnostics b = row_count;
  end if;
  if p_que in ('reservas', 'todo', 'auto') then
    delete from public.reservas where estado in ('expirada', 'rechazada') and updated_at < now() - interval '60 days';
    get diagnostics c = row_count;
  end if;
  if p_que in ('fotos', 'todo', 'auto') then
    delete from public.fotos_trabajo where created_at < now() - make_interval(days => coalesce(public.cfg_int('dias_fotos'), 365));
    get diagnostics f = row_count;
  end if;
  if p_que in ('otros', 'todo', 'auto') then
    delete from public.auditoria where created_at < now() - interval '365 days';
    delete from public.invitaciones where created_at < now() - interval '2 days';
    get diagnostics d = row_count;
  end if;
  if auth.uid() is not null then perform public.auditar('limpieza', p_que); end if;
  return jsonb_build_object('comprobantes', a, 'notificaciones', b, 'reservas', c, 'otros', d, 'fotos', f);
end $$;

-- Claves push (las genera el panel del admin).
create or replace function public.admin_push_claves(p_publica text, p_privada text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_check();
  if p_publica !~ '^[A-Za-z0-9_-]{80,100}$' or p_privada !~ '^[A-Za-z0-9_-]{40,50}$' then raise exception 'Claves no válidas'; end if;
  insert into public.secretos (clave, valor) values ('vapid_privada', p_privada) on conflict (clave) do update set valor = excluded.valor;
  insert into public.config (clave, valor) values ('vapid_publica', to_jsonb(p_publica)) on conflict (clave) do update set valor = excluded.valor;
  delete from public.push_subs where true;  -- las suscripciones con la clave anterior ya no sirven
  perform public.auditar('push', 'claves nuevas');
end $$;

-- ---------------------------------------------------------------------
-- 15. Push (celular)
-- ---------------------------------------------------------------------
create or replace function public.push_guardar(p_endpoint text, p_p256dh text, p_auth text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Inicia sesión'; end if;
  if p_endpoint !~ '^https://' then raise exception 'Suscripción no válida'; end if;
  insert into public.push_subs (endpoint, perfil_id, p256dh, auth) values (p_endpoint, auth.uid(), p_p256dh, p_auth)
  on conflict (endpoint) do update set perfil_id = excluded.perfil_id, p256dh = excluded.p256dh, auth = excluded.auth;
end $$;

create or replace function public.push_quitar(p_endpoint text) returns void
language sql security definer set search_path = '' as $$
  delete from public.push_subs where endpoint = p_endpoint and perfil_id = auth.uid()
$$;

-- Solo el servidor: avisos pendientes de enviar por push.
create or replace function public.push_pendientes() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare ids uuid[]; out jsonb;
begin
  select array_agg(id) into ids from (
    select id from public.notificaciones where not push_enviado and created_at > now() - interval '1 day'
    order by created_at limit 300 for update skip locked) x;
  if ids is null then return jsonb_build_object('claves', null, 'envios', '[]'::jsonb); end if;
  update public.notificaciones set push_enviado = true where id = any (ids);
  select coalesce(jsonb_agg(jsonb_build_object('endpoint', s.endpoint, 'p256dh', s.p256dh, 'auth', s.auth,
           'titulo', n.titulo, 'cuerpo', n.cuerpo, 'url', n.url, 'id', n.id)), '[]')
    into out from public.notificaciones n join public.push_subs s on s.perfil_id = n.para where n.id = any (ids);
  return jsonb_build_object('envios', out, 'claves', jsonb_build_object(
    'publica', (select valor #>> '{}' from public.config where clave = 'vapid_publica'),
    'privada', (select valor from public.secretos where clave = 'vapid_privada')));
end $$;

create or replace function public.push_borrar_endpoint(p_endpoint text) returns void
language sql security definer set search_path = '' as $$ delete from public.push_subs where endpoint = p_endpoint $$;

-- ---------------------------------------------------------------------
-- 16. Tareas automáticas (cada 5 minutos con pg_cron)
-- ---------------------------------------------------------------------
create or replace function public.tareas_periodicas() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n_exp int := 0; n_rec int := 0; n_venc int := 0; r record; dias_av int := coalesce(public.cfg_int('dias_aviso_vencimiento'), 3);
begin
  -- 1) Horas retenidas sin pago: se liberan.
  with x as (
    update public.reservas set estado = 'expirada', abono_estado = 'no_pagado', historial = public.historial_mas(historial, 'expirada'), updated_at = now()
    where estado = 'por_pagar' and expira_at <= now() returning cliente_id, token)
  select count(*) into n_exp from x;

  -- 2) Recordatorio el día antes de la hora (clientes con cuenta).
  for r in select x.id, x.cliente_id, x.token, x.hora, t.nombre from public.reservas x join public.talleres t on t.id = x.taller_id
           where x.estado = 'confirmada' and not x.recordado and x.cliente_id is not null
             and (x.fecha + x.hora) at time zone t.zona between now() and now() + interval '24 hours' loop
    perform public.avisar(r.cliente_id, '⏰ Mañana tienes hora', r.nombre || ' a las ' || to_char(r.hora, 'HH24:MI'), '/r/?t=' || r.token);
    update public.reservas set recordado = true where id = r.id;
    n_rec := n_rec + 1;
  end loop;

  -- 3) Mantención (clientes Premium con la función activa).
  for r in select x.id, x.cliente_id, t.nombre, t.slug from public.reservas x join public.talleres t on t.id = x.taller_id
           where x.estado = 'completada' and not x.mantencion_avisada and x.cliente_id is not null and x.proxima_mantencion <= current_date
             and coalesce((public.limite_cliente(x.cliente_id, 'recordatorios'))::boolean, false) loop
    perform public.avisar(r.cliente_id, '🔧 Le toca mantención a tu bici', 'Reserva tu hora en ' || r.nombre, '/t/?s=' || r.slug);
    update public.reservas set mantencion_avisada = true where id = r.id;
  end loop;

  -- 4) Premium por vencer y vencido (talleres y clientes), con botón para pagar.
  for r in select id, premium_hasta from public.talleres
           where premium_hasta between now() and now() + make_interval(days => dias_av) and aviso_venc_para is distinct from premium_hasta loop
    perform public.avisar_taller(r.id, '⏳ Tu Premium vence pronto', 'Vence el ' || to_char(r.premium_hasta at time zone 'America/Santiago', 'DD/MM') ||
      '. Toca para pagar y subir tu comprobante.', '/taller/#plan');
    update public.talleres set aviso_venc_para = premium_hasta where id = r.id;
    n_venc := n_venc + 1;
  end loop;
  for r in select id, premium_hasta from public.talleres
           where premium_hasta < now() and premium_hasta > now() - interval '30 days' and aviso_vencido_para is distinct from premium_hasta loop
    perform public.avisar_taller(r.id, 'Tu Premium venció', 'Tu taller volvió a la versión gratis. Renueva cuando quieras.', '/taller/#plan');
    update public.talleres set aviso_vencido_para = premium_hasta where id = r.id;
  end loop;
  for r in select id, premium_hasta from public.perfiles
           where rol = 'cliente' and premium_hasta between now() and now() + make_interval(days => dias_av) and aviso_venc_para is distinct from premium_hasta loop
    perform public.avisar(r.id, '⏳ Tu Premium vence pronto', 'Toca para renovarlo.', '/cliente/#plan');
    update public.perfiles set aviso_venc_para = premium_hasta where id = r.id;
  end loop;
  for r in select id, premium_hasta from public.perfiles
           where rol = 'cliente' and premium_hasta < now() and premium_hasta > now() - interval '30 days' and aviso_vencido_para is distinct from premium_hasta loop
    perform public.avisar(r.id, 'Tu Premium venció', 'Volviste a la versión gratis.', '/cliente/#plan');
    update public.perfiles set aviso_vencido_para = premium_hasta where id = r.id;
  end loop;

  -- 5) Limpieza automática (una vez al día, a las 4 de la mañana).
  if extract(hour from now() at time zone 'America/Santiago') = 4 and extract(minute from now()) < 5 then
    perform public.limpiar('auto');
  end if;
  return jsonb_build_object('expiradas', n_exp, 'recordatorios', n_rec, 'vencimientos', n_venc);
end $$;

-- ---------------------------------------------------------------------
-- 17. Permisos de las funciones
-- ---------------------------------------------------------------------
revoke execute on all functions in schema public from public, anon, authenticated;

grant execute on function
  public.config_publica(), public.taller_publico(text), public.horas_libres(uuid, date, int, uuid), public.dias_libres(uuid, int),
  public.reservar(uuid, uuid, date, text, text, text, text, text, text, uuid[]), public.reserva_ver(text), public.reserva_comprobante(text, text),
  public.reserva_cancelar(text), public.reserva_reagendar(text, date, text), public.reserva_calificar(text, int, text),
  public.db_version(), public.tel_norm(text)
to anon, authenticated;

grant execute on function
  public.is_admin(), public.taller_de(uuid), public.mi_taller(), public.es_dueno(uuid), public.ocupa_hora(public.reservas),
  public.mi_cuenta(), public.registrar_visto(), public.mi_perfil_guardar(text, text), public.cliente_inicio(),
  public.taller_panel(), public.taller_guardar(jsonb), public.link_guardar(text, int, int, text, text, boolean, date),
  public.taller_reservas(date, date, text[], uuid), public.taller_comprobante(uuid), public.taller_revisar(uuid, boolean, text),
  public.taller_estado(uuid, text), public.taller_trabajo(uuid, jsonb, text, text, uuid, date),
  public.taller_reserva_manual(date, text, uuid, text, text, text, text, boolean), public.taller_devuelto(uuid),
  public.taller_calificar(uuid, int, text), public.taller_clientes(), public.taller_equipo_suspender(uuid, boolean),
  public.taller_estadisticas(), public.taller_recordatorios(), public.taller_limpiar_comprobantes(),
  public.premium_pagar(text, text, boolean), public.mi_pago_pendiente(),
  public.admin_resumen(), public.admin_talleres(), public.admin_clientes(), public.admin_premium(text, uuid, int, text),
  public.admin_suspender(text, uuid, boolean, text), public.admin_pagos(text), public.admin_pago_comprobante(uuid),
  public.admin_pago_resolver(uuid, boolean, text), public.admin_links(), public.admin_plan_guardar(text, text, text, jsonb, jsonb, int, text),
  public.admin_config_guardar(text, jsonb, text), public.admin_texto_guardar(text, text, text), public.admin_calificaciones(),
  public.admin_calificacion_borrar(uuid, text), public.admin_aviso(text, text, text), public.admin_auditoria(), public.limpiar(text),
  public.admin_push_claves(text, text), public.push_guardar(text, text, text), public.push_quitar(text)
to authenticated;
-- Usadas por las políticas de seguridad.
grant execute on function public.is_admin(), public.taller_de(uuid), public.mi_taller(), public.es_dueno(uuid) to authenticated;
-- (v1.3: chat y borrado en la sección 18, más abajo)
-- Las de solo-servidor (preparar_cuenta, cancelar_invitacion, push_pendientes, push_borrar_endpoint, tareas_periodicas)
-- quedan sin permiso para la app: solo las usa la función "servidor" (rol service_role) y pg_cron.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on all functions in schema public to service_role';
  end if;
end $$;


-- =====================================================================
-- 18. (v1.3) Chat: cliente ↔ su taller · taller ↔ administrador
--     cliente_id vacío = conversación del taller con el administrador.
-- =====================================================================
create table if not exists public.mensajes (
  id          uuid primary key default gen_random_uuid(),
  taller_id   uuid not null references public.talleres (id) on delete cascade,
  cliente_id  uuid references public.perfiles (id) on delete cascade,
  autor       uuid references public.perfiles (id) on delete set null,
  de_taller   boolean not null,
  texto       text not null check (length(trim(texto)) between 1 and 1000),
  leido       boolean not null default false,
  created_at  timestamptz not null default now()
);
create index if not exists mensajes_conv_idx on public.mensajes (taller_id, cliente_id, created_at desc);
alter table public.mensajes enable row level security;

create or replace function public.chat_puede(t uuid, c uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.taller_de(auth.uid()) = t
      or (c is null and (public.is_admin() or public.es_socio()))
      or (c = auth.uid() and exists (select 1 from public.perfiles p where p.id = c and p.rol = 'cliente' and p.taller_id = t and not p.suspendido))
$$;

drop policy if exists "ver mensajes" on public.mensajes;
create policy "ver mensajes" on public.mensajes for select to authenticated using (public.chat_puede(taller_id, cliente_id));
grant select on public.mensajes to authenticated;
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'mensajes') then
    alter publication supabase_realtime add table public.mensajes;
  end if;
end $$;

create or replace function public.chat_enviar(p_taller uuid, p_cliente uuid, p_texto text) returns void
language plpgsql security definer set search_path = '' as $$
declare dt boolean; quien text; t public.talleres;
begin
  if not public.chat_puede(p_taller, p_cliente) then raise exception 'Sin permiso'; end if;
  if trim(coalesce(p_texto, '')) = '' then raise exception 'Escribe un mensaje'; end if;
  if (select count(*) from public.mensajes where autor = auth.uid() and created_at > now() - interval '10 minutes') >= 40 then
    raise exception 'Muchos mensajes seguidos. Espera unos minutos.';
  end if;
  select * into t from public.talleres where id = p_taller;
  dt := coalesce(public.taller_de(auth.uid()) = p_taller, false);
  insert into public.mensajes (taller_id, cliente_id, autor, de_taller, texto) values (p_taller, p_cliente, auth.uid(), dt, left(trim(p_texto), 1000));
  if dt and p_cliente is not null then
    perform public.avisar(p_cliente, '💬 ' || t.nombre, left(trim(p_texto), 120), '/cliente/#chat');
  elsif dt then
    perform public.avisar_admin('💬 ' || t.nombre, left(trim(p_texto), 120), '/admin/#chat');
  else
    select coalesce(nullif(nombre, ''), email) into quien from public.perfiles where id = auth.uid();
    perform public.avisar_taller(p_taller, '💬 ' || case when p_cliente is null then 'BiciTaller (soporte)' else quien end,
      left(trim(p_texto), 120), '/taller/#chat');
  end if;
end $$;

-- Mensajes de una conversación (marca como leídos los recibidos).
create or replace function public.chat_leer(p_taller uuid, p_cliente uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare dt boolean;
begin
  if not public.chat_puede(p_taller, p_cliente) then raise exception 'Sin permiso'; end if;
  dt := coalesce(public.taller_de(auth.uid()) = p_taller, false);
  update public.mensajes set leido = true
  where taller_id = p_taller and cliente_id is not distinct from p_cliente and not leido and de_taller <> dt;
  return (select coalesce(jsonb_agg(x order by x.created_at), '[]') from (
    select id, texto, created_at, de_taller = dt as mio from public.mensajes
    where taller_id = p_taller and cliente_id is not distinct from p_cliente order by created_at desc limit 150) x);
end $$;

-- Conversaciones de quien entra (con no leídos).
create or replace function public.chat_lista() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare me public.perfiles; tid uuid := public.taller_de(auth.uid());
begin
  select * into me from public.perfiles where id = auth.uid();
  if tid is not null then
    return (select coalesce(jsonb_agg(x order by x.ultimo desc nulls last), '[]') from (
      select p.id as cliente_id, coalesce(nullif(p.nombre, ''), p.email) as nombre, tid as taller_id, max(m.created_at) as ultimo,
        count(*) filter (where not m.leido and not m.de_taller) as no_leidos
      from public.mensajes m join public.perfiles p on p.id = m.cliente_id
      where m.taller_id = tid group by p.id, p.nombre, p.email) x);
  elsif public.is_admin() or public.es_socio() then
    return (select coalesce(jsonb_agg(x order by x.ultimo desc), '[]') from (
      select null::uuid as cliente_id, t.nombre, t.id as taller_id, max(m.created_at) as ultimo,
        count(*) filter (where not m.leido and m.de_taller) as no_leidos
      from public.mensajes m join public.talleres t on t.id = m.taller_id
      where m.cliente_id is null group by t.id, t.nombre) x);
  elsif me.rol = 'cliente' then
    return jsonb_build_array(jsonb_build_object('cliente_id', me.id, 'taller_id', me.taller_id,
      'nombre', (select nombre from public.talleres where id = me.taller_id),
      'no_leidos', (select count(*) from public.mensajes m where m.taller_id = me.taller_id and m.cliente_id = me.id and not m.leido and m.de_taller)));
  end if;
  return '[]'::jsonb;
end $$;

-- =====================================================================
-- 19. (v1.3) Borrar cuentas (solo el administrador; lo ejecuta la función "servidor")
-- =====================================================================
-- Lo llama el servidor. El administrador borra libre; el socio (v1.9) borra talleres, clientes y equipo con un motivo,
-- que queda en el registro y le llega como aviso al administrador. Nadie borra al administrador; los socios solo el admin.
drop function if exists public.preparar_borrado(uuid, text, uuid);
create or replace function public.preparar_borrado(p_caller uuid, p_tipo text, p_id uuid, p_motivo text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare p public.perfiles; c public.perfiles; ids uuid[]; admin boolean; det text; m text := nullif(trim(coalesce(p_motivo, '')), '');
begin
  select * into c from public.perfiles where id = p_caller and not suspendido;
  admin := c.rol = 'admin' and c.email = public.admin_email();
  if not admin and coalesce(c.rol, '') <> 'socio' then return jsonb_build_object('ok', false, 'error', 'Solo el administrador'); end if;
  if not admin and length(coalesce(m, '')) < 5 then return jsonb_build_object('ok', false, 'error', 'Escribe el motivo (mínimo 5 letras)'); end if;
  if p_tipo = 'taller' then
    select array_agg(id) into ids from public.perfiles where taller_id = p_id and rol not in ('admin', 'socio');
    select 'taller ' || nombre into det from public.talleres where id = p_id;
    if det is null then return jsonb_build_object('ok', false, 'error', 'Taller no encontrado'); end if;
  else
    select * into p from public.perfiles where id = p_id;
    if p.id is null then return jsonb_build_object('ok', false, 'error', 'Usuario no encontrado'); end if;
    if p.rol = 'admin' then return jsonb_build_object('ok', false, 'error', 'No puedes borrar al administrador'); end if;
    if p.rol = 'taller' then return jsonb_build_object('ok', false, 'error', 'Es el dueño: elimina el taller completo'); end if;
    if p.rol = 'socio' and not admin then return jsonb_build_object('ok', false, 'error', 'Solo el administrador elimina socios'); end if;
    ids := array[p.id];
    det := p.rol || ' ' || p.email;
  end if;
  insert into public.auditoria (quien, accion, detalle)
  values (p_caller, case when p_tipo = 'taller' then 'borrar_taller' else 'borrar_usuario' end, left(det || coalesce(' · Motivo: ' || m, ''), 500));
  if not admin then
    insert into public.notificaciones (para, titulo, cuerpo, url)
    select a.id, left('🗑️ ' || coalesce(nullif(c.nombre, ''), c.email) || ' eliminó ' || det, 90), left('Motivo: ' || m, 240), '/admin/#ajustes'
    from public.perfiles a where a.rol = 'admin' and a.email = public.admin_email();
  end if;
  return jsonb_build_object('ok', true, 'ids', coalesce(to_jsonb(ids), '[]'::jsonb), 'taller', case when p_tipo = 'taller' then p_id end);
end $$;

create or replace function public.borrar_taller(p_id uuid) returns void
language sql security definer set search_path = '' as $$ delete from public.talleres where id = p_id $$;

revoke execute on function public.chat_puede(uuid, uuid), public.chat_enviar(uuid, uuid, text), public.chat_leer(uuid, uuid),
  public.chat_lista(), public.preparar_borrado(uuid, text, uuid, text), public.borrar_taller(uuid),
  public.preparar_cuenta(uuid, text, text, text, text, text, uuid) from public, anon, authenticated;
grant execute on function public.chat_puede(uuid, uuid), public.chat_enviar(uuid, uuid, text), public.chat_leer(uuid, uuid),
  public.chat_lista() to authenticated;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on all functions in schema public to service_role';
  end if;
end $$;


-- =====================================================================
-- 20. (v1.5) Entrega estimada, chat con fotos y límite, perfil Premium del cliente
-- =====================================================================
update public.config set valor = '"+56950868263"' where clave = 'soporte_whatsapp' and valor = '""';
update public.config set valor = '5' where clave = 'dias_aviso_vencimiento' and valor = '3';

-- Cola: cada día de trabajo el taller termina "capacidad_dia" bicis. La bici entra a la cola
-- en el orden de su hora de entrega y sale el primer día en que le alcanza la capacidad.
create or replace function public.estimar_entrega(p_taller uuid, p_fecha date, p_hora time, p_excluir uuid default null) returns date
language plpgsql stable security definer set search_path = '' as $$
declare c public.talleres; hoy date; f date[]; k int; hechas int := 0; llegadas int; d date; i int := 0;
begin
  select * into c from public.talleres where id = p_taller;
  if c.id is null or c.capacidad_dia <= 0 then return null; end if;
  hoy := (now() at time zone c.zona)::date;
  -- Cola en orden de llegada (fecha y hora de entrega de la bici), incluyendo la nueva.
  select array_agg(x.fecha order by x.fecha, x.hora) into f from (
    select r.fecha, r.hora from public.reservas r
    where r.taller_id = p_taller and public.ocupa_hora(r) and (p_excluir is null or r.id <> p_excluir) and r.fecha >= hoy - 60
      and r.estado in ('por_pagar', 'en_revision', 'confirmada', 'recibida', 'en_reparacion', 'esperando_repuesto')
    union all select p_fecha, p_hora) x;
  k := (select count(*) from unnest(f) WITH ORDINALITY u(fe, n) where u.fe < p_fecha)
     + (select count(*) from public.reservas r where r.taller_id = p_taller and public.ocupa_hora(r) and (p_excluir is null or r.id <> p_excluir)
          and r.estado in ('por_pagar', 'en_revision', 'confirmada', 'recibida', 'en_reparacion', 'esperando_repuesto')
          and r.fecha = p_fecha and r.hora <= p_hora) + 1;
  -- Cada día de trabajo se terminan "capacidad_dia" bicis de las que ya llegaron.
  loop
    d := hoy + i;
    if extract(dow from d)::int = any (c.dias)
       and not exists (select 1 from public.bloqueos b where b.taller_id = p_taller and b.fecha = d and b.desde is null) then
      select count(*) into llegadas from unnest(f) u(fe) where u.fe <= d;
      hechas := least(hechas + c.capacidad_dia, llegadas);
      if hechas >= k then return d; end if;
    end if;
    i := i + 1;
    exit when i > 400;
  end loop;
  return null;
end $$;

create or replace function public.entrega_estimada(p_taller uuid, p_fecha date, p_hora text) returns date
language sql stable security definer set search_path = '' as $$ select public.estimar_entrega(p_taller, p_fecha, p_hora::time, null) $$;

-- Chat: foto adjunta y máximo 3 mensajes seguidos (cliente → taller y taller → administrador).
alter table public.mensajes add column if not exists imagen text check (imagen is null or (imagen ~ '^data:image/(jpeg|png|webp);base64,' and length(imagen) <= 400000));
alter table public.mensajes drop constraint if exists mensajes_texto_check;
alter table public.mensajes add constraint mensajes_texto_check check (length(texto) <= 1000 and (length(trim(texto)) > 0 or imagen is not null));

drop function if exists public.chat_enviar(uuid, uuid, text);
create or replace function public.chat_enviar(p_taller uuid, p_cliente uuid, p_texto text, p_imagen text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare dt boolean; quien text; t public.talleres; n int;
begin
  if not public.chat_puede(p_taller, p_cliente) then raise exception 'Sin permiso'; end if;
  if trim(coalesce(p_texto, '')) = '' and p_imagen is null then raise exception 'Escribe un mensaje'; end if;
  if p_imagen is not null and (p_imagen !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$' or length(p_imagen) > 400000) then
    raise exception 'Imagen no válida o muy pesada';
  end if;
  dt := coalesce(public.taller_de(auth.uid()) = p_taller, false);
  -- Máximo 3 seguidos sin respuesta: el cliente al taller y el taller al administrador.
  if (not dt and p_cliente is not null) or (dt and p_cliente is null) then
    select count(*) into n from public.mensajes
    where taller_id = p_taller and cliente_id is not distinct from p_cliente and de_taller = dt
      and created_at > coalesce((select max(created_at) from public.mensajes where taller_id = p_taller
                                 and cliente_id is not distinct from p_cliente and de_taller <> dt), '-infinity');
    if n >= 3 then raise exception 'Ya enviaste 3 mensajes. Espera la respuesta para escribir de nuevo.'; end if;
  end if;
  select * into t from public.talleres where id = p_taller;
  insert into public.mensajes (taller_id, cliente_id, autor, de_taller, texto, imagen)
  values (p_taller, p_cliente, auth.uid(), dt, left(trim(coalesce(p_texto, '')), 1000), p_imagen);
  if dt and p_cliente is not null then
    perform public.avisar(p_cliente, '💬 ' || t.nombre, coalesce(nullif(left(trim(p_texto), 120), ''), '📷 Foto'), '/cliente/#chat');
  elsif dt then
    perform public.avisar_admin('💬 ' || t.nombre, coalesce(nullif(left(trim(p_texto), 120), ''), '📷 Foto'), '/admin/#chat');
  else
    select coalesce(nullif(nombre, ''), email) into quien from public.perfiles where id = auth.uid();
    perform public.avisar_taller(p_taller, '💬 ' || case when p_cliente is null then 'BiciTaller (soporte)' else quien end,
      coalesce(nullif(left(trim(p_texto), 120), ''), '📷 Foto'), '/taller/#chat');
  end if;
end $$;

create or replace function public.chat_leer(p_taller uuid, p_cliente uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare dt boolean;
begin
  if not public.chat_puede(p_taller, p_cliente) then raise exception 'Sin permiso'; end if;
  dt := coalesce(public.taller_de(auth.uid()) = p_taller, false);
  update public.mensajes set leido = true
  where taller_id = p_taller and cliente_id is not distinct from p_cliente and not leido and de_taller <> dt;
  return (select coalesce(jsonb_agg(x order by x.created_at), '[]') from (
    select id, texto, imagen, created_at, de_taller = dt as mio from public.mensajes
    where taller_id = p_taller and cliente_id is not distinct from p_cliente order by created_at desc limit 150) x);
end $$;

create or replace function public.chat_limpiar(p_taller uuid, p_cliente uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.chat_puede(p_taller, p_cliente) then raise exception 'Sin permiso'; end if;
  if public.es_socio() then raise exception 'Solo el administrador borra conversaciones'; end if;
  delete from public.mensajes where taller_id = p_taller and cliente_id is not distinct from p_cliente;
end $$;

-- Perfil del cliente: foto, color, ícono y descripción (Premium).
alter table public.perfiles add column if not exists foto text check (foto is null or (foto ~ '^data:image/(jpeg|png|webp);base64,' and length(foto) <= 120000));
alter table public.perfiles add column if not exists color text check (color is null or color ~ '^#[0-9a-fA-F]{6}$');
alter table public.perfiles add column if not exists icono text check (icono is null or length(icono) <= 8);
alter table public.perfiles add column if not exists descripcion text not null default '' check (length(descripcion) <= 300);

create or replace function public.cliente_estilo(p_color text, p_icono text, p_foto text, p_descripcion text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.perfiles where id = auth.uid() and rol = 'cliente') then raise exception 'Solo clientes'; end if;
  if not public.cliente_es_premium(auth.uid()) then raise exception 'Personalizar tu perfil es Premium'; end if;
  update public.perfiles set color = nullif(p_color, ''), icono = nullif(p_icono, ''), foto = nullif(p_foto, ''),
    descripcion = left(coalesce(p_descripcion, ''), 300) where id = auth.uid();
end $$;

create or replace function public.mi_cuenta() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', p.id, 'email', p.email, 'nombre', p.nombre, 'telefono', p.telefono, 'rol', p.rol,
    'suspendido', p.suspendido or coalesce(t.suspendido, false),
    'is_admin', public.is_admin(), 'is_socio', p.rol = 'socio' and not p.suspendido,
    'taller_id', p.taller_id,
    'foto', p.foto, 'color', p.color, 'icono', p.icono, 'descripcion', p.descripcion,
    'taller', case when t.id is null then null else jsonb_build_object(
       'id', t.id, 'nombre', t.nombre, 'slug', t.slug, 'logo', t.logo, 'color', t.color, 'icono', t.icono,
       'telefono', t.telefono, 'premium', public.taller_es_premium(t.id), 'premium_hasta', t.premium_hasta) end,
    'premium', case when p.rol = 'cliente' then public.cliente_es_premium(p.id)
                    when p.rol in ('taller', 'equipo') then public.taller_es_premium(p.taller_id)
                    else true end,
    'premium_hasta', case when p.rol = 'cliente' then p.premium_hasta else t.premium_hasta end)
  from public.perfiles p left join public.talleres t on t.id = p.taller_id
  where p.id = auth.uid()
$$;

revoke execute on function public.estimar_entrega(uuid, date, time, uuid), public.entrega_estimada(uuid, date, text),
  public.chat_enviar(uuid, uuid, text, text), public.chat_leer(uuid, uuid), public.chat_limpiar(uuid, uuid),
  public.cliente_estilo(text, text, text, text), public.mi_cuenta() from public, anon, authenticated;
grant execute on function public.entrega_estimada(uuid, date, text) to anon, authenticated;
grant execute on function public.chat_enviar(uuid, uuid, text, text), public.chat_leer(uuid, uuid), public.chat_limpiar(uuid, uuid),
  public.cliente_estilo(text, text, text, text), public.mi_cuenta() to authenticated;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on all functions in schema public to service_role';
  end if;
end $$;

-- =====================================================================
-- 21. (v1.6) Registro abierto de talleres, directorio, referidos y fotos antes/después
-- =====================================================================
-- Página /n/: ¿está abierto el registro? ¿quién invita?
create or replace function public.registro_info(p_ref text default null) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'abierto', coalesce(public.cfg_int('registro_talleres'), 1) > 0,
    'dias_regalo', coalesce(public.cfg_int('dias_regalo_taller'), 30),
    'ref', (select jsonb_build_object('nombre', t.nombre, 'slug', t.slug, 'logo', t.logo, 'icono', t.icono, 'color', t.color)
            from public.talleres t where t.slug = lower(trim(coalesce(p_ref, ''))) and t.activo and not t.suspendido))
$$;

-- Directorio público: talleres activos con al menos un servicio. Los Premium aparecen primero.
create or replace function public.directorio(p_comuna text default null, p_q text default null, p_desde int default 0) returns jsonb
language sql stable security definer set search_path = '' as $$
  with v as (
    select t.*, public.taller_es_premium(t.id) as prem, public.nota_taller(t.id) as nota
    from public.talleres t
    where t.activo and not t.suspendido and t.en_directorio
      and exists (select 1 from public.servicios s where s.taller_id = t.id and s.activo))
  select jsonb_build_object(
    'comunas', (select coalesce(jsonb_agg(c order by c), '[]') from (select distinct initcap(lower(trim(comuna))) as c from v where trim(comuna) <> '') x),
    'total', (select count(*) from v where (coalesce(trim(p_comuna), '') = '' or lower(trim(v.comuna)) = lower(trim(p_comuna)))
                and (coalesce(trim(p_q), '') = '' or (v.nombre || ' ' || v.comuna || ' ' || v.descripcion) ilike '%' || trim(p_q) || '%')),
    'talleres', (select coalesce(jsonb_agg(x), '[]') from (
      select v.slug, v.nombre, v.comuna, v.direccion, v.descripcion, v.logo, v.icono, v.color, v.prem as premium, v.nota,
        v.reservas_online and (public.link_activo(v.id, 'abono')).id is not null as reservas_online,
        (select min(s.precio) from public.servicios s where s.taller_id = v.id and s.activo and not s.adicional and s.precio > 0) as desde
      from v
      where (coalesce(trim(p_comuna), '') = '' or lower(trim(v.comuna)) = lower(trim(p_comuna)))
        and (coalesce(trim(p_q), '') = '' or (v.nombre || ' ' || v.comuna || ' ' || v.descripcion) ilike '%' || trim(p_q) || '%')
      order by v.prem desc, (v.nota ->> 'promedio')::numeric desc nulls last, (v.nota ->> 'total')::int desc, v.nombre
      offset greatest(coalesce(p_desde, 0), 0) limit 30) x))
$$;

-- Referidos del taller: su link para invitar a otros talleres y a quiénes invitó.
create or replace function public.taller_referidos() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid());
begin
  if tid is null or not public.es_dueno(tid) then raise exception 'Solo el dueño del taller'; end if;
  return jsonb_build_object(
    'slug', (select slug from public.talleres where id = tid),
    'dias', coalesce(public.cfg_int('dias_referido'), 30),
    'abierto', coalesce(public.cfg_int('registro_talleres'), 1) > 0,
    'invitados', (select coalesce(jsonb_agg(jsonb_build_object('nombre', t.nombre, 'created_at', t.created_at, 'premiado', t.referido_premiado)
                   order by t.created_at desc), '[]') from public.talleres t where t.referido_por = tid));
end $$;

-- Fotos antes/después del trabajo (taller Premium; máximo 2 de cada una por reserva).
create or replace function public.taller_foto_subir(p_reserva uuid, p_tipo text, p_imagen text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); r public.reservas;
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  select * into r from public.reservas where id = p_reserva and taller_id = tid;
  if r.id is null then raise exception 'Reserva no encontrada'; end if;
  if not coalesce((public.limite_taller(tid, 'fotos'))::boolean, false) then raise exception 'Las fotos antes/después son una función Premium'; end if;
  if p_tipo not in ('antes', 'despues') then raise exception 'Tipo no válido'; end if;
  if p_imagen !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$' or length(p_imagen) > 160000 then raise exception 'Imagen no válida o muy pesada'; end if;
  if (select count(*) from public.fotos_trabajo where reserva_id = r.id and tipo = p_tipo) >= 2 then
    raise exception 'Máximo 2 fotos de "%". Borra una para subir otra.', case when p_tipo = 'antes' then 'antes' else 'después' end;
  end if;
  insert into public.fotos_trabajo (reserva_id, tipo, imagen) values (r.id, p_tipo, p_imagen);
  return public.taller_fotos(r.id);
end $$;

create or replace function public.taller_fotos(p_reserva uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'tipo', f.tipo, 'imagen', f.imagen) order by f.tipo, f.created_at), '[]')
  from public.fotos_trabajo f join public.reservas r on r.id = f.reserva_id
  where f.reserva_id = p_reserva and r.taller_id = public.taller_de(auth.uid())
$$;

create or replace function public.taller_foto_borrar(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.fotos_trabajo f using public.reservas r
  where f.id = p_id and r.id = f.reserva_id and r.taller_id = public.taller_de(auth.uid());
  if not found then raise exception 'Foto no encontrada'; end if;
end $$;

-- El cliente ve las fotos desde el enlace de su reserva (ver fotos_visibles).
create or replace function public.reserva_fotos(p_token text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('tipo', f.tipo, 'imagen', f.imagen) order by f.tipo, f.created_at), '[]')
  from public.reservas r join public.fotos_trabajo f on f.reserva_id = r.id
  where r.token = p_token and length(p_token) >= 20 and public.fotos_visibles(r)
$$;

revoke execute on function public.registro_info(text), public.directorio(text, text, int), public.taller_referidos(),
  public.taller_foto_subir(uuid, text, text), public.taller_fotos(uuid), public.taller_foto_borrar(uuid), public.reserva_fotos(text),
  public.hora_premium_cerrada(uuid, date, text, uuid), public.fotos_visibles(public.reservas) from public, anon, authenticated;
grant execute on function public.registro_info(text), public.directorio(text, text, int), public.reserva_fotos(text) to anon, authenticated;
grant execute on function public.taller_referidos(), public.taller_foto_subir(uuid, text, text), public.taller_fotos(uuid),
  public.taller_foto_borrar(uuid) to authenticated;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on all functions in schema public to service_role';
  end if;
end $$;

-- =====================================================================
-- 22. (v1.7) Socios: los crea el administrador; ven todo, no crean ni eliminan, y cada cambio lleva motivo.
-- =====================================================================
create or replace function public.admin_socios() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nombre', p.nombre, 'email', p.email, 'telefono', p.telefono,
    'suspendido', p.suspendido, 'visto_at', p.visto_at, 'created_at', p.created_at,
    'cambios', (select count(*) from public.auditoria a where a.quien = p.id)) order by p.created_at), '[]')
    from public.perfiles p where p.rol = 'socio');
end $$;

revoke execute on function public.es_socio(), public.admin_ver(), public.admin_editar(text), public.admin_socios(),
  public.link_publico(text) from public, anon, authenticated;
grant execute on function public.admin_socios() to authenticated;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on all functions in schema public to service_role';
  end if;
end $$;

-- Que la API de Supabase vea las funciones nuevas al instante.
notify pgrst, 'reload schema';

-- =====================================================================
-- v2.1 · Limpieza y respaldo
--   · Avisos y mensajes se guardan 30 días (antes se avisa). Cada persona borra un aviso o todos (campanita).
--   · Cada lunes: servicios desactivados y promociones vencidas, para borrarlos si ya no se ofrecen.
--   · El taller descarga su respaldo en Excel. Funciones cfx_* para el Centro de Mando.
-- =====================================================================
alter table public.perfiles add column if not exists aviso_limpieza_at timestamptz;

create or replace function public.recordar_catalogo() returns int
language plpgsql security definer set search_path = '' as $$
declare r record; k int := 0;
begin
  for r in select t.owner_id,
             (select count(*) from public.servicios s where s.taller_id = t.id and not s.activo and s.created_at < now() - interval '30 days') as sv,
             (select count(*) from public.promos o where o.taller_id = t.id and (not o.activa or o.hasta < (now() at time zone t.zona)::date - 7)) as pr
           from public.talleres t where t.owner_id is not null and not t.suspendido
  loop
    continue when r.sv + r.pr = 0;
    perform public.avisar(r.owner_id, '🧹 Ordena tu catálogo',
      concat_ws(' y ', case when r.sv = 1 then '1 servicio desactivado' when r.sv > 1 then r.sv || ' servicios desactivados' end,
                       case when r.pr = 1 then '1 promoción vencida' when r.pr > 1 then r.pr || ' promociones vencidas' end)
        || '. Si ya no los ofreces, bórralos para que tu página se vea ordenada.', '/taller/#servicios');
    k := k + 1;
  end loop;
  return k;
end $$;

create or replace function public.limpiar(p_que text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare w record; a int := 0; b int := 0; c int := 0; d int := 0; f int := 0; dias int := coalesce(public.cfg_int('dias_comprobantes'), 30);
begin
  if auth.uid() is not null then perform public.admin_check(); end if;
  if p_que in ('comprobantes', 'todo', 'auto') then
    delete from public.comprobantes k where k.created_at < now() - make_interval(days => case when p_que = 'comprobantes' then 0 else dias end)
      and not exists (select 1 from public.reservas r where r.id = k.reserva_id and r.estado = 'en_revision')
      and not exists (select 1 from public.pagos g where g.id = k.pago_id and g.estado = 'en_revision');
    get diagnostics a = row_count;
  end if;
  if p_que in ('notificaciones', 'todo', 'auto') then
    -- v2.1: avisos y mensajes se guardan 30 días; antes se avisa (máx. 1 vez por semana, al menos 2 días antes).
    if p_que = 'auto' then
      for w in select p.id,
                 (select count(*) from public.notificaciones x where x.para = p.id and x.created_at < now() - interval '21 days') as av,
                 (select count(*) from public.mensajes x where (x.cliente_id = p.id or (x.taller_id = p.taller_id and p.rol in ('taller', 'equipo')))
                    and x.created_at < now() - interval '21 days') as ms
               from public.perfiles p
               where not p.suspendido and (p.aviso_limpieza_at is null or p.aviso_limpieza_at < now() - interval '7 days')
                 and (exists (select 1 from public.notificaciones x where x.para = p.id and x.created_at < now() - interval '28 days')
                   or exists (select 1 from public.mensajes x where (x.cliente_id = p.id or (x.taller_id = p.taller_id and p.rol in ('taller', 'equipo')))
                    and x.created_at < now() - interval '28 days'))
      loop
        perform public.avisar(w.id, '🧹 Limpieza automática',
          concat_ws(' y ', case when w.ms = 1 then '1 mensaje' when w.ms > 1 then w.ms || ' mensajes' end, case when w.av = 1 then '1 aviso' when w.av > 1 then w.av || ' avisos' end)
            || ' con más de 30 días se borran solos en los próximos días. Tus reservas y clientes no se tocan.', '');
        update public.perfiles set aviso_limpieza_at = now() where id = w.id;
      end loop;
      if extract(isodow from now() at time zone 'America/Santiago') = 1 then perform public.recordar_catalogo(); end if;
    end if;
    delete from public.notificaciones where created_at < now() - interval '30 days';
    get diagnostics b = row_count;
    delete from public.mensajes where created_at < now() - interval '30 days';
  end if;
  if p_que in ('reservas', 'todo', 'auto') then
    delete from public.reservas where estado in ('expirada', 'rechazada') and updated_at < now() - interval '60 days';
    get diagnostics c = row_count;
  end if;
  if p_que in ('fotos', 'todo', 'auto') then
    delete from public.fotos_trabajo where created_at < now() - make_interval(days => coalesce(public.cfg_int('dias_fotos'), 365));
    get diagnostics f = row_count;
  end if;
  if p_que in ('otros', 'todo', 'auto') then
    delete from public.auditoria where created_at < now() - interval '365 days';
    delete from public.invitaciones where created_at < now() - interval '2 days';
    get diagnostics d = row_count;
  end if;
  if auth.uid() is not null then perform public.auditar('limpieza', p_que); end if;
  return jsonb_build_object('comprobantes', a, 'notificaciones', b, 'reservas', c, 'otros', d, 'fotos', f);
end $$;

-- Respaldo del taller (Excel): clientes, reservas, servicios, promociones y calificaciones. Solo el dueño.
create or replace function public.mi_respaldo() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare t uuid := public.taller_de(auth.uid());
begin
  if t is null or not public.es_dueno(t) then raise exception 'Solo el dueño del taller'; end if;
  return jsonb_build_object(
    'Reservas', (select coalesce(jsonb_agg(x order by x.fecha, x.hora), '[]') from (select fecha, hora, nombre as cliente, telefono, email, bici, servicio_nombre as servicio,
        precio, abono_monto as abono, abono_estado, estado, nota, origen, created_at as creada from public.reservas where taller_id = t) x),
    'Clientes', (select coalesce(jsonb_agg(x order by x.nombre), '[]') from (select p.nombre, u.email as correo, p.telefono, p.premium_hasta, p.created_at as creado
        from public.perfiles p left join auth.users u on u.id = p.id where p.taller_id = t and p.rol = 'cliente') x),
    'Servicios', (select coalesce(jsonb_agg(x order by x.orden), '[]') from (select nombre, descripcion, precio, duracion_min, activo, orden from public.servicios where taller_id = t) x),
    'Promociones', (select coalesce(jsonb_agg(x order by x.creada), '[]') from (select titulo, texto, precio, precio_antes, hasta, activa, created_at as creada from public.promos where taller_id = t) x),
    'Calificaciones', (select coalesce(jsonb_agg(x order by x.fecha), '[]') from (select created_at as fecha, autor, estrellas, comentario from public.calificaciones where taller_id = t) x));
end $$;

-- ---------- Centro de Mando: respaldo y limpieza (común a las 6 apps) ----------
create or replace function public.cfx_respaldo() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return jsonb_build_object(
    'Talleres', (select coalesce(jsonb_agg(x order by x.creado), '[]') from (select t.nombre, t.slug, t.comuna, t.telefono, u.email as dueno, t.premium_hasta, t.suspendido,
        (select count(*) from public.reservas r where r.taller_id = t.id) as reservas, t.created_at as creado
      from public.talleres t left join auth.users u on u.id = t.owner_id) x),
    'Cuentas', (select coalesce(jsonb_agg(x order by x.creada), '[]') from (select u.email as correo, p.nombre, p.rol, t.nombre as taller, p.premium_hasta, p.suspendido, p.created_at as creada
      from public.perfiles p left join auth.users u on u.id = p.id left join public.talleres t on t.id = p.taller_id) x),
    'Pagos', (select coalesce(jsonb_agg(x order by x.fecha), '[]') from (select g.created_at as fecha, u.email as correo, g.tipo, g.monto, g.estado, g.nota, g.resuelto_at as resuelto
      from public.pagos g left join auth.users u on u.id = g.perfil_id) x),
    'Ajustes', (select coalesce(jsonb_agg(jsonb_build_object('clave', clave, 'valor', valor #>> '{}') order by clave), '[]') from public.config),
    'Registro', (select coalesce(jsonb_agg(to_jsonb(a) order by a.created_at), '[]') from public.auditoria a));
end $$;

create or replace function public.cfx_limpieza() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return jsonb_build_array(
    jsonb_build_object('clave', 'comprobantes', 'titulo', 'Comprobantes', 'detalle', 'Fotos de abonos y pagos ya revisados.',
      'filas', (select count(*) from public.comprobantes k where not exists (select 1 from public.reservas r where r.id = k.reserva_id and r.estado = 'en_revision')
        and not exists (select 1 from public.pagos g where g.id = k.pago_id and g.estado = 'en_revision'))),
    jsonb_build_object('clave', 'notificaciones', 'titulo', 'Avisos y mensajes', 'detalle', 'Más de 30 días (se borran solos cada día).',
      'filas', (select count(*) from public.notificaciones where created_at < now() - interval '30 days') + (select count(*) from public.mensajes where created_at < now() - interval '30 days')),
    jsonb_build_object('clave', 'reservas', 'titulo', 'Reservas expiradas o rechazadas', 'detalle', 'Más de 60 días.',
      'filas', (select count(*) from public.reservas where estado in ('expirada', 'rechazada') and updated_at < now() - interval '60 days')),
    jsonb_build_object('clave', 'fotos', 'titulo', 'Fotos de trabajos', 'detalle', 'Más de ' || coalesce(public.cfg_int('dias_fotos'), 365) || ' días.',
      'filas', (select count(*) from public.fotos_trabajo where created_at < now() - make_interval(days => coalesce(public.cfg_int('dias_fotos'), 365)))),
    jsonb_build_object('clave', 'otros', 'titulo', 'Registro e invitaciones', 'detalle', 'Registro de más de 1 año e invitaciones vencidas.',
      'filas', (select count(*) from public.auditoria where created_at < now() - interval '365 days') + (select count(*) from public.invitaciones where created_at < now() - interval '2 days')));
end $$;

create or replace function public.cfx_limpiar(p_clave text) returns int
language plpgsql security definer set search_path = '' as $$
declare r jsonb;
begin
  perform public.admin_check();
  if p_clave not in ('comprobantes', 'notificaciones', 'reservas', 'fotos', 'otros') then raise exception 'Opción no válida'; end if;
  r := public.limpiar(p_clave);
  return (select coalesce(sum(v::int), 0) from jsonb_each_text(r) as t(k, v));
end $$;

revoke all on function public.recordar_catalogo(), public.mi_respaldo(), public.cfx_respaldo(), public.cfx_limpieza(), public.cfx_limpiar(text), public.limpiar(text) from public, anon;
revoke all on function public.recordar_catalogo() from authenticated;
grant execute on function public.mi_respaldo(), public.cfx_respaldo(), public.cfx_limpieza(), public.cfx_limpiar(text), public.limpiar(text) to authenticated;

-- ---------------------------------------------------------------------
-- Ganchos para el núcleo (pagos): dueño del taller = negocio (Premium del taller), cliente = cliente.
-- ---------------------------------------------------------------------
create or replace function public.cfx_yo() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', p.id, 'email', p.email, 'nombre', coalesce(t.nombre, p.nombre),
    'premium_hasta', case when p.rol = 'taller' then t.premium_hasta else p.premium_hasta end, 'creado', coalesce(t.created_at, p.created_at),
    'rol', case p.rol when 'taller' then 'negocio' when 'cliente' then 'cliente' when 'equipo' then 'otro' else 'admin' end)
  from public.perfiles p left join public.talleres t on t.owner_id = p.id where p.id = auth.uid()
$$;
create or replace function public.cfx_dar_premium(p_cuenta uuid, p_rol text, p_dias int) returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare h timestamptz;
begin
  if p_rol = 'negocio' then
    update public.talleres set premium_hasta = greatest(coalesce(premium_hasta, now()), now()) + make_interval(days => p_dias) where owner_id = p_cuenta returning premium_hasta into h;
  else
    update public.perfiles set premium_hasta = greatest(coalesce(premium_hasta, now()), now()) + make_interval(days => p_dias) where id = p_cuenta returning premium_hasta into h;
  end if;
  return h;
end $$;
create or replace function public.cfx_avisar(p_cuenta uuid, p_titulo text, p_cuerpo text) returns void
language sql security definer set search_path = '' as $$ select public.avisar(p_cuenta, p_titulo, p_cuerpo, '') $$;
create or replace function public.cfx_avisar_admin(p_titulo text, p_cuerpo text) returns void
language sql security definer set search_path = '' as $$ select public.avisar_admin(p_titulo, p_cuerpo, '/admin/#pagos') $$;

-- Ganchos de administración para el núcleo (planes, textos, a quién avisar y verificación).
create or replace function public.cfx_planes_app() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('grupo', m.g, 'clave', k, 'free', f.limites -> k, 'premium', p.limites -> k) order by m.g, k), '[]')
  from (values ('negocio', 'taller_free', 'taller_premium'), ('cliente', 'cliente_free', 'cliente_premium')) m(g, fc, pc) join public.planes f on f.codigo = m.fc join public.planes p on p.codigo = m.pc,
  lateral (select jsonb_object_keys(f.limites || p.limites) as k) x
$$;
create or replace function public.cfx_plan_guardar_app(p_grupo text, p_clave text, p_free jsonb, p_premium jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare fc text; pc text;
begin
  select m.fc, m.pc into fc, pc from (values ('negocio', 'taller_free', 'taller_premium'), ('cliente', 'cliente_free', 'cliente_premium')) m(g, fc, pc) where m.g = p_grupo;
  if fc is null or p_clave !~ '^[a-z_]{2,40}$' then raise exception 'Plan no válido'; end if;
  update public.planes set limites = limites || jsonb_build_object(p_clave, p_free) where codigo = fc;
  update public.planes set limites = limites || jsonb_build_object(p_clave, p_premium) where codigo = pc;
end $$;
create or replace function public.cfx_textos_app() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('clave', clave, 'valor', valor) order by clave), '[]') from public.textos
$$;
create or replace function public.cfx_texto_guardar_app(p_clave text, p_valor text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.textos set valor = p_valor where clave = p_clave;
  if not found then raise exception 'Texto no encontrado'; end if;
end $$;
create or replace function public.cfx_destinatarios(p_destino text) returns setof uuid
language sql stable security definer set search_path = '' as $$
  select p.id from public.perfiles p left join public.talleres t on t.owner_id = p.id where not p.suspendido and p.rol in ('taller', 'equipo', 'cliente')
    and (p_destino = 'todos' or (p_destino = 'negocios' and p.rol = 'taller') or (p_destino = 'clientes' and p.rol = 'cliente')
      or (p_destino = 'premium' and coalesce(case when p.rol = 'taller' then t.premium_hasta else p.premium_hasta end > now(), false))
      or (p_destino = 'gratis' and not coalesce(case when p.rol = 'taller' then t.premium_hasta else p.premium_hasta end > now(), false)))
$$;
create or replace function public.cfx_marcar_verificado(p_cuenta uuid, p_si boolean) returns void
language sql security definer set search_path = '' as $$ select null::void $$;

-- Guía para partir (núcleo · ayuda): lo que le falta configurar al taller. Se marca solo cuando lo hace.
create or replace function public.cfx_guia_app() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce((select jsonb_build_array(
    jsonb_build_object('k', 'perfil', 't', 'Datos del taller', 'd', 'Descripción, dirección y teléfono para tus clientes.', 'ir', 'taller/#mas/perfil',
      'ok', t.descripcion <> '' and t.direccion <> '' and t.telefono <> ''),
    jsonb_build_object('k', 'logo', 't', 'Tu logo', 'd', 'Se ve en tu página de reservas.', 'ir', 'taller/#mas/perfil', 'ok', t.logo is not null),
    jsonb_build_object('k', 'servicios', 't', 'Servicios y precios', 'd', 'Mantención, ajuste de cambios, frenos… con precio y duración.', 'ir', 'taller/#mas/servicios',
      'ok', exists (select 1 from public.servicios s where s.taller_id = t.id)),
    jsonb_build_object('k', 'horario', 't', 'Horario de atención', 'd', 'Los días y horas en que recibes bicicletas.', 'ir', 'taller/#mas/horario', 'ok', t.horarios <> '{}'::jsonb),
    jsonb_build_object('k', 'abono', 't', 'Link de pago del abono', 'd', 'Tu link de pago para cobrar el abono previo de cada reserva.', 'ir', 'taller/#mas/abono',
      'ok', exists (select 1 from public.links_pago l where l.taller_id = t.id and l.tipo = 'abono' and l.activo and l.url <> '')))
  from public.talleres t where t.owner_id = auth.uid()), '[]'::jsonb)
$$;

-- >>> CFX núcleo (no editar aquí: se copia de saas/nucleo/sql con sincronizar.py)
-- ---------------------------------------------------------------------
-- CodeFix · Pagos (igual en las 6 apps; lo reparte nucleo/sincronizar.py). Se administra desde el Centro de Mando → Pagos.
--   Precios iguales en las 6: negocio (inicio, mensual, anual) y cliente (mensual, anual). Link de pago SIN monto (la persona
--   escribe el monto; se le suma el cargo por pago online, visible como una línea aparte), tarjeta (otro link, con su propio cargo)
--   o transferencia (precio exacto, sin cargo), y foto del comprobante. Tú apruebas y se activa el Premium por días enteros.
--   Liberar: por N días nadie queda bloqueado y las cuentas creadas en ese tiempo no pagan el primer pago (quedan en gratis).
--   El comprobante se borra al aprobar o rechazar (ya no sirve). Negocios nuevos: bloqueados hasta su primer pago (si está activado).
--   Cada app define antes: cfx_yo(), cfx_dar_premium(uuid, text, int), cfx_avisar(uuid, text, text) y cfx_avisar_admin(text, text).
-- ---------------------------------------------------------------------
create table if not exists public.cfx_config (clave text primary key, valor jsonb not null);
alter table public.cfx_config enable row level security;
insert into public.cfx_config (clave, valor) values ('pagos', jsonb_build_object(
  'negocio', jsonb_build_object('inicio', 4900, 'inicio_dias', 30, 'mensual', 4900, 'anual', 49900, 'exigir_inicio', true),
  'cliente', jsonb_build_object('mensual', 3000, 'anual', 29900),
  'link', '', 'comision_pct', 0, 'whatsapp', '', 'tarjeta', jsonb_build_object('link', '', 'comision_pct', 0),
  'transferencia', jsonb_build_object('banco', '', 'tipo', '', 'numero', '', 'rut', '', 'titular', '', 'correo', ''),
  'inicio_desde', now()))
on conflict (clave) do nothing;

create table if not exists public.cfx_pagos (
  id          uuid primary key default gen_random_uuid(),
  cuenta      uuid not null,
  email       text not null default '',
  nombre      text not null default '',
  rol         text not null check (rol in ('negocio', 'cliente', 'otro')),
  periodo     text not null check (periodo in ('inicio', 'mensual', 'anual', 'otro')),
  monto       int not null check (monto between 1 and 100000000),
  medio       text not null check (medio in ('link', 'transferencia')),
  nota        text not null default '' check (length(nota) <= 300),
  comprobante text check (comprobante is null or (comprobante ~ '^data:image/(jpeg|png|webp);base64,' and length(comprobante) <= 400000)),
  estado      text not null default 'pendiente' check (estado in ('pendiente', 'aprobado', 'rechazado')),
  dias        int,
  motivo      text not null default '',
  creado      timestamptz not null default now(),
  resuelto    timestamptz
);
alter table public.cfx_pagos add column if not exists cupon text;
alter table public.cfx_pagos add column if not exists meses int check (meses is null or meses between 1 and 24);
alter table public.cfx_pagos drop constraint if exists cfx_pagos_medio_check;
alter table public.cfx_pagos add constraint cfx_pagos_medio_check check (medio in ('link', 'transferencia', 'tarjeta'));
alter table public.cfx_pagos drop constraint if exists cfx_pagos_periodo_check;
alter table public.cfx_pagos add constraint cfx_pagos_periodo_check check (periodo in ('inicio', 'mensual', 'meses', 'anual', 'otro'));
create index if not exists cfx_pagos_cuenta_idx on public.cfx_pagos (cuenta, creado desc);
create index if not exists cfx_pagos_estado_idx on public.cfx_pagos (estado, creado);
alter table public.cfx_pagos enable row level security;
create table if not exists public.cfx_exentos (cuenta uuid primary key, nota text not null default '', creado timestamptz not null default now());
alter table public.cfx_exentos enable row level security;
revoke all on public.cfx_config, public.cfx_pagos, public.cfx_exentos from anon, authenticated;

-- ¿Cómo estoy? Precios, mi rol, si debo el primer pago y mi último pago.
create or replace function public.cfx_pago_estado() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare c jsonb := (select valor from public.cfx_config where clave = 'pagos'); y jsonb := public.cfx_yo(); pagado boolean; debe boolean; bloq boolean;
        lib jsonb := (select valor from public.cfx_config where clave = 'liberar'); ld timestamptz := (lib ->> 'desde')::timestamptz; lh timestamptz := (lib ->> 'hasta')::timestamptz;
begin
  if y is null or (y ->> 'id') is null then raise exception 'Inicia sesión'; end if;
  pagado := exists (select 1 from public.cfx_pagos where cuenta = (y ->> 'id')::uuid and estado = 'aprobado')
    or exists (select 1 from public.cfx_exentos where cuenta = (y ->> 'id')::uuid);
  -- debe_inicio: cuenta nueva (desde que activaste la regla) sin primer pago. bloqueado: además es un negocio.
  -- Solo si ya hay una forma de pago configurada (si no, nadie podría pagar).
  debe := coalesce((c #>> '{negocio,exigir_inicio}')::boolean, false) and not pagado
     and (coalesce(c ->> 'link', '') <> '' or coalesce(c #>> '{transferencia,numero}', '') <> '' or coalesce(c #>> '{tarjeta,link}', '') <> '')
     and (y ->> 'creado')::timestamptz > coalesce((c ->> 'inicio_desde')::timestamptz, now())
     -- Liberado: mientras dure nadie queda bloqueado; las cuentas creadas en ese tiempo quedan en gratis sin primer pago.
     and not (lh is not null and (now() < lh or (y ->> 'creado')::timestamptz between coalesce(ld, '-infinity') and lh));
  bloq := debe and y ->> 'rol' = 'negocio';
  return jsonb_build_object('config', c - 'inicio_desde', 'yo', y, 'pagado', pagado, 'bloqueado', bloq, 'debe_inicio', debe,
    'liberado_hasta', case when lh > now() then lh end,
    'ultimo', (select to_jsonb(x) from (select id, periodo, monto, medio, estado, dias, motivo, creado, resuelto from public.cfx_pagos
               where cuenta = (y ->> 'id')::uuid order by creado desc limit 1) x));
end $$;

drop function if exists public.cfx_pago_pedir(text, int, text, text, text);
drop function if exists public.cfx_pago_pedir(text, int, text, text, text, text);
create or replace function public.cfx_pago_pedir(p_periodo text, p_monto int, p_medio text, p_comprobante text, p_nota text default '', p_cupon text default null, p_meses int default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); i uuid; cup text := nullif(upper(trim(coalesce(p_cupon, ''))), '');
begin
  if y is null or (y ->> 'id') is null then raise exception 'Inicia sesión'; end if;
  if y ->> 'rol' not in ('negocio', 'cliente') and p_periodo <> 'otro' then raise exception 'Pide al dueño de la cuenta que haga el pago'; end if;
  if p_periodo not in ('inicio', 'mensual', 'meses', 'anual', 'otro') or p_medio not in ('link', 'transferencia', 'tarjeta') then raise exception 'Datos no válidos'; end if;
  if p_periodo = 'meses' and coalesce(p_meses, 0) not between 2 and 11 then raise exception 'Elige de 2 a 11 meses'; end if;
  if coalesce(p_monto, 0) < 1 then raise exception 'Escribe el monto que pagaste'; end if;
  if coalesce(length(p_comprobante), 0) < 200 then raise exception 'Sube la foto del comprobante'; end if;
  if cup is not null then perform public.cfx_cupon_ver(cup); end if;
  if exists (select 1 from public.cfx_pagos where cuenta = (y ->> 'id')::uuid and estado = 'pendiente') then raise exception 'Ya tienes un pago en revisión. Te avisamos apenas se apruebe.'; end if;
  if (select count(*) from public.cfx_pagos where cuenta = (y ->> 'id')::uuid and creado > now() - interval '1 day') >= 5 then raise exception 'Demasiados intentos hoy. Escribe a soporte.'; end if;
  insert into public.cfx_pagos (cuenta, email, nombre, rol, periodo, monto, medio, nota, comprobante, cupon, meses)
  values ((y ->> 'id')::uuid, coalesce(y ->> 'email', ''), left(coalesce(y ->> 'nombre', ''), 80), case when y ->> 'rol' in ('negocio', 'cliente') then y ->> 'rol' else 'otro' end,
          p_periodo, p_monto, p_medio, left(coalesce(p_nota, ''), 300), p_comprobante, cup, case when p_periodo = 'meses' then p_meses end)
  returning id into i;
  -- Aviso al tiro: al Centro de Mando si la app está vinculada (si no, al administrador de esta app).
  perform public.cfx_al_cm('💳 Pago por revisar', coalesce(nullif(y ->> 'nombre', ''), y ->> 'email') || ' · $' || p_monto || ' (' || case p_periodo when 'meses' then p_meses || ' meses' else p_periodo end || ', ' || p_medio || ')' || coalesce(' · cupón ' || cup, ''), 'pago');
  return i;
end $$;

-- Precios públicos (para la portada, sin iniciar sesión).
create or replace function public.cfx_precios() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('negocio', valor -> 'negocio', 'cliente', valor -> 'cliente', 'comision_pct', valor -> 'comision_pct',
    'liberado_hasta', (select case when (l.valor ->> 'hasta')::timestamptz > now() then l.valor -> 'hasta' end from public.cfx_config l where l.clave = 'liberar'))
  from public.cfx_config where clave = 'pagos'
$$;
revoke all on function public.cfx_precios() from public;
grant execute on function public.cfx_precios() to anon, authenticated;

-- ---------- Administrador (lo llama el Centro de Mando) ----------
create or replace function public.cfx_pagos_config() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return (select valor from public.cfx_config where clave = 'pagos');
end $$;

create or replace function public.cfx_pagos_config_guardar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v jsonb := (select valor from public.cfx_config where clave = 'pagos');
begin
  perform public.admin_check();
  if jsonb_typeof(p) <> 'object' then raise exception 'Datos no válidos'; end if;
  if coalesce(p ->> 'link', '') <> '' and (p ->> 'link') !~ '^https://[^ ]+$' then raise exception 'El link de pago debe empezar con https://'; end if;
  if coalesce((p ->> 'comision_pct')::numeric, 0) not between 0 and 20 or coalesce((p #>> '{tarjeta,comision_pct}')::numeric, 0) not between 0 and 20 then raise exception 'El cargo por pago online va de 0 a 20 %%'; end if;
  if coalesce(p #>> '{tarjeta,link}', '') <> '' and (p #>> '{tarjeta,link}') !~ '^https://[^ ]+$' then raise exception 'El link de tarjeta debe empezar con https://'; end if;
  -- Al activar "bloquear hasta el primer pago", solo aplica a los negocios que se registren desde ahora.
  -- También cuando se configura la primera forma de pago (antes nadie podía pagar, así que nadie quedó obligado).
  if coalesce((p #>> '{negocio,exigir_inicio}')::boolean, false) and (not coalesce((v #>> '{negocio,exigir_inicio}')::boolean, false)
     or (coalesce(v ->> 'link', '') = '' and coalesce(v #>> '{transferencia,numero}', '') = '' and coalesce(v #>> '{tarjeta,link}', '') = ''
         and (coalesce(p ->> 'link', '') <> '' or coalesce(p #>> '{transferencia,numero}', '') <> '' or coalesce(p #>> '{tarjeta,link}', '') <> ''))) then
    p := p || jsonb_build_object('inicio_desde', now());
  end if;
  v := v || (p - 'inicio_desde') || case when p ? 'inicio_desde' then jsonb_build_object('inicio_desde', p -> 'inicio_desde') else '{}'::jsonb end;
  update public.cfx_config set valor = v where clave = 'pagos';
  return v;
end $$;

create or replace function public.cfx_pagos_lista(p_estado text default 'pendiente') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return (select coalesce(jsonb_agg(x order by x.creado desc), '[]') from (
    select id, cuenta, email, nombre, rol, periodo, meses, monto, medio, nota, estado, dias, motivo, creado, resuelto, comprobante is not null as con_comprobante,
      public.cfx_dias_sugeridos(g) as sugeridos,
      (select count(*) from public.cfx_pagos z where z.cuenta = g.cuenta and z.estado = 'aprobado') as aprobados
    from public.cfx_pagos g where p_estado = 'todos' or estado = p_estado order by creado desc limit 200) x);
end $$;

create or replace function public.cfx_pago_comprobante(p_id uuid) returns text
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return (select comprobante from public.cfx_pagos where id = p_id);
end $$;

-- Días que corresponden a un pago (siempre días enteros): mensual 30, anual 365, N meses = N × 30, primer pago lo configurado,
-- y "otro monto" en proporción al precio mensual (sin contar el cargo por pago online).
create or replace function public.cfx_dias_sugeridos(g public.cfx_pagos) returns int
language plpgsql stable security definer set search_path = '' as $$
declare c jsonb := (select valor from public.cfx_config where clave = 'pagos'); m numeric; pct numeric; neto numeric;
begin
  if g.periodo = 'inicio' then return coalesce((c #>> '{negocio,inicio_dias}')::int, 30); end if;
  if g.periodo = 'mensual' then return 30; end if;
  if g.periodo = 'anual' then return 365; end if;
  if g.periodo = 'meses' then return 30 * coalesce(g.meses, 1); end if;
  m := nullif((c #>> array[case when g.rol = 'cliente' then 'cliente' else 'negocio' end, 'mensual'])::numeric, 0);
  pct := case g.medio when 'link' then coalesce((c ->> 'comision_pct')::numeric, 0) when 'tarjeta' then coalesce((c #>> '{tarjeta,comision_pct}')::numeric, 0) else 0 end;
  neto := g.monto / (1 + pct / 100);
  return case when m is null then 0 else least(3660, floor(neto * 30 / m))::int end;
end $$;
revoke all on function public.cfx_dias_sugeridos(public.cfx_pagos) from public, anon, authenticated;

create or replace function public.cfx_pago_resolver(p_id uuid, p_aprobar boolean, p_dias int default null, p_motivo text default '') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare g public.cfx_pagos; c jsonb := (select valor from public.cfx_config where clave = 'pagos'); d int; hasta timestamptz;
begin
  perform public.admin_check();
  select * into g from public.cfx_pagos where id = p_id and estado = 'pendiente' for update;
  if g.id is null then raise exception 'Pago no encontrado o ya resuelto'; end if;
  d := coalesce(p_dias, public.cfx_dias_sugeridos(g));
  if p_aprobar then
    if d < 0 or d > 3660 then raise exception 'Días no válidos'; end if;
    if d > 0 then hasta := public.cfx_dar_premium(g.cuenta, g.rol, d); end if;
    update public.cfx_pagos set estado = 'aprobado', dias = d, motivo = left(coalesce(p_motivo, ''), 200), resuelto = now(), comprobante = null where id = p_id;
    perform public.cfx_avisar(g.cuenta, '✅ Pago aprobado', case when hasta is not null then 'Premium activo hasta el ' || to_char(hasta at time zone 'America/Santiago', 'DD/MM/YYYY') || '. ¡Gracias!' else 'Gracias, tu pago quedó registrado.' end);
  else
    update public.cfx_pagos set estado = 'rechazado', motivo = left(coalesce(nullif(p_motivo, ''), 'No pudimos validar el comprobante'), 200), resuelto = now(), comprobante = null where id = p_id;
    perform public.cfx_avisar(g.cuenta, '⚠️ Pago rechazado', left(coalesce(nullif(p_motivo, ''), 'No pudimos validar el comprobante'), 200) || '. Puedes subirlo de nuevo.');
  end if;
  return jsonb_build_object('estado', case when p_aprobar then 'aprobado' else 'rechazado' end, 'dias', d, 'hasta', hasta);
end $$;

-- Liberar el registro por N días (0 = terminar ahora). Sin p_dias solo devuelve cómo está.
create or replace function public.cfx_liberar(p_dias int default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v jsonb := (select valor from public.cfx_config where clave = 'liberar');
begin
  perform public.admin_check();
  if p_dias is not null then
    if p_dias < 0 or p_dias > 90 then raise exception 'De 0 a 90 días'; end if;
    v := case when p_dias = 0 then coalesce(v, '{}'::jsonb) || jsonb_build_object('hasta', least(coalesce((v ->> 'hasta')::timestamptz, now()), now()))
         else jsonb_build_object('desde', case when (v ->> 'hasta')::timestamptz > now() then v -> 'desde' else to_jsonb(now()) end, 'hasta', now() + make_interval(days => p_dias)) end;
    insert into public.cfx_config (clave, valor) values ('liberar', v) on conflict (clave) do update set valor = excluded.valor;
  end if;
  return jsonb_build_object('desde', v -> 'desde', 'hasta', v -> 'hasta', 'activo', coalesce((v ->> 'hasta')::timestamptz > now(), false));
end $$;
revoke all on function public.cfx_liberar(int) from public, anon;
grant execute on function public.cfx_liberar(int) to authenticated;

-- Cuentas que no pagan el inicio (por ejemplo, las que creas tú de regalo).
create or replace function public.cfx_exento(p_cuenta uuid, p_si boolean, p_nota text default '') returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_check();
  if p_si then insert into public.cfx_exentos (cuenta, nota) values (p_cuenta, left(coalesce(p_nota, ''), 200)) on conflict (cuenta) do update set nota = excluded.nota;
  else delete from public.cfx_exentos where cuenta = p_cuenta; end if;
end $$;

create or replace function public.cfx_exento_email(p_email text, p_si boolean) returns text
language plpgsql security definer set search_path = '' as $$
declare u uuid;
begin
  perform public.admin_check();
  select id into u from auth.users where lower(email) = lower(trim(coalesce(p_email, '')));
  if u is null then raise exception 'No hay una cuenta con ese correo en esta app'; end if;
  perform public.cfx_exento(u, p_si, 'Desde el Centro de Mando');
  return lower(trim(p_email));
end $$;

revoke all on function public.cfx_exento_email(text, boolean) from public, anon;
grant execute on function public.cfx_exento_email(text, boolean) to authenticated;
revoke all on function public.cfx_pago_estado(), public.cfx_pago_pedir(text, int, text, text, text, text, int), public.cfx_pagos_config(), public.cfx_pagos_config_guardar(jsonb),
  public.cfx_pagos_lista(text), public.cfx_pago_comprobante(uuid), public.cfx_pago_resolver(uuid, boolean, int, text), public.cfx_exento(uuid, boolean, text) from public, anon;
grant execute on function public.cfx_pago_estado(), public.cfx_pago_pedir(text, int, text, text, text, text, int), public.cfx_pagos_config(), public.cfx_pagos_config_guardar(jsonb),
  public.cfx_pagos_lista(text), public.cfx_pago_comprobante(uuid), public.cfx_pago_resolver(uuid, boolean, int, text), public.cfx_exento(uuid, boolean, text) to authenticated;
revoke all on function public.cfx_yo(), public.cfx_dar_premium(uuid, text, int), public.cfx_avisar(uuid, text, text), public.cfx_avisar_admin(text, text) from public, anon, authenticated;
-- ---------------------------------------------------------------------
-- CodeFix · Administración común (igual en las 6 apps; se maneja desde el Centro de Mando → Control).
--   Planes (interruptores sí/no y límites), textos, aviso a todos, keys de Premium, cupones de descuento,
--   verificación de identidad y registro de lo que hace el administrador.
--   Cada app define antes: cfx_planes_app(), cfx_plan_guardar_app(text, text, jsonb, jsonb), cfx_textos_app(),
--   cfx_texto_guardar_app(text, text), cfx_destinatarios(text) y cfx_marcar_verificado(uuid, boolean).
-- ---------------------------------------------------------------------
create table if not exists public.cfx_registro (
  id bigserial primary key, quien text not null default '', accion text not null, detalle text not null default '', creado timestamptz not null default now());
create table if not exists public.cfx_keys (
  id uuid primary key default gen_random_uuid(), hash text not null unique, ultimos text not null, rol text not null check (rol in ('negocio', 'cliente')),
  dias int not null check (dias between 1 and 3660), nota text not null default '', creado timestamptz not null default now(),
  usada_por uuid, usada_email text, usada_at timestamptz, revocada boolean not null default false);
create table if not exists public.cfx_cupones (
  codigo text primary key check (codigo ~ '^[A-Z0-9-]{3,20}$'), pct int not null check (pct between 1 and 100), usos_max int, usos int not null default 0,
  vence date, activo boolean not null default true, creado timestamptz not null default now());
create table if not exists public.cfx_verificaciones (
  cuenta uuid primary key, email text not null default '', nombre text not null default '', rut text not null, documento text not null default '',
  frente text, reverso text, selfie text, estado text not null default 'pendiente' check (estado in ('pendiente', 'aprobada', 'rechazada')),
  motivo text not null default '', creado timestamptz not null default now(), resuelto timestamptz);
alter table public.cfx_registro enable row level security;
alter table public.cfx_keys enable row level security;
alter table public.cfx_cupones enable row level security;
alter table public.cfx_verificaciones enable row level security;
revoke all on public.cfx_registro, public.cfx_keys, public.cfx_cupones, public.cfx_verificaciones from anon, authenticated;

create or replace function public.cfx_anotar(p_accion text, p_detalle text) returns void
language sql security definer set search_path = '' as $$
  insert into public.cfx_registro (quien, accion, detalle) values (coalesce((select email from auth.users where id = auth.uid()), 'sistema'), left(p_accion, 60), left(coalesce(p_detalle, ''), 400))
$$;
create or replace function public.cfx_registro_lista(p_limite int default 200) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return (select coalesce(jsonb_agg(x order by x.id desc), '[]') from (select * from public.cfx_registro order by id desc limit greatest(1, least(coalesce(p_limite, 200), 2000))) x);
end $$;

-- ---------- Planes: [{grupo, clave, free, premium}] (números o sí/no) ----------
-- Borrar el registro de cambios (el común y el propio de la app, si tiene): lo de más de N días, o todo con 0. Solo el administrador.
create or replace function public.cfx_registro_borrar(p_dias int default 30) returns int
language plpgsql security definer set search_path = '' as $$
declare n int := 0; k int; col text; desde timestamptz := case when coalesce(p_dias, 0) <= 0 then 'infinity'::timestamptz else now() - make_interval(days => p_dias) end;
begin
  perform public.admin_check();
  delete from public.cfx_registro where creado < desde; get diagnostics n = row_count;
  if to_regclass('public.auditoria') is not null then
    select c.column_name into col from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'auditoria'
      and c.column_name in ('created_at', 'at', 'creado', 'fecha') and c.data_type like 'timestamp%' order by c.ordinal_position limit 1;
    if col is not null then execute format('delete from public.auditoria where %I < $1', col) using desde; get diagnostics k = row_count; n := n + k; end if;
  end if;
  insert into public.cfx_registro (quien, accion, detalle) values (coalesce((select email from auth.users where id = auth.uid()), 'sistema'), 'registro borrado',
    case when coalesce(p_dias, 0) <= 0 then 'todo' else 'más de ' || p_dias || ' días' end || ' (' || n || ' filas)');
  return n;
end $$;
revoke all on function public.cfx_registro_borrar(int) from public, anon;
grant execute on function public.cfx_registro_borrar(int) to authenticated;

create or replace function public.cfx_planes() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return public.cfx_planes_app();
end $$;
create or replace function public.cfx_plan_guardar(p_grupo text, p_clave text, p_free jsonb, p_premium jsonb) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_check();
  if jsonb_typeof(p_free) not in ('number', 'boolean') or jsonb_typeof(p_premium) not in ('number', 'boolean') then raise exception 'Valor no válido'; end if;
  perform public.cfx_plan_guardar_app(p_grupo, p_clave, p_free, p_premium);
  perform public.cfx_anotar('plan', p_grupo || '.' || p_clave || ': gratis ' || p_free::text || ' · premium ' || p_premium::text);
end $$;

-- ---------- Textos: [{clave, valor}] ----------
create or replace function public.cfx_textos() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return public.cfx_textos_app();
end $$;
create or replace function public.cfx_texto_guardar(p_clave text, p_valor text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_check();
  perform public.cfx_texto_guardar_app(p_clave, left(coalesce(p_valor, ''), 2000));
  perform public.cfx_anotar('texto', p_clave);
end $$;

-- ---------- Aviso a todos: destino todos | negocios | clientes | premium | gratis ----------
create or replace function public.cfx_aviso_masivo(p_destino text, p_titulo text, p_cuerpo text) returns int
language plpgsql security definer set search_path = '' as $$
declare u uuid; n int := 0;
begin
  perform public.admin_check();
  if trim(coalesce(p_titulo, '')) = '' then raise exception 'Escribe el título'; end if;
  if p_destino not in ('todos', 'negocios', 'clientes', 'premium', 'gratis') then raise exception 'Destino no válido'; end if;
  for u in select * from public.cfx_destinatarios(p_destino) loop
    perform public.cfx_avisar(u, left(p_titulo, 80), left(coalesce(p_cuerpo, ''), 240));
    n := n + 1;
  end loop;
  perform public.cfx_anotar('aviso', p_destino || ' (' || n || '): ' || p_titulo);
  return n;
end $$;

-- ---------- Keys de Premium (de un solo uso). Se guardan cifradas: el código completo solo se ve al crearlas. ----------
create or replace function public.cfx_keys_crear(p_n int, p_rol text, p_dias int, p_nota text default '') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c text; out jsonb := '[]'::jsonb;
begin
  perform public.admin_check();
  if p_rol not in ('negocio', 'cliente') or coalesce(p_dias, 0) not between 1 and 3660 or coalesce(p_n, 0) not between 1 and 50 then raise exception 'Datos no válidos'; end if;
  for i in 1..p_n loop
    c := upper(replace(gen_random_uuid()::text, '-', ''));
    c := 'CFX-' || substr(c, 1, 4) || '-' || substr(c, 5, 4) || '-' || substr(c, 9, 4);
    insert into public.cfx_keys (hash, ultimos, rol, dias, nota) values (encode(sha256(convert_to(c, 'UTF8')), 'hex'), right(c, 4), p_rol, p_dias, left(coalesce(p_nota, ''), 120));
    out := out || to_jsonb(c);
  end loop;
  perform public.cfx_anotar('keys', p_n || ' keys ' || p_rol || ' de ' || p_dias || ' días');
  return out;
end $$;
create or replace function public.cfx_keys_lista() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return (select coalesce(jsonb_agg(to_jsonb(k) - 'hash' order by k.creado desc), '[]') from (select * from public.cfx_keys order by creado desc limit 300) k);
end $$;
create or replace function public.cfx_key_revocar(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_check();
  update public.cfx_keys set revocada = true where id = p_id and usada_por is null;
  perform public.cfx_anotar('key revocada', p_id::text);
end $$;
create or replace function public.cfx_key_canjear(p_codigo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); k public.cfx_keys; h timestamptz; c text := upper(trim(coalesce(p_codigo, '')));
begin
  if y is null or (y ->> 'id') is null then raise exception 'Inicia sesión'; end if;
  if (select count(*) from public.cfx_registro where accion = 'key fallida' and detalle = (y ->> 'id') and creado > now() - interval '1 hour') >= 10 then
    raise exception 'Demasiados intentos. Prueba en una hora.';
  end if;
  select * into k from public.cfx_keys where hash = encode(sha256(convert_to(c, 'UTF8')), 'hex') for update;
  if k.id is null or k.revocada or k.usada_por is not null then
    insert into public.cfx_registro (quien, accion, detalle) values (coalesce(y ->> 'email', ''), 'key fallida', y ->> 'id');
    raise exception 'Key no válida o ya usada';
  end if;
  if k.rol <> coalesce(y ->> 'rol', '') then raise exception 'Esta key es para cuentas de %', case when k.rol = 'negocio' then 'negocio' else 'cliente' end; end if;
  h := public.cfx_dar_premium((y ->> 'id')::uuid, k.rol, k.dias);
  update public.cfx_keys set usada_por = (y ->> 'id')::uuid, usada_email = y ->> 'email', usada_at = now() where id = k.id;
  insert into public.cfx_exentos (cuenta, nota) values ((y ->> 'id')::uuid, 'Key ' || k.ultimos) on conflict (cuenta) do nothing;
  perform public.cfx_avisar_admin('🔑 Key canjeada', coalesce(y ->> 'email', '') || ' · ' || k.dias || ' días');
  return jsonb_build_object('hasta', h, 'dias', k.dias);
end $$;

-- ---------- Cupones de descuento (se aplican al pagar Premium) ----------
create or replace function public.cfx_cupon_ver(p_codigo text) returns int
language plpgsql stable security definer set search_path = '' as $$
declare c public.cfx_cupones;
begin
  if auth.uid() is null then raise exception 'Inicia sesión'; end if;
  select * into c from public.cfx_cupones where codigo = upper(trim(coalesce(p_codigo, '')));
  if c.codigo is null or not c.activo or (c.vence is not null and c.vence < current_date) or (c.usos_max is not null and c.usos >= c.usos_max) then
    raise exception 'Cupón no válido o vencido';
  end if;
  return c.pct;
end $$;
create or replace function public.cfx_cupones_lista() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return (select coalesce(jsonb_agg(to_jsonb(c) order by c.creado desc), '[]') from public.cfx_cupones c);
end $$;
create or replace function public.cfx_cupon_guardar(p_codigo text, p_pct int, p_usos_max int default null, p_vence date default null, p_activo boolean default true) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_check();
  insert into public.cfx_cupones (codigo, pct, usos_max, vence, activo) values (upper(trim(p_codigo)), p_pct, p_usos_max, p_vence, coalesce(p_activo, true))
  on conflict (codigo) do update set pct = excluded.pct, usos_max = excluded.usos_max, vence = excluded.vence, activo = excluded.activo;
  perform public.cfx_anotar('cupón', upper(trim(p_codigo)) || ' ' || p_pct || '%');
end $$;
create or replace function public.cfx_cupon_borrar(p_codigo text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_check();
  delete from public.cfx_cupones where codigo = upper(trim(p_codigo));
end $$;

-- ---------- Verificación de identidad (RUT, N° de documento, fotos de la cédula y selfie). Las fotos se borran al revisar. ----------
create or replace function public.cfx_rut_ok(r text) returns boolean
language plpgsql immutable as $$
declare s text := upper(regexp_replace(coalesce(r, ''), '[^0-9kK]', '', 'g')); cuerpo text; dv text; suma int := 0; m int := 2; res text;
begin
  if length(s) < 2 then return false; end if;
  cuerpo := left(s, length(s) - 1); dv := right(s, 1);
  if cuerpo !~ '^[0-9]+$' then return false; end if;
  for i in reverse length(cuerpo)..1 loop
    suma := suma + substr(cuerpo, i, 1)::int * m; m := case when m = 7 then 2 else m + 1 end;
  end loop;
  res := case 11 - suma % 11 when 11 then '0' when 10 then 'K' else (11 - suma % 11)::text end;
  return res = dv;
end $$;
create or replace function public.cfx_verif_estado() returns jsonb
language sql stable security definer set search_path = '' as $$
  select (select jsonb_build_object('estado', estado, 'motivo', motivo, 'creado', creado, 'resuelto', resuelto) from public.cfx_verificaciones where cuenta = auth.uid())
$$;
create or replace function public.cfx_verif_enviar(p_rut text, p_documento text, p_frente text, p_reverso text, p_selfie text) returns void
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); r text := upper(regexp_replace(coalesce(p_rut, ''), '[^0-9kK]', '', 'g'));
begin
  if y is null or (y ->> 'id') is null then raise exception 'Inicia sesión'; end if;
  if not public.cfx_rut_ok(r) then raise exception 'RUT no válido'; end if;
  if exists (select 1 from public.cfx_verificaciones where rut = r and cuenta <> (y ->> 'id')::uuid and estado <> 'rechazada') then raise exception 'Ese RUT ya está en otra cuenta'; end if;
  if exists (select 1 from public.cfx_verificaciones where cuenta = (y ->> 'id')::uuid and estado = 'aprobada') then raise exception 'Tu identidad ya está verificada'; end if;
  if coalesce(length(p_frente), 0) < 200 or coalesce(length(p_reverso), 0) < 200 or coalesce(length(p_selfie), 0) < 200 then raise exception 'Faltan fotos'; end if;
  if length(p_frente) > 500000 or length(p_reverso) > 500000 or length(p_selfie) > 500000 then raise exception 'Fotos muy pesadas'; end if;
  insert into public.cfx_verificaciones (cuenta, email, nombre, rut, documento, frente, reverso, selfie, estado, motivo, creado, resuelto)
  values ((y ->> 'id')::uuid, coalesce(y ->> 'email', ''), left(coalesce(y ->> 'nombre', ''), 80), r, left(coalesce(p_documento, ''), 20), p_frente, p_reverso, p_selfie, 'pendiente', '', now(), null)
  on conflict (cuenta) do update set rut = excluded.rut, documento = excluded.documento, frente = excluded.frente, reverso = excluded.reverso, selfie = excluded.selfie,
    estado = 'pendiente', motivo = '', creado = now(), resuelto = null;
  perform public.cfx_avisar_admin('🪪 Verificación por revisar', coalesce(nullif(y ->> 'nombre', ''), y ->> 'email'));
end $$;
create or replace function public.cfx_verif_lista(p_estado text default 'pendiente') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return (select coalesce(jsonb_agg(x order by x.creado desc), '[]') from (select cuenta, email, nombre, rut, documento, estado, motivo, creado, resuelto
    from public.cfx_verificaciones where p_estado = 'todos' or estado = p_estado order by creado desc limit 200) x);
end $$;
create or replace function public.cfx_verif_fotos(p_cuenta uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return (select jsonb_build_object('frente', frente, 'reverso', reverso, 'selfie', selfie) from public.cfx_verificaciones where cuenta = p_cuenta);
end $$;
create or replace function public.cfx_verif_resolver(p_cuenta uuid, p_aprobar boolean, p_motivo text default '') returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_check();
  update public.cfx_verificaciones set estado = case when p_aprobar then 'aprobada' else 'rechazada' end, motivo = left(coalesce(p_motivo, ''), 200),
    resuelto = now(), frente = null, reverso = null, selfie = null where cuenta = p_cuenta and estado = 'pendiente';
  if not found then raise exception 'No hay una verificación pendiente'; end if;
  perform public.cfx_marcar_verificado(p_cuenta, p_aprobar);
  perform public.cfx_avisar(p_cuenta, case when p_aprobar then '🪪 Identidad verificada' else '🪪 Verificación rechazada' end,
    case when p_aprobar then 'Ya apareces como persona verificada.' else coalesce(nullif(p_motivo, ''), 'Revisa las fotos') || '. Puedes enviarla de nuevo.' end);
  perform public.cfx_anotar(case when p_aprobar then 'verificación aprobada' else 'verificación rechazada' end, p_cuenta::text);
end $$;

create or replace function public.cfx_cupon_usado() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.estado = 'aprobado' and old.estado = 'pendiente' and new.cupon is not null then update public.cfx_cupones set usos = usos + 1 where codigo = new.cupon; end if;
  return new;
end $$;
drop trigger if exists cfx_cupon_usado on public.cfx_pagos;
create trigger cfx_cupon_usado after update of estado on public.cfx_pagos for each row execute function public.cfx_cupon_usado();

-- ---------- Verificación humana (Cloudflare Turnstile): la site key es pública; la secret key va en Supabase → Authentication → CAPTCHA ----------
insert into public.cfx_config (clave, valor) values ('humano', '{"site_key": ""}') on conflict (clave) do nothing;
create or replace function public.cfx_humano() returns jsonb
language sql stable security definer set search_path = '' as $$ select valor from public.cfx_config where clave = 'humano' $$;
create or replace function public.cfx_humano_guardar(p_site_key text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_check();
  if coalesce(p_site_key, '') <> '' and p_site_key !~ '^[0-9A-Za-z_-]{10,60}$' then raise exception 'Site key no válida'; end if;
  update public.cfx_config set valor = jsonb_build_object('site_key', coalesce(p_site_key, '')) where clave = 'humano';
  perform public.cfx_anotar('humano', case when coalesce(p_site_key, '') = '' then 'apagado' else 'site key ' || right(p_site_key, 4) end);
end $$;
revoke all on function public.cfx_humano(), public.cfx_humano_guardar(text) from public;
grant execute on function public.cfx_humano() to anon, authenticated;
grant execute on function public.cfx_humano_guardar(text) to authenticated;

revoke all on function public.cfx_anotar(text, text), public.cfx_cupon_usado() from public, anon, authenticated;
revoke all on function public.cfx_registro_lista(int), public.cfx_planes(), public.cfx_plan_guardar(text, text, jsonb, jsonb), public.cfx_textos(), public.cfx_texto_guardar(text, text),
  public.cfx_aviso_masivo(text, text, text), public.cfx_keys_crear(int, text, int, text), public.cfx_keys_lista(), public.cfx_key_revocar(uuid), public.cfx_key_canjear(text),
  public.cfx_cupon_ver(text), public.cfx_cupones_lista(), public.cfx_cupon_guardar(text, int, int, date, boolean), public.cfx_cupon_borrar(text),
  public.cfx_verif_estado(), public.cfx_verif_enviar(text, text, text, text, text), public.cfx_verif_lista(text), public.cfx_verif_fotos(uuid), public.cfx_verif_resolver(uuid, boolean, text) from public, anon;
grant execute on function public.cfx_registro_lista(int), public.cfx_planes(), public.cfx_plan_guardar(text, text, jsonb, jsonb), public.cfx_textos(), public.cfx_texto_guardar(text, text),
  public.cfx_aviso_masivo(text, text, text), public.cfx_keys_crear(int, text, int, text), public.cfx_keys_lista(), public.cfx_key_revocar(uuid), public.cfx_key_canjear(text),
  public.cfx_cupon_ver(text), public.cfx_cupones_lista(), public.cfx_cupon_guardar(text, int, int, date, boolean), public.cfx_cupon_borrar(text),
  public.cfx_verif_estado(), public.cfx_verif_enviar(text, text, text, text, text), public.cfx_verif_lista(text), public.cfx_verif_fotos(uuid), public.cfx_verif_resolver(uuid, boolean, text) to authenticated;
revoke all on function public.cfx_planes_app(), public.cfx_plan_guardar_app(text, text, jsonb, jsonb), public.cfx_textos_app(), public.cfx_texto_guardar_app(text, text),
  public.cfx_destinatarios(text), public.cfx_marcar_verificado(uuid, boolean) from public, anon, authenticated;

-- ---------- Series para el Resumen del Centro de Mando: por mes, cuentas nuevas y pagos/ingresos aprobados (últimos N meses) ----------
create or replace function public.cfx_series(p_meses int default 6) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare n int := greatest(1, least(coalesce(p_meses, 6), 24));
begin
  perform public.admin_check();
  return (select jsonb_agg(jsonb_build_object('mes', to_char(m, 'YYYY-MM'),
      'cuentas', (select count(*) from auth.users u where u.created_at >= m and u.created_at < m + interval '1 month'),
      'pagos', (select count(*) from public.cfx_pagos p where p.estado = 'aprobado' and p.creado >= m and p.creado < m + interval '1 month'),
      'ingresos', (select coalesce(sum(p.monto), 0) from public.cfx_pagos p where p.estado = 'aprobado' and p.creado >= m and p.creado < m + interval '1 month')) order by m)
    from generate_series(date_trunc('month', now()) - make_interval(months => n - 1), date_trunc('month', now()), interval '1 month') m);
end $$;
-- ---------------------------------------------------------------------
-- CodeFix · Ayuda (igual en las 6 apps; lo reparte nucleo/sincronizar.py).
--   1) Puente al Centro de Mando: los avisos importantes (pagos por revisar, mensajes de soporte) le llegan al tiro
--      al Centro de Mando. El Centro de Mando vincula cada app solo (cfx_cm_vincular) al abrir Pagos o Mensajes.
--   2) Chat de soporte: cada persona escribe desde su app y tú respondes desde el Centro de Mando → Mensajes.
--   3) Guía para partir: lo que le falta configurar a cada negocio (cfx_guia_app() de cada app). No se marca
--      como listo hasta que de verdad lo hace, y se le recuerda cada vez que entra.
--   Cada app define antes: cfx_guia_app() → [{ k, t, d, ok, ir }].
-- ---------------------------------------------------------------------

-- ---------- 1) Puente al Centro de Mando ----------
create or replace function public.cfx_cm_vincular(p_url text, p_key text, p_secreto text, p_app text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_check();
  if coalesce(p_url, '') !~ '^https://[a-z0-9.-]+$' or length(coalesce(p_key, '')) < 20 or length(coalesce(p_secreto, '')) < 24 or coalesce(p_app, '') !~ '^[a-z]{2,20}$' then
    raise exception 'Datos de vínculo no válidos';
  end if;
  insert into public.cfx_config (clave, valor) values ('cm', jsonb_build_object('url', p_url, 'key', p_key, 'secreto', p_secreto, 'app', p_app, 'desde', now()))
  on conflict (clave) do update set valor = excluded.valor;
  return jsonb_build_object('vinculado', true, 'app', p_app);
end $$;

create or replace function public.cfx_cm_estado() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := (select valor from public.cfx_config where clave = 'cm');
begin
  perform public.admin_check();
  return jsonb_build_object('vinculado', coalesce(v ->> 'secreto', '') <> '', 'app', v ->> 'app', 'url', v ->> 'url', 'desde', v -> 'desde');
end $$;

-- Avisa al Centro de Mando (si la app está vinculada); si no, al administrador de esta app. Nunca hace fallar lo que la llama.
create or replace function public.cfx_al_cm(p_titulo text, p_cuerpo text, p_tipo text default 'aviso') returns void
language plpgsql security definer set search_path = '' as $$
declare v jsonb := (select valor from public.cfx_config where clave = 'cm');
begin
  if coalesce(v ->> 'secreto', '') = '' then
    perform public.cfx_avisar_admin(p_titulo, p_cuerpo);
    return;
  end if;
  begin
    perform net.http_post(
      url := (v ->> 'url') || '/rest/v1/rpc/cfx_aviso_externo',
      body := jsonb_build_object('p_app', v ->> 'app', 'p_secreto', v ->> 'secreto', 'p_titulo', left(p_titulo, 90), 'p_cuerpo', left(coalesce(p_cuerpo, ''), 240), 'p_tipo', p_tipo),
      headers := jsonb_build_object('apikey', v ->> 'key', 'Authorization', 'Bearer ' || (v ->> 'key'), 'Content-Type', 'application/json'));
  exception when others then
    begin perform public.cfx_avisar_admin(p_titulo, p_cuerpo); exception when others then null; end;
  end;
end $$;

-- ---------- 2) Chat de soporte ----------
create table if not exists public.cfx_chat (
  id      bigserial primary key,
  cuenta  uuid not null,
  email   text not null default '',
  nombre  text not null default '',
  rol     text not null default '',
  de      text not null check (de in ('persona', 'soporte')),
  texto   text not null check (length(texto) between 1 and 1000),
  leido   boolean not null default false,
  creado  timestamptz not null default now()
);
create index if not exists cfx_chat_cuenta_idx on public.cfx_chat (cuenta, id);
create index if not exists cfx_chat_sin_leer_idx on public.cfx_chat (de, leido) where not leido;
alter table public.cfx_chat enable row level security;
revoke all on public.cfx_chat from anon, authenticated;

create or replace function public.cfx_chat_mio() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); u uuid := (y ->> 'id')::uuid;
begin
  if u is null then raise exception 'Inicia sesión'; end if;
  update public.cfx_chat set leido = true where cuenta = u and de = 'soporte' and not leido;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'de', de, 'texto', texto, 'creado', creado) order by id), '[]')
          from (select * from public.cfx_chat where cuenta = u order by id desc limit 100) x);
end $$;

create or replace function public.cfx_chat_sin_leer() returns int
language sql stable security definer set search_path = '' as $$
  select count(*)::int from public.cfx_chat where cuenta = auth.uid() and de = 'soporte' and not leido
$$;

create or replace function public.cfx_chat_enviar(p_texto text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); u uuid := (y ->> 'id')::uuid; t text := trim(coalesce(p_texto, '')); i bigint;
begin
  if u is null then raise exception 'Inicia sesión'; end if;
  if t = '' then raise exception 'Escribe tu mensaje'; end if;
  if length(t) > 1000 then raise exception 'Máximo 1000 letras'; end if;
  if (select count(*) from public.cfx_chat where cuenta = u and de = 'persona' and creado > now() - interval '1 hour') >= 20 then
    raise exception 'Muchos mensajes seguidos. Espera un poco y te respondemos.';
  end if;
  insert into public.cfx_chat (cuenta, email, nombre, rol, de, texto)
  values (u, coalesce(y ->> 'email', ''), left(coalesce(y ->> 'nombre', ''), 80), coalesce(y ->> 'rol', ''), 'persona', t) returning id into i;
  delete from public.cfx_chat where cuenta = u and creado < now() - interval '365 days';
  perform public.cfx_al_cm('💬 ' || coalesce(nullif(y ->> 'nombre', ''), y ->> 'email', 'Mensaje'), left(t, 200), 'chat');
  return i;
end $$;

-- Administrador: bandeja (una fila por persona), conversación y respuesta.
create or replace function public.cfx_chat_bandeja() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return (select coalesce(jsonb_agg(x order by x.ultimo desc), '[]') from (
    select c.cuenta, max(c.email) as email, max(c.nombre) as nombre, max(c.rol) as rol, max(c.creado) as ultimo,
      (array_agg(c.texto order by c.id desc))[1] as texto, (array_agg(c.de order by c.id desc))[1] as de,
      count(*) filter (where c.de = 'persona' and not c.leido) as sin_leer
    from public.cfx_chat c group by c.cuenta order by max(c.creado) desc limit 200) x);
end $$;

create or replace function public.cfx_chat_hilo(p_cuenta uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_check();
  update public.cfx_chat set leido = true where cuenta = p_cuenta and de = 'persona' and not leido;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'de', de, 'texto', texto, 'creado', creado) order by id), '[]')
          from (select * from public.cfx_chat where cuenta = p_cuenta order by id desc limit 200) x);
end $$;

create or replace function public.cfx_chat_responder(p_cuenta uuid, p_texto text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare t text := trim(coalesce(p_texto, '')); i bigint; o public.cfx_chat;
begin
  perform public.admin_check();
  if t = '' or length(t) > 1000 then raise exception 'Escribe la respuesta (máx. 1000 letras)'; end if;
  select * into o from public.cfx_chat where cuenta = p_cuenta order by id desc limit 1;
  if o.id is null then raise exception 'Conversación no encontrada'; end if;
  insert into public.cfx_chat (cuenta, email, nombre, rol, de, texto, leido) values (p_cuenta, o.email, o.nombre, o.rol, 'soporte', t, false) returning id into i;
  update public.cfx_chat set leido = true where cuenta = p_cuenta and de = 'persona' and not leido;
  perform public.cfx_avisar(p_cuenta, '💬 Soporte te respondió', left(t, 200));
  return i;
end $$;

-- El administrador escribe primero a una cuenta (consejos o recomendaciones): queda en su chat de soporte (🛟) y en CM → Mensajes.
create or replace function public.cfx_chat_iniciar(p_cuenta uuid, p_texto text, p_email text default '', p_nombre text default '', p_rol text default 'negocio') returns bigint
language plpgsql security definer set search_path = '' as $$
declare t text := trim(coalesce(p_texto, '')); i bigint; o public.cfx_chat;
begin
  perform public.admin_check();
  if t = '' or length(t) > 1000 then raise exception 'Escribe el mensaje (máx. 1000 letras)'; end if;
  select * into o from public.cfx_chat where cuenta = p_cuenta order by id desc limit 1;
  insert into public.cfx_chat (cuenta, email, nombre, rol, de, texto, leido)
  values (p_cuenta, coalesce(o.email, left(coalesce(p_email, ''), 200)), coalesce(o.nombre, left(coalesce(p_nombre, ''), 120)), coalesce(o.rol, left(coalesce(p_rol, 'negocio'), 20)), 'soporte', t, false)
  returning id into i;
  perform public.cfx_avisar(p_cuenta, '💬 Soporte te escribió', left(t, 200));
  return i;
end $$;
revoke all on function public.cfx_chat_iniciar(uuid, text, text, text, text) from public, anon;
grant execute on function public.cfx_chat_iniciar(uuid, text, text, text, text) to authenticated;

-- ---------- 3) Guía para partir ----------
-- Pendientes de configuración del negocio (los arma cada app) + verificar identidad. Solo para negocios.
create or replace function public.cfx_guia() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); l jsonb;
begin
  if y is null or (y ->> 'id') is null then raise exception 'Inicia sesión'; end if;
  if y ->> 'rol' <> 'negocio' then return jsonb_build_object('items', '[]'::jsonb, 'sin_leer', public.cfx_chat_sin_leer()); end if;
  l := coalesce(public.cfx_guia_app(), '[]'::jsonb);
  -- Sin guía propia (Centro de Mando): nada que mostrar.
  if jsonb_array_length(l) > 0 and not exists (select 1 from jsonb_array_elements(l) e where e ->> 'k' = 'verificar') then l := l || jsonb_build_array(jsonb_build_object('k', 'verificar', 't', 'Verifica tu identidad',
    'd', 'Tus clientes confían más en un negocio verificado. Toma 2 minutos.',
    'ok', exists (select 1 from public.cfx_verificaciones v where v.cuenta = (y ->> 'id')::uuid and v.estado = 'aprobada'), 'ir', 'verificar')); end if;
  return jsonb_build_object('items', l, 'sin_leer', public.cfx_chat_sin_leer());
end $$;

revoke all on function public.cfx_al_cm(text, text, text) from public, anon, authenticated;
revoke all on function public.cfx_cm_vincular(text, text, text, text), public.cfx_cm_estado(), public.cfx_chat_mio(), public.cfx_chat_sin_leer(), public.cfx_chat_enviar(text),
  public.cfx_chat_bandeja(), public.cfx_chat_hilo(uuid), public.cfx_chat_responder(uuid, text), public.cfx_guia() from public, anon;
grant execute on function public.cfx_cm_vincular(text, text, text, text), public.cfx_cm_estado(), public.cfx_chat_mio(), public.cfx_chat_sin_leer(), public.cfx_chat_enviar(text),
  public.cfx_chat_bandeja(), public.cfx_chat_hilo(uuid), public.cfx_chat_responder(uuid, text), public.cfx_guia() to authenticated;
revoke all on function public.cfx_guia_app() from public, anon, authenticated;
-- ---------------------------------------------------------------------
-- CodeFix · Inventario (igual en las 6 apps; lo usa el Centro de Mando → Apps → Respaldo y limpieza).
--   Muestra las tablas que esta versión ya NO usa (restos de versiones antiguas) con cuántas filas tienen.
--   Nada se borra solo: las vacías se borran con un toque; las que tienen datos piden descargar el respaldo y escribir "sí".
--   cfx_tablas() = las tablas que crea este archivo (la revisa pruebas/inventario.py --verificar).
-- ---------------------------------------------------------------------
create or replace function public.cfx_tablas() returns text[] language sql immutable as $$ select array['public.auditoria', 'public.bloqueos', 'public.calificaciones', 'public.cfx_chat', 'public.cfx_config', 'public.cfx_cupones', 'public.cfx_exentos', 'public.cfx_keys', 'public.cfx_pagos', 'public.cfx_registro', 'public.cfx_verificaciones', 'public.comprobantes', 'public.config', 'public.fotos_trabajo', 'public.invitaciones', 'public.links_pago', 'public.mensajes', 'public.notificaciones', 'public.pagos', 'public.perfiles', 'public.planes', 'public.promos', 'public.push_subs', 'public.reservas', 'public.secretos', 'public.servicios', 'public.talleres', 'public.textos'] $$;
create or replace function public.cfx_inventario() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r record; n bigint; out jsonb := '[]'::jsonb;
begin
  perform public.admin_check();
  for r in select s.nspname || '.' || c.relname as t, pg_total_relation_size(c.oid) as b from pg_class c join pg_namespace s on s.oid = c.relnamespace
           where s.nspname in ('public', 'privado') and c.relkind in ('r', 'p') and not (s.nspname || '.' || c.relname = any (public.cfx_tablas()))
           and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e') order by 1
  loop
    execute 'select count(*) from ' || r.t into n;
    out := out || jsonb_build_object('tabla', r.t, 'filas', n, 'bytes', r.b);
  end loop;
  return out;
end $$;
create or replace function public.cfx_inventario_datos(p_tabla text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare j jsonb;
begin
  perform public.admin_check();
  if not exists (select 1 from jsonb_array_elements(public.cfx_inventario()) x where x ->> 'tabla' = p_tabla) then raise exception 'Esa tabla no está en la lista de sobrantes'; end if;
  execute 'select coalesce(jsonb_agg(to_jsonb(t)), ''[]'') from (select * from ' || p_tabla || ' limit 20000) t' into j;
  return j;
end $$;
create or replace function public.cfx_inventario_borrar(p_tabla text, p_confirmacion text default '') returns text
language plpgsql security definer set search_path = '' as $$
declare x jsonb;
begin
  perform public.admin_check();
  select e into x from jsonb_array_elements(public.cfx_inventario()) e where e ->> 'tabla' = p_tabla;
  if x is null then raise exception 'Esa tabla no está en la lista de sobrantes'; end if;
  if (x ->> 'filas')::bigint > 0 and lower(trim(coalesce(p_confirmacion, ''))) not in ('sí', 'si') then
    raise exception 'La tabla tiene % filas: descarga el respaldo y escribe "sí" para borrarla', x ->> 'filas';
  end if;
  execute 'drop table ' || p_tabla || ' cascade';
  return p_tabla || ' borrada';
end $$;
revoke all on function public.cfx_tablas(), public.cfx_inventario(), public.cfx_inventario_datos(text), public.cfx_inventario_borrar(text, text) from public, anon;
grant execute on function public.cfx_inventario(), public.cfx_inventario_datos(text), public.cfx_inventario_borrar(text, text) to authenticated;
-- <<< CFX núcleo

