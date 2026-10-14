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
language sql immutable as $$ select '1.0'::text $$;

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
  ('vapid_publica', '""')
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
  bloque_min        int not null default 60 check (bloque_min in (15, 20, 30, 45, 60, 90, 120)),
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

alter table public.talleres drop constraint if exists talleres_owner_fk;
alter table public.talleres add constraint talleres_owner_fk foreign key (owner_id) references public.perfiles (id) on delete set null
  deferrable initially deferred;

-- Invitaciones: las crea el servidor (función "servidor") antes de crear la cuenta.
create table if not exists public.invitaciones (
  email        text primary key,
  rol          text not null check (rol in ('taller', 'equipo')),
  nombre       text not null default '',
  telefono     text not null default '',
  taller_id    uuid references public.talleres (id) on delete cascade,
  taller_nombre text not null default '',
  created_by   uuid,
  created_at   timestamptz not null default now()
);
alter table public.invitaciones enable row level security;

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
-- 3. Cuentas nuevas (registro cerrado)
--   · Admin: por correo.  · Taller y equipo: solo con invitación (servidor).
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
      values (new.id, em, left(inv.nombre, 80), inv.telefono, 'equipo', inv.taller_id, inv.created_by);
    end if;
    delete from public.invitaciones where email = em;
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

  raise exception 'El registro está cerrado. Pide tu acceso a tu taller.';
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
create or replace function public.preparar_cuenta(p_caller uuid, p_email text, p_nombre text, p_telefono text,
  p_rol text, p_taller_nombre text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  c public.perfiles;
  em text := lower(trim(coalesce(p_email, '')));
  admin boolean;
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
  elsif p_rol = 'equipo' then
    if c.rol <> 'taller' or public.taller_de(c.id) is null then
      return jsonb_build_object('ok', false, 'error', 'Solo el dueño del taller crea a su equipo');
    end if;
    if (select count(*) from public.perfiles where taller_id = c.taller_id and rol = 'equipo')
       >= coalesce((public.limite_taller(c.taller_id, 'equipo'))::int, 0) then
      return jsonb_build_object('ok', false, 'error', case when public.taller_es_premium(c.taller_id)
        then 'Llegaste al máximo de personas en tu equipo' else 'Tu equipo es una función Premium. Activa Premium para agregar mecánicos.' end);
    end if;
    insert into public.invitaciones (email, rol, nombre, telefono, taller_id, created_by)
    values (em, 'equipo', trim(p_nombre), trim(coalesce(p_telefono, '')), c.taller_id, c.id)
    on conflict (email) do update set rol = excluded.rol, nombre = excluded.nombre, telefono = excluded.telefono,
      taller_id = excluded.taller_id, taller_nombre = '', created_by = excluded.created_by, created_at = now();
  else
    return jsonb_build_object('ok', false, 'error', 'Tipo de cuenta no válido');
  end if;
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
  if tg_table_name = 'servicios' and tg_op = 'INSERT' then
    select count(*) into n from public.servicios where taller_id = new.taller_id;
    lim := coalesce((public.limite_taller(new.taller_id, 'servicios'))::int, 5);
    if n >= lim then raise exception 'Tu plan permite % servicios. Activa Premium para tener más.', lim; end if;
  elsif tg_table_name = 'promos' and new.activa and (tg_op = 'INSERT' or not old.activa) then
    select count(*) into n from public.promos where taller_id = new.taller_id and activa and id <> new.id;
    lim := coalesce((public.limite_taller(new.taller_id, 'promos'))::int, 1);
    if n >= lim then raise exception 'Tu plan permite % promociones activas. Activa Premium para tener más.', lim; end if;
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

insert into public.links_pago (taller_id, tipo, slot, monto, texto, activo)
select null, x.tipo, x.slot, 4990, '', x.slot = 1
from (values ('premium_taller', 1::smallint), ('premium_taller', 2::smallint),
             ('premium_cliente', 1::smallint), ('premium_cliente', 2::smallint)) x(tipo, slot)
where not exists (select 1 from public.links_pago l where l.taller_id is null and l.tipo = x.tipo and l.slot = x.slot);

create or replace function public.link_activo(p_taller uuid, p_tipo text) returns public.links_pago
language sql stable security definer set search_path = '' as $$
  select * from public.links_pago
  where tipo = p_tipo and taller_id is not distinct from p_taller and activo and url <> '' and monto > 0
  order by slot limit 1
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
  from public.perfiles p where p.rol = 'admin' and p.email = public.admin_email()
$$;

create or replace function public.auditar(p_accion text, p_detalle text) returns void
language sql security definer set search_path = '' as $$
  insert into public.auditoria (quien, accion, detalle) values (auth.uid(), p_accion, left(coalesce(p_detalle, ''), 500))
$$;

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
    'premium_taller', (select jsonb_build_object('monto', l.monto, 'url', l.url, 'texto', l.texto)
                       from public.link_activo(null, 'premium_taller') l where l.id is not null),
    'premium_cliente', (select jsonb_build_object('monto', l.monto, 'url', l.url, 'texto', l.texto)
                        from public.link_activo(null, 'premium_cliente') l where l.id is not null))
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
    'colacion_desde', to_char(t.colacion_desde, 'HH24:MI'), 'colacion_hasta', to_char(t.colacion_hasta, 'HH24:MI'),
    'anticipacion_dias', t.anticipacion_dias, 'hoy', (now() at time zone t.zona)::date,
    'reservas_online', t.reservas_online and (public.link_activo(t.id, 'abono')).id is not null,
    'abono', (public.link_activo(t.id, 'abono')).monto,
    'nota', public.nota_taller(t.id),
    'acepta_cuentas', (select count(*) from public.perfiles where taller_id = t.id and rol = 'cliente')
                      < coalesce((public.limite_taller(t.id, 'clientes_cuenta'))::int, 30),
    'servicios', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'nombre', s.nombre, 'descripcion', s.descripcion,
                    'precio', s.precio, 'duracion_min', s.duracion_min) order by s.orden, s.nombre), '[]')
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
  ini := (extract(epoch from c.abre) / 60)::int;
  fin := (extract(epoch from c.cierra) / 60)::int;
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

-- Días con horas libres (para pintar el calendario de reserva).
create or replace function public.dias_libres(p_taller uuid, p_min int) returns setof date
language plpgsql stable security definer set search_path = '' as $$
declare c public.talleres; d date; hoy date; extra int := 0; me public.perfiles;
begin
  select * into c from public.talleres where id = p_taller and activo and not suspendido;
  if c.id is null then return; end if;
  select * into me from public.perfiles where id = auth.uid();
  if me.rol = 'cliente' and me.taller_id = p_taller then extra := coalesce((public.limite_cliente(me.id, 'anticipacion_extra'))::int, 0); end if;
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
create or replace function public.reservar(p_taller uuid, p_servicio uuid, p_fecha date, p_hora text,
  p_nombre text, p_telefono text, p_email text, p_bici text, p_nota text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  c public.talleres; s public.servicios; me public.perfiles; l public.links_pago;
  hoy date; extra int := 0; mins int; nom text; tel text; r public.reservas; n int;
begin
  select * into c from public.talleres where id = p_taller and activo and not suspendido;
  if c.id is null or not c.reservas_online then return jsonb_build_object('ok', false, 'error', 'Este taller no está recibiendo reservas online'); end if;
  l := public.link_activo(p_taller, 'abono');
  if l.id is null then return jsonb_build_object('ok', false, 'error', 'El taller aún no configura el pago del abono'); end if;
  select * into me from public.perfiles where id = auth.uid();
  if me.id is not null and (me.rol <> 'cliente' or me.taller_id <> p_taller) then me := null; end if;
  if me.id is not null then extra := coalesce((public.limite_cliente(me.id, 'anticipacion_extra'))::int, 0); end if;
  nom := left(trim(coalesce(nullif(trim(p_nombre), ''), me.nombre, '')), 80);
  tel := left(trim(coalesce(nullif(trim(p_telefono), ''), me.telefono, '')), 30);
  if nom = '' then return jsonb_build_object('ok', false, 'error', 'Escribe tu nombre'); end if;
  if length(public.tel_norm(tel)) < 9 then return jsonb_build_object('ok', false, 'error', 'Escribe tu WhatsApp'); end if;
  if p_servicio is not null then
    select * into s from public.servicios where id = p_servicio and taller_id = p_taller and activo;
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
  mins := (ceil(mins::numeric / c.bloque_min) * c.bloque_min)::int;
  insert into public.reservas (taller_id, servicio_id, servicio_nombre, precio, fecha, hora, hora_fin, nombre, telefono, tel_norm,
    email, bici, nota, cliente_id, origen, estado, expira_at, abono_monto, abono_estado, historial)
  values (p_taller, s.id, coalesce(s.nombre, 'Revisión general'), coalesce(s.precio, 0), p_fecha, p_hora::time,
    p_hora::time + make_interval(mins => mins), nom, tel, public.tel_norm(tel),
    left(lower(trim(coalesce(nullif(p_email, ''), me.email, ''))), 120), left(trim(coalesce(p_bici, '')), 120),
    left(trim(coalesce(p_nota, '')), 500), me.id, case when me.id is null then 'online' else 'cliente' end,
    'por_pagar', now() + make_interval(mins => coalesce(public.cfg_int('minutos_pago'), 30)), l.monto, 'pendiente',
    public.historial_mas('[]', 'por_pagar'))
  returning * into r;
  perform public.avisar_taller(p_taller, '📅 Nueva reserva', nom || ' · ' || to_char(p_fecha, 'DD/MM') || ' ' || p_hora ||
    ' · esperando abono', '/taller/#reservas');
  return jsonb_build_object('ok', true, 'token', r.token);
end $$;

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
    'proxima_mantencion', r.proxima_mantencion, 'saldo_hasta', r.saldo_hasta, 'created_at', r.created_at,
    'historial', (select coalesce(jsonb_agg(jsonb_build_object('estado', h ->> 'estado', 'at', h ->> 'at')), '[]') from jsonb_array_elements(r.historial) h),
    'cita', cita, 'cancelar', tipo,
    'reagendar', (r.estado = 'confirmada' and cita - now() >= make_interval(hours => hrs))
              or (r.estado = 'cancelada' and r.abono_estado = 'saldo' and r.saldo_hasta > now()),
    'pagar_url', case when r.estado = 'por_pagar' then l.url end,
    'calificada', exists (select 1 from public.calificaciones where reserva_id = r.id and autor = 'cliente'),
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
  update public.reservas set fecha = p_fecha, hora = p_hora::time, hora_fin = p_hora::time + make_interval(mins => mins),
    estado = 'confirmada', abono_estado = 'pagado', saldo_hasta = null, recordado = false, reagendada = reagendada + 1,
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
                  'saldo_hasta', r.saldo_hasta) order by r.fecha, r.hora), '[]')
                from public.reservas r where r.cliente_id = me.id
                  and ((r.estado in ('por_pagar', 'en_revision', 'confirmada', 'recibida', 'en_reparacion', 'esperando_repuesto', 'lista')
                        and public.ocupa_hora(r))
                       or (r.estado = 'cancelada' and r.abono_estado = 'saldo' and r.saldo_hasta > now()))),
    'historial', (select coalesce(jsonb_agg(x order by x.fecha desc), '[]') from (
                  select r.token, r.estado, r.fecha, to_char(r.hora, 'HH24:MI') as hora, r.servicio_nombre as servicio, r.total,
                         r.bici, r.diagnostico, r.items, r.proxima_mantencion,
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
    reservas_online = coalesce((p ->> 'reservas_online')::boolean, reservas_online)
  where id = tid;
  return public.taller_panel();
end $$;

-- Links de pago del abono (2 espacios, uno activo).
create or replace function public.link_guardar(p_tipo text, p_slot int, p_monto int, p_url text, p_texto text, p_activar boolean)
returns void
language plpgsql security definer set search_path = '' as $$
declare tid uuid;
begin
  if p_tipo = 'abono' then
    tid := public.taller_de(auth.uid());
    if tid is null or not public.es_dueno(tid) then raise exception 'Solo el dueño del taller'; end if;
  elsif p_tipo in ('premium_taller', 'premium_cliente') then
    if not public.is_admin() then raise exception 'Solo el administrador'; end if;
    tid := null;
  else raise exception 'Tipo no válido'; end if;
  if p_slot not in (1, 2) then raise exception 'Espacio no válido'; end if;
  if coalesce(p_url, '') <> '' and p_url !~ '^https://' then raise exception 'El link debe empezar con https://'; end if;
  if p_activar and (coalesce(p_url, '') = '' or coalesce(p_monto, 0) <= 0) then raise exception 'Para activarlo pon el monto y el link'; end if;
  insert into public.links_pago (taller_id, tipo, slot, monto, url, texto, activo)
  values (tid, p_tipo, p_slot, greatest(coalesce(p_monto, 0), 0), coalesce(p_url, ''), left(coalesce(p_texto, ''), 300), coalesce(p_activar, false))
  on conflict (coalesce(taller_id, '00000000-0000-0000-0000-000000000000'::uuid), tipo, slot)
  do update set monto = excluded.monto, url = excluded.url, texto = excluded.texto, activo = excluded.activo, updated_at = now();
  if p_activar then
    update public.links_pago set activo = false where tipo = p_tipo and taller_id is not distinct from tid and slot <> p_slot;
  end if;
  if tid is null then perform public.auditar('link', p_tipo || ' espacio ' || p_slot || ' $' || p_monto || case when p_activar then ' (activo)' else '' end); end if;
end $$;

-- Reservas del taller en un rango de fechas (con la nota del cliente).
drop function if exists public.taller_reservas(date, date, text[]);
create or replace function public.taller_reservas(p_desde date, p_hasta date, p_estados text[] default null, p_id uuid default null) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(x order by x.fecha, x.hora), '[]') from (
    select r.id, r.fecha, to_char(r.hora, 'HH24:MI') as hora, to_char(r.hora_fin, 'HH24:MI') as hora_fin, r.nombre, r.telefono,
      r.email, r.bici, r.nota, r.servicio_id, r.servicio_nombre, r.precio, r.estado, r.abono_monto, r.abono_estado, r.expira_at,
      r.origen, r.cliente_id, r.mecanico_id, r.items, r.total, r.diagnostico, r.notas_internas, r.proxima_mantencion,
      r.token, r.motivo, r.reagendada, r.created_at, r.comprobante_at, r.saldo_hasta,
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
    bici, nota, origen, estado, abono_monto, abono_estado, historial, items, total)
  values (tid, s.id, coalesce(s.nombre, 'Revisión general'), coalesce(s.precio, 0), p_fecha, p_hora::time, p_hora::time + make_interval(mins => mins),
    left(trim(p_nombre), 80), left(trim(coalesce(p_telefono, '')), 30), public.tel_norm(p_telefono), left(trim(coalesce(p_bici, '')), 120),
    left(trim(coalesce(p_nota, '')), 500), 'taller', 'confirmada', 0, 'sin_abono', public.historial_mas('[]', 'confirmada'),
    case when s.id is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('nombre', s.nombre, 'cant', 1, 'precio', s.precio)) end,
    coalesce(s.precio, 0));
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
    'email', coalesce(c.email, r.email), 'cuenta', c.id is not null, 'premium', coalesce(c.premium, false),
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
  if not coalesce((public.limite_taller(tid, 'estadisticas'))::boolean, false) then
    return jsonb_build_object('bloqueado', true);
  end if;
  return jsonb_build_object(
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
-- ---------------------------------------------------------------------
create or replace function public.premium_pagar(p_tipo text, p_imagen text) returns jsonb
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
  l := public.link_activo(null, p_tipo);
  if l.id is null then return jsonb_build_object('ok', false, 'error', 'El pago aún no está disponible'); end if;
  if p_imagen !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$' or length(p_imagen) > 600000 then
    return jsonb_build_object('ok', false, 'error', 'Imagen no válida o muy pesada');
  end if;
  if exists (select 1 from public.pagos where perfil_id = me.id and estado = 'en_revision') then
    return jsonb_build_object('ok', false, 'error', 'Ya tienes un comprobante en revisión');
  end if;
  insert into public.pagos (perfil_id, taller_id, tipo, monto) values (me.id, case when p_tipo = 'premium_taller' then me.taller_id end, p_tipo, l.monto)
  returning * into pg;
  insert into public.comprobantes (pago_id, imagen) values (pg.id, p_imagen);
  quien := case when p_tipo = 'premium_taller' then (select nombre from public.talleres where id = me.taller_id)
                else coalesce(nullif(me.nombre, ''), me.email) || ' (cliente)' end;
  perform public.avisar_admin('💰 Pago Premium por revisar', quien || ' · $' || l.monto, '/admin/#pagos');
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.mi_pago_pendiente() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', id, 'monto', monto, 'estado', estado, 'created_at', created_at, 'nota', nota)
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

create or replace function public.admin_resumen() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare tablas jsonb;
begin
  perform public.admin_check();
  select jsonb_object_agg(t, pg_total_relation_size(('public.' || t)::regclass)) into tablas
  from unnest(array['perfiles', 'talleres', 'servicios', 'promos', 'reservas', 'comprobantes', 'pagos', 'calificaciones',
                    'notificaciones', 'push_subs', 'auditoria']) t;
  return jsonb_build_object(
    'talleres', (select count(*) from public.talleres),
    'talleres_premium', (select count(*) from public.talleres where premium_hasta > now()),
    'talleres_activos_7d', (select count(distinct p.taller_id) from public.perfiles p where p.rol in ('taller', 'equipo') and p.visto_at > now() - interval '7 days'),
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
      'notificaciones', (select count(*) from public.notificaciones), 'reservas', (select count(*) from public.reservas)),
    'version', public.db_version());
end $$;

create or replace function public.admin_talleres() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return (select coalesce(jsonb_agg(x order by x.created_at desc), '[]') from (
    select t.id, t.nombre, t.slug, t.telefono, t.comuna, t.logo, t.color, t.icono, t.premium_hasta, t.premium_hasta > now() as premium,
      t.activo, t.suspendido, t.created_at, t.reservas_online,
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
  perform public.admin_check();
  return (select coalesce(jsonb_agg(x order by x.created_at desc), '[]') from (
    select p.id, p.nombre, p.email, p.telefono, p.premium_hasta, p.premium_hasta > now() as premium, p.suspendido, p.visto_at,
      p.created_at, t.nombre as taller, t.id as taller_id, public.nota_cliente(p.telefono) as nota,
      (select count(*) from public.reservas r where r.cliente_id = p.id and r.estado = 'completada') as visitas
    from public.perfiles p left join public.talleres t on t.id = p.taller_id where p.rol = 'cliente' limit 5000) x);
end $$;

-- Dar o quitar Premium (días; 0 = quitar).
create or replace function public.admin_premium(p_tipo text, p_id uuid, p_dias int) returns void
language plpgsql security definer set search_path = '' as $$
declare h timestamptz; owner uuid; nom text;
begin
  perform public.admin_check();
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

create or replace function public.admin_suspender(p_tipo text, p_id uuid, p_suspender boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_check();
  if p_tipo = 'taller' then
    update public.talleres set suspendido = p_suspender where id = p_id;
  else
    update public.perfiles set suspendido = p_suspender where id = p_id and rol <> 'admin';
  end if;
  perform public.auditar(case when p_suspender then 'suspender' else 'reactivar' end, p_tipo || ' ' || p_id);
end $$;

create or replace function public.admin_pagos(p_estado text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return (select coalesce(jsonb_agg(x order by x.created_at desc), '[]') from (
    select g.id, g.tipo, g.monto, g.estado, g.nota, g.created_at, g.resuelto_at,
      coalesce(t.nombre, nullif(p.nombre, ''), p.email) as quien, p.email, p.telefono,
      case when g.tipo = 'premium_taller' then t.premium_hasta else p.premium_hasta end as premium_hasta,
      exists (select 1 from public.comprobantes k where k.pago_id = g.id) as tiene_comprobante
    from public.pagos g join public.perfiles p on p.id = g.perfil_id left join public.talleres t on t.id = g.taller_id
    where p_estado is null or g.estado = p_estado limit 300) x);
end $$;

create or replace function public.admin_pago_comprobante(p_id uuid) returns text
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return (select imagen from public.comprobantes where pago_id = p_id order by created_at desc limit 1);
end $$;

create or replace function public.admin_pago_resolver(p_id uuid, p_aprobar boolean, p_nota text) returns void
language plpgsql security definer set search_path = '' as $$
declare g public.pagos; dias int;
begin
  perform public.admin_check();
  select * into g from public.pagos where id = p_id for update;
  if g.id is null or g.estado <> 'en_revision' then raise exception 'Este pago ya fue revisado'; end if;
  update public.pagos set estado = case when p_aprobar then 'aprobado' else 'rechazado' end, nota = left(coalesce(p_nota, ''), 300),
    resuelto_at = now() where id = g.id;
  if p_aprobar then
    select duracion_dias into dias from public.planes where codigo = case when g.tipo = 'premium_taller' then 'taller_premium' else 'cliente_premium' end;
    if g.tipo = 'premium_taller' then perform public.admin_premium('taller', g.taller_id, coalesce(dias, 30));
    else perform public.admin_premium('cliente', g.perfil_id, coalesce(dias, 30)); end if;
  else
    perform public.avisar(g.perfil_id, '❌ Pago rechazado', coalesce(nullif(p_nota, ''), 'Revisa el comprobante e inténtalo de nuevo.'),
      case when g.tipo = 'premium_taller' then '/taller/#mas' else '/cliente/' end);
  end if;
  perform public.auditar('pago', g.tipo || ' $' || g.monto || ' ' || case when p_aprobar then 'aprobado' else 'rechazado' end);
end $$;

create or replace function public.admin_links() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return (select coalesce(jsonb_agg(jsonb_build_object('tipo', tipo, 'slot', slot, 'monto', monto, 'url', url, 'texto', texto,
    'activo', activo) order by tipo, slot), '[]') from public.links_pago where taller_id is null);
end $$;

create or replace function public.admin_plan_guardar(p_codigo text, p_nombre text, p_descripcion text, p_limites jsonb,
  p_beneficios jsonb, p_duracion int) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_check();
  if jsonb_typeof(p_limites) <> 'object' or jsonb_typeof(p_beneficios) <> 'array' then raise exception 'Datos no válidos'; end if;
  update public.planes set nombre = left(trim(p_nombre), 40), descripcion = left(coalesce(p_descripcion, ''), 300),
    limites = p_limites, beneficios = p_beneficios, duracion_dias = greatest(1, least(coalesce(p_duracion, 30), 3650))
  where codigo = p_codigo;
  if not found then raise exception 'Plan no encontrado'; end if;
  perform public.auditar('plan', p_codigo);
end $$;

create or replace function public.admin_config_guardar(p_clave text, p_valor jsonb) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_check();
  if p_clave not in ('minutos_pago', 'minutos_devolucion', 'horas_cancelacion', 'dias_saldo', 'dias_regalo_taller',
                     'dias_aviso_vencimiento', 'dias_comprobantes', 'soporte_whatsapp', 'vapid_publica') then
    raise exception 'Ajuste no válido';
  end if;
  insert into public.config (clave, valor) values (p_clave, p_valor) on conflict (clave) do update set valor = excluded.valor;
  perform public.auditar('ajuste', p_clave || ' = ' || p_valor::text);
end $$;

create or replace function public.admin_texto_guardar(p_clave text, p_valor text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_check();
  update public.textos set valor = left(coalesce(p_valor, ''), 2000) where clave = p_clave;
  if not found then raise exception 'Texto no encontrado'; end if;
  perform public.auditar('texto', p_clave);
end $$;

create or replace function public.admin_calificaciones() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return (select coalesce(jsonb_agg(x order by x.created_at desc), '[]') from (
    select q.id, q.autor, q.estrellas, q.comentario, q.created_at, t.nombre as taller, r.nombre as cliente
    from public.calificaciones q join public.talleres t on t.id = q.taller_id join public.reservas r on r.id = q.reserva_id
    order by q.created_at desc limit 300) x);
end $$;

create or replace function public.admin_calificacion_borrar(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_check();
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
  perform public.admin_check();
  return (select coalesce(jsonb_agg(x order by x.id desc), '[]') from (select * from public.auditoria order by id desc limit 200) x);
end $$;

-- Limpieza del servidor.
create or replace function public.limpiar(p_que text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare a int := 0; b int := 0; c int := 0; d int := 0; dias int := coalesce(public.cfg_int('dias_comprobantes'), 30);
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
  if p_que in ('otros', 'todo', 'auto') then
    delete from public.auditoria where created_at < now() - interval '365 days';
    delete from public.invitaciones where created_at < now() - interval '2 days';
    get diagnostics d = row_count;
  end if;
  if auth.uid() is not null then perform public.auditar('limpieza', p_que); end if;
  return jsonb_build_object('comprobantes', a, 'notificaciones', b, 'reservas', c, 'otros', d);
end $$;

-- Claves push (las genera el panel del admin).
create or replace function public.admin_push_claves(p_publica text, p_privada text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_check();
  if p_publica !~ '^[A-Za-z0-9_-]{80,100}$' or p_privada !~ '^[A-Za-z0-9_-]{40,50}$' then raise exception 'Claves no válidas'; end if;
  insert into public.secretos (clave, valor) values ('vapid_privada', p_privada) on conflict (clave) do update set valor = excluded.valor;
  insert into public.config (clave, valor) values ('vapid_publica', to_jsonb(p_publica)) on conflict (clave) do update set valor = excluded.valor;
  delete from public.push_subs;  -- las suscripciones con la clave anterior ya no sirven
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
  public.reservar(uuid, uuid, date, text, text, text, text, text, text), public.reserva_ver(text), public.reserva_comprobante(text, text),
  public.reserva_cancelar(text), public.reserva_reagendar(text, date, text), public.reserva_calificar(text, int, text),
  public.db_version(), public.tel_norm(text)
to anon, authenticated;

grant execute on function
  public.is_admin(), public.taller_de(uuid), public.mi_taller(), public.es_dueno(uuid), public.ocupa_hora(public.reservas),
  public.mi_cuenta(), public.registrar_visto(), public.mi_perfil_guardar(text, text), public.cliente_inicio(),
  public.taller_panel(), public.taller_guardar(jsonb), public.link_guardar(text, int, int, text, text, boolean),
  public.taller_reservas(date, date, text[], uuid), public.taller_comprobante(uuid), public.taller_revisar(uuid, boolean, text),
  public.taller_estado(uuid, text), public.taller_trabajo(uuid, jsonb, text, text, uuid, date),
  public.taller_reserva_manual(date, text, uuid, text, text, text, text, boolean), public.taller_devuelto(uuid),
  public.taller_calificar(uuid, int, text), public.taller_clientes(), public.taller_equipo_suspender(uuid, boolean),
  public.taller_estadisticas(), public.taller_recordatorios(), public.taller_limpiar_comprobantes(),
  public.premium_pagar(text, text), public.mi_pago_pendiente(),
  public.admin_resumen(), public.admin_talleres(), public.admin_clientes(), public.admin_premium(text, uuid, int),
  public.admin_suspender(text, uuid, boolean), public.admin_pagos(text), public.admin_pago_comprobante(uuid),
  public.admin_pago_resolver(uuid, boolean, text), public.admin_links(), public.admin_plan_guardar(text, text, text, jsonb, jsonb, int),
  public.admin_config_guardar(text, jsonb), public.admin_texto_guardar(text, text), public.admin_calificaciones(),
  public.admin_calificacion_borrar(uuid), public.admin_aviso(text, text, text), public.admin_auditoria(), public.limpiar(text),
  public.admin_push_claves(text, text), public.push_guardar(text, text, text), public.push_quitar(text)
to authenticated;
-- Usadas por las políticas de seguridad.
grant execute on function public.is_admin(), public.taller_de(uuid), public.mi_taller(), public.es_dueno(uuid) to authenticated;
-- Las de solo-servidor (preparar_cuenta, cancelar_invitacion, push_pendientes, push_borrar_endpoint, tareas_periodicas)
-- quedan sin permiso para la app: las usa la función "servidor" con su clave de servicio y pg_cron.
