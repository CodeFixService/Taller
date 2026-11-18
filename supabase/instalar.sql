-- =====================================================================
--  BiciTaller · INSTALACIÓN / ACTUALIZACIÓN COMPLETA (base de datos + tareas automáticas)
--  Generado de schema.sql + cron.sql. Se puede volver a correr sin perder datos.
-- =====================================================================
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
language sql immutable as $$ select '2.64'::text $$;

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
  ('reserva_pago', 'Para confirmar tu hora paga el abono: con ⚡ Mercado Pago se confirma solo; con el link, sube la foto o captura del comprobante. Tienes {minutos} minutos; si no, la hora se libera.'),
  ('reserva_politica', 'Puedes cancelar sin costo dentro de los primeros {devolucion} minutos (se te devuelve el abono). Después, si cancelas con {horas} horas o más de anticipación, el abono queda como saldo a favor para reagendar. Si cancelas con menos de {horas} horas o no llegas, pierdes el abono. El abono se descuenta del total del servicio.'),
  ('premium_taller_titulo', 'BiciTaller Premium'),
  ('premium_taller_texto', 'Más reservas, tu equipo de mecánicos, estadísticas y recordatorios de mantención para que tus clientes vuelvan.'),
  ('premium_cliente_titulo', 'Cliente Premium'),
  ('premium_cliente_texto', 'Historial completo de tu bici, recordatorios de mantención y reserva con más anticipación.'),
  ('pago_instrucciones', 'Toca "Pagar", paga en Mercado Pago, toma una captura del comprobante y súbela aquí. Te avisamos apenas se apruebe.'),
  ('bienvenida_taller', '¡Bienvenido! Completa tu perfil, tu horario, tus servicios y el cobro del abono (link o ⚡ Mercado Pago) para empezar a recibir reservas.'),
  ('terminos', 'Al usar BiciTaller aceptas que tus datos (nombre, teléfono y correo) se usen solo para gestionar tus reservas con el taller.')
on conflict (clave) do nothing;
-- G100 ⚡ Textos que pedían el link: se actualizan solo si el admin no los cambió.
update public.textos set valor = '¡Bienvenido! Completa tu perfil, tu horario, tus servicios y el cobro del abono (link o ⚡ Mercado Pago) para empezar a recibir reservas.'
where clave = 'bienvenida_taller' and valor = '¡Bienvenido! Completa tu perfil, tu horario, tus servicios y el link de pago del abono para empezar a recibir reservas.';
update public.textos set valor = 'Para confirmar tu hora paga el abono: con ⚡ Mercado Pago se confirma solo; con el link, sube la foto o captura del comprobante. Tienes {minutos} minutos; si no, la hora se libera.'
where clave = 'reserva_pago' and valor = 'Para confirmar tu hora paga el abono con el botón "Pagar abono" y sube la foto o captura del comprobante. Tienes {minutos} minutos; si no, la hora se libera.';
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
              null)  -- G95: parte FREE; la prueba Premium es con el botón 🎁 (antes: dias_regalo_taller)
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
            null, true, ref.id)  -- G95: parte FREE; la prueba Premium es con el botón 🎁 (antes: dias_regalo_taller)
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
-- G100 ⚡ El abono sirve SIN link si el taller tiene su Mercado Pago conectado (plpgsql: cfx_mp_neg_activo es del núcleo, más abajo).
create or replace function public.link_activo(p_taller uuid, p_tipo text) returns public.links_pago
language plpgsql stable security definer set search_path = '' as $$
declare l public.links_pago; mp boolean := false;
begin
  if p_taller is not null then
    select public.cfx_mp_neg_activo(t.owner_id) into mp from public.talleres t where t.id = p_taller;
  end if;
  select * into l from public.links_pago
  where tipo = p_tipo and taller_id is not distinct from p_taller and activo and (url <> '' or coalesce(mp, false)) and monto > 0
    and (hasta is null or hasta >= (now() at time zone 'America/Santiago')::date)
  order by case when p_taller is null then -slot else slot end limit 1;
  return l;
end $$;

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
-- v2.28 (G59): 🧾 checklist de revisión de la bici { frenos: 'ok' | 'ajuste' | 'cambio', ... } (lo ve el cliente en su enlace).
alter table public.reservas add column if not exists checklist jsonb not null default '{}'::jsonb;
-- G59 🧩 ✅ Presupuesto por link: { estado: enviado|respondido, enviado_at, respondido_at }. Cada ítem lleva aprob: pend|si|no.
alter table public.reservas add column if not exists presupuesto jsonb;
-- G59c 🔔 Aviso "bici lista": cuándo quedó lista y si ya le recordamos que la retire.
alter table public.reservas add column if not exists lista_at timestamptz;
alter table public.reservas add column if not exists lista_recordada boolean not null default false;
-- G59f 🧩 🪪 Pasaporte de la bici: orden enlazada al pasaporte (su historial). Sin FK: el pasaporte se crea más abajo.
alter table public.reservas add column if not exists pasaporte_id uuid;
-- G59g 🧩 🚐 Mecánico a domicilio: { direccion, comuna, ref, orden (ruta del día), camino_at }. El taller: { activo, recargo, zona }.
alter table public.reservas add column if not exists domicilio jsonb;
-- G59i 🔁 % de descuento del plan de mantención usado en esta orden (lo aplica orden_total).
alter table public.reservas add column if not exists plan_desc int not null default 0;
-- G98 ⚡ abono con el Mercado Pago del taller (núcleo mp_negocio.sql).
alter table public.reservas add column if not exists mp_desde timestamptz;
alter table public.reservas add column if not exists mp_pago text;
alter table public.reservas drop constraint if exists reservas_plan_desc_chk;
alter table public.reservas add constraint reservas_plan_desc_chk check (plan_desc between 0 and 50);
alter table public.talleres add column if not exists domicilio jsonb not null default '{}'::jsonb;
alter table public.talleres add column if not exists google_resenas text;  -- G74c ⭐ link para dejar reseña en Google (https://)

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
-- G91 📸 Foto del daño por ítem: tipo 'dano' (el ítem guarda su id en items[i].foto).
alter table public.fotos_trabajo drop constraint if exists fotos_trabajo_tipo_check;
alter table public.fotos_trabajo add constraint fotos_trabajo_tipo_check check (tipo in ('antes', 'despues', 'dano'));

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
  c_ini int; c_fin int; ahora timestamp; ok boolean; n int; hd jsonb; cup int; mx int;
begin
  select * into c from public.talleres where id = p_taller;
  if c.id is null or not c.activo or c.suspendido then return; end if;
  if not (extract(dow from p_fecha)::int = any (c.dias)) then return; end if;
  if exists (select 1 from public.bloqueos b where b.taller_id = p_taller and b.fecha = p_fecha and b.desde is null) then return; end if;
  ahora := now() at time zone c.zona;
  -- G91 🚲 cada día puede tener su intervalo (bloque), bicis a la vez (cupos) y máximo del día (max); si no, los generales.
  hd := coalesce(c.horarios -> (extract(dow from p_fecha)::int)::text, '{}'::jsonb);
  paso := coalesce(nullif(hd ->> 'bloque', '')::int, c.bloque_min);
  cup := coalesce(nullif(hd ->> 'cupos', '')::int, c.cupos);
  mx := coalesce(nullif(hd ->> 'max', '')::int, c.max_dia);
  dur := (ceil(greatest(coalesce(p_min, paso), 1)::numeric / paso) * paso)::int;
  -- Horario propio del día (si tiene) y cupo máximo de bicis por día.
  ini := (extract(epoch from coalesce((c.horarios -> (extract(dow from p_fecha)::int)::text ->> 'abre')::time, c.abre)) / 60)::int;
  fin := (extract(epoch from coalesce((c.horarios -> (extract(dow from p_fecha)::int)::text ->> 'cierra')::time, c.cierra)) / 60)::int;
  if mx > 0 and (select count(*) from public.reservas r where r.taller_id = p_taller and r.fecha = p_fecha
      and public.ocupa_hora(r) and (p_excluir is null or r.id <> p_excluir)) >= mx then return; end if;
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
      if n >= cup then ok := false; end if;
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
  -- G98 ⚡ antes de liberar: si abrió Mercado Pago, se pregunta una última vez si pagó.
  if r.estado = 'por_pagar' and r.expira_at <= now() and r.mp_desde is not null and to_regprocedure('public.cfx_mp_neg_revisar(text)') is not null then
    perform public.cfx_mp_neg_revisar('reserva:' || r.id);
    select * into r from public.reservas where id = r.id;
  end if;
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
    'motivo', r.motivo, 'items', r.items, 'total', r.total, 'diagnostico', r.diagnostico, 'checklist', r.checklist, 'presupuesto', r.presupuesto,
    'proxima_mantencion', r.proxima_mantencion, 'saldo_hasta', r.saldo_hasta, 'created_at', r.created_at, 'entrega_estimada', r.entrega_estimada,
    'historial', (select coalesce(jsonb_agg(jsonb_build_object('estado', h ->> 'estado', 'at', h ->> 'at')), '[]') from jsonb_array_elements(r.historial) h),
    'cita', cita, 'cancelar', tipo,
    'reagendar', (r.estado = 'confirmada' and cita - now() >= make_interval(hours => hrs))
              or (r.estado = 'cancelada' and r.abono_estado = 'saldo' and r.saldo_hasta > now()),
    'pagar_url', case when r.estado = 'por_pagar' then l.url end,
    'mp', r.estado = 'por_pagar' and r.abono_monto > 0 and public.cfx_mp_neg_activo(c.owner_id),  -- G98 ⚡
    'medios', case when r.estado = 'por_pagar' and r.abono_monto > 0 then public.cfx_mp_neg_medios(c.owner_id) end,  -- G107 ⚡ MP / 💳 Flow
    'calificada', exists (select 1 from public.calificaciones where reserva_id = r.id and autor = 'cliente'),
    -- Fotos antes/después: se ven durante el trabajo y una semana después; luego, solo el cliente Premium.
    'fotos_n', (select count(*) from public.fotos_trabajo f where f.reserva_id = r.id),
    'fotos_visibles', public.fotos_visibles(r),
    'taller', jsonb_build_object('id', c.id, 'nombre', c.nombre, 'slug', c.slug, 'telefono', c.telefono, 'logo', c.logo,
      'color', c.color, 'icono', c.icono, 'direccion', c.direccion, 'comuna', c.comuna),
    'minutos_devolucion', dev, 'horas_cancelacion', hrs,
    -- G59f 🪪 link del dueño a su pasaporte (con la clave para reportar robo), si el taller tiene el módulo.
    'pasaporte', (select jsonb_build_object('token', p.token, 'clave', p.clave) from public.pasaportes p where p.id = r.pasaporte_id and public.cfx_modulo_de('pasaporte', c.owner_id)),
    -- G59g 🚐 visita a domicilio (dirección y si el mecánico va en camino).
    'domicilio', case when r.domicilio is not null then jsonb_build_object('direccion', r.domicilio ->> 'direccion', 'comuna', r.domicilio ->> 'comuna',
      'ref', r.domicilio ->> 'ref', 'camino_at', r.domicilio ->> 'camino_at') end,
    -- G59h 🛡️ garantía de esta orden (link /g/), si el taller tiene el módulo.
    'garantia', (select jsonb_build_object('token', g.token, 'hasta', g.hasta, 'cubre', g.cubre, 'reclamo', g.reclamo) from public.garantias g
      where g.reserva_id = r.id and public.cfx_modulo_de('garantias', c.owner_id)),
    -- G59i 🔁 descuento del plan en esta orden y el plan del cliente (por teléfono), si el taller tiene el módulo.
    'plan_desc', r.plan_desc,
    'plan', (select jsonb_build_object('nombre', j ->> 'plan_nombre', 'hasta', j -> 'hasta', 'vigente', j -> 'vigente', 'quedan', j -> 'quedan', 'visitas', j -> 'visitas', 'descuento', j -> 'descuento')
      from public.plan_socios s, lateral (select public.plan_socio_json(s, false) j) x
      where s.taller_id = c.id and s.tel_norm = r.tel_norm and length(r.tel_norm) >= 8 and s.activa and public.cfx_modulo_de('plan_mant', c.owner_id) order by s.hasta desc limit 1));
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
  -- G74c ⭐ módulo Reseñas en Google: al cliente feliz (4-5 ★) le pasamos el link de Google del taller.
  return jsonb_build_object('ok', true, 'google', case when p_estrellas >= 4 then
    (select t.google_resenas from public.talleres t where t.id = r.taller_id and public.cfx_modulo_de('resenas', t.owner_id)) end);
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
    'abono_ok', (public.link_activo(tid, 'abono')).id is not null,  -- G100 ⚡ con link o con Mercado Pago conectado
    'pago_pendiente', (select jsonb_build_object('id', id, 'monto', monto, 'created_at', created_at) from public.pagos
                       where taller_id = tid and tipo = 'premium_taller' and estado = 'en_revision' order by created_at desc limit 1),
    'modulos', public.cfx_modulos(), 'venta', public.cfx_venta_on(),  -- G59 🧩 qué módulos puede usar y si se venden
    'por_revisar', (select count(*) from public.reservas where taller_id = tid and estado = 'en_revision'),
    'stock_bajo', (select count(*) from public.repuestos where taller_id = tid and stock <= minimo and minimo > 0),  -- G59d 📦
    'domicilio_hoy', (select count(*) from public.reservas where taller_id = tid and fecha = hoy and domicilio is not null
      and estado not in ('rechazada', 'expirada', 'cancelada', 'no_asistio', 'completada')),  -- G59g 🚐
    'garantia_reclamos', (select count(*) from public.garantias where taller_id = tid and reclamo = 'abierto'),  -- G59h 🛡️
    'planes_vencen', (select count(*) from public.plan_socios where taller_id = tid and activa and hasta between hoy - 7 and hoy + 5),  -- G59i 🔁
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
  -- G91 🚲 lo propio de cada día (sábado/domingo): intervalo, bicis a la vez y máximo del día.
  if exists (select 1 from public.talleres t, jsonb_each(t.horarios) h where t.id = tid and (
       (h.value ? 'bloque' and coalesce(h.value ->> 'bloque', '') !~ '^(15|20|30|45|60|90|120|180|240)$')
    or (h.value ? 'cupos' and coalesce(h.value ->> 'cupos', '') !~ '^([1-9]|1[0-9]|20)$')
    or (h.value ? 'max' and coalesce(h.value ->> 'max', '') !~ '^([0-9]|[1-9][0-9]|1[0-9][0-9]|200)$'))) then
    raise exception 'Revisa sábado y domingo: intervalo, bicis a la vez (1 a 20) o máximo del día (0 a 200)';
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
  if p_activar and coalesce(p_monto, 0) <= 0 then raise exception 'Para activarlo pon el monto'; end if;
  -- G100 ⚡ Abono sin link: vale si el taller tiene su Mercado Pago conectado.
  if p_activar and coalesce(p_url, '') = '' and (tid is null or not exists (select 1 from public.talleres t where t.id = tid and public.cfx_mp_neg_activo(t.owner_id))) then
    raise exception 'Para activarlo pon el link (o conecta ⚡ Mercado Pago abajo)'; end if;
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
      r.token, r.motivo, r.reagendada, r.created_at, r.comprobante_at, r.saldo_hasta, r.entrega_estimada, r.checklist, r.presupuesto, r.lista_at, r.pasaporte_id, r.domicilio, r.plan_desc,
      (select p.nombre from public.perfiles p where p.id = r.mecanico_id) as mecanico,
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
    lista_at = case when p_estado = 'lista' and r.estado <> 'lista' then now() else lista_at end,
    lista_recordada = case when p_estado = 'lista' and r.estado <> 'lista' then false else lista_recordada end,
    historial = public.historial_mas(historial, p_estado), updated_at = now()
  where id = r.id;
  if p_estado = 'completada' then perform public.taller_stock_descontar(r.id); end if;  -- G59d 📦 (si tiene el módulo)
  perform public.avisar(r.cliente_id,
    case p_estado when 'recibida' then '🚲 Recibimos tu bici' when 'en_reparacion' then '🔧 Tu bici está en reparación'
      when 'esperando_repuesto' then '📦 Esperando un repuesto' when 'lista' then '🔧 Tu bici está lista para retiro'
      when 'completada' then '🎉 ¡Gracias por venir!' when 'no_asistio' then '🚫 No llegaste a tu hora'
      when 'cancelada' then '❌ El taller canceló tu reserva' else '📅 Reserva actualizada' end,
    c.nombre || ' · ' || to_char(r.fecha, 'DD/MM'), '/r/?t=' || r.token);
end $$;

-- Detalle del trabajo: servicios y repuestos, diagnóstico, mecánico.
create or replace function public.taller_trabajo(p_id uuid, p_items jsonb, p_diagnostico text, p_notas text,
  p_mecanico uuid, p_proxima date) returns void
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); tot int; antes uuid; r public.reservas; pd int;
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  if jsonb_typeof(p_items) <> 'array' then raise exception 'Ítems no válidos'; end if;
  select mecanico_id, plan_desc into antes, pd from public.reservas where id = p_id and taller_id = tid;
  if p_mecanico is not null and not exists (select 1 from public.perfiles where id = p_mecanico and taller_id = tid and rol in ('taller', 'equipo')) then
    raise exception 'Mecánico no válido';
  end if;
  tot := public.orden_total(p_items, pd);  -- G59: lo que el cliente rechazó no se cobra · G59i 🔁 menos el % del plan
  update public.reservas set items = p_items, total = tot, diagnostico = left(coalesce(p_diagnostico, ''), 1000),
    notas_internas = left(coalesce(p_notas, ''), 1000), mecanico_id = p_mecanico, proxima_mantencion = p_proxima, updated_at = now()
  where id = p_id and taller_id = tid
  returning * into r;
  if r.id is null then raise exception 'Reserva no encontrada'; end if;
  -- G91 📸 La foto del daño de un ítem que ya no está se borra.
  delete from public.fotos_trabajo f where f.reserva_id = r.id and f.tipo = 'dano'
    and not exists (select 1 from jsonb_array_elements(p_items) it where it->>'foto' = f.id::text);
  -- Al mecánico que le asignan la reserva (si no se la asignó él mismo).
  if p_mecanico is not null and p_mecanico is distinct from antes and p_mecanico <> auth.uid() then
    perform public.avisar(p_mecanico, '📅 Te asignaron una reserva',
      coalesce(nullif(r.nombre, ''), 'Cliente') || ' · ' || to_char(r.fecha, 'DD/MM') || ' ' || to_char(r.hora, 'HH24:MI'), '/taller/#agenda');
  end if;
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
               and estado not in ('expirada', 'rechazada')),
    -- G91 📊 Reportes: por mecánico (90 días: trabajos, ingresos y horas promedio de recibida a lista), caja del mes y lo más vendido.
    'mecanicos', (select coalesce(jsonb_agg(x order by x.trabajos desc), '[]') from (
       select coalesce((select coalesce(nullif(p.nombre, ''), p.email) from public.perfiles p where p.id = r.mecanico_id), 'Sin asignar') as nombre,
         count(*) as trabajos, coalesce(sum(r.total), 0) as ingresos,
         round(avg(extract(epoch from (
           (select min((h ->> 'at')::timestamptz) from jsonb_array_elements(r.historial) h where h ->> 'estado' = 'lista') -
           (select min((h ->> 'at')::timestamptz) from jsonb_array_elements(r.historial) h where h ->> 'estado' = 'recibida'))) / 3600)::numeric, 1) as horas
       from public.reservas r where r.taller_id = tid and r.estado = 'completada' and r.completada_at > now() - interval '90 days'
       group by r.mecanico_id) x),
    'caja_mes', (select jsonb_build_object('efectivo', coalesce(sum(total) filter (where medio = 'efectivo'), 0), 'transferencia', coalesce(sum(total) filter (where medio = 'transferencia'), 0),
        'tarjeta', coalesce(sum(total) filter (where medio = 'tarjeta'), 0), 'mostrador', coalesce(sum(total) filter (where reserva_id is null), 0),
        'ordenes', coalesce(sum(total) filter (where reserva_id is not null), 0), 'total', coalesce(sum(total), 0), 'n', count(*))
      from public.caja where taller_id = tid and fecha >= date_trunc('month', public.caja_hoy(tid))::date),
    'vendidos', (select coalesce(jsonb_agg(x order by x.n desc), '[]') from (
       select min(trim(i ->> 'nombre')) as nombre, sum(greatest(coalesce((i ->> 'cant')::numeric, 1), 0)) as n from (
         select i from public.reservas r, jsonb_array_elements(r.items) i where r.taller_id = tid and r.estado = 'completada' and r.completada_at > now() - interval '90 days'
           and coalesce(i ->> 'aprob', '') <> 'no' and jsonb_typeof(r.items) = 'array'
         union all
         select i from public.caja k, jsonb_array_elements(k.items) i where k.taller_id = tid and k.reserva_id is null and k.fecha > current_date - 90) z
       where trim(coalesce(i ->> 'nombre', '')) <> '' group by lower(trim(i ->> 'nombre')) order by 2 desc limit 8) x));
end $$;

-- G91 📊 Reporte para descargar (CSV/Excel): cada cobro de la Caja entre 2 fechas (máx. 1 año). Premium (como las estadísticas).
create or replace function public.taller_reporte(p_desde date, p_hasta date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid());
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  if not coalesce((public.limite_taller(tid, 'estadisticas'))::boolean, false) then raise exception 'Los reportes para descargar son de ⭐ Premium'; end if;
  if p_desde is null or p_hasta is null or p_hasta < p_desde or p_hasta - p_desde > 366 then raise exception 'Elige un rango de hasta 1 año'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('fecha', k.fecha, 'hora', to_char(k.created_at at time zone t.zona, 'HH24:MI'),
      'tipo', case when k.reserva_id is null then 'Mostrador' else 'Orden' end, 'cliente', coalesce(nullif(k.nombre, ''), r.nombre, ''),
      'bici', coalesce(r.bici, ''), 'mecanico', coalesce((select coalesce(nullif(p.nombre, ''), p.email) from public.perfiles p where p.id = r.mecanico_id), ''),
      'detalle', (select coalesce(string_agg(trim(i ->> 'nombre') || case when coalesce((i ->> 'cant')::numeric, 1) <> 1 then ' x' || (i ->> 'cant') else '' end, ', '), '')
                  from jsonb_array_elements(case when jsonb_typeof(k.items) = 'array' then k.items else '[]'::jsonb end) i),
      'medio', k.medio, 'total', k.total, 'boleta', coalesce(k.boleta, '')) order by k.created_at), '[]')
    from public.caja k join public.talleres t on t.id = k.taller_id left join public.reservas r on r.id = k.reserva_id
    where k.taller_id = tid and k.fecha between p_desde and p_hasta);
end $$;
-- (permiso: en la lista de grants de abajo, después del revoke general)

-- Mantenciones por recordar (Premium).
create or replace function public.taller_recordatorios() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid());
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  -- Premium lo trae (como antes) o el módulo ⏰ Recordatorio de mantención (G59c).
  if not coalesce((public.limite_taller(tid, 'recordatorios'))::boolean, false) and not public.taller_tiene('mantencion') then
    return jsonb_build_object('bloqueado', true);
  end if;
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
    'ingresos_mes', (select coalesce(sum(monto), 0) from public.pagos where estado = 'aprobado' and resuelto_at >= greatest(date_trunc('month', now()), public.cfx_ingresos_desde())),
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
  -- 1) Horas retenidas sin pago: se liberan (G98 ⚡ antes se pregunta a Mercado Pago por las que lo abrieron).
  if to_regprocedure('public.cfx_mp_neg_revisar(text)') is not null then
    for r in select id from public.reservas where estado = 'por_pagar' and expira_at <= now() and mp_desde is not null loop
      perform public.cfx_mp_neg_revisar('reserva:' || r.id);
    end loop;
  end if;
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
             and (coalesce((public.limite_cliente(x.cliente_id, 'recordatorios'))::boolean, false)
                  or public.cfx_modulo_de('mantencion', t.owner_id)) loop  -- G59c: o el taller tiene ⏰ Recordatorio de mantención
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

  -- 3b) G59c 🔔 Bici lista hace 2 días y no la retiran (taller con el módulo Aviso "bici lista").
  for r in select x.id, x.cliente_id, x.token, t.nombre from public.reservas x join public.talleres t on t.id = x.taller_id
           where x.estado = 'lista' and not x.lista_recordada and x.lista_at < now() - interval '2 days'
             and public.cfx_modulo_de('aviso_lista', t.owner_id) loop
    perform public.avisar(r.cliente_id, '🔔 Tu bici te espera', 'Ya está lista en ' || r.nombre || ': pasa a retirarla', '/r/?t=' || r.token);
    perform public.avisar_taller((select taller_id from public.reservas where id = r.id), '🔔 Bici lista sin retirar',
      'Hace 2 días: escríbele al cliente', '/taller/#hoy');
    update public.reservas set lista_recordada = true where id = r.id;
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
  public.taller_estadisticas(), public.taller_reporte(date, date), public.taller_recordatorios(), public.taller_limpiar_comprobantes(),
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
    'dias_regalo', 0,  -- G95: ya no hay regalo al registrarse (prueba con botón 🎁); 'prueba' = sí hay botón
    'prueba', true,
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
  -- G59: las fotos de llegada y entrega son GRATIS (antes eran Premium).
  if p_tipo not in ('antes', 'despues', 'dano') then raise exception 'Tipo no válido'; end if;
  if p_imagen !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$' or length(p_imagen) > 160000 then raise exception 'Imagen no válida o muy pesada'; end if;
  if p_tipo = 'dano' and (select count(*) from public.fotos_trabajo where reserva_id = r.id and tipo = 'dano') >= 12 then
    raise exception 'Máximo 12 fotos de daño por orden. Borra una para subir otra.';
  end if;
  if p_tipo <> 'dano' and (select count(*) from public.fotos_trabajo where reserva_id = r.id and tipo = p_tipo) >= 2 then
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
  select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'tipo', f.tipo, 'imagen', f.imagen) order by f.tipo, f.created_at), '[]')
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

create or replace function public.cfx_limpieza_app() returns jsonb
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

create or replace function public.cfx_limpiar_app(p_clave text) returns int
language plpgsql security definer set search_path = '' as $$
declare r jsonb;
begin
  perform public.admin_check();
  if p_clave not in ('comprobantes', 'notificaciones', 'reservas', 'fotos', 'otros') then raise exception 'Opción no válida'; end if;
  r := public.limpiar(p_clave);
  return (select coalesce(sum(v::int), 0) from jsonb_each_text(r) as t(k, v));
end $$;

revoke all on function public.recordar_catalogo(), public.mi_respaldo(), public.cfx_respaldo(), public.cfx_limpieza_app(), public.cfx_limpiar_app(text), public.limpiar(text) from public, anon;
revoke all on function public.recordar_catalogo() from authenticated;
grant execute on function public.mi_respaldo(), public.cfx_respaldo(), public.cfx_limpieza_app(), public.cfx_limpiar_app(text), public.limpiar(text) to authenticated;

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

-- G87 A · Lista de cuentas para el Centro de Mando → Control → Negocios (antes decía "aún no tiene la lista de negocios").
-- Negocio = cada taller (con el correo de su dueño) · Cliente = clientes con cuenta. Solo la llama cfx_negocios (admin).
create or replace function public.cfx_cuentas_app(p_rol text, p_q text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select case when p_rol = 'cliente' then
    (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'email', p.email, 'nombre', p.nombre, 'rol', 'cliente',
        'premium_hasta', case when p.premium_hasta > now() then p.premium_hasta end, 'creado', p.created_at, 'suspendido', p.suspendido) order by p.created_at desc), '[]'::jsonb)
     from (select x.* from public.perfiles x where x.rol = 'cliente'
             and (coalesce(p_q, '') = '' or x.email ilike '%' || p_q || '%' or x.nombre ilike '%' || p_q || '%')
           order by x.created_at desc limit 300) p)
  else
    (select coalesce(jsonb_agg(jsonb_build_object('id', t.owner_id, 'email', coalesce(t.correo, ''), 'nombre', t.nombre, 'rol', 'negocio',
        'premium_hasta', case when t.premium_hasta > now() then t.premium_hasta end, 'creado', t.created_at, 'suspendido', t.suspendido) order by t.created_at desc), '[]'::jsonb)
     from (select x.*, d.email as correo from public.talleres x left join public.perfiles d on d.id = x.owner_id
           where coalesce(p_q, '') = '' or x.nombre ilike '%' || p_q || '%' or coalesce(d.email, '') ilike '%' || p_q || '%'
           order by x.created_at desc limit 300) t)
  end
$$;
create or replace function public.cfx_quitar_premium(p_cuenta uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.talleres set premium_hasta = null where owner_id = p_cuenta;
  update public.perfiles set premium_hasta = null where id = p_cuenta and rol = 'cliente';
end $$;
revoke all on function public.cfx_cuentas_app(text, text), public.cfx_quitar_premium(uuid) from public, anon, authenticated;

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
    jsonb_build_object('k', 'abono', 't', 'Cobro del abono', 'd', 'Tu link de pago o ⚡ Mercado Pago para cobrar el abono previo de cada reserva.', 'ir', 'taller/#mas/abono',
      'ok', (public.link_activo(t.id, 'abono')).id is not null))
  from public.talleres t where t.owner_id = auth.uid()), '[]'::jsonb)
$$;

-- =====================================================================
-- v2.28 · G59 🚲 Taller FREE: 🚦 tablero, 📸 fotos de llegada/entrega gratis, 🧾 checklist de revisión
-- =====================================================================
-- Las fotos ya no son Premium: se saca de la lista de beneficios Premium (si el administrador no la cambió, queda igual).
update public.planes set beneficios = beneficios - 'Fotos antes/después en tus órdenes de trabajo'
where codigo = 'taller_premium' and beneficios ? 'Fotos antes/después en tus órdenes de trabajo';

-- Checklist de revisión: cada punto queda en ok (✅ bien), ajuste (🔧 ajustado) o cambio (🔁 hay que cambiar). Vacío = sin revisar.
create or replace function public.taller_checklist(p_id uuid, p_check jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); limpio jsonb := '{}'::jsonb; k text; v text;
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  if jsonb_typeof(coalesce(p_check, '{}'::jsonb)) <> 'object' then raise exception 'Checklist no válido'; end if;
  for k, v in select key, value #>> '{}' from jsonb_each(coalesce(p_check, '{}'::jsonb)) loop
    if k not in ('frenos', 'cambios', 'ruedas', 'neumaticos', 'cadena', 'pedalier', 'direccion', 'suspension', 'cuadro', 'luces') then
      raise exception 'Punto de revisión no válido: %', k;
    end if;
    if v not in ('ok', 'ajuste', 'cambio') then raise exception 'Valor no válido en %', k; end if;
    limpio := limpio || jsonb_build_object(k, v);
  end loop;
  update public.reservas set checklist = limpio, updated_at = now() where id = p_id and taller_id = tid;
  if not found then raise exception 'Reserva no encontrada'; end if;
  return limpio;
end $$;
revoke all on function public.taller_checklist(uuid, jsonb) from public, anon;
grant execute on function public.taller_checklist(uuid, jsonb) to authenticated;

-- ---------- G59 🧩 Módulos de BiciTaller (catálogo del núcleo: modulos_venta.sql) ----------
-- Negocio = cuenta del dueño del taller (así el núcleo sabe quién compra y prueba). Los módulos NO vienen en Premium (G39): Premium paga -20 %.
create or replace function public.cfx_negocio_de_cuenta(u uuid) returns uuid
language sql stable security definer set search_path = '' as $$
  select t.owner_id from public.talleres t where t.id = public.taller_de(u)
$$;
create or replace function public.cfx_es_premium(n uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select public.taller_es_premium(t.id) from public.talleres t where t.owner_id = n), false)
$$;
create or replace function public.cfx_modulos_app() returns text[]
language sql immutable as $$ select array['presupuesto', 'aviso_lista', 'mantencion', 'stock', 'certificadas', 'tradein', 'pasaporte', 'domicilio', 'garantias', 'plan_mant', 'resenas', 'promos'] $$;  -- G96 b: + 📣 promos
revoke all on function public.cfx_negocio_de_cuenta(uuid), public.cfx_es_premium(uuid), public.cfx_modulos_app() from public, anon, authenticated;
-- G96 b 📣 Promos en la app (núcleo anuncios.sql): el cliente ve las del taller al que pertenece (perfiles.taller_id).
create or replace function public.cfx_promo_negocios_app(u uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce((select jsonb_agg(jsonb_build_object('n', t.owner_id, 'nombre', t.nombre)) from public.perfiles p join public.talleres t on t.id = p.taller_id
    where p.id = u and p.rol = 'cliente' and t.owner_id is not null), '[]')
$$;
revoke all on function public.cfx_promo_negocios_app(uuid) from public, anon, authenticated;
create or replace function public.taller_tiene(p_modulo text) returns boolean
language plpgsql stable security definer set search_path = '' as $$ begin return public.cfx_modulo_de(p_modulo, public.cfx_negocio_de_cuenta(auth.uid())); end $$;
revoke all on function public.taller_tiene(text) from public, anon, authenticated;

-- ✅ Presupuesto por link: el taller pide aprobación de lo que no está aprobado; el cliente responde ítem por ítem en /r/.
create or replace function public.taller_presupuesto(p_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); r public.reservas; nuevos jsonb; n int; c public.talleres;
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  if not public.taller_tiene('presupuesto') then raise exception 'Necesitas el módulo ✅ Presupuesto por link'; end if;
  select * into r from public.reservas where id = p_id and taller_id = tid for update;
  if r.id is null then raise exception 'Reserva no encontrada'; end if;
  if r.estado in ('completada', 'cancelada', 'no_asistio', 'rechazada', 'expirada') then raise exception 'Esta reserva ya cerró'; end if;
  select coalesce(jsonb_agg(case when coalesce(i ->> 'aprob', '') in ('si', 'no') then i else i || '{"aprob":"pend"}' end order by o), '[]'),
         count(*) filter (where coalesce(i ->> 'aprob', '') not in ('si', 'no'))
    into nuevos, n from jsonb_array_elements(r.items) with ordinality x(i, o);
  if n = 0 then raise exception 'No hay nada nuevo para aprobar: agrega servicios o repuestos'; end if;
  update public.reservas set items = nuevos, updated_at = now(),
    presupuesto = jsonb_build_object('estado', 'enviado', 'enviado_at', now())
  where id = r.id;
  select * into c from public.talleres where id = tid;
  perform public.avisar(r.cliente_id, '🧾 Presupuesto para aprobar', c.nombre || ': aprueba o rechaza cada arreglo', '/r/?t=' || r.token);
  return jsonb_build_object('pendientes', n, 'token', r.token);
end $$;
revoke all on function public.taller_presupuesto(uuid) from public, anon;
grant execute on function public.taller_presupuesto(uuid) to authenticated;

-- El cliente responde: p_resp = {"0": "si", "2": "no"} (posición del ítem). Tiene que responder todos los pendientes.
create or replace function public.reserva_presupuesto(p_token text, p_resp jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r public.reservas; nuevos jsonb; tot int; nsi int; nno int; falta int;
begin
  select * into r from public.reservas where token = p_token and length(p_token) >= 20 for update;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'Reserva no encontrada'); end if;
  if coalesce(r.presupuesto ->> 'estado', '') <> 'enviado' then return jsonb_build_object('ok', false, 'error', 'No hay presupuesto por responder'); end if;
  if jsonb_typeof(coalesce(p_resp, 'null')) <> 'object' then return jsonb_build_object('ok', false, 'error', 'Respuesta no válida'); end if;
  select count(*) into falta from jsonb_array_elements(r.items) with ordinality x(i, o)
  where i ->> 'aprob' = 'pend' and coalesce(p_resp ->> (o - 1)::text, '') not in ('si', 'no');
  if falta > 0 then return jsonb_build_object('ok', false, 'error', 'Responde Sí o No en cada arreglo'); end if;
  select coalesce(jsonb_agg(case when i ->> 'aprob' = 'pend' then i || jsonb_build_object('aprob', p_resp ->> (o - 1)::text) else i end order by o), '[]')
    into nuevos from jsonb_array_elements(r.items) with ordinality x(i, o);
  select coalesce(sum(greatest(coalesce((i ->> 'cant')::numeric, 1), 0) * greatest(coalesce((i ->> 'precio')::numeric, 0), 0))
           filter (where coalesce(i ->> 'aprob', '') <> 'no'), 0)::int,
         count(*) filter (where i ->> 'aprob' = 'si'), count(*) filter (where i ->> 'aprob' = 'no')
    into tot, nsi, nno from jsonb_array_elements(nuevos) i;
  tot := public.orden_total(nuevos, r.plan_desc);  -- G59i 🔁
  update public.reservas set items = nuevos, total = tot, updated_at = now(),
    presupuesto = r.presupuesto || jsonb_build_object('estado', 'respondido', 'respondido_at', now())
  where id = r.id;
  perform public.avisar_taller(r.taller_id, '🧾 ' || left(r.nombre, 40) || ' respondió el presupuesto',
    nsi || ' aprobado' || case when nsi = 1 then '' else 's' end || ' · ' || nno || ' rechazado' || case when nno = 1 then '' else 's' end, '/taller/#reservas');
  return jsonb_build_object('ok', true, 'total', tot);
end $$;
revoke all on function public.reserva_presupuesto(text, jsonb) from public;
grant execute on function public.reserva_presupuesto(text, jsonb) to anon, authenticated;

-- ---------- G59d 🧩 📦 Repuestos y stock + 🛒 pedido a proveedor (G68: genérico, los proveedores del taller) ----------
-- El stock baja solo al entregar la orden (por nombre del ítem, una vez: reservas.stock_at). Stock ≤ mínimo → se pide.
create table if not exists public.proveedores (
  id         uuid primary key default gen_random_uuid(),
  taller_id  uuid not null references public.talleres (id) on delete cascade,
  nombre     text not null check (length(trim(nombre)) between 1 and 80),
  telefono   text not null default '' check (length(telefono) <= 30),
  email      text not null default '' check (length(email) <= 120),
  nota       text not null default '' check (length(nota) <= 300),
  created_at timestamptz not null default now()
);
create index if not exists proveedores_t_idx on public.proveedores (taller_id);
alter table public.proveedores enable row level security;
create table if not exists public.repuestos (
  id           uuid primary key default gen_random_uuid(),
  taller_id    uuid not null references public.talleres (id) on delete cascade,
  nombre       text not null check (length(trim(nombre)) between 1 and 100),
  precio       int not null default 0 check (precio >= 0),
  stock        int not null default 0 check (stock >= 0),
  minimo       int not null default 0 check (minimo >= 0),
  proveedor_id uuid references public.proveedores (id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create unique index if not exists repuestos_nombre_idx on public.repuestos (taller_id, lower(trim(nombre)));
alter table public.repuestos enable row level security;
-- G91 🛒 Tienda (va con el módulo 📦 Repuestos y stock): lo publicado sale en la página del taller (/t/) y se pide por WhatsApp.
alter table public.repuestos add column if not exists tienda boolean not null default false;
alter table public.repuestos add column if not exists tipo text not null default 'repuesto';
alter table public.repuestos add column if not exists descripcion text not null default '';
alter table public.repuestos add column if not exists foto text;
alter table public.repuestos drop constraint if exists repuestos_tienda_chk;
alter table public.repuestos add constraint repuestos_tienda_chk check (tipo in ('repuesto', 'accesorio', 'bici') and length(descripcion) <= 300
  and (foto is null or (foto ~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$' and length(foto) <= 120000)));
alter table public.reservas add column if not exists stock_at timestamptz;

create or replace function public.taller_stock() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid());
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  if not public.taller_tiene('stock') then return jsonb_build_object('bloqueado', true); end if;
  return jsonb_build_object(
    'repuestos', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'nombre', r.nombre, 'precio', r.precio, 'stock', r.stock, 'minimo', r.minimo,
                   'proveedor_id', r.proveedor_id, 'tienda', r.tienda, 'tipo', r.tipo, 'descripcion', r.descripcion, 'con_foto', r.foto is not null) order by lower(r.nombre)), '[]')
                  from public.repuestos r where r.taller_id = tid),
    'proveedores', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nombre', p.nombre, 'telefono', p.telefono, 'email', p.email, 'nota', p.nota)
                   order by lower(p.nombre)), '[]') from public.proveedores p where p.taller_id = tid));
end $$;

create or replace function public.taller_repuesto_guardar(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); rid uuid := nullif(p ->> 'id', '')::uuid; pv uuid := nullif(p ->> 'proveedor_id', '')::uuid; n text := trim(coalesce(p ->> 'nombre', ''));
begin
  if tid is null or not public.es_dueno(tid) then raise exception 'Solo el dueño del taller puede cambiar esto'; end if;
  if not public.taller_tiene('stock') then raise exception 'Necesitas el módulo 📦 Repuestos y stock'; end if;
  if n = '' then raise exception 'Escribe el nombre del repuesto'; end if;
  if pv is not null and not exists (select 1 from public.proveedores where id = pv and taller_id = tid) then raise exception 'Proveedor no válido'; end if;
  if exists (select 1 from public.repuestos where taller_id = tid and lower(trim(nombre)) = lower(n) and id is distinct from rid) then raise exception 'Ya tienes un repuesto con ese nombre'; end if;
  if rid is null then
    if (select count(*) from public.repuestos where taller_id = tid) >= 500 then raise exception 'Llegaste al máximo de 500 repuestos'; end if;
    insert into public.repuestos (taller_id, nombre, precio, stock, minimo, proveedor_id)
    values (tid, left(n, 100), greatest(coalesce((p ->> 'precio')::int, 0), 0), greatest(coalesce((p ->> 'stock')::int, 0), 0),
            greatest(coalesce((p ->> 'minimo')::int, 0), 0), pv) returning id into rid;
  else
    update public.repuestos set nombre = left(n, 100), precio = greatest(coalesce((p ->> 'precio')::int, precio), 0), stock = greatest(coalesce((p ->> 'stock')::int, stock), 0),
      minimo = greatest(coalesce((p ->> 'minimo')::int, minimo), 0), proveedor_id = pv, updated_at = now()
    where id = rid and taller_id = tid;
    if not found then raise exception 'Repuesto no encontrado'; end if;
  end if;
  -- G91 🛒 lo de la tienda (solo si viene; si no, queda como estaba)
  if p ? 'tienda' and coalesce((p ->> 'tienda')::boolean, false) and not (select r.tienda from public.repuestos r where r.id = rid)
     and (select count(*) from public.repuestos where taller_id = tid and tienda) >= 40 then raise exception 'Máximo 40 productos en la tienda'; end if;
  update public.repuestos set
    tienda = case when p ? 'tienda' then coalesce((p ->> 'tienda')::boolean, false) else tienda end,
    tipo = case when p ->> 'tipo' in ('repuesto', 'accesorio', 'bici') then p ->> 'tipo' else tipo end,
    descripcion = case when p ? 'descripcion' then left(trim(coalesce(p ->> 'descripcion', '')), 300) else descripcion end,
    foto = case when p ? 'foto' then nullif(p ->> 'foto', '') else foto end
  where id = rid;
  return rid;
end $$;

create or replace function public.taller_repuesto_foto(p_id uuid) returns text
language sql stable security definer set search_path = '' as $$
  select r.foto from public.repuestos r where r.id = p_id and r.taller_id = public.taller_de(auth.uid())
$$;
-- G91 🛒 Tienda pública del taller (solo con el módulo 📦 y lo marcado "en mi tienda").
create or replace function public.tienda_publica(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'nombre', r.nombre, 'precio', r.precio, 'tipo', r.tipo, 'descripcion', r.descripcion, 'foto', r.foto,
           'hay', r.stock > 0, 'quedan', case when r.stock between 1 and 3 then r.stock end) order by r.tipo = 'bici' desc, r.stock > 0 desc, lower(r.nombre))
    from public.talleres t join public.repuestos r on r.taller_id = t.id and r.tienda
    where t.slug = lower(p_slug) and t.activo and not t.suspendido and public.cfx_modulo_de('stock', t.owner_id)), '[]');
end $$;
revoke all on function public.taller_repuesto_foto(uuid), public.tienda_publica(text) from public, anon, authenticated;
grant execute on function public.taller_repuesto_foto(uuid) to authenticated;
grant execute on function public.tienda_publica(text) to anon, authenticated;
create or replace function public.taller_repuesto_borrar(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid());
begin
  if tid is null or not public.es_dueno(tid) then raise exception 'Solo el dueño del taller puede cambiar esto'; end if;
  delete from public.repuestos where id = p_id and taller_id = tid;
end $$;

-- Todo el equipo: ➖➕ al stock y 📥 "llegó el pedido" (p = {"<id>": cantidad, ...}, puede ser negativo para ➖).
create or replace function public.taller_stock_sumar(p jsonb) returns int
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); n int;
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  if not public.taller_tiene('stock') then raise exception 'Necesitas el módulo 📦 Repuestos y stock'; end if;
  if jsonb_typeof(coalesce(p, 'null')) <> 'object' then raise exception 'Datos no válidos'; end if;
  update public.repuestos r set stock = greatest(r.stock + (x.value)::int, 0), updated_at = now()
  from jsonb_each_text(p) x where x.key ~ '^[0-9a-f-]{36}$' and r.id = x.key::uuid and r.taller_id = tid and x.value ~ '^-?[0-9]{1,5}$';
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.taller_proveedor_guardar(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); pid uuid := nullif(p ->> 'id', '')::uuid; n text := trim(coalesce(p ->> 'nombre', ''));
begin
  if tid is null or not public.es_dueno(tid) then raise exception 'Solo el dueño del taller puede cambiar esto'; end if;
  if not public.taller_tiene('stock') then raise exception 'Necesitas el módulo 📦 Repuestos y stock'; end if;
  if n = '' then raise exception 'Escribe el nombre del proveedor'; end if;
  if pid is null then
    if (select count(*) from public.proveedores where taller_id = tid) >= 50 then raise exception 'Llegaste al máximo de 50 proveedores'; end if;
    insert into public.proveedores (taller_id, nombre, telefono, email, nota)
    values (tid, left(n, 80), left(trim(coalesce(p ->> 'telefono', '')), 30), left(lower(trim(coalesce(p ->> 'email', ''))), 120), left(coalesce(p ->> 'nota', ''), 300)) returning id into pid;
  else
    update public.proveedores set nombre = left(n, 80), telefono = left(trim(coalesce(p ->> 'telefono', '')), 30),
      email = left(lower(trim(coalesce(p ->> 'email', ''))), 120), nota = left(coalesce(p ->> 'nota', ''), 300)
    where id = pid and taller_id = tid;
    if not found then raise exception 'Proveedor no encontrado'; end if;
  end if;
  return pid;
end $$;

create or replace function public.taller_proveedor_borrar(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid());
begin
  if tid is null or not public.es_dueno(tid) then raise exception 'Solo el dueño del taller puede cambiar esto'; end if;
  delete from public.proveedores where id = p_id and taller_id = tid;
end $$;

-- ✨ Repuestos de fábrica (la lista viene de shared/fabrica.js: [[nombre, precio], ...]); agrega los que faltan, stock 0.
create or replace function public.taller_repuestos_fabrica(p_lista jsonb) returns int
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); n int := 0; x jsonb; hay int;
begin
  if tid is null or not public.es_dueno(tid) then raise exception 'Solo el dueño del taller puede cambiar esto'; end if;
  if not public.taller_tiene('stock') then raise exception 'Necesitas el módulo 📦 Repuestos y stock'; end if;
  if jsonb_typeof(coalesce(p_lista, 'null')) <> 'array' then raise exception 'Lista no válida'; end if;
  select count(*) into hay from public.repuestos where taller_id = tid;
  for x in select * from jsonb_array_elements(p_lista) limit 100 loop
    exit when hay + n >= 500;
    continue when jsonb_typeof(x) <> 'array' or length(trim(coalesce(x ->> 0, ''))) not between 1 and 100;
    insert into public.repuestos (taller_id, nombre, precio)
    values (tid, trim(x ->> 0), greatest(coalesce(case when (x ->> 1) ~ '^[0-9]{1,7}$' then (x ->> 1)::int end, 0), 0))
    on conflict (taller_id, lower(trim(nombre))) do nothing;
    if found then n := n + 1; end if;
  end loop;
  return n;
end $$;

-- Al entregar: descuenta lo que se usó (ítems con el mismo nombre que un repuesto; lo rechazado no). Avisa lo que quedó bajo el mínimo.
create or replace function public.taller_stock_descontar(p_reserva uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare r public.reservas; bajos text;
begin
  select * into r from public.reservas where id = p_reserva for update;
  if r.id is null or r.stock_at is not null or not public.taller_tiene('stock') then return; end if;
  with uso as (
    select lower(trim(i ->> 'nombre')) n, sum(greatest(coalesce((i ->> 'cant')::numeric, 1), 0))::int c
    from jsonb_array_elements(r.items) i where coalesce(i ->> 'aprob', '') <> 'no' group by 1),
  bajo as (
    update public.repuestos p set stock = greatest(p.stock - u.c, 0), updated_at = now()
    from uso u where p.taller_id = r.taller_id and lower(trim(p.nombre)) = u.n and u.c > 0
    returning p.nombre, p.stock, p.minimo, p.stock + u.c antes)
  select string_agg(nombre, ', ') into bajos from bajo where minimo > 0 and stock <= minimo and antes > minimo;
  update public.reservas set stock_at = now() where id = r.id;
  if bajos is not null then
    perform public.avisar_taller(r.taller_id, '📦 Se está acabando: ' || left(bajos, 80), 'Toca para armar el pedido a tu proveedor', '/taller/#mas/stock');
  end if;
end $$;
revoke all on function public.taller_stock_descontar(uuid) from public, anon, authenticated;
revoke all on function public.taller_stock(), public.taller_repuesto_guardar(jsonb), public.taller_repuesto_borrar(uuid), public.taller_stock_sumar(jsonb),
  public.taller_proveedor_guardar(jsonb), public.taller_proveedor_borrar(uuid), public.taller_repuestos_fabrica(jsonb) from public, anon;
grant execute on function public.taller_stock(), public.taller_repuesto_guardar(jsonb), public.taller_repuesto_borrar(uuid), public.taller_stock_sumar(jsonb),
  public.taller_proveedor_guardar(jsonb), public.taller_proveedor_borrar(uuid), public.taller_repuestos_fabrica(jsonb) to authenticated;

-- ---------- G59e 🧩 🏷️ Bicis usadas certificadas (informe de 50 puntos + fotos + garantía → vitrina /t/ y ficha /u/) ----------
-- informe = { punto: ok|ajuste|cambio } (los 50 puntos están en taller.js y u/). Publicar exige los 50 revisados y 1 foto.
-- 🔄 Parte de pago (tradein) es una calculadora en la pantalla: no guarda nada aquí (puede crear un borrador de usada).
create table if not exists public.bicis_usadas (
  id          uuid primary key default gen_random_uuid(),
  taller_id   uuid not null references public.talleres (id) on delete cascade,
  titulo      text not null check (length(trim(titulo)) between 1 and 100),
  talla       text not null default '' check (length(talla) <= 20),
  anio        int check (anio between 1980 and 2100),
  precio      int not null default 0 check (precio >= 0),
  garantia    int not null default 3 check (garantia between 0 and 24),
  nota        text not null default '' check (length(nota) <= 600),
  informe     jsonb not null default '{}',
  fotos       jsonb not null default '[]',
  mini        text not null default '',
  estado      text not null default 'borrador' check (estado in ('borrador', 'publicada', 'vendida')),
  token       text not null unique default replace(gen_random_uuid()::text, '-', ''),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  vendida_at  timestamptz
);
create index if not exists bicis_usadas_t_idx on public.bicis_usadas (taller_id, estado);
alter table public.bicis_usadas enable row level security;

create or replace function public.usada_revisados(i jsonb) returns int
language sql immutable set search_path = '' as $$
  select count(*)::int from jsonb_each_text(coalesce(i, '{}')) e where e.value in ('ok', 'ajuste', 'cambio')
$$;
create or replace function public.usada_json(b public.bicis_usadas, p_fotos boolean) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object('id', b.id, 'titulo', b.titulo, 'talla', b.talla, 'anio', b.anio, 'precio', b.precio, 'garantia', b.garantia,
    'nota', b.nota, 'informe', b.informe, 'revisados', public.usada_revisados(b.informe), 'mini', b.mini, 'nfotos', jsonb_array_length(b.fotos),
    'estado', b.estado, 'token', b.token, 'vendida_at', b.vendida_at, 'created_at', b.created_at)
    || case when p_fotos then jsonb_build_object('fotos', b.fotos) else '{}'::jsonb end
$$;

create or replace function public.taller_usadas() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid());
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  if not public.taller_tiene('certificadas') then return jsonb_build_object('bloqueado', true); end if;
  return jsonb_build_object('bicis', (select coalesce(jsonb_agg(public.usada_json(b, false)
    order by case b.estado when 'publicada' then 0 when 'borrador' then 1 else 2 end, b.updated_at desc), '[]') from public.bicis_usadas b where b.taller_id = tid));
end $$;

create or replace function public.taller_usada(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); b public.bicis_usadas;
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  select * into b from public.bicis_usadas where id = p_id and taller_id = tid;
  if b.id is null then raise exception 'Bici no encontrada'; end if;
  return public.usada_json(b, true);
end $$;

-- Todo el equipo puede inspeccionar y guardar; publicar/vender también (lo ve el dueño). Borrar: solo el dueño.
create or replace function public.taller_usada_guardar(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); bid uuid := nullif(p ->> 'id', '')::uuid; n text := trim(coalesce(p ->> 'titulo', ''));
  est text := coalesce(nullif(p ->> 'estado', ''), 'borrador'); inf jsonb := coalesce(p -> 'informe', '{}'); fs jsonb := p -> 'fotos'; mi text := p ->> 'mini'; f text;
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  if not public.taller_tiene('certificadas') then raise exception 'Necesitas el módulo 🏷️ Bicis usadas certificadas'; end if;
  if n = '' then raise exception 'Escribe la marca y el modelo'; end if;
  if est not in ('borrador', 'publicada', 'vendida') then raise exception 'Estado no válido'; end if;
  if jsonb_typeof(inf) <> 'object' or (select count(*) from jsonb_object_keys(inf)) > 60 then raise exception 'Informe no válido'; end if;
  if fs is not null then
    if jsonb_typeof(fs) <> 'array' or jsonb_array_length(fs) > 4 then raise exception 'Máximo 4 fotos'; end if;
    for f in select jsonb_array_elements_text(fs) loop
      if f !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$' or length(f) > 160000 then raise exception 'Foto no válida o muy pesada'; end if;
    end loop;
  end if;
  if mi is not null and mi <> '' and (mi !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$' or length(mi) > 60000) then raise exception 'Foto no válida'; end if;
  if est = 'publicada' then
    if public.usada_revisados(inf) < 50 then raise exception 'Para publicarla como certificada revisa los 50 puntos (van %)', public.usada_revisados(inf); end if;
    if jsonb_array_length(coalesce(fs, (select fotos from public.bicis_usadas where id = bid and taller_id = tid), '[]')) = 0 then raise exception 'Sube al menos 1 foto para publicarla'; end if;
    if coalesce((p ->> 'precio')::int, 0) <= 0 then raise exception 'Pon el precio para publicarla'; end if;
  end if;
  if bid is null then
    if (select count(*) from public.bicis_usadas where taller_id = tid and estado <> 'vendida') >= 100 then raise exception 'Llegaste al máximo de 100 bicis a la venta'; end if;
    insert into public.bicis_usadas (taller_id, titulo, talla, anio, precio, garantia, nota, informe, fotos, mini, estado, vendida_at)
    values (tid, left(n, 100), left(trim(coalesce(p ->> 'talla', '')), 20), nullif(p ->> 'anio', '')::int, greatest(coalesce((p ->> 'precio')::int, 0), 0),
            least(greatest(coalesce((p ->> 'garantia')::int, 3), 0), 24), left(coalesce(p ->> 'nota', ''), 600), inf, coalesce(fs, '[]'), coalesce(mi, ''), est,
            case when est = 'vendida' then now() end) returning id into bid;
  else
    update public.bicis_usadas set titulo = left(n, 100), talla = left(trim(coalesce(p ->> 'talla', '')), 20), anio = nullif(p ->> 'anio', '')::int,
      precio = greatest(coalesce((p ->> 'precio')::int, 0), 0), garantia = least(greatest(coalesce((p ->> 'garantia')::int, 3), 0), 24),
      nota = left(coalesce(p ->> 'nota', ''), 600), informe = inf, fotos = coalesce(fs, fotos), mini = coalesce(mi, mini), estado = est,
      vendida_at = case when est = 'vendida' then coalesce(vendida_at, now()) end, updated_at = now()
    where id = bid and taller_id = tid;
    if not found then raise exception 'Bici no encontrada'; end if;
  end if;
  return bid;
end $$;

create or replace function public.taller_usada_borrar(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid());
begin
  if tid is null or not public.es_dueno(tid) then raise exception 'Solo el dueño del taller puede borrar'; end if;
  delete from public.bicis_usadas where id = p_id and taller_id = tid;
  if not found then raise exception 'Bici no encontrada'; end if;
end $$;

-- Público: vitrina del taller (/t/) y ficha con el informe (/u/). Solo si el taller tiene el módulo.
-- plpgsql (no sql): cfx_modulo_de viene más abajo, en el bloque del núcleo.
create or replace function public.usadas_publicas(p_slug text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  return coalesce((select jsonb_agg(jsonb_build_object('titulo', b.titulo, 'talla', b.talla, 'anio', b.anio, 'precio', b.precio, 'garantia', b.garantia,
           'revisados', public.usada_revisados(b.informe), 'mini', b.mini, 'token', b.token) order by b.updated_at desc)
    from public.talleres t join public.bicis_usadas b on b.taller_id = t.id and b.estado = 'publicada'
    where t.slug = p_slug and public.cfx_modulo_de('certificadas', t.owner_id)), '[]');
end $$;
create or replace function public.usada_ver(p_token text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  return (select public.usada_json(b, true) - 'id' - 'mini' || jsonb_build_object('taller', jsonb_build_object('nombre', t.nombre, 'slug', t.slug, 'telefono', t.telefono,
           'logo', t.logo, 'color', t.color, 'icono', t.icono, 'comuna', t.comuna, 'direccion', t.direccion))
  from public.bicis_usadas b join public.talleres t on t.id = b.taller_id
  where b.token = p_token and length(p_token) >= 20 and b.estado in ('publicada', 'vendida') and public.cfx_modulo_de('certificadas', t.owner_id));
end $$;
revoke all on function public.usada_revisados(jsonb), public.usada_json(public.bicis_usadas, boolean), public.taller_usadas(), public.taller_usada(uuid),
  public.taller_usada_guardar(jsonb), public.taller_usada_borrar(uuid), public.usadas_publicas(text), public.usada_ver(text) from public, anon, authenticated;
grant execute on function public.taller_usadas(), public.taller_usada(uuid), public.taller_usada_guardar(jsonb), public.taller_usada_borrar(uuid) to authenticated;
grant execute on function public.usadas_publicas(text), public.usada_ver(text) to anon, authenticated;

-- ---------- G59f 🧩 🪪 Pasaporte de la bici (sticker QR en el cuadro: historial, dueño, robo reportado → ficha /p/) ----------
-- token = el QR (público: lo escanea cualquiera) · clave = del dueño (va en su link /p/?t=..&c=..): con ella reporta 🚨 robo o ✅ recuperada.
-- Historial = órdenes del taller enlazadas (reservas.pasaporte_id): al crear el pasaporte se enlazan las de ese teléfono + bici, y las nuevas solas (trigger).
create table if not exists public.pasaportes (
  id          uuid primary key default gen_random_uuid(),
  taller_id   uuid not null references public.talleres (id) on delete cascade,
  bici        text not null check (length(trim(bici)) between 1 and 120),
  serie       text not null default '' check (length(serie) <= 60),
  color       text not null default '' check (length(color) <= 40),
  dueno       text not null default '' check (length(dueno) <= 80),
  telefono    text not null default '' check (length(telefono) <= 30),
  tel_norm    text not null default '',
  robada      boolean not null default false,
  robada_at   timestamptz,
  robada_nota text not null default '' check (length(robada_nota) <= 300),
  token       text not null unique default replace(gen_random_uuid()::text, '-', ''),
  clave       text not null default replace(gen_random_uuid()::text, '-', ''),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists pasaportes_t_idx on public.pasaportes (taller_id, tel_norm);
create unique index if not exists pasaportes_serie_idx on public.pasaportes (taller_id, lower(serie)) where serie <> '';
-- G91 📍 Rastreo v2: el cliente registra su bici desde su app (GRATIS). La seguridad (reportar, rastrear) no depende del módulo.
alter table public.pasaportes add column if not exists cliente_id uuid references auth.users (id) on delete set null;
create index if not exists pasaportes_c_idx on public.pasaportes (cliente_id) where cliente_id is not null;
alter table public.pasaportes enable row level security;
-- G86 📍 Rastreo de la bici robada: quien escanea el QR comparte su ubicación (el navegador le pide permiso) y, si la bici está reportada,
-- el dueño, el taller y CodeFix la reciben en vivo. silencio = quien escanea NO ve "REPORTADA COMO ROBADA" (para que no sospeche).
-- Privacidad: sin políticas (solo por las funciones de abajo), solo se guarda si está robada, se borra sola a los 30 días.
alter table public.pasaportes add column if not exists silencio boolean not null default false;
alter table public.pasaportes add column if not exists rastro_aviso_at timestamptz;
create table if not exists public.pasaporte_rastros (
  id           bigint generated always as identity primary key,
  pasaporte_id uuid not null references public.pasaportes (id) on delete cascade,
  sesion       text not null check (sesion ~ '^[a-f0-9]{16,40}$'),
  lat          double precision check (lat between -90 and 90),
  lng          double precision check (lng between -180 and 180),
  prec         int check (prec between 0 and 100000),
  created_at   timestamptz not null default now()
);
create index if not exists pasaporte_rastros_p_idx on public.pasaporte_rastros (pasaporte_id, created_at desc);
create index if not exists pasaporte_rastros_f_idx on public.pasaporte_rastros (created_at);
alter table public.pasaporte_rastros enable row level security;
revoke all on public.pasaporte_rastros from public, anon, authenticated;

-- Órdenes nuevas del mismo teléfono y la misma bici quedan en su historial solas.
create or replace function public.pasaporte_enlazar() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.pasaporte_id is null and trim(new.bici) <> '' and public.tel_norm(new.telefono) <> '' then
    select p.id into new.pasaporte_id from public.pasaportes p
    where p.taller_id = new.taller_id and p.tel_norm = public.tel_norm(new.telefono) and lower(trim(p.bici)) = lower(trim(new.bici)) limit 1;
  end if;
  return new;
end $$;
drop trigger if exists zz_pasaporte_enlazar on public.reservas;
create trigger zz_pasaporte_enlazar before insert on public.reservas for each row execute function public.pasaporte_enlazar();

create or replace function public.pasaporte_historial(p_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('fecha', r.fecha, 'servicio', r.servicio_nombre,
    'trabajos', (select coalesce(jsonb_agg(i ->> 'nombre'), '[]') from jsonb_array_elements(r.items) i where coalesce(i ->> 'aprob', '') <> 'no')) order by r.fecha desc), '[]')
  from public.reservas r where r.pasaporte_id = p_id and r.estado in ('lista', 'completada')
$$;
create or replace function public.pasaporte_json(p public.pasaportes) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object('id', p.id, 'bici', p.bici, 'serie', p.serie, 'color', p.color, 'dueno', p.dueno, 'telefono', p.telefono,
    'robada', p.robada, 'robada_at', p.robada_at, 'robada_nota', p.robada_nota, 'token', p.token, 'clave', p.clave, 'created_at', p.created_at,
    'servicios', (select count(*) from public.reservas r where r.pasaporte_id = p.id and r.estado in ('lista', 'completada')),
    'silencio', p.silencio, 'visto_at', (select max(x.created_at) from public.pasaporte_rastros x where x.pasaporte_id = p.id))
$$;
-- G86 📍 Últimos 60 puntos (el más nuevo primero). disp = a qué teléfono corresponde (sin identificar a nadie).
create or replace function public.pasaporte_rastros_json(p_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('lat', x.lat, 'lng', x.lng, 'prec', x.prec, 'at', x.created_at, 'disp', left(x.sesion, 6)) order by x.created_at desc), '[]')
  from (select * from public.pasaporte_rastros r where r.pasaporte_id = p_id order by r.created_at desc limit 60) x
$$;

create or replace function public.taller_pasaportes() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid());
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  if not public.taller_tiene('pasaporte') then return jsonb_build_object('bloqueado', true); end if;
  return jsonb_build_object('pasaportes', (select coalesce(jsonb_agg(public.pasaporte_json(p) order by p.robada desc, p.updated_at desc), '[]')
    from public.pasaportes p where p.taller_id = tid));
end $$;

create or replace function public.taller_pasaporte(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); p public.pasaportes;
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  select * into p from public.pasaportes where id = p_id and taller_id = tid;
  if p.id is null then raise exception 'Pasaporte no encontrado'; end if;
  return public.pasaporte_json(p) || jsonb_build_object('historial', public.pasaporte_historial(p.id), 'rastros', public.pasaporte_rastros_json(p.id));
end $$;

-- Todo el equipo crea, edita y reporta robo. p.reserva = orden desde la que se crea (se enlaza con las de ese teléfono y bici).
create or replace function public.taller_pasaporte_guardar(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); pid uuid := nullif(p ->> 'id', '')::uuid; b text := trim(coalesce(p ->> 'bici', ''));
  s text := trim(coalesce(p ->> 'serie', '')); tel text := left(trim(coalesce(p ->> 'telefono', '')), 30); rid uuid := nullif(p ->> 'reserva', '')::uuid;
  rob boolean := coalesce((p ->> 'robada')::boolean, false); tn text; sil boolean := case when p ? 'silencio' then coalesce((p ->> 'silencio')::boolean, true) end;
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  if not public.taller_tiene('pasaporte') then raise exception 'Necesitas el módulo 🪪 Pasaporte de la bici'; end if;
  if b = '' then raise exception 'Escribe la marca y el modelo de la bici'; end if;
  tn := public.tel_norm(tel);
  if s <> '' and exists (select 1 from public.pasaportes where taller_id = tid and lower(serie) = lower(s) and id is distinct from pid) then
    raise exception 'Ya hay un pasaporte con el nº de serie %', s; end if;
  if pid is null then
    if (select count(*) from public.pasaportes where taller_id = tid) >= 5000 then raise exception 'Llegaste al máximo de 5.000 pasaportes'; end if;
    insert into public.pasaportes (taller_id, bici, serie, color, dueno, telefono, tel_norm, robada, robada_at, robada_nota, silencio)
    values (tid, left(b, 120), left(s, 60), left(trim(coalesce(p ->> 'color', '')), 40), left(trim(coalesce(p ->> 'dueno', '')), 80), tel, tn,
            rob, case when rob then now() end, left(coalesce(p ->> 'robada_nota', ''), 300), rob and coalesce(sil, true)) returning id into pid;
    update public.reservas r set pasaporte_id = pid where r.taller_id = tid and r.pasaporte_id is null
      and (r.id = rid or (tn <> '' and r.tel_norm = tn and lower(trim(r.bici)) = lower(b)));
  else
    update public.pasaportes set bici = left(b, 120), serie = left(s, 60), color = left(trim(coalesce(p ->> 'color', '')), 40),
      dueno = left(trim(coalesce(p ->> 'dueno', '')), 80), telefono = tel, tel_norm = tn, robada = rob,
      robada_at = case when rob then coalesce(robada_at, now()) end, robada_nota = case when rob then left(coalesce(p ->> 'robada_nota', ''), 300) else '' end, updated_at = now(),
      silencio = case when not rob then false when sil is not null then sil when robada then silencio else true end,
      rastro_aviso_at = case when rob and robada then rastro_aviso_at end
    where id = pid and taller_id = tid;
    if not found then raise exception 'Pasaporte no encontrado'; end if;
  end if;
  return pid;
end $$;

create or replace function public.taller_pasaporte_borrar(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid());
begin
  if tid is null or not public.es_dueno(tid) then raise exception 'Solo el dueño del taller puede borrar'; end if;
  update public.reservas set pasaporte_id = null where pasaporte_id = p_id and taller_id = tid;
  delete from public.pasaportes where id = p_id and taller_id = tid;
  if not found then raise exception 'Pasaporte no encontrado'; end if;
end $$;

-- Público: lo que ve quien escanea el QR (nº de serie tapado salvo los 4 últimos; dueño solo el nombre). Con la clave: el dueño.
create or replace function public.pasaporte_ver(p_token text, p_clave text default '') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare p public.pasaportes; t public.talleres; du boolean; ve boolean;
begin
  select * into p from public.pasaportes where token = p_token and length(p_token) >= 20;
  if p.id is null then return null; end if;
  select * into t from public.talleres where id = p.taller_id;
  -- G91: la seguridad (reporte y rastreo) sirve siempre; el historial de mantenciones solo lo ve el dueño (con su clave) y con el módulo.
  du := length(coalesce(p_clave, '')) >= 20 and p_clave = p.clave;
  ve := p.robada and (du or not p.silencio);  -- G86: en silencio, quien escanea no sabe que está reportada
  return jsonb_build_object('bici', p.bici, 'color', p.color, 'dueno', split_part(p.dueno, ' ', 1), 'robada', ve, 'robada_at', case when ve then p.robada_at end,
    'robada_nota', case when ve then p.robada_nota else '' end, 'creado', p.created_at, 'es_dueno', du,
    'silencio', du and p.silencio, 'rastros', case when du then public.pasaporte_rastros_json(p.id) else '[]'::jsonb end,
    'serie', case when du or length(p.serie) <= 4 then p.serie else repeat('•', least(length(p.serie) - 4, 8)) || right(p.serie, 4) end,
    'historial', case when du and public.cfx_modulo_de('pasaporte', t.owner_id) then public.pasaporte_historial(p.id) else '[]'::jsonb end,
    'rastrear', p.robada and not du,  -- G91: sin reporte el QR no pide la ubicación
    'taller', jsonb_build_object('nombre', t.nombre, 'slug', t.slug, 'telefono', t.telefono, 'logo', t.logo, 'color', t.color, 'icono', t.icono,
      'comuna', t.comuna, 'direccion', t.direccion));
end $$;

-- G86 🔔 Avisa a todos: equipo del taller, el cliente dueño de la bici (si tiene cuenta: por sus órdenes o su teléfono) y CodeFix.
create or replace function public.pasaporte_avisar(p public.pasaportes, p_titulo text, p_cuerpo text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.avisar_taller(p.taller_id, p_titulo, p_cuerpo, '/taller/#mas/pasaporte');
  insert into public.notificaciones (para, titulo, cuerpo, url)
  select x.id, left(p_titulo, 90), left(p_cuerpo, 240), '/p/?t=' || p.token || '&c=' || p.clave
  from (select r.cliente_id as id from public.reservas r where r.pasaporte_id = p.id and r.cliente_id is not null
        union
        select f.id from public.perfiles f where f.rol = 'cliente' and f.taller_id = p.taller_id and not f.suspendido
          and p.tel_norm <> '' and public.tel_norm(f.telefono) = p.tel_norm) x;
  perform public.avisar_admin(p_titulo, left(p_cuerpo || ' · ' || coalesce((select t.nombre from public.talleres t where t.id = p.taller_id), ''), 240), '/admin/');
end $$;

-- El dueño (con su clave) reporta 🚨 robo o ✅ recuperada; avisamos a todos. p_silencio = quien escanea no ve el aviso (G86).
drop function if exists public.pasaporte_reportar(text, text, boolean, text);
create or replace function public.pasaporte_reportar(p_token text, p_clave text, p_robada boolean, p_nota text default '', p_silencio boolean default true) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare p public.pasaportes; t public.talleres; rob boolean := coalesce(p_robada, false);
begin
  select * into p from public.pasaportes where token = p_token and length(p_token) >= 20 and clave = p_clave and length(coalesce(p_clave, '')) >= 20 for update;
  if p.id is null then return jsonb_build_object('ok', false, 'error', 'Este link no es del dueño de la bici'); end if;
  select * into t from public.talleres where id = p.taller_id;
  -- G91: reportar un robo NO depende de que el taller pague el módulo.
  if p.robada = rob then
    if rob and p.silencio is distinct from coalesce(p_silencio, true) then update public.pasaportes set silencio = coalesce(p_silencio, true), updated_at = now() where id = p.id; end if;
    return jsonb_build_object('ok', true);
  end if;
  update public.pasaportes set robada = rob, robada_at = case when rob then now() end, silencio = rob and coalesce(p_silencio, true), rastro_aviso_at = null,
    robada_nota = case when rob then left(coalesce(p_nota, ''), 300) else '' end, updated_at = now() where id = p.id;
  perform public.pasaporte_avisar(p, case when rob then '🚨 Bici robada' else '✅ Bici recuperada' end,
    split_part(p.dueno, ' ', 1) || case when rob then ' reportó robada su ' else ' recuperó su ' end || p.bici || coalesce(nullif(' · ' || p.serie, ' · '), ''));
  return jsonb_build_object('ok', true);
end $$;

-- G86 📍 Público: el teléfono que escaneó el QR manda su ubicación (el navegador pidió permiso). p_lat nulo = "la escanearon" sin ubicación.
-- Seguridad: responde SIEMPRE lo mismo (no revela si está reportada) · solo guarda si está robada · valida formato y rango ·
-- frenos: 1 punto cada 4 s por teléfono, 900 puntos y 30 teléfonos por hora por bici · avisos: 1.º de cada teléfono y después cada 10 min.
create or replace function public.pasaporte_rastro(p_token text, p_sesion text, p_lat double precision default null, p_lng double precision default null,
  p_prec double precision default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare p public.pasaportes; si jsonb := jsonb_build_object('ok', true); con boolean; nueva boolean; primera boolean; pr int;
begin
  if coalesce(p_token, '') !~ '^[a-zA-Z0-9]{20,64}$' or coalesce(p_sesion, '') !~ '^[a-f0-9]{16,40}$' then return si; end if;
  select * into p from public.pasaportes where token = p_token;
  if p.id is null or not p.robada then return si; end if;
  perform pg_advisory_xact_lock(hashtext('rastro:' || p.id::text));
  select * into p from public.pasaportes where id = p.id;
  if not p.robada then return si; end if;
  con := coalesce(p_lat between -90 and 90 and p_lng between -180 and 180 and not (p_lat = 0 and p_lng = 0), false);
  delete from public.pasaporte_rastros where created_at < now() - interval '30 days';
  nueva := not exists (select 1 from public.pasaporte_rastros x where x.pasaporte_id = p.id and x.sesion = p_sesion);
  if not con and not nueva then return si; end if;
  if con and exists (select 1 from public.pasaporte_rastros x where x.pasaporte_id = p.id and x.sesion = p_sesion and x.lat is not null
    and x.created_at > now() - interval '4 seconds') then return si; end if;
  if (select count(*) from public.pasaporte_rastros x where x.pasaporte_id = p.id and x.created_at > now() - interval '1 hour') >= 900 then return si; end if;
  if nueva and (select count(distinct x.sesion) from public.pasaporte_rastros x where x.pasaporte_id = p.id and x.created_at > now() - interval '1 hour') >= 30 then return si; end if;
  primera := con and not exists (select 1 from public.pasaporte_rastros x where x.pasaporte_id = p.id and x.sesion = p_sesion and x.lat is not null);
  pr := case when con and p_prec between 0 and 100000 then round(p_prec)::int end;
  insert into public.pasaporte_rastros (pasaporte_id, sesion, lat, lng, prec)
  values (p.id, p_sesion, case when con then round(p_lat::numeric, 6)::double precision end, case when con then round(p_lng::numeric, 6)::double precision end, pr);
  if primera or p.rastro_aviso_at is null or p.rastro_aviso_at < now() - interval '10 minutes' then
    update public.pasaportes set rastro_aviso_at = now() where id = p.id;
    perform public.pasaporte_avisar(p, case when not con then '👀 Escanearon la bici robada' when primera then '📍 Bici robada: ubicación recibida' else '📍 La bici robada se mueve' end,
      p.bici || coalesce(nullif(' de ' || split_part(p.dueno, ' ', 1), ' de '), '') || case when con then ' · toca para ver dónde está' else ' · sin ubicación todavía' end);
  end if;
  return si;
end $$;
revoke all on function public.pasaporte_enlazar(), public.pasaporte_historial(uuid), public.pasaporte_json(public.pasaportes), public.taller_pasaportes(), public.taller_pasaporte(uuid),
  public.taller_pasaporte_guardar(jsonb), public.taller_pasaporte_borrar(uuid), public.pasaporte_ver(text, text), public.pasaporte_reportar(text, text, boolean, text, boolean),
  public.pasaporte_rastros_json(uuid), public.pasaporte_avisar(public.pasaportes, text, text), public.pasaporte_rastro(text, text, double precision, double precision, double precision) from public, anon, authenticated;
grant execute on function public.taller_pasaportes(), public.taller_pasaporte(uuid), public.taller_pasaporte_guardar(jsonb), public.taller_pasaporte_borrar(uuid) to authenticated;
grant execute on function public.pasaporte_ver(text, text), public.pasaporte_reportar(text, text, boolean, text, boolean),
  public.pasaporte_rastro(text, text, double precision, double precision, double precision) to anon, authenticated;

-- G91 📍 Mis bicis (app del cliente, GRATIS): las que registró él + las de sus órdenes + las de su teléfono en su taller.
create or replace function public.cliente_bicis() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare f public.perfiles;
begin
  select * into f from public.perfiles where id = auth.uid() and rol = 'cliente';
  if f.id is null then return '[]'::jsonb; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'bici', p.bici, 'color', p.color, 'serie', p.serie, 'robada', p.robada, 'silencio', p.silencio,
      'token', p.token, 'clave', p.clave, 'propia', p.cliente_id = f.id,
      'visto_at', (select max(x.created_at) from public.pasaporte_rastros x where x.pasaporte_id = p.id)) order by p.robada desc, p.created_at), '[]')
    from public.pasaportes p
    where p.cliente_id = f.id or p.id in (select r.pasaporte_id from public.reservas r where r.cliente_id = f.id and r.pasaporte_id is not null)
      or (p.taller_id = f.taller_id and p.tel_norm <> '' and p.tel_norm = public.tel_norm(f.telefono)));
end $$;
create or replace function public.cliente_bici_guardar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare f public.perfiles; b text := trim(coalesce(p ->> 'bici', '')); se text := trim(coalesce(p ->> 'serie', ''));
begin
  select * into f from public.perfiles where id = auth.uid() and rol = 'cliente' and not suspendido;
  if f.id is null or f.taller_id is null then raise exception 'Solo para clientes de un taller'; end if;
  if b = '' then raise exception 'Escribe qué bici es (marca y modelo)'; end if;
  if (select count(*) from public.pasaportes where cliente_id = f.id) >= 5 then raise exception 'Máximo 5 bicis'; end if;
  if se <> '' and exists (select 1 from public.pasaportes where taller_id = f.taller_id and lower(serie) = lower(se)) then
    raise exception 'Ese nº de serie ya está registrado: pídele al taller tu pasaporte'; end if;
  insert into public.pasaportes (taller_id, bici, serie, color, dueno, telefono, tel_norm, cliente_id)
  values (f.taller_id, left(b, 120), left(se, 60), left(trim(coalesce(p ->> 'color', '')), 40), left(f.nombre, 80), left(f.telefono, 30), public.tel_norm(f.telefono), f.id);
  return public.cliente_bicis();
end $$;
revoke all on function public.cliente_bicis(), public.cliente_bici_guardar(jsonb) from public, anon, authenticated;
grant execute on function public.cliente_bicis(), public.cliente_bici_guardar(jsonb) to authenticated;

-- =====================================================================
-- G59g 🧩 🚐 Mecánico a domicilio: el cliente reserva con su dirección (+ recargo de visita), el taller arma la ruta del día
-- (orden ▲▼, abrir en Google Maps) y avisa "🚐 Voy en camino". Configuración en talleres.domicilio { activo, recargo, zona }.
-- =====================================================================
create or replace function public.domicilio_cfg(t public.talleres) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('activo', coalesce((t.domicilio ->> 'activo')::boolean, false),
    'recargo', greatest(0, coalesce((t.domicilio ->> 'recargo')::int, 0)), 'zona', coalesce(t.domicilio ->> 'zona', ''))
$$;
-- Pone (o saca, con d = null) la dirección de la visita y el ítem "🚐 Visita a domicilio" con el recargo (una sola vez).
create or replace function public.domicilio_aplicar(p_id uuid, d jsonb, p_recargo int) returns void
language plpgsql security definer set search_path = '' as $$
declare r public.reservas; viejo int; nuevos jsonb; nom constant text := '🚐 Visita a domicilio';
begin
  select * into r from public.reservas where id = p_id for update;
  select coalesce(sum((i ->> 'precio')::int * coalesce((i ->> 'cant')::int, 1)), 0) into viejo
    from jsonb_array_elements(r.items) i where i ->> 'nombre' = nom;
  select coalesce(jsonb_agg(i), '[]') into nuevos from jsonb_array_elements(r.items) i where i ->> 'nombre' is distinct from nom;
  if d is not null and p_recargo > 0 then nuevos := nuevos || jsonb_build_array(jsonb_build_object('nombre', nom, 'cant', 1, 'precio', p_recargo)); end if;
  update public.reservas set domicilio = d, items = nuevos,
    total = public.orden_total(nuevos, r.plan_desc),  -- G59i 🔁
    precio = greatest(0, precio - viejo + case when d is not null then p_recargo else 0 end), updated_at = now()
  where id = r.id;
end $$;
create or replace function public.domicilio_limpio(p jsonb, viejo jsonb) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare dir text := left(trim(coalesce(p ->> 'direccion', '')), 160);
begin
  if length(dir) < 5 then raise exception 'Escribe la dirección (calle y número)'; end if;
  return jsonb_build_object('direccion', dir, 'comuna', left(trim(coalesce(p ->> 'comuna', '')), 60), 'ref', left(trim(coalesce(p ->> 'ref', '')), 160),
    'orden', viejo -> 'orden', 'camino_at', viejo -> 'camino_at');
end $$;

-- Pública: ¿este taller va a domicilio? (para /t/). null = no.
create or replace function public.domicilio_info(p_taller uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare t public.talleres; c jsonb;
begin
  select * into t from public.talleres where id = p_taller and activo and not suspendido;
  if t.id is null or not public.cfx_modulo_de('domicilio', t.owner_id) then return null; end if;
  c := public.domicilio_cfg(t);
  if not (c ->> 'activo')::boolean then return null; end if;
  return c - 'activo';
end $$;

-- Pública: el cliente (con el link de su reserva) pide la visita a domicilio.
create or replace function public.reserva_domicilio(p_token text, p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r public.reservas; t public.talleres; c jsonb; d jsonb;
begin
  select * into r from public.reservas where token = p_token and length(p_token) >= 20;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'Reserva no encontrada'); end if;
  if r.estado not in ('por_pagar', 'en_revision', 'confirmada') then return jsonb_build_object('ok', false, 'error', 'Esta reserva ya no se puede cambiar'); end if;
  select * into t from public.talleres where id = r.taller_id;
  c := public.domicilio_info(t.id);
  if c is null then return jsonb_build_object('ok', false, 'error', 'Este taller no está yendo a domicilio'); end if;
  begin d := public.domicilio_limpio(p, r.domicilio);
  exception when others then return jsonb_build_object('ok', false, 'error', sqlerrm); end;
  perform public.domicilio_aplicar(r.id, d, (c ->> 'recargo')::int);
  if r.domicilio is null then
    perform public.avisar_taller(t.id, '🚐 Visita a domicilio', r.nombre || ' · ' || to_char(r.fecha, 'DD/MM') || ' ' || to_char(r.hora, 'HH24:MI') || ' · ' || (d ->> 'direccion'), '/taller/#mas/domicilio');
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- Taller: configuración (solo el dueño).
create or replace function public.taller_domicilio_config(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); rec int := coalesce(nullif(p ->> 'recargo', '')::int, 0);
begin
  if tid is null or not public.es_dueno(tid) then raise exception 'Solo el dueño del taller'; end if;
  if not public.taller_tiene('domicilio') then raise exception 'Necesitas el módulo 🚐 Mecánico a domicilio'; end if;
  if rec < 0 or rec > 200000 then raise exception 'El recargo va de $0 a $200.000'; end if;
  update public.talleres set domicilio = jsonb_build_object('activo', coalesce((p ->> 'activo')::boolean, false), 'recargo', rec,
    'zona', left(trim(coalesce(p ->> 'zona', '')), 160)) where id = tid;
  return public.domicilio_cfg((select t from public.talleres t where t.id = tid));
end $$;

-- Taller: poner/sacar la dirección de una orden (todo el equipo). p null o sin dirección = ya no es a domicilio.
create or replace function public.taller_domicilio(p_id uuid, p jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); r public.reservas; t public.talleres;
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  if not public.taller_tiene('domicilio') then raise exception 'Necesitas el módulo 🚐 Mecánico a domicilio'; end if;
  select * into r from public.reservas where id = p_id and taller_id = tid;
  if r.id is null then raise exception 'Orden no encontrada'; end if;
  if r.estado in ('completada', 'rechazada', 'expirada', 'cancelada', 'no_asistio') then raise exception 'Esta orden ya está cerrada'; end if;
  select * into t from public.talleres where id = tid;
  if p is null or trim(coalesce(p ->> 'direccion', '')) = '' then
    perform public.domicilio_aplicar(r.id, null, 0);
  else
    -- Sin "recargo" (editar la dirección) = queda el recargo que ya tenía la orden.
    perform public.domicilio_aplicar(r.id, public.domicilio_limpio(p, r.domicilio), case
      when not (p ? 'recargo') then (select coalesce(sum((i ->> 'precio')::int), 0)::int from jsonb_array_elements(r.items) i where i ->> 'nombre' = '🚐 Visita a domicilio')
      when coalesce((p ->> 'recargo')::boolean, true) then (public.domicilio_cfg(t) ->> 'recargo')::int else 0 end);
  end if;
end $$;

-- Taller: ruta del día (todo el equipo).
create or replace function public.taller_ruta(p_fecha date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); t public.talleres;
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  select * into t from public.talleres where id = tid;
  if not public.taller_tiene('domicilio') then return jsonb_build_object('bloqueado', true); end if;
  return jsonb_build_object('config', public.domicilio_cfg(t), 'hoy', (now() at time zone t.zona)::date,
    'origen', concat_ws(', ', nullif(t.direccion, ''), nullif(t.comuna, '')),
    'paradas', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'hora', to_char(r.hora, 'HH24:MI'), 'nombre', r.nombre, 'telefono', r.telefono,
        'bici', r.bici, 'servicio', r.servicio_nombre, 'estado', r.estado, 'token', r.token, 'total', r.total,
        'direccion', r.domicilio ->> 'direccion', 'comuna', r.domicilio ->> 'comuna', 'ref', r.domicilio ->> 'ref', 'camino_at', r.domicilio ->> 'camino_at')
        order by (r.domicilio ->> 'orden')::int nulls last, r.hora), '[]')
      from public.reservas r where r.taller_id = tid and r.fecha = p_fecha and r.domicilio is not null
        and r.estado not in ('rechazada', 'expirada', 'cancelada', 'no_asistio')
        and not (r.estado = 'por_pagar' and r.expira_at <= now())));
end $$;

-- Taller: guardar el orden de la ruta (lista de ids en el orden de visita).
create or replace function public.taller_ruta_orden(p_ids uuid[]) returns void
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); i int;
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  if not public.taller_tiene('domicilio') then raise exception 'Necesitas el módulo 🚐 Mecánico a domicilio'; end if;
  for i in 1 .. coalesce(array_length(p_ids, 1), 0) loop
    update public.reservas set domicilio = jsonb_set(domicilio, '{orden}', to_jsonb(i)) where id = p_ids[i] and taller_id = tid and domicilio is not null;
  end loop;
end $$;

-- Taller: "🚐 Voy en camino" → push al cliente con cuenta (la app abre además el WhatsApp).
create or replace function public.taller_en_camino(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); r public.reservas; t public.talleres;
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  if not public.taller_tiene('domicilio') then raise exception 'Necesitas el módulo 🚐 Mecánico a domicilio'; end if;
  select * into r from public.reservas where id = p_id and taller_id = tid and domicilio is not null for update;
  if r.id is null then raise exception 'Esta orden no es a domicilio'; end if;
  select * into t from public.talleres where id = tid;
  update public.reservas set domicilio = jsonb_set(domicilio, '{camino_at}', to_jsonb(now())), updated_at = now() where id = r.id;
  perform public.avisar(r.cliente_id, '🚐 Vamos en camino', t.nombre || ' va a ' || (r.domicilio ->> 'direccion'), '/r/?t=' || r.token);
end $$;
revoke all on function public.domicilio_cfg(public.talleres), public.domicilio_aplicar(uuid, jsonb, int), public.domicilio_limpio(jsonb, jsonb),
  public.domicilio_info(uuid), public.reserva_domicilio(text, jsonb), public.taller_domicilio_config(jsonb), public.taller_domicilio(uuid, jsonb),
  public.taller_ruta(date), public.taller_ruta_orden(uuid[]), public.taller_en_camino(uuid) from public, anon, authenticated;
grant execute on function public.taller_domicilio_config(jsonb), public.taller_domicilio(uuid, jsonb), public.taller_ruta(date),
  public.taller_ruta_orden(uuid[]), public.taller_en_camino(uuid) to authenticated;

-- =====================================================================
-- G59h 🧩 🛡️ Garantías: del trabajo, de los repuestos o de la bici (usada vendida), con vencimiento.
-- El cliente la ve en su link (/g/?t=token, también desde /r/) y la "usa" (reclamo) → el taller la ve en Hoy y la resuelve.
-- =====================================================================
create table if not exists public.garantias (
  id          uuid primary key default gen_random_uuid(),
  taller_id   uuid not null references public.talleres (id) on delete cascade,
  reserva_id  uuid,
  usada_id    uuid,
  cliente_id  uuid,
  nombre      text not null default '' check (length(nombre) <= 80),
  telefono    text not null default '' check (length(telefono) <= 30),
  tel_norm    text not null default '',
  bici        text not null default '' check (length(bici) <= 120),
  cubre       text not null default 'trabajo' check (cubre in ('trabajo', 'repuestos', 'todo', 'bici')),
  detalle     text not null default '' check (length(detalle) <= 300),
  meses       int  not null default 3 check (meses between 1 and 36),
  desde       date not null,
  hasta       date not null,
  token       text not null unique default replace(gen_random_uuid()::text, '-', ''),
  reclamo     text not null default '' check (reclamo in ('', 'abierto', 'resuelto', 'rechazado')),
  reclamo_nota text not null default '' check (length(reclamo_nota) <= 300),
  reclamo_at  timestamptz,
  respuesta   text not null default '' check (length(respuesta) <= 300),
  resuelto_at timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists garantias_reserva_idx on public.garantias (reserva_id) where reserva_id is not null;
create index if not exists garantias_t_idx on public.garantias (taller_id, hasta);
alter table public.garantias enable row level security;

create or replace function public.garantia_json(g public.garantias) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', g.id, 'reserva', g.reserva_id, 'usada', g.usada_id, 'nombre', g.nombre, 'telefono', g.telefono, 'bici', g.bici,
    'cubre', g.cubre, 'detalle', g.detalle, 'meses', g.meses, 'desde', g.desde, 'hasta', g.hasta, 'token', g.token,
    'dias', g.hasta - (now() at time zone t.zona)::date, 'reclamo', g.reclamo, 'reclamo_nota', g.reclamo_nota, 'reclamo_at', g.reclamo_at,
    'respuesta', g.respuesta, 'resuelto_at', g.resuelto_at)
  from public.talleres t where t.id = g.taller_id
$$;

create or replace function public.taller_garantias() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid());
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  if not public.taller_tiene('garantias') then return jsonb_build_object('bloqueado', true); end if;
  return jsonb_build_object('garantias', (select coalesce(jsonb_agg(public.garantia_json(g) order by (g.reclamo = 'abierto') desc, g.hasta), '[]')
    from public.garantias g where g.taller_id = tid));
end $$;

-- Una garantía por id o la de una orden (null si no tiene).
create or replace function public.taller_garantia(p_id uuid, p_reserva uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); g public.garantias;
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  select * into g from public.garantias where taller_id = tid and (id = p_id or (p_id is null and reserva_id = p_reserva));
  if g.id is null then return null; end if;
  return public.garantia_json(g);
end $$;

-- Crear o editar (todo el equipo). p: { id?, reserva?, usada?, nombre, telefono, bici, cubre, detalle, meses, desde? }
create or replace function public.taller_garantia_guardar(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); gid uuid := nullif(p ->> 'id', '')::uuid; r public.reservas; t public.talleres;
  m int := coalesce(nullif(p ->> 'meses', '')::int, 3); cu text := coalesce(nullif(p ->> 'cubre', ''), 'trabajo'); d date; tel text;
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  if not public.taller_tiene('garantias') then raise exception 'Necesitas el módulo 🛡️ Garantías'; end if;
  if m < 1 or m > 36 then raise exception 'La garantía va de 1 a 36 meses'; end if;
  if cu not in ('trabajo', 'repuestos', 'todo', 'bici') then raise exception 'Elige qué cubre la garantía'; end if;
  select * into t from public.talleres where id = tid;
  if gid is null and nullif(p ->> 'reserva', '') is not null then
    select * into r from public.reservas where id = (p ->> 'reserva')::uuid and taller_id = tid;
    if r.id is null then raise exception 'Orden no encontrada'; end if;
    if r.estado not in ('lista', 'completada') then raise exception 'La garantía se da cuando la bici está lista o entregada'; end if;
    select id into gid from public.garantias where reserva_id = r.id;
  end if;
  tel := left(trim(coalesce(p ->> 'telefono', r.telefono, '')), 30);
  if gid is null then
    if (select count(*) from public.garantias where taller_id = tid) >= 20000 then raise exception 'Llegaste al máximo de 20.000 garantías'; end if;
    d := coalesce(nullif(p ->> 'desde', '')::date, (now() at time zone t.zona)::date);
    insert into public.garantias (taller_id, reserva_id, usada_id, cliente_id, nombre, telefono, tel_norm, bici, cubre, detalle, meses, desde, hasta)
    values (tid, r.id, case when r.id is null then nullif(p ->> 'usada', '')::uuid end, r.cliente_id,
      left(trim(coalesce(nullif(p ->> 'nombre', ''), r.nombre, '')), 80), tel, public.tel_norm(tel), left(trim(coalesce(nullif(p ->> 'bici', ''), r.bici, '')), 120),
      cu, left(trim(coalesce(p ->> 'detalle', '')), 300), m, d, (d + make_interval(months => m))::date)
    returning id into gid;
  else
    update public.garantias g set nombre = left(trim(coalesce(p ->> 'nombre', g.nombre)), 80), telefono = tel, tel_norm = public.tel_norm(tel),
      bici = left(trim(coalesce(p ->> 'bici', g.bici)), 120), cubre = cu, detalle = left(trim(coalesce(p ->> 'detalle', '')), 300), meses = m,
      desde = coalesce(nullif(p ->> 'desde', '')::date, g.desde), hasta = (coalesce(nullif(p ->> 'desde', '')::date, g.desde) + make_interval(months => m))::date,
      updated_at = now()
    where g.id = gid and g.taller_id = tid;
    if not found then raise exception 'Garantía no encontrada'; end if;
  end if;
  return gid;
end $$;

create or replace function public.taller_garantia_borrar(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid());
begin
  if tid is null or not public.es_dueno(tid) then raise exception 'Solo el dueño del taller'; end if;
  delete from public.garantias where id = p_id and taller_id = tid;
end $$;

-- El taller responde el reclamo: resuelto (la arregló) o rechazado (no lo cubre). Avisa al cliente si tiene cuenta.
create or replace function public.taller_garantia_resolver(p_id uuid, p_estado text, p_resp text default '') returns void
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); g public.garantias; t public.talleres;
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  if not public.taller_tiene('garantias') then raise exception 'Necesitas el módulo 🛡️ Garantías'; end if;
  if p_estado not in ('resuelto', 'rechazado') then raise exception 'Estado no válido'; end if;
  select * into g from public.garantias where id = p_id and taller_id = tid for update;
  if g.id is null then raise exception 'Garantía no encontrada'; end if;
  if g.reclamo <> 'abierto' then raise exception 'Esta garantía no tiene un reclamo abierto'; end if;
  select * into t from public.talleres where id = tid;
  update public.garantias set reclamo = p_estado, respuesta = left(trim(coalesce(p_resp, '')), 300), resuelto_at = now(), updated_at = now() where id = g.id;
  if g.cliente_id is not null then
    perform public.avisar(g.cliente_id, case when p_estado = 'resuelto' then '🛡️ Garantía: listo' else '🛡️ Garantía: respuesta del taller' end,
      t.nombre || ' · ' || coalesce(nullif(trim(p_resp), ''), case when p_estado = 'resuelto' then 'Tu reclamo quedó resuelto' else 'Tu reclamo no lo cubre la garantía' end), '/g/?t=' || g.token);
  end if;
end $$;

-- Pública: la garantía (link del cliente).
create or replace function public.garantia_ver(p_token text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare g public.garantias; t public.talleres;
begin
  select * into g from public.garantias where token = p_token and length(p_token) >= 20;
  if g.id is null then return null; end if;
  select * into t from public.talleres where id = g.taller_id;
  if not public.cfx_modulo_de('garantias', t.owner_id) then return null; end if;
  return (public.garantia_json(g) - 'id' - 'reserva' - 'usada' - 'telefono') || jsonb_build_object('nombre', split_part(g.nombre, ' ', 1),
    'taller', jsonb_build_object('nombre', t.nombre, 'slug', t.slug, 'telefono', t.telefono, 'logo', t.logo, 'color', t.color, 'icono', t.icono,
      'comuna', t.comuna, 'direccion', t.direccion));
end $$;

-- Pública: el cliente "usa" su garantía (vigente y sin otro reclamo abierto) → aviso al taller.
create or replace function public.garantia_reclamar(p_token text, p_nota text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare g public.garantias; t public.talleres; n text := left(trim(coalesce(p_nota, '')), 300);
begin
  select * into g from public.garantias where token = p_token and length(p_token) >= 20 for update;
  if g.id is null then return jsonb_build_object('ok', false, 'error', 'Garantía no encontrada'); end if;
  select * into t from public.talleres where id = g.taller_id;
  if not public.cfx_modulo_de('garantias', t.owner_id) then return jsonb_build_object('ok', false, 'error', 'El taller ya no tiene las garantías activas'); end if;
  if g.hasta < (now() at time zone t.zona)::date then return jsonb_build_object('ok', false, 'error', 'Esta garantía ya venció'); end if;
  if g.reclamo = 'abierto' then return jsonb_build_object('ok', false, 'error', 'Ya enviaste un reclamo: el taller te va a contactar'); end if;
  if length(n) < 3 then return jsonb_build_object('ok', false, 'error', 'Cuéntanos qué pasó'); end if;
  update public.garantias set reclamo = 'abierto', reclamo_nota = n, reclamo_at = now(), respuesta = '', resuelto_at = null, updated_at = now() where id = g.id;
  perform public.avisar_taller(t.id, '🛡️ Usaron una garantía', coalesce(nullif(g.nombre, ''), 'Un cliente') || ' · ' || g.bici || ' · ' || n, '/taller/#mas/garantias');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.garantia_json(public.garantias), public.taller_garantias(), public.taller_garantia(uuid, uuid), public.taller_garantia_guardar(jsonb),
  public.taller_garantia_borrar(uuid), public.taller_garantia_resolver(uuid, text, text), public.garantia_ver(text), public.garantia_reclamar(text, text) from public, anon, authenticated;
grant execute on function public.taller_garantias(), public.taller_garantia(uuid, uuid), public.taller_garantia_guardar(jsonb), public.taller_garantia_borrar(uuid),
  public.taller_garantia_resolver(uuid, text, text) to authenticated;
grant execute on function public.garantia_ver(text), public.garantia_reclamar(text, text) to anon, authenticated;
grant execute on function public.domicilio_info(uuid), public.reserva_domicilio(text, jsonb) to anon, authenticated;

-- ---------------------------------------------------------------------
-- G59i 🔁 Plan de mantención (módulo 'plan_mant'): el cliente paga al mes y tiene N visitas incluidas + % de descuento en la orden.
--   planes_mant (los planes del taller) · plan_socios (quién tiene plan y hasta cuándo) · plan_cobros (lo cobrado) · plan_usos (visitas usadas).
--   Usar el plan en una orden = 1 visita del mes + reservas.plan_desc (el total baja ese %: orden_total).
-- ---------------------------------------------------------------------
create table if not exists public.planes_mant (
  id         uuid primary key default gen_random_uuid(),
  taller_id  uuid not null references public.talleres (id) on delete cascade,
  nombre     text not null check (length(nombre) between 2 and 60),
  precio     int  not null default 0 check (precio between 0 and 1000000),
  visitas    int  not null default 1 check (visitas between 1 and 10),
  descuento  int  not null default 0 check (descuento between 0 and 50),
  incluye    text not null default '' check (length(incluye) <= 300),
  activo     boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists planes_mant_t_idx on public.planes_mant (taller_id);
alter table public.planes_mant enable row level security;
create table if not exists public.plan_socios (
  id         uuid primary key default gen_random_uuid(),
  taller_id  uuid not null references public.talleres (id) on delete cascade,
  plan_id    uuid not null references public.planes_mant (id) on delete cascade,
  cliente_id uuid,
  nombre     text not null check (length(nombre) between 2 and 80),
  telefono   text not null default '' check (length(telefono) <= 30),
  tel_norm   text not null default '',
  bici       text not null default '' check (length(bici) <= 120),
  hasta      date not null,
  activa     boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists plan_socios_t_idx on public.plan_socios (taller_id, tel_norm);
alter table public.plan_socios enable row level security;
create table if not exists public.plan_cobros (
  id         uuid primary key default gen_random_uuid(),
  taller_id  uuid not null references public.talleres (id) on delete cascade,
  socio_id   uuid not null references public.plan_socios (id) on delete cascade,
  meses      int  not null check (meses between 1 and 12),
  monto      int  not null default 0,
  medio      text not null default 'efectivo' check (medio in ('efectivo', 'transferencia', 'tarjeta')),
  por        uuid,
  created_at timestamptz not null default now()
);
create index if not exists plan_cobros_t_idx on public.plan_cobros (taller_id, created_at);
alter table public.plan_cobros enable row level security;
create table if not exists public.plan_usos (
  id         uuid primary key default gen_random_uuid(),
  socio_id   uuid not null references public.plan_socios (id) on delete cascade,
  reserva_id uuid unique,
  por        uuid,
  created_at timestamptz not null default now()
);
create index if not exists plan_usos_s_idx on public.plan_usos (socio_id, created_at);
alter table public.plan_usos enable row level security;

-- Total de una orden: suma de ítems (sin los rechazados) menos el % del plan.
create or replace function public.orden_total(p_items jsonb, p_desc int) returns int
language sql immutable set search_path = '' as $$
  select (s - s * greatest(0, least(50, coalesce(p_desc, 0))) / 100)::int
  from (select coalesce(sum(greatest(coalesce((i ->> 'cant')::numeric, 1), 0) * greatest(coalesce((i ->> 'precio')::numeric, 0), 0)), 0)::bigint s
        from jsonb_array_elements(coalesce(p_items, '[]')) i where coalesce(i ->> 'aprob', '') <> 'no') x
$$;

create or replace function public.plan_socio_json(s public.plan_socios, plata boolean) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', s.id, 'plan', s.plan_id, 'plan_nombre', p.nombre, 'visitas', p.visitas, 'descuento', p.descuento, 'incluye', p.incluye,
    'precio', case when plata then p.precio end, 'nombre', s.nombre, 'telefono', s.telefono, 'bici', s.bici, 'hasta', s.hasta, 'activa', s.activa,
    'dias', s.hasta - h.hoy, 'vigente', s.activa and s.hasta >= h.hoy, 'usados', u.n, 'quedan', greatest(0, p.visitas - u.n))
  from public.planes_mant p, public.talleres t,
    lateral (select (now() at time zone t.zona)::date hoy) h,
    lateral (select count(*)::int n from public.plan_usos x where x.socio_id = s.id and x.created_at >= (date_trunc('month', h.hoy::timestamp) at time zone t.zona)) u
  where p.id = s.plan_id and t.id = s.taller_id
$$;

-- Planes + socios del taller ({bloqueado} sin módulo). El equipo no ve precios ni lo cobrado.
create or replace function public.taller_planes() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); d boolean; t public.talleres;
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  if not public.taller_tiene('plan_mant') then return jsonb_build_object('bloqueado', true); end if;
  d := public.es_dueno(tid);
  select * into t from public.talleres where id = tid;
  return jsonb_build_object(
    'planes', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nombre', p.nombre, 'precio', case when d then p.precio end, 'visitas', p.visitas,
        'descuento', p.descuento, 'incluye', p.incluye, 'activo', p.activo,
        'socios', (select count(*) from public.plan_socios s where s.plan_id = p.id and s.activa)) order by p.activo desc, p.precio), '[]')
      from public.planes_mant p where p.taller_id = tid),
    'socios', (select coalesce(jsonb_agg(public.plan_socio_json(s, d) order by s.hasta), '[]') from public.plan_socios s where s.taller_id = tid and (d or s.activa)),
    'cobrado_mes', case when d then (select coalesce(sum(monto), 0) from public.plan_cobros
      where taller_id = tid and created_at >= (date_trunc('month', now() at time zone t.zona) at time zone t.zona)) end);
end $$;

-- Crear/editar un plan (solo dueño). p: { id?, nombre, precio, visitas, descuento, incluye, activo }
create or replace function public.taller_plan_guardar(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); pid uuid := nullif(p ->> 'id', '')::uuid;
  v int := coalesce(nullif(p ->> 'visitas', '')::int, 1); ds int := coalesce(nullif(p ->> 'descuento', '')::int, 0); pr int := coalesce(nullif(p ->> 'precio', '')::int, 0);
begin
  if tid is null or not public.es_dueno(tid) then raise exception 'Solo el dueño del taller'; end if;
  if not public.taller_tiene('plan_mant') then raise exception 'Necesitas el módulo 🔁 Plan de mantención'; end if;
  if length(trim(coalesce(p ->> 'nombre', ''))) < 2 then raise exception 'Ponle nombre al plan'; end if;
  if v < 1 or v > 10 then raise exception 'Las visitas van de 1 a 10 al mes'; end if;
  if ds < 0 or ds > 50 then raise exception 'El descuento va de 0 a 50%%'; end if;
  if pr < 0 or pr > 1000000 then raise exception 'Precio no válido'; end if;
  if pid is null then
    if (select count(*) from public.planes_mant where taller_id = tid) >= 10 then raise exception 'Máximo 10 planes'; end if;
    insert into public.planes_mant (taller_id, nombre, precio, visitas, descuento, incluye)
    values (tid, left(trim(p ->> 'nombre'), 60), pr, v, ds, left(trim(coalesce(p ->> 'incluye', '')), 300)) returning id into pid;
  else
    update public.planes_mant set nombre = left(trim(p ->> 'nombre'), 60), precio = pr, visitas = v, descuento = ds,
      incluye = left(trim(coalesce(p ->> 'incluye', '')), 300), activo = coalesce((p ->> 'activo')::boolean, activo)
    where id = pid and taller_id = tid;
    if not found then raise exception 'Plan no encontrado'; end if;
  end if;
  return pid;
end $$;

create or replace function public.taller_plan_borrar(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid());
begin
  if tid is null or not public.es_dueno(tid) then raise exception 'Solo el dueño del taller'; end if;
  if exists (select 1 from public.plan_socios where plan_id = p_id and activa) then raise exception 'Este plan tiene clientes: mejor apágalo (Ya no se vende)'; end if;
  delete from public.planes_mant where id = p_id and taller_id = tid;
end $$;

-- Sumar/editar un cliente con plan y cobrar meses (solo dueño). p: { id?, plan, nombre, telefono, bici, activa?, meses (0 = solo editar), medio }
create or replace function public.taller_socio_guardar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); sid uuid := nullif(p ->> 'id', '')::uuid; s public.plan_socios; pl public.planes_mant; t public.talleres;
  meses int := coalesce(nullif(p ->> 'meses', '')::int, 0); hoy date; tel text := left(trim(coalesce(p ->> 'telefono', '')), 30); cli uuid;
begin
  if tid is null or not public.es_dueno(tid) then raise exception 'Solo el dueño del taller'; end if;
  if not public.taller_tiene('plan_mant') then raise exception 'Necesitas el módulo 🔁 Plan de mantención'; end if;
  if meses < 0 or meses > 12 then raise exception 'Cobra de 1 a 12 meses'; end if;
  select * into t from public.talleres where id = tid;
  hoy := (now() at time zone t.zona)::date;
  select * into pl from public.planes_mant where id = nullif(p ->> 'plan', '')::uuid and taller_id = tid;
  if pl.id is null then raise exception 'Elige el plan'; end if;
  if length(trim(coalesce(p ->> 'nombre', ''))) < 2 then raise exception 'Escribe el nombre del cliente'; end if;
  if length(public.tel_norm(tel)) < 8 then raise exception 'Escribe el teléfono del cliente (así lo reconoce en sus órdenes)'; end if;
  -- Si el cliente tiene cuenta y ya vino con ese teléfono, queda enlazado (le llegan los avisos).
  select r.cliente_id into cli from public.reservas r where r.taller_id = tid and r.tel_norm = public.tel_norm(tel) and r.cliente_id is not null order by r.created_at desc limit 1;
  if sid is null then
    if not pl.activo then raise exception 'Ese plan ya no se vende'; end if;
    if exists (select 1 from public.plan_socios where taller_id = tid and tel_norm = public.tel_norm(tel) and activa) then raise exception 'Ese teléfono ya tiene un plan: ábrelo y cóbrale el mes'; end if;
    if (select count(*) from public.plan_socios where taller_id = tid and activa) >= 2000 then raise exception 'Máximo 2.000 clientes con plan'; end if;
    insert into public.plan_socios (taller_id, plan_id, cliente_id, nombre, telefono, tel_norm, bici, hasta)
    values (tid, pl.id, cli, left(trim(p ->> 'nombre'), 80), tel, public.tel_norm(tel), left(trim(coalesce(p ->> 'bici', '')), 120), hoy - 1) returning * into s;
  else
    update public.plan_socios x set plan_id = pl.id, cliente_id = coalesce(cli, x.cliente_id), nombre = left(trim(p ->> 'nombre'), 80), telefono = tel, tel_norm = public.tel_norm(tel),
      bici = left(trim(coalesce(p ->> 'bici', x.bici)), 120), activa = coalesce((p ->> 'activa')::boolean, x.activa), updated_at = now()
    where x.id = sid and x.taller_id = tid returning * into s;
    if s.id is null then raise exception 'Cliente con plan no encontrado'; end if;
  end if;
  if meses > 0 then
    update public.plan_socios set activa = true, hasta = (greatest(hasta, hoy - 1) + make_interval(months => meses))::date, updated_at = now()
    where id = s.id returning * into s;
    insert into public.plan_cobros (taller_id, socio_id, meses, monto, medio, por)
    values (tid, s.id, meses, pl.precio * meses, case when p ->> 'medio' in ('transferencia', 'tarjeta') then p ->> 'medio' else 'efectivo' end, auth.uid());
  end if;
  return public.plan_socio_json(s, true);
end $$;

create or replace function public.taller_socio_borrar(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid());
begin
  if tid is null or not public.es_dueno(tid) then raise exception 'Solo el dueño del taller'; end if;
  update public.reservas r set plan_desc = 0, total = public.orden_total(r.items, 0), updated_at = now()
  where r.id in (select reserva_id from public.plan_usos where socio_id = p_id) and r.taller_id = tid and r.estado <> 'completada';
  delete from public.plan_socios where id = p_id and taller_id = tid;
end $$;

-- ¿El cliente de esta orden tiene plan? (por teléfono). Trae si ya se usó en esta orden.
create or replace function public.taller_plan_orden(p_reserva uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); r public.reservas; s public.plan_socios; u uuid;
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  if not public.taller_tiene('plan_mant') then return null; end if;
  select * into r from public.reservas where id = p_reserva and taller_id = tid;
  if r.id is null then return null; end if;
  select x.socio_id into u from public.plan_usos x where x.reserva_id = r.id;
  if u is not null then select * into s from public.plan_socios where id = u;
  elsif length(r.tel_norm) >= 8 then select * into s from public.plan_socios where taller_id = tid and tel_norm = r.tel_norm and activa order by hasta desc limit 1;
  end if;
  if s.id is null then return null; end if;
  return public.plan_socio_json(s, public.es_dueno(tid)) || jsonb_build_object('usado', u is not null);
end $$;

-- Usar (o quitar) el plan en una orden (todo el equipo): 1 visita del mes + descuento en el total.
create or replace function public.taller_plan_usar(p_reserva uuid, p_usar boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); r public.reservas; s public.plan_socios; j jsonb; pl public.planes_mant;
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  if not public.taller_tiene('plan_mant') then raise exception 'Necesitas el módulo 🔁 Plan de mantención'; end if;
  select * into r from public.reservas where id = p_reserva and taller_id = tid for update;
  if r.id is null then raise exception 'Orden no encontrada'; end if;
  if r.estado in ('completada', 'rechazada', 'expirada', 'cancelada', 'no_asistio') then raise exception 'Esta orden ya está cerrada'; end if;
  if not coalesce(p_usar, false) then
    delete from public.plan_usos where reserva_id = r.id;
    update public.reservas set plan_desc = 0, total = public.orden_total(items, 0), updated_at = now() where id = r.id;
    return jsonb_build_object('ok', true, 'total', public.orden_total(r.items, 0));
  end if;
  if exists (select 1 from public.plan_usos where reserva_id = r.id) then raise exception 'El plan ya se usó en esta orden'; end if;
  select * into s from public.plan_socios where taller_id = tid and tel_norm = r.tel_norm and length(r.tel_norm) >= 8 and activa order by hasta desc limit 1 for update;
  if s.id is null then raise exception 'Este cliente no tiene plan'; end if;
  j := public.plan_socio_json(s, false);
  if not (j ->> 'vigente')::boolean then raise exception 'El plan de % venció: cóbrale el mes en Más → 🔁 Planes', s.nombre; end if;
  if (j ->> 'quedan')::int <= 0 then raise exception '% ya usó sus % visitas de este mes', s.nombre, j ->> 'visitas'; end if;
  select * into pl from public.planes_mant where id = s.plan_id;
  insert into public.plan_usos (socio_id, reserva_id, por) values (s.id, r.id, auth.uid());
  update public.reservas set plan_desc = pl.descuento, total = public.orden_total(items, pl.descuento), updated_at = now() where id = r.id;
  return jsonb_build_object('ok', true, 'total', public.orden_total(r.items, pl.descuento));
end $$;

-- Pública: planes que vende el taller (para /t/). [] si no tiene el módulo.
create or replace function public.planes_publicos(p_taller uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare t public.talleres;
begin
  select * into t from public.talleres where id = p_taller and activo and not suspendido;
  if t.id is null or not public.cfx_modulo_de('plan_mant', t.owner_id) then return '[]'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('nombre', p.nombre, 'precio', p.precio, 'visitas', p.visitas, 'descuento', p.descuento, 'incluye', p.incluye)
    order by p.precio), '[]') from public.planes_mant p where p.taller_id = t.id and p.activo);
end $$;
revoke all on function public.orden_total(jsonb, int), public.plan_socio_json(public.plan_socios, boolean), public.taller_planes(), public.taller_plan_guardar(jsonb),
  public.taller_plan_borrar(uuid), public.taller_socio_guardar(jsonb), public.taller_socio_borrar(uuid), public.taller_plan_orden(uuid), public.taller_plan_usar(uuid, boolean),
  public.planes_publicos(uuid) from public, anon, authenticated;
grant execute on function public.taller_planes(), public.taller_plan_guardar(jsonb), public.taller_plan_borrar(uuid), public.taller_socio_guardar(jsonb),
  public.taller_socio_borrar(uuid), public.taller_plan_orden(uuid), public.taller_plan_usar(uuid, boolean) to authenticated;
grant execute on function public.planes_publicos(uuid) to anon, authenticated;

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
-- G19: pago de un módulo o pack (null = Premium).
alter table public.cfx_pagos add column if not exists producto text check (producto is null or producto ~ '^[a-z_]{2,30}$');
alter table public.cfx_pagos drop constraint if exists cfx_pagos_medio_check;
alter table public.cfx_pagos add constraint cfx_pagos_medio_check check (medio in ('link', 'transferencia', 'tarjeta', 'mp', 'flow'));
-- G85 ⚡ Mercado Pago automático: cuándo se abrió y el n° de pago que lo confirmó (un pago de MP sirve una sola vez).
alter table public.cfx_pagos add column if not exists mp_desde timestamptz;
alter table public.cfx_pagos add column if not exists mp_pago text;
-- G87 K: hasta cuándo quedó activo · 🎁 regalo (en vez de activarse, crea una key de 1 uso) · key_regalo = la key (solo la ve quien pagó y el admin).
alter table public.cfx_pagos add column if not exists hasta timestamptz;
alter table public.cfx_pagos add column if not exists regalo boolean not null default false;
alter table public.cfx_pagos add column if not exists key_regalo text;
create unique index if not exists cfx_pagos_mp_pago_idx on public.cfx_pagos (mp_pago) where mp_pago is not null;
alter table public.cfx_pagos drop constraint if exists cfx_pagos_periodo_check;
alter table public.cfx_pagos add constraint cfx_pagos_periodo_check check (periodo in ('inicio', 'mensual', 'meses', 'anual', 'otro'));
create index if not exists cfx_pagos_cuenta_idx on public.cfx_pagos (cuenta, creado desc);
create index if not exists cfx_pagos_estado_idx on public.cfx_pagos (estado, creado);
alter table public.cfx_pagos enable row level security;
create table if not exists public.cfx_exentos (cuenta uuid primary key, nota text not null default '', creado timestamptz not null default now());
alter table public.cfx_exentos enable row level security;
revoke all on public.cfx_config, public.cfx_pagos, public.cfx_exentos from anon, authenticated;

-- G85: ¿Está prendido el pago automático con Mercado Pago? (el token nunca sale de la base)
create or replace function public.cfx_mp_on() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select coalesce(valor ->> 'token', '') <> '' and coalesce((valor ->> 'activo')::boolean, false) from public.cfx_config where clave = 'mp'), false)
$$;
revoke all on function public.cfx_mp_on() from public, anon, authenticated;
-- G38 ⚡ Flow (Webpay + transferencia + MACH en una sola cuenta): ¿está prendido? (las llaves nunca salen de la base)
create or replace function public.cfx_flow_on() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select coalesce(valor ->> 'apikey', '') <> '' and coalesce(valor ->> 'secret', '') <> '' and coalesce((valor ->> 'activo')::boolean, false)
    from public.cfx_config where clave = 'flow'), false)
$$;
revoke all on function public.cfx_flow_on() from public, anon, authenticated;

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
     and (coalesce(c ->> 'link', '') <> '' or coalesce(c #>> '{transferencia,numero}', '') <> '' or coalesce(c #>> '{tarjeta,link}', '') <> '' or public.cfx_mp_on() or public.cfx_flow_on())
     and (y ->> 'creado')::timestamptz > coalesce((c ->> 'inicio_desde')::timestamptz, now())
     -- Liberado: mientras dure nadie queda bloqueado; las cuentas creadas en ese tiempo quedan en gratis sin primer pago.
     and not (lh is not null and (now() < lh or (y ->> 'creado')::timestamptz between coalesce(ld, '-infinity') and lh));
  bloq := debe and y ->> 'rol' = 'negocio';
  return jsonb_build_object('config', c - 'inicio_desde', 'yo', y, 'pagado', pagado, 'bloqueado', bloq, 'debe_inicio', debe,
    'liberado_hasta', case when lh > now() then lh end, 'mp', public.cfx_mp_on(), 'flow', public.cfx_flow_on(),
    'prueba_pro', public.cfx_pro_prueba(y),  -- G95
    'subs', public.cfx_mp_subs_de((y ->> 'id')::uuid),  -- G108 🔁
    'ultimo', (select to_jsonb(x) from (select id, periodo, monto, medio, estado, dias, motivo, creado, resuelto, hasta, producto, regalo from public.cfx_pagos
               where cuenta = (y ->> 'id')::uuid order by creado desc limit 1) x),
    -- G87 K: 🔑 keys que compré (🎁 regalo o respaldo), con si ya se usaron.
    'keys', (select coalesce(jsonb_agg(jsonb_build_object('key', p.key_regalo, 'producto', p.producto, 'dias', p.dias, 'regalo', p.regalo, 'creado', p.resuelto,
               'usada', k.usada_at is not null) order by p.resuelto desc), '[]') from public.cfx_pagos p
               left join public.cfx_keys k on k.hash = encode(sha256(convert_to(p.key_regalo, 'UTF8')), 'hex')
               where p.cuenta = (y ->> 'id')::uuid and p.key_regalo is not null and p.resuelto > now() - interval '1 year'));
end $$;

drop function if exists public.cfx_pago_pedir(text, int, text, text, text);
drop function if exists public.cfx_pago_pedir(text, int, text, text, text, text);
drop function if exists public.cfx_pago_pedir(text, int, text, text, text, text, int);  -- G36: la de 7 dejaba 2 versiones ("Could not choose the best candidate")
drop function if exists public.cfx_pago_pedir(text, int, text, text, text, text, int, text);
create or replace function public.cfx_pago_pedir(p_periodo text, p_monto int, p_medio text, p_comprobante text, p_nota text default '', p_cupon text default null, p_meses int default null, p_producto text default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); i uuid; cup text := nullif(upper(trim(coalesce(p_cupon, ''))), '');
begin
  if y is null or (y ->> 'id') is null then raise exception 'Inicia sesión'; end if;
  if y ->> 'rol' not in ('negocio', 'cliente') and p_periodo <> 'otro' then raise exception 'Pide al dueño de la cuenta que haga el pago'; end if;
  if p_periodo not in ('inicio', 'mensual', 'meses', 'anual', 'otro') or p_medio not in ('link', 'transferencia', 'tarjeta') then raise exception 'Datos no válidos'; end if;
  if p_periodo = 'meses' and coalesce(p_meses, 0) not between 2 and 11 then raise exception 'Elige de 2 a 11 meses'; end if;
  -- Módulo o pack (G19): solo el dueño del negocio, 1 mes o 1 año, y que se venda en esta app.
  if p_producto is not null then
    if public.cfx_negocio_cuenta((y ->> 'id')::uuid) is distinct from (y ->> 'id')::uuid then raise exception 'Pide al dueño del negocio que haga el pago'; end if;
    if p_periodo not in ('mensual', 'anual') or not coalesce((public.cfx_venta() ->> 'activo')::boolean, false) or cardinality(public.cfx_venta_modulos(p_producto)) = 0 then raise exception 'Módulo no válido'; end if;
  end if;
  if coalesce(p_monto, 0) < 1 then raise exception 'Escribe el monto que pagaste'; end if;
  if coalesce(length(p_comprobante), 0) < 200 then raise exception 'Sube la foto del comprobante'; end if;
  if cup is not null then perform public.cfx_cupon_ver(cup); end if;
  if exists (select 1 from public.cfx_pagos where cuenta = (y ->> 'id')::uuid and estado = 'pendiente' and medio not in ('mp', 'flow')) then raise exception 'Ya tienes un pago en revisión. Te avisamos apenas se apruebe.'; end if;
  if (select count(*) from public.cfx_pagos where cuenta = (y ->> 'id')::uuid and creado > now() - interval '1 day' and medio not in ('mp', 'flow')) >= 5 then raise exception 'Demasiados intentos hoy. Escribe a soporte.'; end if;
  insert into public.cfx_pagos (cuenta, email, nombre, rol, periodo, monto, medio, nota, comprobante, cupon, meses, producto)
  values ((y ->> 'id')::uuid, coalesce(y ->> 'email', ''), left(coalesce(y ->> 'nombre', ''), 80), case when y ->> 'rol' in ('negocio', 'cliente') then y ->> 'rol' else 'otro' end,
          p_periodo, p_monto, p_medio, left(coalesce(p_nota, ''), 300), p_comprobante, cup, case when p_periodo = 'meses' then p_meses end, p_producto)
  returning id into i;
  -- Aviso al tiro: al Centro de Mando si la app está vinculada (si no, al administrador de esta app).
  perform public.cfx_al_cm('💳 Pago por revisar', coalesce(nullif(y ->> 'nombre', ''), y ->> 'email') || ' · $' || p_monto || coalesce(' · 🧩 ' || p_producto, '') || ' (' || case p_periodo when 'meses' then p_meses || ' meses' else p_periodo end || ', ' || p_medio || ')' || coalesce(' · cupón ' || cup, ''), 'pago');
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
    select id, cuenta, email, nombre, rol, periodo, meses, producto, monto, medio, mp_pago, nota, estado, dias, motivo, creado, resuelto, comprobante is not null as con_comprobante, hasta, regalo, key_regalo,
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

-- G87 K · 🔑 Key de 1 uso con lo que se pagó (Premium o módulo/pack, los mismos días). Sirve para 🎁 regalar a otra cuenta y de
-- respaldo si la activación automática falla: el pago queda aprobado con su key (la persona la canjea en Premium/🧩 Módulos).
create or replace function public.cfx_pago_key(g public.cfx_pagos, p_dias int, p_estado text, p_motivo text) returns text
language plpgsql security definer set search_path = '' as $$
declare c text := upper(replace(gen_random_uuid()::text, '-', ''));
begin
  c := 'CFX-' || substr(c, 1, 4) || '-' || substr(c, 5, 4) || '-' || substr(c, 9, 4);
  insert into public.cfx_keys (hash, ultimos, rol, dias, nota, item)
  values (encode(sha256(convert_to(c, 'UTF8')), 'hex'), right(c, 4), case when g.producto is not null then 'negocio' when g.rol = 'cliente' then 'cliente' else 'negocio' end,
          greatest(1, least(3660, p_dias)), left(case when g.regalo then '🎁 Regalo de ' else '🔑 Respaldo de ' end || coalesce(nullif(g.email, ''), g.cuenta::text), 120), coalesce(g.producto, ''));
  update public.cfx_pagos set estado = p_estado, dias = p_dias, key_regalo = c, motivo = left(coalesce(p_motivo, ''), 200), resuelto = now(), comprobante = null where id = g.id;
  perform public.cfx_avisar(g.cuenta, case when g.regalo then '🎁 Tu key de regalo está lista' else '🔑 Tu pago quedó con una key' end,
    'Key ' || c || ' (' || case when g.producto is not null then '🧩 ' || g.producto else 'Premium' end || ', ' || p_dias || ' días). Se canjea en Premium → ¿Tienes una key?');
  return c;
end $$;
revoke all on function public.cfx_pago_key(public.cfx_pagos, int, text, text) from public, anon, authenticated;

-- Aprueba un pago pendiente y activa lo que pagó (lo usan el administrador y el pago automático de Mercado Pago).
create or replace function public.cfx_pago_aprobar(p_id uuid, p_dias int default null, p_motivo text default '') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare g public.cfx_pagos; d int; h timestamptz;
begin
  select * into g from public.cfx_pagos where id = p_id and estado = 'pendiente' for update;
  if g.id is null then raise exception 'Pago no encontrado o ya resuelto'; end if;
  d := coalesce(p_dias, public.cfx_dias_sugeridos(g));
  if d < 0 or d > 3660 then raise exception 'Días no válidos'; end if;
  if g.regalo and d > 0 then
    perform public.cfx_pago_key(g, d, 'aprobado', p_motivo);
    return jsonb_build_object('estado', 'aprobado', 'dias', d, 'hasta', null, 'regalo', true);
  end if;
  if d > 0 and g.producto is not null then h := public.cfx_modulos_dar(public.cfx_negocio_cuenta(g.cuenta), g.producto, d, 'pago');
  elsif d > 0 then h := public.cfx_dar_premium(g.cuenta, g.rol, d); end if;
  update public.cfx_pagos set estado = 'aprobado', dias = d, hasta = h, motivo = left(coalesce(p_motivo, ''), 200), resuelto = now(), comprobante = null where id = p_id;
  perform public.cfx_avisar(g.cuenta, '✅ Pago aprobado', case when h is not null then case when g.producto is not null then '🧩 Módulo activo' else 'Premium activo' end || ' hasta el ' || to_char(h at time zone 'America/Santiago', 'DD/MM/YYYY') || '. ¡Gracias!' else 'Gracias, tu pago quedó registrado.' end);
  return jsonb_build_object('estado', 'aprobado', 'dias', d, 'hasta', h);
end $$;
revoke all on function public.cfx_pago_aprobar(uuid, int, text) from public, anon, authenticated;

create or replace function public.cfx_pago_resolver(p_id uuid, p_aprobar boolean, p_dias int default null, p_motivo text default '') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare g public.cfx_pagos; d int; hasta timestamptz;
begin
  perform public.admin_check();
  select * into g from public.cfx_pagos where id = p_id and estado = 'pendiente' for update;
  if g.id is null then raise exception 'Pago no encontrado o ya resuelto'; end if;
  d := coalesce(p_dias, public.cfx_dias_sugeridos(g));
  if p_aprobar then
    return public.cfx_pago_aprobar(p_id, d, p_motivo);
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
revoke all on function public.cfx_pago_estado(), public.cfx_pago_pedir(text, int, text, text, text, text, int, text), public.cfx_pagos_config(), public.cfx_pagos_config_guardar(jsonb),
  public.cfx_pagos_lista(text), public.cfx_pago_comprobante(uuid), public.cfx_pago_resolver(uuid, boolean, int, text), public.cfx_exento(uuid, boolean, text) from public, anon;
grant execute on function public.cfx_pago_estado(), public.cfx_pago_pedir(text, int, text, text, text, text, int, text), public.cfx_pagos_config(), public.cfx_pagos_config_guardar(jsonb),
  public.cfx_pagos_lista(text), public.cfx_pago_comprobante(uuid), public.cfx_pago_resolver(uuid, boolean, int, text), public.cfx_exento(uuid, boolean, text) to authenticated;
revoke all on function public.cfx_yo(), public.cfx_dar_premium(uuid, text, int), public.cfx_avisar(uuid, text, text), public.cfx_avisar_admin(text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- G85 ⚡ Pago AUTOMÁTICO con Mercado Pago (Checkout Pro) para pagar la app: Premium, primer pago y módulos.
--   CodeFix pega SU Access Token una vez en CM → Pagos (se guarda en las 7 apps; nadie lo puede leer después).
--   La persona toca "⚡ Pagar con Mercado Pago" → paga → al volver (o cada 2 min) la base lo confirma con Mercado Pago,
--   activa el plan sola, le llega push "✅ Pago aprobado" y al Centro de Mando "⚡ Pago automático". Sin comprobante.
--   El link general (abierto, con pantallazo) sigue igual: ese lo revisa el administrador.
-- ---------------------------------------------------------------------
do $$ begin create extension if not exists http with schema extensions; exception when others then raise notice 'http: %', sqlerrm; end $$;

create or replace function public.cfx_mp_api(p_token text, p_metodo text, p_ruta text, p_cuerpo jsonb default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare st int; c text;
begin
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '10');
  execute 'select status, content from extensions.http(row($1, $2, $3, $4, $5)::extensions.http_request)' into st, c
    using p_metodo, 'https://api.mercadopago.com' || p_ruta, array[row('Authorization', 'Bearer ' || p_token)::extensions.http_header],
          'application/json', p_cuerpo::text;
  return jsonb_build_object('status', st, 'body', case when c ~ '^\s*[\{\[]' then c::jsonb end);
exception when others then
  return jsonb_build_object('status', 0, 'error', sqlerrm);
end $$;

-- G99 a ⚡ AVISO INSTANTÁNEO de Mercado Pago (webhook). Cada cobro lleva notification_url = función de la app + ?cfx_mp=<ref>.
--   La función solo llama cfx_mp_aviso(ref): NO se confía en lo que manda MP; la base vuelve a preguntarle por ESE cobro.
--   Si no hay URL (o el aviso no llega), todo sigue igual: se confirma al volver y con el cron de cada 1 min.
--   URL: cfx_config 'mp_aviso' → {"url": ...} (opcional) · si no, gancho de la app cfx_mp_aviso_url_app().
create table if not exists public.cfx_mp_avisos (ref text primary key, at timestamptz not null default now());
alter table public.cfx_mp_avisos enable row level security;
revoke all on public.cfx_mp_avisos from anon, authenticated;

create or replace function public.cfx_mp_notif(p_ref text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare u text := (select valor ->> 'url' from public.cfx_config where clave = 'mp_aviso');
begin
  if coalesce(u, '') = '' and to_regprocedure('public.cfx_mp_aviso_url_app()') is not null then
    begin execute 'select public.cfx_mp_aviso_url_app()' into u; exception when others then u := null; end;
  end if;
  if coalesce(u, '') !~ '^https://[^\s"<>?#]+$' or p_ref is null then return '{}'::jsonb; end if;
  return jsonb_build_object('notification_url', u || '?cfx_mp=' || p_ref);
end $$;
revoke all on function public.cfx_mp_notif(text) from public, anon, authenticated;

-- p:<id> = pago de la app (cfx_pagos) · n:<id> = cobro del negocio (mp_negocio.sql) · otra letra = gancho cfx_mp_aviso_app(ref).
create or replace function public.cfx_mp_aviso(p_ref text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare r text := lower(left(coalesce(p_ref, ''), 80)); i uuid; ok boolean := false;
begin
  if r !~ '^[a-z]:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return false; end if;
  i := substr(r, 3)::uuid;
  -- Freno: el mismo cobro se pregunta a MP como mucho 1 vez cada 5 s (MP manda varios avisos por pago).
  if exists (select 1 from public.cfx_mp_avisos where ref = r and at > now() - interval '5 seconds') then return false; end if;
  insert into public.cfx_mp_avisos (ref) values (r) on conflict (ref) do update set at = now();
  delete from public.cfx_mp_avisos where at < now() - interval '3 days';
  if left(r, 1) in ('p', 'f') then
    if exists (select 1 from public.cfx_pagos where id = i and medio in ('mp', 'flow') and estado = 'pendiente') then ok := public.cfx_mp_confirmar(i) = 'aprobado'; end if;
  elsif left(r, 1) = 'n' then
    if to_regprocedure('public.cfx_mp_neg_confirmar(uuid)') is not null then execute 'select public.cfx_mp_neg_confirmar($1)' into ok using i; end if;
  elsif to_regprocedure('public.cfx_mp_aviso_app(text)') is not null then
    execute 'select public.cfx_mp_aviso_app($1)' into ok using r;
  end if;
  return coalesce(ok, false);
exception when others then return false;
end $$;
revoke all on function public.cfx_mp_aviso(text) from public, anon, authenticated;
grant execute on function public.cfx_mp_aviso(text) to service_role;

-- Lo que cuesta el plan (igual que lo muestra la app): precio (− cupón, o − descuento Premium en módulos) + cargo por pago online.
create or replace function public.cfx_mp_monto(p_periodo text, p_meses int, p_producto text, p_cupon text) returns int
language plpgsql stable security definer set search_path = '' as $$
declare c jsonb := (select valor from public.cfx_config where clave = 'pagos'); y jsonb := public.cfx_yo(); g jsonb; v jsonb; b numeric; d int := 0;
begin
  if p_producto is not null then
    v := public.cfx_venta();
    if public.cfx_negocio_premium(public.cfx_negocio_cuenta((y ->> 'id')::uuid)) then d := greatest(0, least(90, coalesce((v ->> 'descuento_premium')::int, 0))); end if;
    b := round(public.cfx_venta_precio(p_producto) * (100 - d) / 100.0);
    if p_periodo = 'anual' then b := b * greatest(1, least(12, coalesce((v ->> 'anual_meses')::int, 10))); end if;
  else
    g := case when y ->> 'rol' = 'cliente' then c -> 'cliente' else c -> 'negocio' end;
    b := case p_periodo when 'inicio' then coalesce(nullif((c #>> '{negocio,inicio}')::numeric, 0), (c #>> '{negocio,mensual}')::numeric)
                        when 'mensual' then (g ->> 'mensual')::numeric when 'meses' then (g ->> 'mensual')::numeric * coalesce(p_meses, 1)
                        when 'anual' then (g ->> 'anual')::numeric end;
    if p_cupon is not null then b := round(b * (100 - public.cfx_cupon_ver(p_cupon)) / 100.0); end if;
  end if;
  b := coalesce(b, 0);
  return (b + ceil(b * coalesce((c ->> 'comision_pct')::numeric, 0) / 100))::int;
end $$;

-- Busca en Mercado Pago el pago aprobado de este cobro; si está (monto completo), lo aprueba y avisa (push a la persona y al CM).
create or replace function public.cfx_mp_confirmar(p_id uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare g public.cfx_pagos; tk text := (select valor ->> 'token' from public.cfx_config where clave = 'mp'); r jsonb; pg jsonb;
begin
  select * into g from public.cfx_pagos where id = p_id for update;
  if g.medio = 'flow' and g.estado = 'pendiente' then return public.cfx_flow_confirmar(p_id); end if;  -- G38
  if g.id is null or g.medio <> 'mp' or g.estado <> 'pendiente' then return g.estado; end if;
  if coalesce(tk, '') = '' then return g.estado; end if;
  r := public.cfx_mp_api(tk, 'GET', '/v1/payments/search?sort=date_created&criteria=desc&external_reference=' || g.id::text);
  select e into pg from jsonb_array_elements(coalesce(r #> '{body,results}', '[]'::jsonb)) e
  where e ->> 'status' = 'approved' and e ->> 'external_reference' = g.id::text
    and coalesce(e ->> 'currency_id', 'CLP') = 'CLP' and (e ->> 'transaction_amount')::numeric >= g.monto
    and not exists (select 1 from public.cfx_pagos z where z.mp_pago = e ->> 'id') limit 1;
  if pg is null then
    -- Abrió Mercado Pago y no pagó en 2 días: se cierra (queda en el historial, nada se borra).
    if g.creado < now() - interval '2 days' then
      update public.cfx_pagos set estado = 'rechazado', motivo = 'No se completó el pago en Mercado Pago', resuelto = now() where id = g.id;
      return 'rechazado';
    end if;
    return g.estado;
  end if;
  update public.cfx_pagos set mp_pago = left(pg ->> 'id', 40) where id = g.id;
  begin
    perform public.cfx_pago_aprobar(g.id, null, '⚡ Mercado Pago n° ' || left(pg ->> 'id', 40));
  exception when others then
    -- G87 K: no se pudo activar solo → el pago igual queda aprobado con una 🔑 key de respaldo (nunca se pierde lo pagado).
    select * into g from public.cfx_pagos where id = p_id;
    perform public.cfx_pago_key(g, public.cfx_dias_sugeridos(g), 'aprobado', '⚡ Mercado Pago n° ' || left(pg ->> 'id', 40) || ' · activación falló (' || left(sqlerrm, 80) || '): key de respaldo');
  end;
  begin
    perform public.cfx_al_cm('⚡ Pago automático aprobado', coalesce(nullif(g.nombre, ''), g.email) || ' · $' || g.monto || coalesce(' · 🧩 ' || g.producto, '') ||
      ' (' || case g.periodo when 'meses' then g.meses || ' meses' else g.periodo end || ', Mercado Pago)' || coalesce(' · cupón ' || g.cupon, ''), 'pago');
  exception when others then null; end;
  return 'aprobado';
end $$;

-- La persona paga: crea el cobro y devuelve la página de Mercado Pago (G38: o la de Flow; p_medio 'mp' | 'flow').
drop function if exists public.cfx_mp_pagar(text, int, text, text, text);
create or replace function public.cfx_auto_pagar(p_medio text, p_periodo text, p_meses int, p_producto text, p_cupon text, p_volver text, p_regalo boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); m jsonb := (select valor from public.cfx_config where clave = 'mp'); cup text := nullif(upper(trim(coalesce(p_cupon, ''))), '');
        v text := left(coalesce(p_volver, ''), 500); monto int; i uuid; r jsonb; x uuid; tit text;
begin
  if y is null or (y ->> 'id') is null then raise exception 'Inicia sesión'; end if;
  if p_medio not in ('mp', 'flow') or (p_medio = 'mp' and not public.cfx_mp_on()) or (p_medio = 'flow' and not public.cfx_flow_on()) then
    raise exception 'El pago automático no está disponible. Usa el link de pago o la transferencia.'; end if;
  if y ->> 'rol' not in ('negocio', 'cliente') then raise exception 'Pide al dueño de la cuenta que haga el pago'; end if;
  if p_periodo not in ('inicio', 'mensual', 'meses', 'anual') then raise exception 'Elige un plan'; end if;
  if p_periodo = 'meses' and coalesce(p_meses, 0) not between 2 and 11 then raise exception 'Elige de 2 a 11 meses'; end if;
  if coalesce(p_regalo, false) and p_periodo = 'inicio' then raise exception 'El primer pago es para tu cuenta: elige otro plan para regalar'; end if;
  if coalesce(p_regalo, false) and p_producto is not null and y ->> 'rol' <> 'negocio' then raise exception 'Los módulos se regalan desde una cuenta de negocio'; end if;
  if p_producto is not null and not coalesce(p_regalo, false) then
    if public.cfx_negocio_cuenta((y ->> 'id')::uuid) is distinct from (y ->> 'id')::uuid then raise exception 'Pide al dueño del negocio que haga el pago'; end if;
    if p_periodo not in ('mensual', 'anual') or not coalesce((public.cfx_venta() ->> 'activo')::boolean, false) or cardinality(public.cfx_venta_modulos(p_producto)) = 0 then raise exception 'Módulo no válido'; end if;
    cup := null;
  elsif p_producto is not null then
    if p_periodo not in ('mensual', 'anual') or not coalesce((public.cfx_venta() ->> 'activo')::boolean, false) or cardinality(public.cfx_venta_modulos(p_producto)) = 0 then raise exception 'Módulo no válido'; end if;
    cup := null;
  end if;
  if exists (select 1 from public.cfx_pagos where cuenta = (y ->> 'id')::uuid and estado = 'pendiente' and medio not in ('mp', 'flow')) then raise exception 'Ya tienes un pago en revisión. Te avisamos apenas se apruebe.'; end if;
  if (select count(*) from public.cfx_pagos where cuenta = (y ->> 'id')::uuid and medio in ('mp', 'flow') and creado > now() - interval '1 day') >= 10 then raise exception 'Demasiados intentos hoy. Escribe a soporte.'; end if;
  monto := public.cfx_mp_monto(p_periodo, p_meses, p_producto, cup);
  if monto < 1 then raise exception 'Este plan aún no tiene precio'; end if;
  -- Un intento anterior sin pagar: se revisa (por si sí pagó) y se cierra; nunca se borra.
  for x in select id from public.cfx_pagos where cuenta = (y ->> 'id')::uuid and estado = 'pendiente' and medio in ('mp', 'flow') loop
    if public.cfx_mp_confirmar(x) = 'aprobado' then return jsonb_build_object('ok', true, 'aprobado', true); end if;
    update public.cfx_pagos set estado = 'rechazado', motivo = 'Volviste a pagar en línea', resuelto = now() where id = x and estado = 'pendiente' and mp_pago is null;
  end loop;
  insert into public.cfx_pagos (cuenta, email, nombre, rol, periodo, monto, medio, nota, cupon, meses, producto, mp_desde, regalo)
  values ((y ->> 'id')::uuid, coalesce(y ->> 'email', ''), left(coalesce(y ->> 'nombre', ''), 80), y ->> 'rol', p_periodo, monto, p_medio,
          case when coalesce(p_regalo, false) then '🎁 Regalo · ' else '' end || case p_medio when 'flow' then '⚡ Flow automático' else '⚡ Mercado Pago automático' end, cup,
          case when p_periodo = 'meses' then p_meses end, p_producto, now(), coalesce(p_regalo, false))
  returning id into i;
  tit := case when coalesce(p_regalo, false) then '🎁 Regalo · ' else '' end || case when p_producto is not null then 'Módulo ' || p_producto else 'Premium' end || ' · ' ||
         case p_periodo when 'anual' then '1 año' when 'meses' then p_meses || ' meses' else '1 mes' end;
  if v !~ '^https://[^\s"<>]+$' then v := null; end if;
  if p_medio = 'flow' then return public.cfx_flow_cobro(i, tit, monto, coalesce(y ->> 'email', ''), v); end if;
  r := public.cfx_mp_api(m ->> 'token', 'POST', '/checkout/preferences', jsonb_build_object(
    'items', jsonb_build_array(jsonb_build_object('id', i, 'title', left('CodeFix · ' || tit, 120), 'quantity', 1, 'currency_id', 'CLP', 'unit_price', monto)),
    'external_reference', i::text, 'statement_descriptor', 'CODEFIX',
    'payer', jsonb_build_object('email', coalesce(y ->> 'email', '')),
    'payment_methods', jsonb_build_object('excluded_payment_types', jsonb_build_array(jsonb_build_object('id', 'ticket'))))
    || public.cfx_mp_notif('p:' || i::text)
    || case when v is null then '{}'::jsonb else jsonb_build_object('back_urls', jsonb_build_object('success', v, 'pending', v, 'failure', v), 'auto_return', 'approved') end);
  if coalesce((r ->> 'status')::int, 0) not in (200, 201) or r #>> '{body,init_point}' is null then
    update public.cfx_pagos set estado = 'rechazado', motivo = 'Mercado Pago no respondió', resuelto = now() where id = i;
    return jsonb_build_object('ok', false, 'error', 'Mercado Pago no respondió. Intenta de nuevo o usa el link de pago.');
  end if;
  return jsonb_build_object('ok', true, 'url', r #>> '{body,init_point}', 'id', i, 'monto', monto);
end $$;
revoke all on function public.cfx_auto_pagar(text, text, int, text, text, text, boolean) from public, anon, authenticated;
create or replace function public.cfx_mp_pagar(p_periodo text, p_meses int default null, p_producto text default null, p_cupon text default null, p_volver text default null, p_regalo boolean default false) returns jsonb
language sql security definer set search_path = '' as $$ select public.cfx_auto_pagar('mp', p_periodo, p_meses, p_producto, p_cupon, p_volver, p_regalo) $$;
create or replace function public.cfx_flow_pagar(p_periodo text, p_meses int default null, p_producto text default null, p_cupon text default null, p_volver text default null, p_regalo boolean default false) returns jsonb
language sql security definer set search_path = '' as $$ select public.cfx_auto_pagar('flow', p_periodo, p_meses, p_producto, p_cupon, p_volver, p_regalo) $$;

-- Al volver de Mercado Pago (o al tocar "Ya pagué"): revisa mis cobros abiertos.
create or replace function public.cfx_mp_revisar() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); x uuid; e text; ok boolean := false;
begin
  if y is null or (y ->> 'id') is null then raise exception 'Inicia sesión'; end if;
  for x in select id from public.cfx_pagos where cuenta = (y ->> 'id')::uuid and estado = 'pendiente' and medio in ('mp', 'flow') loop
    e := public.cfx_mp_confirmar(x); ok := ok or e = 'aprobado';
  end loop;
  -- G108 🔁 renovación automática: al volver de MP también revisa mis suscripciones (cobro nuevo = aprobado).
  begin ok := public.cfx_mp_subs_revisar_mias((y ->> 'id')::uuid) > 0 or ok; exception when others then null; end;
  return jsonb_build_object('aprobado', ok, 'pendiente', exists (select 1 from public.cfx_pagos where cuenta = (y ->> 'id')::uuid and estado = 'pendiente' and medio in ('mp', 'flow')),
    -- G87 K: el último pago automático aprobado (para 🎉 "Activo hasta…", 🧾 comprobante y la 🎁 key).
    'pago', case when ok then (select to_jsonb(q) from (select id, periodo, meses, monto, producto, hasta, dias, regalo, key_regalo, mp_pago, cupon, resuelto, email, nombre
      from public.cfx_pagos where cuenta = (y ->> 'id')::uuid and estado = 'aprobado' and medio in ('mp', 'flow') order by resuelto desc nulls last limit 1) q) end,
    'subs', public.cfx_mp_subs_de((y ->> 'id')::uuid));
end $$;

-- "Pagar de otra forma": cierra el cobro de Mercado Pago sin pagar (queda en el historial).
create or replace function public.cfx_mp_cancelar() returns void
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo();
begin
  if y is null or (y ->> 'id') is null then raise exception 'Inicia sesión'; end if;
  perform public.cfx_mp_revisar();
  update public.cfx_pagos set estado = 'rechazado', motivo = 'Elegiste otra forma de pago', resuelto = now()
  where cuenta = (y ->> 'id')::uuid and estado = 'pendiente' and medio in ('mp', 'flow') and mp_pago is null;
end $$;

-- Cada 2 minutos: por si la persona pagó y no volvió a la app.
create or replace function public.cfx_mp_revisar_pendientes() returns int
language plpgsql security definer set search_path = '' as $$
declare x uuid; n int := 0;
begin
  if not (public.cfx_mp_on() or public.cfx_flow_on()) then return 0; end if;
  for x in select id from public.cfx_pagos where estado = 'pendiente' and medio in ('mp', 'flow') order by creado desc limit 60 loop
    begin if public.cfx_mp_confirmar(x) = 'aprobado' then n := n + 1; end if; exception when others then null; end;
  end loop;
  return n;
end $$;

-- ---------- Administrador (CM → Pagos → ⚡ Mercado Pago automático) ----------
create or replace function public.cfx_mp_estado() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare m jsonb := (select valor from public.cfx_config where clave = 'mp');
begin
  perform public.admin_check();
  return jsonb_build_object('conectado', coalesce(m ->> 'token', '') <> '', 'activo', public.cfx_mp_on(), 'nick', m ->> 'nick', 'fin', right(m ->> 'token', 4));
end $$;

-- Conecta (token), prende/pausa (p_activo) o desconecta (sin token y p_activo null).
create or replace function public.cfx_mp_guardar(p_token text, p_activo boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare tk text := nullif(regexp_replace(coalesce(p_token, ''), '\s', '', 'g'), ''); m jsonb := (select valor from public.cfx_config where clave = 'mp'); r jsonb;
begin
  perform public.admin_check();
  if tk is null then
    if p_activo is null then delete from public.cfx_config where clave = 'mp';
    elsif coalesce(m ->> 'token', '') = '' then raise exception 'Pega tu Access Token de Mercado Pago';
    else update public.cfx_config set valor = valor || jsonb_build_object('activo', p_activo) where clave = 'mp'; end if;
    return public.cfx_mp_estado();
  end if;
  if tk !~ '^(APP_USR|TEST)-[A-Za-z0-9-]{20,}$' or length(tk) > 300 then raise exception 'Ese no es un Access Token: empieza con APP_USR-'; end if;
  r := public.cfx_mp_api(tk, 'GET', '/users/me');
  if coalesce((r ->> 'status')::int, 0) = 0 then raise exception 'No se pudo conectar con Mercado Pago. Intenta de nuevo.'; end if;
  if (r ->> 'status')::int <> 200 then raise exception 'Mercado Pago no aceptó el token: copia el Access Token de producción'; end if;
  insert into public.cfx_config (clave, valor) values ('mp', jsonb_build_object('token', tk, 'activo', coalesce(p_activo, true),
    'nick', left(coalesce(r #>> '{body,nickname}', r #>> '{body,email}', ''), 80)))
  on conflict (clave) do update set valor = excluded.valor;
  return public.cfx_mp_estado();
end $$;

-- "🔄 Revisar" un cobro de Mercado Pago desde CM → Pagos.
create or replace function public.cfx_mp_revisar_admin(p_id uuid) returns text
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return public.cfx_mp_confirmar(p_id);
end $$;

revoke all on function public.cfx_mp_api(text, text, text, jsonb), public.cfx_mp_monto(text, int, text, text), public.cfx_mp_confirmar(uuid), public.cfx_mp_revisar_pendientes() from public, anon, authenticated;
revoke all on function public.cfx_mp_pagar(text, int, text, text, text, boolean), public.cfx_mp_revisar(), public.cfx_mp_cancelar(), public.cfx_mp_estado(), public.cfx_mp_guardar(text, boolean), public.cfx_mp_revisar_admin(uuid) from public, anon;
revoke all on function public.cfx_flow_pagar(text, int, text, text, text, boolean) from public, anon;
grant execute on function public.cfx_flow_pagar(text, int, text, text, text, boolean) to authenticated;
grant execute on function public.cfx_mp_pagar(text, int, text, text, text, boolean), public.cfx_mp_revisar(), public.cfx_mp_cancelar(), public.cfx_mp_estado(), public.cfx_mp_guardar(text, boolean), public.cfx_mp_revisar_admin(uuid) to authenticated;
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'cfx-mp';
  perform cron.schedule('cfx-mp', '* * * * *', 'select public.cfx_mp_revisar_pendientes()');
exception when others then
  raise notice 'Revisión de Mercado Pago no programada (%).', sqlerrm;
end $$;

-- ---------------------------------------------------------------------
-- G38 ⚡ FLOW (flow.cl): segundo pago automático para pagar la app, igual que Mercado Pago. Decisión Claude (G33): Flow trae en
--   UNA sola cuenta Webpay (débito/crédito/prepago), transferencia (Khipu) y MACH → Khipu y Webpay directo no hacen falta aparte.
--   CodeFix pega su API Key + Secret Key en CM → Pagos (se guardan en las 7; nadie los lee después). Cobro: medio 'flow' en cfx_pagos;
--   se confirma preguntándole a Flow (getStatusByCommerceId: pagado + monto completo + n° de Flow usado 1 vez) al volver, con el
--   aviso de Flow (función de la app ?cfx_mp=f:<id>, el mismo de MP) y con el cron de cada 1 min. Flow vuelve con POST: la función
--   de la app lo pasa a la página con ?cfx_volver=1 (cfx_pago_volver); si no hay función, vuelve directo a la app.
-- ---------------------------------------------------------------------
alter table public.cfx_pagos add column if not exists volver text;

create or replace function public.cfx_url_cod(p text) returns text
language sql immutable set search_path = '' as $$
  select coalesce(string_agg(case when ch ~ '^[A-Za-z0-9_.~-]$' then ch else regexp_replace(upper(encode(convert_to(ch, 'UTF8'), 'hex')), '(..)', '%\1', 'g') end, '' order by n), '')
  from regexp_split_to_table(coalesce(p, ''), '') with ordinality t(ch, n)
$$;

-- Llama a Flow firmando (HMAC-SHA256 de los parámetros ordenados: nombre+valor). p_cfg: llaves a probar (si no, las guardadas).
create or replace function public.cfx_flow_api(p_metodo text, p_ruta text, p_params jsonb, p_cfg jsonb default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare f jsonb := coalesce(p_cfg, (select valor from public.cfx_config where clave = 'flow')); pr jsonb; firma text; q text; st int; c text;
        base text := case when coalesce((f ->> 'sandbox')::boolean, false) then 'https://sandbox.flow.cl/api' else 'https://www.flow.cl/api' end;
begin
  if coalesce(f ->> 'apikey', '') = '' or coalesce(f ->> 'secret', '') = '' then return jsonb_build_object('status', 0, 'error', 'Flow sin llaves'); end if;
  pr := coalesce(p_params, '{}'::jsonb) || jsonb_build_object('apiKey', f ->> 'apikey');
  select string_agg(k || v, '' order by k collate "C"), string_agg(k || '=' || public.cfx_url_cod(v), '&' order by k collate "C") into firma, q from jsonb_each_text(pr) t(k, v);
  q := q || '&s=' || encode(extensions.hmac(convert_to(firma, 'UTF8'), convert_to(f ->> 'secret', 'UTF8'), 'sha256'), 'hex');
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '10');
  if upper(p_metodo) = 'GET' then
    execute 'select status, content from extensions.http(row($1, $2, $3, $4, $5)::extensions.http_request)' into st, c
      using 'GET', base || p_ruta || '?' || q, array[]::extensions.http_header[], null::text, null::text;
  else
    execute 'select status, content from extensions.http(row($1, $2, $3, $4, $5)::extensions.http_request)' into st, c
      using 'POST', base || p_ruta, array[]::extensions.http_header[], 'application/x-www-form-urlencoded', q;
  end if;
  return jsonb_build_object('status', st, 'body', case when c ~ '^\s*[\{\[]' then c::jsonb end);
exception when others then
  return jsonb_build_object('status', 0, 'error', sqlerrm);
end $$;

-- Crea el cobro en Flow (lo llama cfx_auto_pagar con el cobro ya anotado) y devuelve la página de pago.
create or replace function public.cfx_flow_cobro(p_id uuid, p_titulo text, p_monto int, p_email text, p_volver text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n text := public.cfx_mp_notif('f:' || p_id::text) ->> 'notification_url'; r jsonb;
begin
  if coalesce(p_email, '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    update public.cfx_pagos set estado = 'rechazado', motivo = 'Falta un correo válido para Flow', resuelto = now() where id = p_id;
    return jsonb_build_object('ok', false, 'error', 'Tu cuenta no tiene un correo válido. Usa otra forma de pago.');
  end if;
  if n is null and p_volver is null then
    update public.cfx_pagos set estado = 'rechazado', motivo = 'Sin dirección de regreso', resuelto = now() where id = p_id;
    return jsonb_build_object('ok', false, 'error', 'Flow no está listo en esta app. Usa otra forma de pago.');
  end if;
  update public.cfx_pagos set volver = p_volver where id = p_id;
  r := public.cfx_flow_api('POST', '/payment/create', jsonb_build_object('commerceOrder', p_id::text, 'subject', left('CodeFix · ' || p_titulo, 120),
    'currency', 'CLP', 'amount', p_monto::text, 'email', p_email, 'paymentMethod', '9',
    'urlConfirmation', coalesce(n, p_volver), 'urlReturn', coalesce(n || '&cfx_volver=1', p_volver)));
  if coalesce((r ->> 'status')::int, 0) <> 200 or coalesce(r #>> '{body,url}', '') !~ '^https://' or coalesce(r #>> '{body,token}', '') = '' then
    update public.cfx_pagos set estado = 'rechazado', motivo = 'Flow no respondió', resuelto = now() where id = p_id;
    return jsonb_build_object('ok', false, 'error', 'Flow no respondió. Intenta de nuevo o usa otra forma de pago.');
  end if;
  return jsonb_build_object('ok', true, 'url', (r #>> '{body,url}') || '?token=' || public.cfx_url_cod(r #>> '{body,token}'), 'id', p_id, 'monto', p_monto);
end $$;

-- Pregunta a Flow por ESTE cobro; pagado (status 2) con el monto completo y un n° de Flow no usado → aprueba y avisa.
create or replace function public.cfx_flow_confirmar(p_id uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare g public.cfx_pagos; r jsonb; b jsonb; nro text;
begin
  select * into g from public.cfx_pagos where id = p_id for update;
  if g.id is null or g.medio <> 'flow' or g.estado <> 'pendiente' then return g.estado; end if;
  r := public.cfx_flow_api('GET', '/payment/getStatusByCommerceId', jsonb_build_object('commerceId', g.id::text));
  b := r -> 'body';
  if coalesce((r ->> 'status')::int, 0) <> 200 or b is null or coalesce((b ->> 'status')::int, 0) <> 2 or b ->> 'commerceOrder' is distinct from g.id::text
     or coalesce(b ->> 'currency', 'CLP') <> 'CLP' or coalesce((b ->> 'amount')::numeric, 0) < g.monto
     or exists (select 1 from public.cfx_pagos z where z.mp_pago = 'flow:' || (b ->> 'flowOrder')) then
    if g.creado < now() - interval '2 days' then
      update public.cfx_pagos set estado = 'rechazado', motivo = 'No se completó el pago en Flow', resuelto = now() where id = g.id;
      return 'rechazado';
    end if;
    return g.estado;
  end if;
  nro := left(b ->> 'flowOrder', 30);
  update public.cfx_pagos set mp_pago = 'flow:' || nro where id = g.id;
  begin
    perform public.cfx_pago_aprobar(g.id, null, '⚡ Flow n° ' || nro);
  exception when others then
    select * into g from public.cfx_pagos where id = p_id;
    perform public.cfx_pago_key(g, public.cfx_dias_sugeridos(g), 'aprobado', '⚡ Flow n° ' || nro || ' · activación falló (' || left(sqlerrm, 80) || '): key de respaldo');
  end;
  begin
    perform public.cfx_al_cm('⚡ Pago automático aprobado', coalesce(nullif(g.nombre, ''), g.email) || ' · $' || g.monto || coalesce(' · 🧩 ' || g.producto, '') ||
      ' (' || case g.periodo when 'meses' then g.meses || ' meses' else g.periodo end || ', Flow)' || coalesce(' · cupón ' || g.cupon, ''), 'pago');
  exception when others then null; end;
  return 'aprobado';
end $$;

-- La función de la app: a dónde vuelve la persona después de Flow (solo cobros de Flow de los últimos 2 días).
create or replace function public.cfx_pago_volver(p_ref text) returns text
language plpgsql stable security definer set search_path = '' as $$
declare r text := lower(left(coalesce(p_ref, ''), 80));
begin
  if r !~ '^[fn]:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return null; end if;
  if left(r, 1) = 'n' then  -- G107 💳 Flow propio del negocio
    return (select volver from public.cfx_mp_neg_cobros where id = substr(r, 3)::uuid and medio = 'flow' and created_at > now() - interval '2 days' and volver ~ '^https://[^\s"<>]+$');
  end if;
  return (select volver from public.cfx_pagos where id = substr(r, 3)::uuid and medio = 'flow' and creado > now() - interval '2 days' and volver ~ '^https://[^\s"<>]+$');
end $$;

-- ---------- Administrador (CM → Pagos → ⚡ Flow) ----------
create or replace function public.cfx_flow_estado() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare f jsonb := (select valor from public.cfx_config where clave = 'flow');
begin
  perform public.admin_check();
  return jsonb_build_object('conectado', coalesce(f ->> 'apikey', '') <> '', 'activo', public.cfx_flow_on(), 'sandbox', coalesce((f ->> 'sandbox')::boolean, false), 'fin', right(f ->> 'apikey', 4));
end $$;

-- Conecta (llaves), prende/pausa (p_activo) o desconecta (sin llaves y p_activo null). p_sandbox = cuenta de pruebas de Flow.
create or replace function public.cfx_flow_guardar(p_apikey text, p_secret text, p_activo boolean, p_sandbox boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare k text := nullif(regexp_replace(coalesce(p_apikey, ''), '\s', '', 'g'), ''); sc text := nullif(regexp_replace(coalesce(p_secret, ''), '\s', '', 'g'), '');
        f jsonb := (select valor from public.cfx_config where clave = 'flow'); cfg jsonb; r jsonb;
begin
  perform public.admin_check();
  if k is null and sc is null then
    if p_activo is null then delete from public.cfx_config where clave = 'flow';
    elsif coalesce(f ->> 'apikey', '') = '' then raise exception 'Pega tu API Key y tu Secret Key de Flow';
    else update public.cfx_config set valor = valor || jsonb_build_object('activo', p_activo) where clave = 'flow'; end if;
    return public.cfx_flow_estado();
  end if;
  if k is null or sc is null then raise exception 'Pega las 2 llaves: API Key y Secret Key'; end if;
  if k !~ '^[A-Za-z0-9-]{20,80}$' then raise exception 'Esa no parece una API Key de Flow (Integración → API Keys)'; end if;
  if sc !~ '^[A-Za-z0-9]{20,100}$' then raise exception 'Esa no parece una Secret Key de Flow'; end if;
  cfg := jsonb_build_object('apikey', k, 'secret', sc, 'activo', coalesce(p_activo, true), 'sandbox', coalesce(p_sandbox, false));
  -- Prueba las llaves con un cobro que no existe: 401/403 = llaves malas; cualquier otra respuesta = Flow las aceptó.
  r := public.cfx_flow_api('GET', '/payment/getStatusByCommerceId', jsonb_build_object('commerceId', 'cfx-prueba'), cfg);
  if coalesce((r ->> 'status')::int, 0) = 0 then raise exception 'No se pudo conectar con Flow. Intenta de nuevo.'; end if;
  if (r ->> 'status')::int in (401, 403) then raise exception 'Flow no aceptó las llaves: cópialas de nuevo (¿son de producción o de pruebas?)'; end if;
  insert into public.cfx_config (clave, valor) values ('flow', cfg) on conflict (clave) do update set valor = excluded.valor;
  return public.cfx_flow_estado();
end $$;

revoke all on function public.cfx_url_cod(text), public.cfx_flow_api(text, text, jsonb, jsonb), public.cfx_flow_cobro(uuid, text, int, text, text), public.cfx_flow_confirmar(uuid), public.cfx_pago_volver(text) from public, anon, authenticated;
grant execute on function public.cfx_pago_volver(text) to service_role;
revoke all on function public.cfx_flow_estado(), public.cfx_flow_guardar(text, text, boolean, boolean) from public, anon;
grant execute on function public.cfx_flow_estado(), public.cfx_flow_guardar(text, text, boolean, boolean) to authenticated;

-- G87 E · ↺ Volver a cero los ingresos (solo admin, con registro). NO borra pagos: los ingresos de los resúmenes se cuentan
-- desde esta fecha (los de prueba quedan en el historial). "Contar todo" lo deshace.
create or replace function public.cfx_ingresos_desde() returns timestamptz
language sql stable security definer set search_path = '' as $$
  select coalesce((select (valor ->> 'desde')::timestamptz from public.cfx_config where clave = 'ingresos_cero'), '-infinity'::timestamptz)
$$;
create or replace function public.cfx_ingresos_cero(p_cero boolean default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_check();
  if p_cero is true then
    insert into public.cfx_config (clave, valor) values ('ingresos_cero', jsonb_build_object('desde', now()))
      on conflict (clave) do update set valor = excluded.valor;
    perform public.cfx_anotar('ingresos a cero', 'Los resúmenes cuentan desde ' || to_char(now() at time zone 'America/Santiago', 'DD-MM-YYYY HH24:MI'));
  elsif p_cero is false then
    delete from public.cfx_config where clave = 'ingresos_cero';
    perform public.cfx_anotar('ingresos a cero', 'Deshecho: vuelve a contar todo el historial');
  end if;
  return jsonb_build_object('desde', nullif(public.cfx_ingresos_desde(), '-infinity'::timestamptz));
end $$;
revoke all on function public.cfx_ingresos_cero(boolean) from public, anon;
grant execute on function public.cfx_ingresos_desde() to anon, authenticated;
grant execute on function public.cfx_ingresos_cero(boolean) to authenticated;

-- ---------------------------------------------------------------------
-- G95 🎁 PRUEBA 7 DÍAS POR BOTÓN: todos parten FREE. "🎁 Probar Pro 7 días" (hoja ⭐ Premium) y "🎁 Probar 7 días" en cada módulo,
--   UNA vez por correo. cfx_pruebas_usadas guarda el hash del correo (no el correo) y NO se borra al eliminar la cuenta ni en la limpieza:
--   si la persona se borra y vuelve con el mismo correo, ya no ve el botón y el servidor lo rechaza. item: 'pro', la clave del módulo o 'pack'.
--   Días: cfx_config 'pagos' → 'prueba_pro_dias' (si no está, los de 🧩 Módulos 'prueba_dias'; 7). 0 = sin prueba.
--   Gancho opcional de la app: cfx_pro_prueba_app(uuid, text, int) → timestamptz (si no está, usa cfx_dar_premium).
-- ---------------------------------------------------------------------
create table if not exists public.cfx_pruebas_usadas (
  hash   text not null,
  item   text not null check (item ~ '^[a-z_:]{2,40}$'),
  creado timestamptz not null default now(),
  primary key (hash, item)
);
alter table public.cfx_pruebas_usadas enable row level security;
revoke all on public.cfx_pruebas_usadas from anon, authenticated;
create or replace function public.cfx_hash_correo(p_email text) returns text
language sql immutable as $$ select encode(sha256(convert_to(lower(btrim(p_email)), 'UTF8')), 'hex') $$;
create or replace function public.cfx_prueba_hash(p_cuenta uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case when nullif(btrim(u.email), '') is not null then public.cfx_hash_correo(u.email) else public.cfx_hash_correo('id:' || u.id::text) end
  from auth.users u where u.id = p_cuenta
$$;
create or replace function public.cfx_prueba_usada(p_cuenta uuid, p_item text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.cfx_pruebas_usadas where hash = public.cfx_prueba_hash(p_cuenta) and item = p_item)
$$;
create or replace function public.cfx_prueba_marcar(p_cuenta uuid, p_item text) returns void
language sql security definer set search_path = '' as $$
  insert into public.cfx_pruebas_usadas (hash, item) select h, p_item from (select public.cfx_prueba_hash(p_cuenta) h) x where h is not null
  on conflict do nothing
$$;
create or replace function public.cfx_pro_prueba_dias() returns int
language sql stable security definer set search_path = '' as $$
  select greatest(0, least(30, coalesce((select (valor ->> 'prueba_pro_dias')::int from public.cfx_config where clave = 'pagos'),
    (select (valor ->> 'prueba_dias')::int from public.cfx_config where clave = 'modulos_venta'), 7)))
$$;
-- ¿Esta cuenta puede tocar 🎁 Probar Pro? (para la hoja ⭐ Premium)
create or replace function public.cfx_pro_prueba(y jsonb) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('dias', d, 'usada', u, 'puede', d > 0 and not u and coalesce(y ->> 'rol', '') in ('negocio', 'cliente')
    and not coalesce((y ->> 'premium_hasta')::timestamptz > now(), false))
  from (select public.cfx_pro_prueba_dias() d, public.cfx_prueba_usada((y ->> 'id')::uuid, 'pro') u) x
$$;
create or replace function public.cfx_pro_probar() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); u uuid := (y ->> 'id')::uuid; d int := public.cfx_pro_prueba_dias(); h timestamptz;
begin
  if u is null or u <> auth.uid() then raise exception 'Inicia sesión'; end if;
  if coalesce(y ->> 'rol', '') not in ('negocio', 'cliente') then raise exception 'Esta cuenta no puede probar Premium'; end if;
  if d <= 0 then raise exception 'La prueba gratis no está disponible ahora'; end if;
  if coalesce((y ->> 'premium_hasta')::timestamptz > now(), false) then raise exception 'Ya tienes Premium activo'; end if;
  if public.cfx_prueba_usada(u, 'pro') then raise exception 'Ya usaste tu prueba gratis de Premium con este correo'; end if;
  perform public.cfx_prueba_marcar(u, 'pro');
  if to_regprocedure('public.cfx_pro_prueba_app(uuid,text,integer)') is not null then
    execute 'select public.cfx_pro_prueba_app($1, $2, $3)' into h using u, y ->> 'rol', d;
  else h := public.cfx_dar_premium(u, y ->> 'rol', d); end if;
  if h is null then raise exception 'No se pudo activar la prueba'; end if;
  perform public.cfx_anotar('premium', 'prueba gratis ' || d || ' días · ' || u);
  return jsonb_build_object('ok', true, 'hasta', h, 'dias', d);
end $$;
-- Centro de Mando → Control → 🎁 Pruebas: quién probó qué y cuándo (correo solo si la cuenta sigue existiendo).
create or replace function public.cfx_pruebas_admin() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return jsonb_build_object('total', (select count(*) from public.cfx_pruebas_usadas),
    'items', (select coalesce(jsonb_object_agg(item, n), '{}') from (select item, count(*) n from public.cfx_pruebas_usadas group by item) x),
    'ultimas', (select coalesce(jsonb_agg(jsonb_build_object('item', p.item, 'creado', p.creado, 'email', coalesce(u.email, '')) order by p.creado desc), '[]')
      from (select * from public.cfx_pruebas_usadas order by creado desc limit 200) p
      left join (select distinct on (h) h, email from (select public.cfx_hash_correo(x.email) h, x.email from auth.users x where nullif(btrim(x.email), '') is not null) y) u on u.h = p.hash));
end $$;
revoke all on function public.cfx_hash_correo(text), public.cfx_prueba_hash(uuid), public.cfx_prueba_usada(uuid, text), public.cfx_prueba_marcar(uuid, text),
  public.cfx_pro_prueba_dias(), public.cfx_pro_prueba(jsonb) from public, anon, authenticated;
revoke all on function public.cfx_pro_probar(), public.cfx_pruebas_admin() from public, anon;
grant execute on function public.cfx_pro_probar(), public.cfx_pruebas_admin() to authenticated;

-- ---------------------------------------------------------------------
-- G108 🔁 RENOVACIÓN AUTOMÁTICA de ⭐ Premium y 🧩 módulos (suscripción "preapproval" de Mercado Pago con la cuenta de CodeFix,
--   el mismo motor de G106). La persona autoriza su tarjeta 1 vez; MP cobra solo cada mes (o cada año). Cada cobro aprobado
--   (CLP, monto completo, n° usado 1 sola vez) crea un pago en cfx_pagos ('🔁 Renovación automática') y se aprueba con
--   cfx_pago_aprobar → suma 30/365 días igual que un pago normal. Si el plan sigue activo, el 1.er cobro es 1 día antes de que venza.
--   Quitar = se apaga EN Mercado Pago (MP caído: no se marca y se reintenta). Sin cupón (el cupón es para un pago suelto).
-- ---------------------------------------------------------------------
create table if not exists public.cfx_mp_subs (
  id          uuid primary key default gen_random_uuid(),
  cuenta      uuid not null,
  email       text not null default '',
  nombre      text not null default '',
  rol         text not null,
  producto    text check (producto is null or producto ~ '^[a-z_]{2,30}$'),
  periodo     text not null check (periodo in ('mensual', 'anual')),
  monto       int not null check (monto > 0),
  pagador     text not null default '',
  preapproval text unique,
  estado      text not null default 'pendiente' check (estado in ('pendiente', 'activa', 'pausada', 'cancelada')),
  inicio      timestamptz,
  cobros      int not null default 0,
  ultimo_at   timestamptz,
  revisado_at timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists cfx_mp_subs_cuenta on public.cfx_mp_subs (cuenta, created_at desc);
create index if not exists cfx_mp_subs_viva on public.cfx_mp_subs (revisado_at) where estado <> 'cancelada';
alter table public.cfx_mp_subs enable row level security;
revoke all on public.cfx_mp_subs from anon, authenticated;

create table if not exists public.cfx_mp_sub_cobros (
  id   text primary key,           -- n° del cobro autorizado de MP (1 sola vez)
  sub  uuid not null,
  pago uuid,
  at   timestamptz not null default now()
);
alter table public.cfx_mp_sub_cobros enable row level security;
revoke all on public.cfx_mp_sub_cobros from anon, authenticated;

-- Mis renovaciones vivas (para la ventana de pago): [{ producto, periodo, monto, estado, inicio, cobros, ultimo }]
create or replace function public.cfx_mp_subs_de(p_cuenta uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('producto', producto, 'periodo', periodo, 'monto', monto, 'estado', estado, 'inicio', inicio,
    'cobros', cobros, 'ultimo', ultimo_at) order by created_at desc), '[]')
  from public.cfx_mp_subs where cuenta = p_cuenta and estado <> 'cancelada'
$$;

-- La persona prende la renovación automática: devuelve { ok, url } (página de MP para autorizar la tarjeta) o { ok: false, error }.
create or replace function public.cfx_mp_suscribir(p_periodo text, p_producto text default null, p_email text default null, p_volver text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); u uuid; tk text := (select valor ->> 'token' from public.cfx_config where clave = 'mp');
        m text := lower(trim(coalesce(p_email, ''))); v text := left(coalesce(p_volver, ''), 500); pr text := nullif(trim(coalesce(p_producto, '')), '');
        monto int; h timestamptz; ini timestamptz; s public.cfx_mp_subs; r jsonb; tit text;
begin
  if y is null or (y ->> 'id') is null then raise exception 'Inicia sesión'; end if;
  u := (y ->> 'id')::uuid;
  if not public.cfx_mp_on() then raise exception 'La renovación automática necesita Mercado Pago. Usa otra forma de pago.'; end if;
  if y ->> 'rol' not in ('negocio', 'cliente') then raise exception 'Pide al dueño de la cuenta que lo active'; end if;
  if p_periodo not in ('mensual', 'anual') then raise exception 'La renovación automática es para 1 mes o 1 año'; end if;
  if pr is not null then
    if public.cfx_negocio_cuenta(u) is distinct from u then raise exception 'Pide al dueño del negocio que lo active'; end if;
    if not coalesce((public.cfx_venta() ->> 'activo')::boolean, false) or cardinality(public.cfx_venta_modulos(pr)) = 0 then raise exception 'Módulo no válido'; end if;
  end if;
  if m !~ '^[^@\s"<>]+@[^@\s"<>]+\.[a-z]{2,}$' or length(m) > 120 then raise exception 'Escribe el correo de tu cuenta de Mercado Pago'; end if;
  if v !~ '^https://[^\s"<>]+$' then raise exception 'Falta la dirección de regreso'; end if;
  if exists (select 1 from public.cfx_mp_subs where cuenta = u and producto is not distinct from pr and estado in ('activa', 'pausada')) then
    raise exception 'Ya se renueva solo'; end if;
  if (select count(*) from public.cfx_mp_subs where cuenta = u and created_at > now() - interval '1 day') >= 10 then raise exception 'Demasiados intentos hoy. Escribe a soporte.'; end if;
  monto := public.cfx_mp_monto(p_periodo, null, pr, null);
  if monto < 1 then raise exception 'Este plan aún no tiene precio'; end if;
  -- Si lo que pagó sigue activo, el 1.er cobro es 1 día antes de que venza (no paga 2 veces lo mismo).
  if pr is null then h := (select max(hasta) from public.cfx_pagos where cuenta = u and producto is null and estado = 'aprobado' and not regalo);
  else h := (select max(hasta) from public.cfx_modulos_negocio where negocio = u and modulo = any (public.cfx_venta_modulos(pr))); end if;
  ini := greatest(now() + interval '5 minutes', coalesce(h - interval '1 day', now()));
  update public.cfx_mp_subs set estado = 'cancelada', updated_at = now() where cuenta = u and producto is not distinct from pr and estado = 'pendiente';  -- intento sin autorizar
  insert into public.cfx_mp_subs (cuenta, email, nombre, rol, producto, periodo, monto, pagador, inicio)
  values (u, coalesce(y ->> 'email', ''), left(coalesce(y ->> 'nombre', ''), 80), y ->> 'rol', pr, p_periodo, monto, m, ini)
  returning * into s;
  tit := 'CodeFix · ' || case when pr is not null then 'Módulo ' || pr else 'Premium' end || case p_periodo when 'anual' then ' · cada año' else ' · cada mes' end;
  r := public.cfx_mp_api(tk, 'POST', '/preapproval', jsonb_build_object(
    'reason', left(tit, 120), 'external_reference', 's:' || s.id::text, 'payer_email', m, 'back_url', v, 'status', 'pending',
    'auto_recurring', jsonb_build_object('frequency', case p_periodo when 'anual' then 12 else 1 end, 'frequency_type', 'months', 'currency_id', 'CLP',
      'transaction_amount', monto, 'start_date', to_char(ini at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS".000+00:00"'))));
  if coalesce((r ->> 'status')::int, 0) not in (200, 201) or r #>> '{body,init_point}' is null or r #>> '{body,id}' is null then
    delete from public.cfx_mp_subs where id = s.id;
    return jsonb_build_object('ok', false, 'error', coalesce('Mercado Pago: ' || left(r #>> '{body,message}', 160), 'Mercado Pago no respondió. Intenta de nuevo.'));
  end if;
  update public.cfx_mp_subs set preapproval = left(r #>> '{body,id}', 60), revisado_at = now() where id = s.id;
  return jsonb_build_object('ok', true, 'url', r #>> '{body,init_point}', 'monto', monto, 'inicio', ini);
end $$;

-- Un cobro aprobado de la suscripción → pago aprobado (activa/extiende). Si la activación falla, queda con 🔑 key de respaldo.
create or replace function public.cfx_mp_sub_cobro(p_sub uuid, p_cobro text, p_pago text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare s public.cfx_mp_subs; i uuid; g public.cfx_pagos; mot text;
begin
  select * into s from public.cfx_mp_subs where id = p_sub;
  if s.id is null then return false; end if;
  insert into public.cfx_mp_sub_cobros (id, sub) values (left(p_cobro, 40), s.id) on conflict do nothing;
  if not found then return false; end if;
  mot := '🔁 Renovación automática · Mercado Pago n° ' || left(coalesce(p_pago, p_cobro), 40);
  insert into public.cfx_pagos (cuenta, email, nombre, rol, periodo, monto, medio, nota, producto, mp_desde, mp_pago)
  values (s.cuenta, s.email, s.nombre, s.rol, s.periodo, s.monto, 'mp', '🔁 Renovación automática', s.producto, now(),
          case when p_pago is not null and not exists (select 1 from public.cfx_pagos where mp_pago = left(p_pago, 40)) then left(p_pago, 40) end)
  returning id into i;
  update public.cfx_mp_sub_cobros set pago = i where id = left(p_cobro, 40);
  begin
    perform public.cfx_pago_aprobar(i, null, mot);
  exception when others then
    select * into g from public.cfx_pagos where id = i;
    perform public.cfx_pago_key(g, public.cfx_dias_sugeridos(g), 'aprobado', left(mot || ' · activación falló (' || left(sqlerrm, 60) || '): key de respaldo', 200));
  end;
  begin
    perform public.cfx_al_cm('🔁 Renovación automática cobrada', coalesce(nullif(s.nombre, ''), s.email) || ' · $' || s.monto || ' · ' ||
      coalesce('🧩 ' || s.producto, '⭐ Premium') || ' (' || s.periodo || ', Mercado Pago)', 'pago');
  exception when others then null; end;
  return true;
end $$;

-- Pregunta a MP por UNA suscripción: estado + cobros nuevos. Devuelve cuántos cobros nuevos encontró.
create or replace function public.cfx_mp_sub_revisar(p_id uuid) returns int
language plpgsql security definer set search_path = '' as $$
declare s public.cfx_mp_subs; tk text := (select valor ->> 'token' from public.cfx_config where clave = 'mp'); r jsonb; e jsonb; nuevo text; n int := 0;
begin
  select * into s from public.cfx_mp_subs where id = p_id for update skip locked;
  if s.id is null or s.preapproval is null or s.estado = 'cancelada' or coalesce(tk, '') = '' then return 0; end if;
  update public.cfx_mp_subs set revisado_at = now() where id = s.id;
  r := public.cfx_mp_api(tk, 'GET', '/preapproval/' || s.preapproval);
  if coalesce((r ->> 'status')::int, 0) = 200 then
    nuevo := case r #>> '{body,status}' when 'authorized' then 'activa' when 'paused' then 'pausada' when 'cancelled' then 'cancelada' else s.estado end;
    if nuevo <> s.estado then
      update public.cfx_mp_subs set estado = nuevo, updated_at = now() where id = s.id;
      begin
        if nuevo = 'activa' and s.estado = 'pendiente' then
          perform public.cfx_avisar(s.cuenta, '🔁 Renovación automática activa', coalesce('🧩 ' || s.producto, '⭐ Premium') || ': se paga solo ' ||
            case s.periodo when 'anual' then 'cada año' else 'cada mes' end || ' ($' || s.monto || '). 1.er cobro el ' || to_char(s.inicio at time zone 'America/Santiago', 'DD/MM/YYYY') || '.');
          perform public.cfx_al_cm('🔁 Renovación automática nueva', coalesce(nullif(s.nombre, ''), s.email) || ' · ' || coalesce('🧩 ' || s.producto, '⭐ Premium') || ' · $' || s.monto || ' (' || s.periodo || ')', 'pago');
        elsif nuevo = 'cancelada' and s.estado <> 'pendiente' then
          perform public.cfx_avisar(s.cuenta, '🔁 Renovación automática apagada', coalesce('🧩 ' || s.producto, '⭐ Premium') || ' ya no se paga solo. Lo que pagaste sigue activo hasta que venza.');
        end if;
      exception when others then null; end;
      if nuevo = 'cancelada' then return n; end if;
    end if;
  end if;
  r := public.cfx_mp_api(tk, 'GET', '/authorized_payments/search?preapproval_id=' || s.preapproval);
  for e in select x from jsonb_array_elements(coalesce(r #> '{body,results}', '[]'::jsonb)) x
           where coalesce(x #>> '{payment,status}', '') = 'approved' and coalesce(x ->> 'preapproval_id', s.preapproval) = s.preapproval
             and coalesce(x ->> 'currency_id', 'CLP') = 'CLP' and coalesce((x ->> 'transaction_amount')::numeric, 0) >= s.monto
             and x ->> 'id' is not null loop
    if public.cfx_mp_sub_cobro(s.id, e ->> 'id', e #>> '{payment,id}') then
      n := n + 1;
      update public.cfx_mp_subs set cobros = cobros + 1, ultimo_at = now(), estado = case when estado = 'pendiente' then 'activa' else estado end, updated_at = now() where id = s.id;
    end if;
  end loop;
  return n;
end $$;

-- Quitar la renovación automática (lo pagado sigue activo hasta que venza). false = MP no respondió (se reintenta).
create or replace function public.cfx_mp_sub_quitar(p_producto text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); s public.cfx_mp_subs; tk text := (select valor ->> 'token' from public.cfx_config where clave = 'mp'); r jsonb; todo boolean := true;
        pr text := nullif(trim(coalesce(p_producto, '')), '');
begin
  if y is null or (y ->> 'id') is null then raise exception 'Inicia sesión'; end if;
  for s in select * from public.cfx_mp_subs where cuenta = (y ->> 'id')::uuid and producto is not distinct from pr and estado <> 'cancelada' for update loop
    if s.preapproval is not null and coalesce(tk, '') <> '' then
      r := public.cfx_mp_api(tk, 'PUT', '/preapproval/' || s.preapproval, jsonb_build_object('status', 'cancelled'));
      if coalesce((r ->> 'status')::int, 0) not in (200, 201) and coalesce(r #>> '{body,status}', '') <> 'cancelled' then todo := false; continue; end if;
    end if;
    update public.cfx_mp_subs set estado = 'cancelada', updated_at = now() where id = s.id;
  end loop;
  if not todo then return jsonb_build_object('ok', false, 'error', 'Mercado Pago no respondió. Intenta de nuevo en un rato.'); end if;
  return jsonb_build_object('ok', true);
end $$;

-- Mis suscripciones (al volver de MP / "Ya autoricé"): revisa y devuelve cuántos cobros nuevos hubo.
create or replace function public.cfx_mp_subs_revisar_mias(p_cuenta uuid) returns int
language plpgsql security definer set search_path = '' as $$
declare i uuid; n int := 0;
begin
  for i in select id from public.cfx_mp_subs where cuenta = p_cuenta and estado <> 'cancelada' and preapproval is not null order by created_at desc limit 5 loop
    n := n + public.cfx_mp_sub_revisar(i);
  end loop;
  return n;
end $$;

-- Cron: pendientes (cada 1 min, 2 días; después se dan por abandonadas) · vivas (cada 30 min).
create or replace function public.cfx_mp_subs_revisar() returns int
language plpgsql security definer set search_path = '' as $$
declare i uuid; n int := 0;
begin
  update public.cfx_mp_subs set estado = 'cancelada', updated_at = now() where estado = 'pendiente' and created_at < now() - interval '2 days' and cobros = 0;
  if not public.cfx_mp_on() then return 0; end if;
  for i in select id from public.cfx_mp_subs where estado <> 'cancelada' and preapproval is not null
             and (revisado_at is null or revisado_at < now() - case when estado = 'pendiente' then interval '1 minute' else interval '30 minutes' end)
           order by revisado_at nulls first limit 30 loop
    begin n := n + public.cfx_mp_sub_revisar(i); exception when others then null; end;
  end loop;
  return n;
end $$;

-- CM → Pagos: cuántas renovaciones automáticas hay vivas (y las últimas).
create or replace function public.cfx_mp_subs_admin() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return jsonb_build_object('activas', (select count(*) from public.cfx_mp_subs where estado = 'activa'),
    'items', (select coalesce(jsonb_agg(jsonb_build_object('email', email, 'nombre', nombre, 'producto', producto, 'periodo', periodo, 'monto', monto,
      'estado', estado, 'cobros', cobros, 'ultimo', ultimo_at, 'inicio', inicio) order by created_at desc), '[]')
      from (select * from public.cfx_mp_subs where estado <> 'cancelada' order by created_at desc limit 100) x));
end $$;

revoke all on function public.cfx_mp_subs_de(uuid), public.cfx_mp_sub_cobro(uuid, text, text), public.cfx_mp_sub_revisar(uuid),
  public.cfx_mp_subs_revisar_mias(uuid), public.cfx_mp_subs_revisar() from public, anon, authenticated;
revoke all on function public.cfx_mp_suscribir(text, text, text, text), public.cfx_mp_sub_quitar(text), public.cfx_mp_subs_admin() from public, anon;
grant execute on function public.cfx_mp_suscribir(text, text, text, text), public.cfx_mp_sub_quitar(text), public.cfx_mp_subs_admin() to authenticated;
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'cfx-mp-subs';
  perform cron.schedule('cfx-mp-subs', '* * * * *', 'select public.cfx_mp_subs_revisar()');
exception when others then
  raise notice 'Revisión de renovaciones automáticas no programada (%).', sqlerrm;
end $$;
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
-- G81 d: item '' = Premium · clave de un módulo o de un pack = activa ese módulo/pack (solo negocios). 1 uso cada key.
alter table public.cfx_keys add column if not exists item text not null default '';
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
  if p_destino not in ('todos', 'negocios', 'clientes', 'premium', 'gratis', 'ofertas') then raise exception 'Destino no válido'; end if;
  -- 'ofertas' = publicidad: solo a quienes aceptaron recibir ofertas (consentimiento, sql/legal.sql).
  for u in select d from public.cfx_destinatarios(case when p_destino = 'ofertas' then 'todos' else p_destino end) d where p_destino <> 'ofertas' or public.cfx_acepta(d, 'ofertas') loop
    perform public.cfx_avisar(u, left(p_titulo, 80), left(coalesce(p_cuerpo, ''), 240));
    n := n + 1;
  end loop;
  perform public.cfx_anotar('aviso', p_destino || ' (' || n || '): ' || p_titulo);
  return n;
end $$;

-- ---------- Nueva versión disponible: push a todos al liberar (una sola vez por versión) ----------
-- G44b: el aviso dice SOLO categorías (🔒 Seguridad · ⚙️ Funcionamiento · 🖥️ Sistema · ✏️ Mejoras · 🎁 Premios/novedades), nunca qué se hizo.
-- p_notas trae las categorías (claves seg/func/sis/mej/pre o sus nombres); el texto libre NO llega a los usuarios.
-- El detalle (p_detalle) queda solo para el administrador: en cfx_versiones (sin políticas = nadie lo lee) y en el 📜 Registro.
create table if not exists public.cfx_versiones (version text primary key, notas text not null default '', avisados int not null default 0, creado timestamptz not null default now());
alter table public.cfx_versiones add column if not exists detalle text not null default '';
alter table public.cfx_versiones enable row level security;
create or replace function public.cfx_version_categorias(p text) returns text
language sql immutable set search_path = '' as $$
  select coalesce(string_agg(c.nombre, ' · ' order by c.orden), '')
  from (values (1, '🔒 Seguridad', '(^|[^a-z])seg([^a-z]|$)|🔒|seguridad'), (2, '⚙️ Funcionamiento', '(^|[^a-z])func([^a-z]|$)|⚙|funcionamiento'),
               (3, '🖥️ Sistema', '(^|[^a-z])sis([^a-z]|$)|🖥|sistema'), (4, '✏️ Mejoras', '(^|[^a-z])mej([^a-z]|$)|✏|mejora'),
               (5, '🎁 Premios/novedades', '(^|[^a-z])pre([^a-z]|$)|🎁|premio|novedad')) c(orden, nombre, patron)
  where lower(coalesce(p, '')) ~ c.patron
$$;
drop function if exists public.cfx_avisar_version(text, text, text);
create or replace function public.cfx_avisar_version(p_version text, p_notas text default '', p_app text default '', p_detalle text default '') returns int
language plpgsql security definer set search_path = '' as $$
declare u uuid; n int := 0; v text := trim(coalesce(p_version, '')); cat text := public.cfx_version_categorias(p_notas);
  det text := left(trim(coalesce(nullif(trim(coalesce(p_detalle, '')), ''), p_notas, '')), 400);
begin
  perform public.admin_check();
  if v !~ '^[0-9]+(\.[0-9]+){0,3}$' then raise exception 'Versión no válida'; end if;
  if exists (select 1 from public.cfx_versiones where version = v) then return 0; end if;
  for u in select * from public.cfx_destinatarios('todos') loop
    perform public.cfx_avisar(u, '🔄 Nueva versión', left(coalesce(nullif(trim(p_app), '') || ' ', '') || 'v' || v || case when cat <> '' then ': ' || cat else '' end || '. Se actualiza sola al abrirla.', 240));
    n := n + 1;
  end loop;
  insert into public.cfx_versiones (version, notas, avisados, detalle) values (v, cat, n, det);
  perform public.cfx_anotar('version', left('v' || v || ' avisada a ' || n || case when cat <> '' then ' · ' || cat else '' end || case when det <> '' then ' — ' || det else '' end, 500));
  return n;
end $$;
revoke execute on function public.cfx_avisar_version(text, text, text, text) from public, anon;
grant execute on function public.cfx_avisar_version(text, text, text, text) to authenticated;
revoke all on function public.cfx_version_categorias(text) from public, anon, authenticated;

-- ---------- Keys de Premium (de un solo uso). Se guardan cifradas: el código completo solo se ve al crearlas. ----------
drop function if exists public.cfx_keys_crear(int, text, int, text);
create or replace function public.cfx_keys_crear(p_n int, p_rol text, p_dias int, p_nota text default '', p_item text default '') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c text; out jsonb := '[]'::jsonb; it text := trim(coalesce(p_item, ''));
begin
  perform public.admin_check();
  if p_rol not in ('negocio', 'cliente') or coalesce(p_dias, 0) not between 1 and 3660 or coalesce(p_n, 0) not between 1 and 50 then raise exception 'Datos no válidos'; end if;
  if it <> '' and (p_rol <> 'negocio' or cardinality(public.cfx_venta_modulos(it)) = 0) then raise exception 'Módulo o pack no válido (las keys de módulos son para negocios)'; end if;
  for i in 1..p_n loop
    c := upper(replace(gen_random_uuid()::text, '-', ''));
    c := 'CFX-' || substr(c, 1, 4) || '-' || substr(c, 5, 4) || '-' || substr(c, 9, 4);
    insert into public.cfx_keys (hash, ultimos, rol, dias, nota, item) values (encode(sha256(convert_to(c, 'UTF8')), 'hex'), right(c, 4), p_rol, p_dias, left(coalesce(p_nota, ''), 120), it);
    out := out || to_jsonb(c);
  end loop;
  perform public.cfx_anotar('keys', p_n || ' keys ' || case when it = '' then 'Premium ' || p_rol else it end || ' de ' || p_dias || ' días');
  return out;
end $$;
-- G81 d: aplica una key ya validada a una cuenta (Premium o módulo/pack). Si el negocio ya tiene todo lo de la key activo, no la gasta.
create or replace function public.cfx_key_dar(k public.cfx_keys, p_cuenta uuid, p_email text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare h timestamptz; n uuid; nom text;
begin
  if coalesce(k.item, '') = '' then
    h := public.cfx_dar_premium(p_cuenta, k.rol, k.dias);
    if h is null then return jsonb_build_object('error', 'No se encontró la cuenta'); end if;
    insert into public.cfx_exentos (cuenta, nota) values (p_cuenta, 'Key ' || k.ultimos) on conflict (cuenta) do nothing;
    nom := 'Premium';
  else
    n := public.cfx_negocio_cuenta(p_cuenta);
    if n is null then return jsonb_build_object('error', 'Esta key es para negocios'); end if;
    nom := coalesce((select c.nombre from public.cfx_modulos_catalogo() c where c.clave = k.item), public.cfx_venta() #>> array['packs', k.item, 'nombre'], k.item);
    if cardinality(public.cfx_venta_modulos(k.item)) = 0 then return jsonb_build_object('error', 'Este módulo ya no está disponible'); end if;
    if not exists (select 1 from unnest(public.cfx_venta_modulos(k.item)) x where not exists (
        select 1 from public.cfx_modulos_negocio m where m.negocio = n and m.modulo = x and m.hasta > now())) then
      return jsonb_build_object('error', 'Ya tienes ' || nom || ' activo. Guarda la key para cuando venza o para otro negocio.');
    end if;
    h := public.cfx_modulos_dar(n, k.item, k.dias, 'pago');
  end if;
  update public.cfx_keys set usada_por = p_cuenta, usada_email = left(coalesce(p_email, ''), 200), usada_at = now() where id = k.id;
  return jsonb_build_object('hasta', h, 'dias', k.dias, 'item', coalesce(k.item, ''), 'nombre', nom);
end $$;
revoke all on function public.cfx_key_dar(public.cfx_keys, uuid, text) from public, anon, authenticated;
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
declare y jsonb := public.cfx_yo(); k public.cfx_keys; r jsonb; c text := upper(trim(coalesce(p_codigo, '')));
begin
  if y is null or (y ->> 'id') is null then raise exception 'Inicia sesión'; end if;
  if (select count(*) from public.cfx_registro where accion = 'key fallida' and detalle = (y ->> 'id') and creado > now() - interval '1 hour') >= 10 then
    raise exception 'Demasiados intentos. Prueba en una hora.';
  end if;
  select * into k from public.cfx_keys where hash = encode(sha256(convert_to(c, 'UTF8')), 'hex') for update;
  if k.id is null or k.revocada or k.usada_por is not null then
    -- Sin raise: si no, el registro se deshace y el límite de 10 por hora nunca cuenta (núcleo 2.48).
    insert into public.cfx_registro (quien, accion, detalle) values (coalesce(y ->> 'email', ''), 'key fallida', y ->> 'id');
    return jsonb_build_object('error', 'Key no válida o ya usada');
  end if;
  if k.rol <> coalesce(y ->> 'rol', '') then raise exception 'Esta key es para cuentas de %', case when k.rol = 'negocio' then 'negocio' else 'cliente' end; end if;
  r := public.cfx_key_dar(k, (y ->> 'id')::uuid, y ->> 'email');
  if r ? 'error' then return r; end if;
  perform public.cfx_avisar_admin('🔑 Key canjeada', coalesce(y ->> 'email', '') || ' · ' || (r ->> 'nombre') || ' · ' || k.dias || ' días');
  return r;
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
-- y, para las compras/reservas sin cuenta, también aquí (cfx_secretos, nunca sale de la base): la base revisa el token con Cloudflare.
insert into public.cfx_config (clave, valor) values ('humano', '{"site_key": ""}') on conflict (clave) do nothing;
create table if not exists public.cfx_secretos (clave text primary key, valor text not null, updated_at timestamptz not null default now());
alter table public.cfx_secretos enable row level security;
revoke all on public.cfx_secretos from anon, authenticated;
create or replace function public.cfx_humano() returns jsonb
language sql stable security definer set search_path = '' as $$
  select valor || jsonb_build_object('invitados', exists (select 1 from public.cfx_secretos where clave = 'turnstile'))
  from public.cfx_config where clave = 'humano' $$;
drop function if exists public.cfx_humano_guardar(text);
create or replace function public.cfx_humano_guardar(p_site_key text, p_secreto text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_check();
  if coalesce(p_site_key, '') <> '' and p_site_key !~ '^[0-9A-Za-z_-]{10,60}$' then raise exception 'Site key no válida'; end if;
  if coalesce(p_secreto, '') <> '' and p_secreto !~ '^[0-9A-Za-z_-]{10,80}$' then raise exception 'Secret key no válida'; end if;
  update public.cfx_config set valor = jsonb_build_object('site_key', coalesce(p_site_key, '')) where clave = 'humano';
  -- null = dejar la secret key como está; '' = quitarla (o si se apaga la site key).
  if coalesce(p_site_key, '') = '' or p_secreto = '' then delete from public.cfx_secretos where clave = 'turnstile';
  elsif p_secreto is not null then
    insert into public.cfx_secretos (clave, valor) values ('turnstile', p_secreto)
    on conflict (clave) do update set valor = excluded.valor, updated_at = now();
  end if;
  perform public.cfx_anotar('humano', case when coalesce(p_site_key, '') = '' then 'apagado' else 'site key ' || right(p_site_key, 4) ||
    case when exists (select 1 from public.cfx_secretos where clave = 'turnstile') then ' + compras sin cuenta' else '' end end);
end $$;
-- ¿El token de Turnstile es de una persona? Sin secret key no se exige. Si Cloudflare no responde, no frena la venta.
create or replace function public.cfx_humano_ok(p_token text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare k text := (select valor from public.cfx_secretos where clave = 'turnstile'); st int; c text;
begin
  if k is null then return true; end if;
  if coalesce(p_token, '') = '' or length(p_token) > 4000 then return false; end if;
  begin
    perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '5');
    execute 'select status, content from extensions.http(row($1, $2, $3, $4, $5)::extensions.http_request)' into st, c
      using 'POST', 'https://challenges.cloudflare.com/turnstile/v0/siteverify', array[]::extensions.http_header[],
            'application/x-www-form-urlencoded', 'secret=' || k || '&response=' || p_token;
  exception when others then return true;
  end;
  if st is distinct from 200 or c !~ '^\s*\{' then return true; end if;
  return coalesce((c::jsonb ->> 'success')::boolean, false);
end $$;
revoke all on function public.cfx_humano(), public.cfx_humano_guardar(text, text), public.cfx_humano_ok(text) from public, anon, authenticated;
grant execute on function public.cfx_humano() to anon, authenticated;
grant execute on function public.cfx_humano_guardar(text, text) to authenticated;

revoke all on function public.cfx_anotar(text, text), public.cfx_cupon_usado() from public, anon, authenticated;
revoke all on function public.cfx_registro_lista(int), public.cfx_planes(), public.cfx_plan_guardar(text, text, jsonb, jsonb), public.cfx_textos(), public.cfx_texto_guardar(text, text),
  public.cfx_aviso_masivo(text, text, text), public.cfx_keys_crear(int, text, int, text, text), public.cfx_keys_lista(), public.cfx_key_revocar(uuid), public.cfx_key_canjear(text),
  public.cfx_cupon_ver(text), public.cfx_cupones_lista(), public.cfx_cupon_guardar(text, int, int, date, boolean), public.cfx_cupon_borrar(text),
  public.cfx_verif_estado(), public.cfx_verif_enviar(text, text, text, text, text), public.cfx_verif_lista(text), public.cfx_verif_fotos(uuid), public.cfx_verif_resolver(uuid, boolean, text) from public, anon;
grant execute on function public.cfx_registro_lista(int), public.cfx_planes(), public.cfx_plan_guardar(text, text, jsonb, jsonb), public.cfx_textos(), public.cfx_texto_guardar(text, text),
  public.cfx_aviso_masivo(text, text, text), public.cfx_keys_crear(int, text, int, text, text), public.cfx_keys_lista(), public.cfx_key_revocar(uuid), public.cfx_key_canjear(text),
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
      'pagos', (select count(*) from public.cfx_pagos p where p.estado = 'aprobado' and p.creado >= m and p.creado < m + interval '1 month' and p.creado >= public.cfx_ingresos_desde()),
      'ingresos', (select coalesce(sum(p.monto), 0) from public.cfx_pagos p where p.estado = 'aprobado' and p.creado >= m and p.creado < m + interval '1 month' and p.creado >= public.cfx_ingresos_desde())) order by m)
    from generate_series(date_trunc('month', now()) - make_interval(months => n - 1), date_trunc('month', now()), interval '1 month') m);
end $$;
revoke all on function public.cfx_series(int) from public, anon;
grant execute on function public.cfx_series(int) to authenticated;

-- ---------- Servidor (igual en las 7 apps): uso de la base, cuentas, tablas más pesadas y tareas automáticas ----------
-- El Centro de Mando lo muestra en el carrusel de servidores. "tareas" sirve para ver si el envío de push está corriendo.
create or replace function public.cfx_servidor() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare t jsonb := '[]'; tb jsonb;
begin
  perform public.admin_check();
  select coalesce(jsonb_agg(x), '[]') into tb from (
    select jsonb_build_object('tabla', c.relname, 'bytes', pg_total_relation_size(c.oid), 'filas', greatest(c.reltuples, 0)::bigint) x
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' order by pg_total_relation_size(c.oid) desc limit 6) q;
  begin
    execute $q$ select coalesce(jsonb_agg(jsonb_build_object('nombre', j.jobname, 'activa', j.active, 'cada', j.schedule,
        'ultima', r.end_time, 'ok', r.status = 'succeeded', 'error', left(r.return_message, 160)) order by j.jobname), '[]')
      from cron.job j left join lateral (select end_time, status, return_message from cron.job_run_details d where d.jobid = j.jobid order by d.runid desc limit 1) r on true $q$ into t;
  exception when others then t := '[]';
  end;
  return jsonb_build_object('db_bytes', pg_database_size(current_database()), 'limite_bytes', 500 * 1024 * 1024,
    'cuentas', (select count(*) from auth.users), 'tablas', tb, 'tareas', t, 'hora', now());
end $$;
revoke all on function public.cfx_servidor() from public, anon;
grant execute on function public.cfx_servidor() to authenticated;

-- ---------- Actualizar la base ahora (núcleo 2.31, igual en las 7 apps) ----------
-- El Centro de Mando lo usa cuando una base quedó atrás ("se está actualizando sola" que no avanza).
-- Programa una tarea de un solo uso (en máx. 1 minuto, sin el límite de tiempo de la app) que corre auto_actualizar() y anota
-- su resultado en cfx_registro ('auto'): así se ve la causa real si falla (la tarea de cada 10 min siempre figura "ok").
drop function if exists public.cfx_actualizar_ahora();
create or replace function public.cfx_actualizar_ahora(p_programar boolean default true) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare prog text := 'ok'; t jsonb := '[]'; ult jsonb;
begin
  perform public.admin_check();
  if p_programar then begin
    execute $q$ select cron.schedule('cfx-ahora', '* * * * *', $c$do $d$ declare r text; begin r := public.auto_actualizar(); perform public.cfx_anotar('auto', r); end $d$; select cron.unschedule('cfx-ahora')$c$) $q$;
  exception when others then prog := sqlerrm;
  end; else prog := ''; end if;
  begin
    execute $q$ select coalesce(jsonb_agg(jsonb_build_object('nombre', j.jobname, 'activa', j.active, 'cada', j.schedule, 'ultima', r.end_time, 'ok', r.status = 'succeeded', 'error', left(r.return_message, 160)) order by j.jobname), '[]')
      from cron.job j left join lateral (select end_time, status, return_message from cron.job_run_details d where d.jobid = j.jobid order by d.runid desc limit 1) r on true
      where j.jobname ~ 'auto|ahora' $q$ into t;
  exception when others then t := '[]';
  end;
  select coalesce(jsonb_agg(jsonb_build_object('detalle', detalle, 'creado', creado) order by id desc), '[]') into ult
    from (select * from public.cfx_registro where accion = 'auto' order by id desc limit 3) q;
  if p_programar then perform public.cfx_anotar('version', 'Actualizar base ahora: ' || left(prog, 200)); end if;
  return jsonb_build_object('programada', prog, 'tareas', t, 'ultimos', ult, 'hora', now());
end $$;
revoke all on function public.cfx_actualizar_ahora(boolean) from public, anon;
grant execute on function public.cfx_actualizar_ahora(boolean) to authenticated;

-- ---------- G20 · 🏪 Negocios desde el Centro de Mando (Control → app → Negocios) ----------
-- Lista de cuentas de la app, Premium 1 mes / 3 meses / 1 año o quitarlo, e ingresar una key a nombre de esa cuenta.
-- Ganchos de cada app (opcionales: sin ellos se avisa que llega en su turno):
--   cfx_cuentas_app(p_rol text, p_q text) → jsonb [{ id, email, nombre, rol, premium_hasta, creado }] · cfx_quitar_premium(p_cuenta uuid)
create or replace function public.cfx_negocios(p_q text default '', p_rol text default 'negocio') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  perform public.admin_check();
  if to_regprocedure('public.cfx_cuentas_app(text,text)') is null then return jsonb_build_object('error', 'Esta app aún no tiene la lista de negocios: llega cuando le toque su turno.'); end if;
  execute 'select public.cfx_cuentas_app($1, $2)' into r using case when p_rol = 'cliente' then 'cliente' else 'negocio' end, left(coalesce(p_q, ''), 80);
  return coalesce(r, '[]'::jsonb);
end $$;
create or replace function public.cfx_premium_cuenta(p_cuenta uuid, p_rol text, p_dias int) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare h timestamptz;
begin
  perform public.admin_check();
  if p_cuenta is null or coalesce(p_rol, '') not in ('negocio', 'cliente') or p_dias is null or p_dias > 3660 then return jsonb_build_object('error', 'Datos no válidos'); end if;
  if p_dias > 0 then
    h := public.cfx_dar_premium(p_cuenta, p_rol, p_dias);
    if h is null then return jsonb_build_object('error', 'No se encontró la cuenta'); end if;
    perform public.cfx_avisar(p_cuenta, '⭐ Premium activado', 'Tienes Premium hasta el ' || to_char(h at time zone 'America/Santiago', 'DD-MM-YYYY') || '.');
    perform public.cfx_anotar('premium', p_dias || ' días a ' || p_cuenta);
    return jsonb_build_object('hasta', h);
  end if;
  if to_regprocedure('public.cfx_quitar_premium(uuid)') is null then return jsonb_build_object('error', 'Esta app aún no permite quitar Premium desde aquí.'); end if;
  execute 'select public.cfx_quitar_premium($1)' using p_cuenta;
  perform public.cfx_anotar('premium quitado', p_cuenta::text);
  return jsonb_build_object('hasta', null);
end $$;
create or replace function public.cfx_key_aplicar(p_cuenta uuid, p_rol text, p_email text, p_codigo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare k public.cfx_keys; r jsonb; c text := upper(trim(coalesce(p_codigo, '')));
begin
  perform public.admin_check();
  if p_cuenta is null or coalesce(p_rol, '') not in ('negocio', 'cliente') then return jsonb_build_object('error', 'Datos no válidos'); end if;
  select * into k from public.cfx_keys where hash = encode(sha256(convert_to(c, 'UTF8')), 'hex') for update;
  if k.id is null or k.revocada or k.usada_por is not null then return jsonb_build_object('error', 'Key no válida o ya usada'); end if;
  if k.rol <> p_rol then return jsonb_build_object('error', 'Esta key es para cuentas de ' || k.rol); end if;
  r := public.cfx_key_dar(k, p_cuenta, p_email);
  if r ? 'error' then return r; end if;
  perform public.cfx_avisar(p_cuenta, '🔑 ' || (r ->> 'nombre') || ' activado', 'Tienes ' || (r ->> 'nombre') || ' por ' || k.dias || ' días.');
  perform public.cfx_anotar('key aplicada', '…' || k.ultimos || ' (' || (r ->> 'nombre') || ') a ' || coalesce(p_email, p_cuenta::text));
  return r;
end $$;
revoke all on function public.cfx_negocios(text, text), public.cfx_premium_cuenta(uuid, text, int), public.cfx_key_aplicar(uuid, text, text, text) from public, anon;
grant execute on function public.cfx_negocios(text, text), public.cfx_premium_cuenta(uuid, text, int), public.cfx_key_aplicar(uuid, text, text, text) to authenticated;

-- ---------- G38 · 💰 Dinero (CM → Resumen): ingresos del mes por Premium/módulo, pruebas por vencer y morosos con su WhatsApp ----------
-- Moroso = su último pago aprobado (Premium o módulo) dejó de cubrir en los últimos 60 días, no tiene otro pago en revisión,
-- no está exento y hoy no tiene Premium activo. Solo lee: no cambia nada.
create or replace function public.cfx_tel_de(p_cuenta uuid) returns text
language plpgsql stable security definer set search_path = '' as $$
declare t text; x record;
begin
  for x in select c.table_name, c.column_name from information_schema.columns c
    where c.table_schema = 'public' and c.table_name in ('perfiles', 'profiles') and c.column_name in ('telefono', 'whatsapp', 'phone') order by c.table_name, c.column_name loop
    begin
      execute format('select nullif(trim(%I::text), %L) from public.%I where id = $1', x.column_name, '', x.table_name) into t using p_cuenta;
    exception when others then t := null; end;
    if t is not null then return left(t, 30); end if;
  end loop;
  select coalesce(nullif(u.phone, ''), u.raw_user_meta_data ->> 'telefono', u.raw_user_meta_data ->> 'whatsapp') into t from auth.users u where u.id = p_cuenta;
  return left(nullif(trim(t), ''), 30);
end $$;
create or replace function public.cfx_dinero() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare z text := 'America/Santiago'; m0 timestamptz := date_trunc('month', now() at time zone z) at time zone z;
        m1 timestamptz := date_trunc('month', (now() at time zone z) - interval '1 month') at time zone z;
        d timestamptz := public.cfx_ingresos_desde(); cu jsonb := '[]'; activos uuid[] := '{}'; ve jsonb; mo jsonb;
begin
  perform public.admin_check();
  if to_regprocedure('public.cfx_cuentas_app(text,text)') is not null then
    begin
      execute 'select coalesce(public.cfx_cuentas_app(''negocio'', ''''), ''[]''::jsonb) || coalesce(public.cfx_cuentas_app(''cliente'', ''''), ''[]''::jsonb)' into cu;
    exception when others then cu := '[]'; end;
  end if;
  select coalesce(array_agg((e ->> 'id')::uuid), '{}') into activos from jsonb_array_elements(cu) e
    where e ->> 'premium_hasta' is not null and (e ->> 'premium_hasta')::timestamptz > now();
  -- Por vencer en 7 días (sin "para siempre"): prueba = nunca ha pagado; renovación = ya pagó antes.
  select coalesce(jsonb_agg(jsonb_build_object('id', e ->> 'id', 'nombre', coalesce(nullif(e ->> 'nombre', ''), e ->> 'email'), 'email', e ->> 'email', 'rol', e ->> 'rol',
      'hasta', e ->> 'premium_hasta', 'tel', public.cfx_tel_de((e ->> 'id')::uuid),
      'pago', exists (select 1 from public.cfx_pagos p where p.cuenta = (e ->> 'id')::uuid and p.estado = 'aprobado')) order by (e ->> 'premium_hasta')::timestamptz), '[]')
    into ve from (select e from jsonb_array_elements(cu) e where e ->> 'premium_hasta' is not null and e ->> 'premium_hasta' <> 'infinity'
      and (e ->> 'premium_hasta')::timestamptz between now() and now() + interval '7 days' and coalesce((e ->> 'suspendido')::boolean, false) = false limit 100) q;
  select coalesce(jsonb_agg(jsonb_build_object('id', u.cuenta, 'nombre', coalesce(nullif(u.nombre, ''), u.email), 'email', u.email, 'rol', u.rol, 'producto', u.prod,
      'vencio', u.fin, 'monto', u.monto, 'periodo', u.periodo, 'tel', public.cfx_tel_de(u.cuenta)) order by u.fin desc), '[]') into mo
  from (select distinct on (p.cuenta, coalesce(p.producto, '')) p.cuenta, p.nombre, p.email, p.rol, p.producto as prod, p.monto, p.periodo,
          coalesce(p.resuelto, p.creado) + make_interval(days => coalesce(p.dias, 0)) as fin
        from public.cfx_pagos p where p.estado = 'aprobado' and coalesce(p.dias, 0) > 0 and not coalesce(p.regalo, false) and p.key_regalo is null
        order by p.cuenta, coalesce(p.producto, ''), coalesce(p.resuelto, p.creado) + make_interval(days => coalesce(p.dias, 0)) desc) u
  where u.fin between now() - interval '60 days' and now()
    and not (u.prod is null and u.cuenta = any (activos))
    and not exists (select 1 from public.cfx_pagos g where g.cuenta = u.cuenta and g.estado = 'pendiente')
    and not exists (select 1 from public.cfx_exentos x where x.cuenta = u.cuenta);
  return jsonb_build_object('desde', nullif(d, '-infinity'::timestamptz),
    'mes', (select jsonb_build_object('monto', coalesce(sum(monto), 0), 'n', count(*)) from public.cfx_pagos where estado = 'aprobado' and creado >= greatest(m0, d)),
    'anterior', (select jsonb_build_object('monto', coalesce(sum(monto), 0), 'n', count(*)) from public.cfx_pagos where estado = 'aprobado' and creado >= greatest(m1, d) and creado < m0),
    'por', (select coalesce(jsonb_agg(jsonb_build_object('producto', k, 'monto', s, 'n', n) order by s desc), '[]') from (
      select coalesce(producto, 'premium') k, sum(monto) s, count(*) n from public.cfx_pagos where estado = 'aprobado' and creado >= greatest(m0, d) group by 1) q),
    'medios', (select coalesce(jsonb_object_agg(medio, s), '{}') from (select medio, sum(monto) s from public.cfx_pagos where estado = 'aprobado' and creado >= greatest(m0, d) group by 1) q),
    'pendientes', (select count(*) from public.cfx_pagos where estado = 'pendiente' and medio not in ('mp', 'flow')),
    'premium', coalesce(cardinality(activos), 0), 'vencen', ve, 'morosos', mo);
end $$;
revoke all on function public.cfx_tel_de(uuid) from public, anon, authenticated;
revoke all on function public.cfx_dinero() from public, anon;
grant execute on function public.cfx_dinero() to authenticated;
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

-- ---------- 4) G55 🐞🎁 Reporte de fallas con premio ----------
-- Cualquiera con cuenta (Más → Cuenta y ayuda → 🐞 Reportar una falla) cuenta qué pasó, con foto opcional; la app adjunta sola
-- versión, pantalla, celular y sus últimos errores. Le llega al Centro de Mando (aviso + push) y se ve en CM → Mensajes → 🐞 Fallas.
-- "🎁 Es real" suma 15 días de Premium al negocio (clientes y equipo: solo las gracias, no pagan), una vez por reporte.
create table if not exists public.cfx_fallas (
  id        bigserial primary key,
  cuenta    uuid not null,
  email     text not null default '',
  nombre    text not null default '',
  rol       text not null default '',
  texto     text not null check (length(texto) between 5 and 1500),
  foto      text check (foto is null or (foto ~ '^data:image/(webp|jpeg|png);base64,' and length(foto) <= 400000)),
  datos     jsonb not null default '{}',
  estado    text not null default 'nuevo' check (estado in ('nuevo', 'revisando', 'real', 'no')),
  respuesta text not null default '',
  dias      int not null default 0,
  creado    timestamptz not null default now(),
  resuelto  timestamptz
);
create index if not exists cfx_fallas_cuenta_idx on public.cfx_fallas (cuenta, creado);
create index if not exists cfx_fallas_estado_idx on public.cfx_fallas (estado, id);
alter table public.cfx_fallas enable row level security;
revoke all on public.cfx_fallas from anon, authenticated;

create or replace function public.cfx_falla_enviar(p_texto text, p_foto text default null, p_datos jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); u uuid := (y ->> 'id')::uuid; t text := trim(coalesce(p_texto, '')); f text := nullif(trim(coalesce(p_foto, '')), ''); d jsonb := coalesce(p_datos, '{}'); i bigint;
begin
  if u is null then raise exception 'Inicia sesión'; end if;
  if length(t) < 5 then raise exception 'Cuéntanos qué pasó (mínimo 5 letras)'; end if;
  if length(t) > 1500 then raise exception 'Máximo 1500 letras'; end if;
  if f is not null and (f !~ '^data:image/(webp|jpeg|png);base64,' or length(f) > 400000) then raise exception 'La foto no sirve: usa una captura o foto JPG/PNG'; end if;
  if jsonb_typeof(d) <> 'object' or length(d::text) > 8000 then d := '{}'; end if;
  if exists (select 1 from public.cfx_fallas where cuenta = u and creado > now() - interval '2 minutes') then raise exception 'Espera 2 minutos antes de enviar otro reporte'; end if;
  if (select count(*) from public.cfx_fallas where cuenta = u and creado > now() - interval '1 day') >= 3 then raise exception 'Ya enviaste 3 reportes hoy. Mañana puedes enviar más 🙏'; end if;
  if (select count(*) from public.cfx_fallas where estado in ('nuevo', 'revisando')) >= 500 then raise exception 'Recibimos muchos reportes. Prueba de nuevo mañana 🙏'; end if;
  delete from public.cfx_fallas where estado in ('real', 'no') and resuelto < now() - interval '180 days';
  insert into public.cfx_fallas (cuenta, email, nombre, rol, texto, foto, datos)
  values (u, coalesce(y ->> 'email', ''), left(coalesce(y ->> 'nombre', ''), 80), coalesce(y ->> 'rol', ''), t, f, d) returning id into i;
  perform public.cfx_al_cm('🐞 Falla: ' || coalesce(nullif(y ->> 'nombre', ''), y ->> 'email', 'reporte'), left(t, 200), 'falla');
  return jsonb_build_object('id', i);
end $$;

-- Mis últimos reportes (para que la persona vea en qué van).
-- premio: si a esta cuenta le tocan los 15 días (solo negocios: clientes y equipo no pagan).
create or replace function public.cfx_fallas_mias() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('premio', coalesce(public.cfx_yo() ->> 'rol', '') = 'negocio', 'lista',
    (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'texto', left(texto, 80), 'estado', estado, 'dias', dias, 'creado', creado) order by id desc), '[]')
     from (select * from public.cfx_fallas where cuenta = auth.uid() order by id desc limit 5) x))
$$;

-- Administrador: lista (sin la foto), detalle (con la foto; lo marca "revisando") y respuesta.
create or replace function public.cfx_fallas_lista(p_estado text default 'abiertos') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'cuenta', f.cuenta, 'email', f.email, 'nombre', f.nombre, 'rol', f.rol, 'texto', f.texto,
      'con_foto', f.foto is not null, 'datos', f.datos, 'estado', f.estado, 'respuesta', f.respuesta, 'dias', f.dias, 'creado', f.creado, 'resuelto', f.resuelto,
      'premiados', (select count(*) from public.cfx_fallas g where g.cuenta = f.cuenta and g.estado = 'real')) order by f.id desc), '[]')
    from (select * from public.cfx_fallas where case coalesce(p_estado, 'abiertos') when 'abiertos' then estado in ('nuevo', 'revisando') when 'todos' then true else estado = p_estado end
          order by id desc limit 200) f);
end $$;

create or replace function public.cfx_falla_ver(p_id bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare f public.cfx_fallas;
begin
  perform public.admin_check();
  update public.cfx_fallas set estado = 'revisando' where id = p_id and estado = 'nuevo';
  select * into f from public.cfx_fallas where id = p_id;
  if f.id is null then raise exception 'Reporte no encontrado'; end if;
  return jsonb_build_object('id', f.id, 'estado', f.estado, 'foto', f.foto);
end $$;

create or replace function public.cfx_falla_resolver(p_id bigint, p_real boolean, p_mensaje text default '', p_dias int default 15) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare f public.cfx_fallas; m text := left(trim(coalesce(p_mensaje, '')), 500); n int := 0; h timestamptz;
begin
  perform public.admin_check();
  select * into f from public.cfx_fallas where id = p_id for update;
  if f.id is null then raise exception 'Reporte no encontrado'; end if;
  if f.estado in ('real', 'no') then raise exception 'Este reporte ya se respondió'; end if;
  if p_real then
    if f.rol = 'negocio' then
      n := coalesce(p_dias, 15);
      if n not between 1 and 60 then raise exception 'De 1 a 60 días'; end if;
      h := public.cfx_dar_premium(f.cuenta, f.rol, n);
      if h is null then raise exception 'No se encontró la cuenta (¿la borró?)'; end if;
      perform public.cfx_avisar(f.cuenta, '🎁 Gracias: tu reporte era real', 'Sumamos ' || n || ' días de Premium (hasta el ' || to_char(h at time zone 'America/Santiago', 'DD-MM-YYYY') || '). ' ||
        coalesce(nullif(m, ''), '¡Gracias por ayudarnos a mejorar!'));
    else
      perform public.cfx_avisar(f.cuenta, '🙌 Gracias: tu reporte era real', coalesce(nullif(m, ''), 'Ya lo estamos arreglando. ¡Gracias por ayudarnos a mejorar!'));
    end if;
  else
    perform public.cfx_avisar(f.cuenta, '🐞 Revisamos tu reporte', coalesce(nullif(m, ''),
      'Gracias por avisarnos. Lo revisamos y en ese punto la app funciona bien. Si vuelve a pasar, escríbenos al 💬 Chat con soporte.'));
  end if;
  update public.cfx_fallas set estado = case when p_real then 'real' else 'no' end, respuesta = m, dias = n, resuelto = now() where id = f.id;
  perform public.cfx_anotar('falla', case when p_real then 'real' || case when n > 0 then ' (+' || n || ' días Premium)' else '' end else 'no es falla' end || ' · #' || f.id || ' ' || f.email);
  return jsonb_build_object('estado', case when p_real then 'real' else 'no' end, 'dias', n, 'hasta', h);
end $$;
revoke all on function public.cfx_falla_enviar(text, text, jsonb), public.cfx_fallas_mias(), public.cfx_fallas_lista(text), public.cfx_falla_ver(bigint),
  public.cfx_falla_resolver(bigint, boolean, text, int) from public, anon;
grant execute on function public.cfx_falla_enviar(text, text, jsonb), public.cfx_fallas_mias(), public.cfx_fallas_lista(text), public.cfx_falla_ver(bigint),
  public.cfx_falla_resolver(bigint, boolean, text, int) to authenticated;

-- ---------- PIN de la app (4 a 6 números), guardado en la cuenta. Se pide al abrir la app y tras 5 min sin usarla. ----------
create table if not exists public.cfx_pin (
  usuario    uuid primary key references auth.users (id) on delete cascade,
  hash       text not null,
  fallos     int not null default 0,
  espera     timestamptz,
  actualizado timestamptz not null default now()
);
alter table public.cfx_pin enable row level security;
revoke all on public.cfx_pin from anon, authenticated;

create or replace function public.cfx_pin_estado() returns boolean
language sql stable security definer set search_path = '' as $$ select exists (select 1 from public.cfx_pin where usuario = auth.uid()) $$;

create or replace function public.cfx_pin_guardar(p_pin text) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Inicia sesión'; end if;
  if coalesce(p_pin, '') = '' then delete from public.cfx_pin where usuario = auth.uid(); return false; end if;
  if p_pin !~ '^[0-9]{4,6}$' then raise exception 'El PIN debe tener de 4 a 6 números'; end if;
  insert into public.cfx_pin (usuario, hash) values (auth.uid(), encode(sha256(convert_to(auth.uid()::text || ':' || p_pin, 'UTF8')), 'hex'))
  on conflict (usuario) do update set hash = excluded.hash, fallos = 0, espera = null, actualizado = now();
  return true;
end $$;

create or replace function public.cfx_pin_verificar(p_pin text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r public.cfx_pin;
begin
  select * into r from public.cfx_pin where usuario = auth.uid();
  if not found then return jsonb_build_object('ok', true); end if;
  if r.espera is not null and r.espera > now() then return jsonb_build_object('ok', false, 'espera', ceil(extract(epoch from r.espera - now()))); end if;
  if r.hash = encode(sha256(convert_to(auth.uid()::text || ':' || coalesce(p_pin, ''), 'UTF8')), 'hex') then
    update public.cfx_pin set fallos = 0, espera = null where usuario = auth.uid(); return jsonb_build_object('ok', true);
  end if;
  update public.cfx_pin set fallos = case when r.fallos + 1 >= 5 then 0 else r.fallos + 1 end,
    espera = case when r.fallos + 1 >= 5 then now() + interval '5 minutes' else null end where usuario = auth.uid();
  return jsonb_build_object('ok', false, 'quedan', greatest(0, 4 - r.fallos), 'espera', case when r.fallos + 1 >= 5 then 300 else 0 end);
end $$;
revoke all on function public.cfx_pin_estado(), public.cfx_pin_guardar(text), public.cfx_pin_verificar(text) from public, anon;
grant execute on function public.cfx_pin_estado(), public.cfx_pin_guardar(text), public.cfx_pin_verificar(text) to authenticated;
-- ---------------------------------------------------------------------
-- CodeFix · Legal (igual en las 7 apps; lo reparte nucleo/sincronizar.py).
--   Términos y Política de privacidad con versión (Ley 19.628 modificada por la Ley 21.719, vigente desde el 1-dic-2026).
--   El texto vive en nucleo/ayuda.js (CFX_LEGAL.version). Aquí solo queda la prueba de quién aceptó qué versión y cuándo.
--   cfx_legal_estado()          → última versión aceptada por la cuenta (0 = ninguna).
--   cfx_legal_aceptar(version)  → guarda la aceptación (una fila por versión, nunca se pisa).
--   cfx_legal_resumen()         → admin: cuántas cuentas aceptaron cada versión.
-- ---------------------------------------------------------------------
create table if not exists public.cfx_legal (
  cuenta    uuid not null,
  version   int  not null check (version between 1 and 10000),
  aceptado  timestamptz not null default now(),
  agente    text not null default '',
  primary key (cuenta, version)
);
alter table public.cfx_legal enable row level security;
revoke all on public.cfx_legal from anon, authenticated;

create or replace function public.cfx_legal_estado() returns int
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(max(version), 0) from public.cfx_legal where cuenta = auth.uid()
$$;

create or replace function public.cfx_legal_aceptar(p_version int) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare u uuid := auth.uid();
begin
  if u is null then raise exception 'Inicia sesión para aceptar.'; end if;
  if p_version is null or p_version < 1 or p_version > 10000 then raise exception 'Versión no válida.'; end if;
  insert into public.cfx_legal (cuenta, version, agente)
  values (u, p_version, left(coalesce(current_setting('request.headers', true)::jsonb ->> 'user-agent', ''), 300))
  on conflict (cuenta, version) do nothing;
end $$;

create or replace function public.cfx_legal_resumen() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public.admin_check();
  return coalesce((select jsonb_agg(jsonb_build_object('version', version, 'cuentas', n, 'ultima', u) order by version desc)
    from (select version, count(*) n, max(aceptado) u from public.cfx_legal group by version) x), '[]'::jsonb);
end $$;

revoke all on function public.cfx_legal_estado(), public.cfx_legal_aceptar(int), public.cfx_legal_resumen() from public, anon;
grant execute on function public.cfx_legal_estado(), public.cfx_legal_aceptar(int), public.cfx_legal_resumen() to authenticated;

-- ---------------------------------------------------------------------
-- A2 · Consentimientos aparte de los términos (se dan y se retiran cuando quieras; queda el historial).
--   'ofertas'  = novedades y ofertas de CodeFix (parte en NO: solo con consentimiento expreso).
--   'negocios' = ofertas de los negocios donde eres cliente (parte en SÍ por la relación de cliente; se puede retirar).
--   cfx_consent_estado() · cfx_consent_guardar(tipo, si) · cfx_acepta(cuenta, tipo) (uso interno) · admin cfx_consent_resumen().
-- A3 · Derechos del titular (acceso, rectificación, supresión, oposición, portabilidad y bloqueo) con plazo de 30 días (+30 una vez).
--   cfx_mis_datos() → copia de todo lo de la cuenta (acceso y portabilidad al instante; queda registrado como solicitud respondida).
--   cfx_derecho_pedir(tipo, detalle) · cfx_derechos_mios() · admin cfx_derechos_lista(todas) y cfx_derecho_responder(id, accion, respuesta).
-- Brechas de seguridad (registro y aviso a la Agencia y a los afectados): admin cfx_brechas_lista(), cfx_brecha_guardar(jsonb),
--   cfx_brecha_marcar(id, 'agencia' | 'cerrar'), cfx_brecha_avisar(id, destino, titulo, cuerpo). Resumen: cfx_privacidad_resumen().
-- ---------------------------------------------------------------------
create table if not exists public.cfx_consent (
  cuenta uuid not null, tipo text not null check (tipo in ('ofertas', 'negocios')), si boolean not null,
  cambiado timestamptz not null default now(), agente text not null default '', primary key (cuenta, tipo));
create table if not exists public.cfx_consent_hist (
  id bigserial primary key, cuenta uuid not null, tipo text not null, si boolean not null, creado timestamptz not null default now(), agente text not null default '');
create table if not exists public.cfx_derechos (
  id bigserial primary key, cuenta uuid not null, email text not null default '',
  tipo text not null check (tipo in ('acceso', 'rectificacion', 'supresion', 'oposicion', 'portabilidad', 'bloqueo')),
  detalle text not null default '', estado text not null default 'pendiente' check (estado in ('pendiente', 'prorrogada', 'respondida', 'rechazada')),
  creado timestamptz not null default now(), vence timestamptz not null default now() + interval '30 days', respuesta text not null default '', respondido timestamptz);
create index if not exists cfx_derechos_cuenta on public.cfx_derechos (cuenta, creado desc);
create table if not exists public.cfx_brechas (
  id bigserial primary key, detectada timestamptz not null default now(), descripcion text not null, datos text not null default '',
  afectados int not null default 0, riesgo text not null default 'medio' check (riesgo in ('bajo', 'medio', 'alto')), medidas text not null default '',
  agencia timestamptz, titulares timestamptz, avisados int not null default 0, cerrada timestamptz, creado timestamptz not null default now());
alter table public.cfx_consent enable row level security;
alter table public.cfx_consent_hist enable row level security;
alter table public.cfx_derechos enable row level security;
alter table public.cfx_brechas enable row level security;
revoke all on public.cfx_consent, public.cfx_consent_hist, public.cfx_derechos, public.cfx_brechas from anon, authenticated;

create or replace function public.cfx_agente() returns text language sql stable set search_path = '' as $$
  select left(coalesce(current_setting('request.headers', true)::jsonb ->> 'user-agent', ''), 300) $$;
create or replace function public.cfx_acepta(p_cuenta uuid, p_tipo text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select si from public.cfx_consent where cuenta = p_cuenta and tipo = p_tipo), p_tipo = 'negocios') $$;
create or replace function public.cfx_consent_estado() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('ofertas', public.cfx_acepta(auth.uid(), 'ofertas'), 'negocios', public.cfx_acepta(auth.uid(), 'negocios'),
    'cambiado', coalesce((select jsonb_object_agg(tipo, cambiado) from public.cfx_consent where cuenta = auth.uid()), '{}'::jsonb)) $$;
create or replace function public.cfx_consent_guardar(p_tipo text, p_si boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid();
begin
  if u is null then raise exception 'Inicia sesión.'; end if;
  if p_tipo not in ('ofertas', 'negocios') or p_si is null then raise exception 'Opción no válida.'; end if;
  insert into public.cfx_consent (cuenta, tipo, si, agente) values (u, p_tipo, p_si, public.cfx_agente())
  on conflict (cuenta, tipo) do update set si = excluded.si, cambiado = now(), agente = excluded.agente;
  insert into public.cfx_consent_hist (cuenta, tipo, si, agente) values (u, p_tipo, p_si, public.cfx_agente());
  return public.cfx_consent_estado();
end $$;
create or replace function public.cfx_consent_resumen() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return coalesce((select jsonb_agg(jsonb_build_object('tipo', tipo, 'si', s, 'no', n) order by tipo)
    from (select tipo, count(*) filter (where si) s, count(*) filter (where not si) n from public.cfx_consent group by tipo) x), '[]'::jsonb);
end $$;

-- Copia de los datos de la cuenta: cada tabla con una columna de dueño (cuenta, owner_id, user_id, cliente_id…) = la cuenta.
-- No incluye claves, PIN, tokens ni llaves de API (se quitan esas columnas). Máx. 1000 filas por tabla.
create or replace function public.cfx_mis_datos() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid(); r record; filas jsonb; out jsonb := '{}'::jsonb; quitar text[];
begin
  if u is null then raise exception 'Inicia sesión.'; end if;
  for r in
    select c.table_schema s, c.table_name t, c.column_name col
    from information_schema.columns c join information_schema.tables tb on tb.table_schema = c.table_schema and tb.table_name = c.table_name and tb.table_type = 'BASE TABLE'
    where c.table_schema in ('public', 'privado') and c.data_type = 'uuid'
      and (c.column_name in ('cuenta', 'owner_id', 'user_id', 'usuario_id', 'cliente_id', 'target_id', 'autor_id', 'creado_por', 'created_by')
        or (c.column_name = 'id' and c.table_name in ('profiles', 'perfiles', 'usuarios', 'cuentas')))
      and c.table_name not in ('cfx_pin', 'cfx_keys', 'boleta_cuentas', 'push_subscriptions', 'app_secrets', 'cfx_verificaciones')
      and c.table_name !~ '(secret|clave|token)'
    order by 1, 2, 3
  loop
    select coalesce(array_agg(column_name::text), '{}') into quitar from information_schema.columns
      where table_schema = r.s and table_name = r.t and column_name ~* '(hash|^pin|pass|token|apikey|api_key|secret|clave|endpoint|^p256dh|^auth$)';
    execute format('select coalesce(jsonb_agg(to_jsonb(x) - $2), ''[]''::jsonb) from (select * from %I.%I where %I = $1 limit 1000) x', r.s, r.t, r.col) into filas using u, quitar;
    if jsonb_array_length(filas) > 0 then
      out := jsonb_set(out, array[r.s || '.' || r.t], coalesce(out -> (r.s || '.' || r.t), '[]'::jsonb) || filas);
    end if;
  end loop;
  insert into public.cfx_derechos (cuenta, email, tipo, detalle, estado, respuesta, respondido)
  values (u, coalesce((select email from auth.users where id = u), ''), 'portabilidad', 'Descarga desde la app', 'respondida', 'Copia entregada al instante (archivo JSON).', now());
  return jsonb_build_object('generado', now(), 'cuenta', jsonb_build_object('id', u, 'email', (select email from auth.users where id = u)),
    'consentimientos', public.cfx_consent_estado(), 'terminos_aceptados', (select coalesce(jsonb_agg(jsonb_build_object('version', version, 'aceptado', aceptado)), '[]'::jsonb) from public.cfx_legal where cuenta = u),
    'datos', out);
end $$;

create or replace function public.cfx_derecho_pedir(p_tipo text, p_detalle text default '') returns bigint
language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid(); e text; i bigint; nom text;
begin
  if u is null then raise exception 'Inicia sesión.'; end if;
  if p_tipo not in ('acceso', 'rectificacion', 'supresion', 'oposicion', 'portabilidad', 'bloqueo') then raise exception 'Tipo de solicitud no válido.'; end if;
  if p_tipo in ('rectificacion', 'oposicion') and length(trim(coalesce(p_detalle, ''))) < 3 then raise exception 'Cuéntanos qué dato o qué uso (en pocas palabras).'; end if;
  if (select count(*) from public.cfx_derechos where cuenta = u and estado in ('pendiente', 'prorrogada')) >= 5 then raise exception 'Ya tienes 5 solicitudes en curso: espera la respuesta.'; end if;
  select email into e from auth.users where id = u;
  insert into public.cfx_derechos (cuenta, email, tipo, detalle) values (u, coalesce(e, ''), p_tipo, left(trim(coalesce(p_detalle, '')), 600)) returning id into i;
  nom := case p_tipo when 'acceso' then 'acceso' when 'rectificacion' then 'rectificación' when 'supresion' then 'supresión (borrar)' when 'oposicion' then 'oposición'
    when 'portabilidad' then 'portabilidad' else 'bloqueo' end;
  perform public.cfx_anotar('derecho', 'Solicitud de ' || nom || ' #' || i || ' de ' || coalesce(e, u::text));
  begin perform public.cfx_avisar_admin('🔒 Solicitud de datos: ' || nom, coalesce(e, '') || ' · responder antes del ' || to_char(now() + interval '30 days', 'DD-MM-YYYY')); exception when others then null; end;
  return i;
end $$;
create or replace function public.cfx_derechos_mios() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'tipo', tipo, 'detalle', detalle, 'estado', estado, 'creado', creado, 'vence', vence, 'respuesta', respuesta, 'respondido', respondido) order by creado desc), '[]'::jsonb)
  from (select * from public.cfx_derechos where cuenta = auth.uid() order by creado desc limit 50) x $$;
create or replace function public.cfx_derechos_lista(p_todas boolean default false) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'cuenta', cuenta, 'email', email, 'tipo', tipo, 'detalle', detalle, 'estado', estado, 'creado', creado, 'vence', vence,
      'dias', ceil(extract(epoch from vence - now()) / 86400)::int, 'respuesta', respuesta, 'respondido', respondido) order by (estado in ('pendiente', 'prorrogada')) desc, vence)
    from (select * from public.cfx_derechos where p_todas or estado in ('pendiente', 'prorrogada') order by creado desc limit 300) x), '[]'::jsonb);
end $$;
create or replace function public.cfx_derecho_responder(p_id bigint, p_accion text, p_respuesta text) returns void
language plpgsql security definer set search_path = '' as $$
declare d public.cfx_derechos; t text := left(trim(coalesce(p_respuesta, '')), 800);
begin
  perform public.admin_check();
  select * into d from public.cfx_derechos where id = p_id for update;
  if d.id is null then raise exception 'No existe esa solicitud.'; end if;
  if d.estado not in ('pendiente', 'prorrogada') then raise exception 'Esa solicitud ya se respondió.'; end if;
  if length(t) < 3 then raise exception 'Escribe la respuesta (o el motivo).'; end if;
  if p_accion = 'prorrogar' then
    if d.estado = 'prorrogada' then raise exception 'Solo se puede prorrogar una vez.'; end if;
    update public.cfx_derechos set estado = 'prorrogada', vence = vence + interval '30 days', respuesta = t where id = p_id;
    perform public.cfx_avisar(d.cuenta, '🔒 Tu solicitud de datos tomará más tiempo', left('Respondemos antes del ' || to_char(d.vence + interval '30 days', 'DD-MM-YYYY') || '. ' || t, 240));
  elsif p_accion in ('responder', 'rechazar') then
    update public.cfx_derechos set estado = case when p_accion = 'responder' then 'respondida' else 'rechazada' end, respuesta = t, respondido = now() where id = p_id;
    perform public.cfx_avisar(d.cuenta, case when p_accion = 'responder' then '🔒 Respondimos tu solicitud de datos' else '🔒 Tu solicitud de datos no se pudo acoger' end, left(t, 240));
  else raise exception 'Acción no válida.'; end if;
  perform public.cfx_anotar('derecho', p_accion || ' #' || p_id || ' (' || d.tipo || ', ' || d.email || ')');
end $$;

create or replace function public.cfx_brechas_lista() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return coalesce((select jsonb_agg(to_jsonb(b) order by b.detectada desc) from public.cfx_brechas b), '[]'::jsonb);
end $$;
create or replace function public.cfx_brecha_guardar(p jsonb) returns bigint
language plpgsql security definer set search_path = '' as $$
declare i bigint := nullif(p ->> 'id', '')::bigint; d text := left(trim(coalesce(p ->> 'descripcion', '')), 1000);
begin
  perform public.admin_check();
  if length(d) < 5 then raise exception 'Describe qué pasó.'; end if;
  if coalesce(p ->> 'riesgo', 'medio') not in ('bajo', 'medio', 'alto') then raise exception 'Riesgo no válido.'; end if;
  if i is null then
    insert into public.cfx_brechas (detectada, descripcion, datos, afectados, riesgo, medidas)
    values (coalesce(nullif(p ->> 'detectada', '')::timestamptz, now()), d, left(coalesce(p ->> 'datos', ''), 500), greatest(coalesce(nullif(p ->> 'afectados', '')::int, 0), 0),
      coalesce(p ->> 'riesgo', 'medio'), left(coalesce(p ->> 'medidas', ''), 1000)) returning id into i;
    perform public.cfx_anotar('brecha', 'Nueva #' || i || ' (' || coalesce(p ->> 'riesgo', 'medio') || '): ' || d);
  else
    update public.cfx_brechas set descripcion = d, datos = left(coalesce(p ->> 'datos', ''), 500), afectados = greatest(coalesce(nullif(p ->> 'afectados', '')::int, 0), 0),
      riesgo = coalesce(p ->> 'riesgo', 'medio'), medidas = left(coalesce(p ->> 'medidas', ''), 1000) where id = i;
    if not found then raise exception 'No existe ese registro.'; end if;
    perform public.cfx_anotar('brecha', 'Editada #' || i);
  end if;
  return i;
end $$;
create or replace function public.cfx_brecha_marcar(p_id bigint, p_que text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_check();
  if p_que = 'agencia' then update public.cfx_brechas set agencia = coalesce(agencia, now()) where id = p_id;
  elsif p_que = 'cerrar' then update public.cfx_brechas set cerrada = coalesce(cerrada, now()) where id = p_id;
  else raise exception 'Acción no válida.'; end if;
  if not found then raise exception 'No existe ese registro.'; end if;
  perform public.cfx_anotar('brecha', p_que || ' #' || p_id);
end $$;
create or replace function public.cfx_brecha_avisar(p_id bigint, p_destino text, p_titulo text, p_cuerpo text) returns int
language plpgsql security definer set search_path = '' as $$
declare u uuid; n int := 0;
begin
  perform public.admin_check();
  if not exists (select 1 from public.cfx_brechas where id = p_id) then raise exception 'No existe ese registro.'; end if;
  if trim(coalesce(p_titulo, '')) = '' or trim(coalesce(p_cuerpo, '')) = '' then raise exception 'Escribe el título y el mensaje.'; end if;
  if p_destino not in ('todos', 'negocios', 'clientes', 'premium', 'gratis') then raise exception 'Destino no válido'; end if;
  for u in select * from public.cfx_destinatarios(p_destino) loop
    perform public.cfx_avisar(u, left(p_titulo, 80), left(p_cuerpo, 240)); n := n + 1;
  end loop;
  update public.cfx_brechas set titulares = now(), avisados = avisados + n where id = p_id;
  perform public.cfx_anotar('brecha', 'Aviso a ' || p_destino || ' (' || n || ') #' || p_id);
  return n;
end $$;
create or replace function public.cfx_privacidad_resumen() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return jsonb_build_object('pendientes', (select count(*) from public.cfx_derechos where estado in ('pendiente', 'prorrogada')),
    'vencen', (select count(*) from public.cfx_derechos where estado in ('pendiente', 'prorrogada') and vence < now() + interval '5 days'),
    'brechas', (select count(*) from public.cfx_brechas where cerrada is null), 'consent', public.cfx_consent_resumen(), 'legal', public.cfx_legal_resumen());
end $$;

revoke all on function public.cfx_agente(), public.cfx_acepta(uuid, text) from public, anon, authenticated;
revoke all on function public.cfx_consent_estado(), public.cfx_consent_guardar(text, boolean), public.cfx_consent_resumen(), public.cfx_mis_datos(),
  public.cfx_derecho_pedir(text, text), public.cfx_derechos_mios(), public.cfx_derechos_lista(boolean), public.cfx_derecho_responder(bigint, text, text),
  public.cfx_brechas_lista(), public.cfx_brecha_guardar(jsonb), public.cfx_brecha_marcar(bigint, text), public.cfx_brecha_avisar(bigint, text, text, text), public.cfx_privacidad_resumen() from public, anon;
grant execute on function public.cfx_consent_estado(), public.cfx_consent_guardar(text, boolean), public.cfx_consent_resumen(), public.cfx_mis_datos(),
  public.cfx_derecho_pedir(text, text), public.cfx_derechos_mios(), public.cfx_derechos_lista(boolean), public.cfx_derecho_responder(bigint, text, text),
  public.cfx_brechas_lista(), public.cfx_brecha_guardar(jsonb), public.cfx_brecha_marcar(bigint, text), public.cfx_brecha_avisar(bigint, text, text, text), public.cfx_privacidad_resumen() to authenticated;
-- ---------------------------------------------------------------------
-- CodeFix · Referidos (igual en las 7 apps; lo reparte nucleo/sincronizar.py). Se administra desde CM → Control → Referidos.
--   Cada usuario (negocio o cliente, nunca el admin) tiene su código. Quien se registra con él queda asociado a esa cuenta.
--   El admin ve quién invitó a quién, da días de Premium o manda un sticker de ánimo. Premio automático (opcional):
--   cuando el invitado paga su primer Premium, quien lo invitó recibe N días (cfx_config 'referidos' → dias_auto; 0 = apagado).
--   Usa lo que cada app define para los pagos: cfx_yo(), cfx_dar_premium(uuid, text, int) y cfx_avisar(uuid, text, text).
-- ---------------------------------------------------------------------
create table if not exists public.cfx_ref_codigos (cuenta uuid primary key, codigo text not null unique check (codigo ~ '^[A-Z0-9]{4,12}$'), creado timestamptz not null default now());
create table if not exists public.cfx_referidos (
  invitado uuid primary key, invito uuid not null, codigo text not null, email text not null default '', nombre text not null default '',
  creado timestamptz not null default now(), premiado boolean not null default false, dias_dados int not null default 0, stickers int not null default 0);
create index if not exists cfx_referidos_invito_idx on public.cfx_referidos (invito);
alter table public.cfx_ref_codigos enable row level security;
alter table public.cfx_referidos enable row level security;
revoke all on public.cfx_ref_codigos, public.cfx_referidos from anon, authenticated;
insert into public.cfx_config (clave, valor) values ('referidos', '{"dias_auto": 0}') on conflict (clave) do nothing;

-- Mi código para invitar (y cuántos se registraron con él). El admin no tiene.
create or replace function public.cfx_ref_mio() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); c text; i int := 0;
begin
  if y is null or y ->> 'rol' = 'admin' then return null; end if;
  select codigo into c from public.cfx_ref_codigos where cuenta = (y ->> 'id')::uuid;
  while c is null and i < 20 loop
    c := upper(left(regexp_replace(translate(coalesce(nullif(y ->> 'nombre', ''), split_part(y ->> 'email', '@', 1)), 'áéíóúñÁÉÍÓÚÑ', 'aeiounAEIOUN'), '[^A-Za-z]', '', 'g'), 6));
    c := (case when length(c) < 2 then 'CF' else c end) || lpad((floor(random() * 10000))::int::text, 4, '0'); i := i + 1;
    begin insert into public.cfx_ref_codigos (cuenta, codigo) values ((y ->> 'id')::uuid, c); exception when unique_violation then c := null; end;
  end loop;
  return jsonb_build_object('codigo', c, 'invitados', (select count(*) from public.cfx_referidos where invito = (y ->> 'id')::uuid),
    'pagaron', (select count(*) from public.cfx_referidos r where r.invito = (y ->> 'id')::uuid and r.premiado));
end $$;
-- La cuenta nueva que llegó con un código queda asociada (una sola vez, solo en sus primeros 3 días, nunca consigo misma).
create or replace function public.cfx_ref_registrar(p_codigo text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare y jsonb := public.cfx_yo(); o uuid; quien text;
begin
  if y is null or y ->> 'rol' = 'admin' then return false; end if;
  if (select created_at from auth.users where id = (y ->> 'id')::uuid) < now() - interval '3 days' then return false; end if;
  select cuenta into o from public.cfx_ref_codigos where codigo = upper(trim(p_codigo));
  if o is null or o = (y ->> 'id')::uuid then return false; end if;
  insert into public.cfx_referidos (invitado, invito, codigo, email, nombre) values ((y ->> 'id')::uuid, o, upper(trim(p_codigo)), coalesce(y ->> 'email', ''), coalesce(y ->> 'nombre', ''))
    on conflict (invitado) do nothing;
  if not found then return false; end if;
  quien := coalesce(nullif(y ->> 'nombre', ''), split_part(y ->> 'email', '@', 1));
  perform public.cfx_avisar(o, '🎉 ' || quien || ' se registró con tu código', 'Gracias por recomendarnos. ¡Sigue invitando!');
  return true;
end $$;
-- Panel: quién invitó a quién (con correo de ambos), si el invitado ya pagó y lo que se le ha dado a quien invitó.
create or replace function public.cfx_ref_lista() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return jsonb_build_object('config', (select valor from public.cfx_config where clave = 'referidos'), 'filas', coalesce((select jsonb_agg(x order by x.creado desc) from (
    select r.invitado, r.email, r.nombre, r.creado, r.codigo, r.invito, u.email invito_email, r.premiado, r.dias_dados, r.stickers,
      exists (select 1 from public.cfx_pagos g where g.cuenta = r.invitado and g.estado = 'aprobado') pago
    from public.cfx_referidos r left join auth.users u on u.id = r.invito limit 1000) x), '[]'));
end $$;
-- Dar días de Premium y/o mandar un sticker (mensaje de ánimo) a quien invita.
create or replace function public.cfx_ref_premiar(p_cuenta uuid, p_dias int default 0, p_mensaje text default '') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare hasta timestamptz; d int := greatest(0, least(coalesce(p_dias, 0), 365)); n int;
begin
  perform public.admin_check();
  select count(*) into n from public.cfx_referidos where invito = p_cuenta;
  if n = 0 then raise exception 'Esa cuenta no ha invitado a nadie'; end if;
  if d > 0 then
    hasta := public.cfx_dar_premium(p_cuenta, 'otro', d);
    update public.cfx_referidos set dias_dados = dias_dados + d where invitado = (select invitado from public.cfx_referidos where invito = p_cuenta order by creado desc limit 1);
  end if;
  if coalesce(trim(p_mensaje), '') <> '' or d > 0 then
    perform public.cfx_avisar(p_cuenta, left(coalesce(nullif(trim(p_mensaje), ''), '🏆 ¡Gracias por invitar!'), 90),
      case when d > 0 then '🎁 Te regalamos ' || d || ' días de Premium por recomendarnos (' || n || ' invitado' || case when n > 1 then 's' else '' end || ').' else 'Vas en ' || n || ' invitado' || case when n > 1 then 's' else '' end || '. ¡Sigue así!' end);
    update public.cfx_referidos set stickers = stickers + 1 where invitado = (select invitado from public.cfx_referidos where invito = p_cuenta order by creado desc limit 1);
  end if;
  perform public.cfx_anotar('referido', 'premio a ' || coalesce((select email from auth.users where id = p_cuenta), p_cuenta::text) || ': ' || d || ' días');
  return jsonb_build_object('dias', d, 'hasta', hasta);
end $$;
create or replace function public.cfx_ref_config_guardar(p_dias_auto int) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_check();
  insert into public.cfx_config (clave, valor) values ('referidos', jsonb_build_object('dias_auto', greatest(0, least(coalesce(p_dias_auto, 0), 365))))
    on conflict (clave) do update set valor = excluded.valor;
  return (select valor from public.cfx_config where clave = 'referidos');
end $$;
-- Premio automático: al aprobarse el primer pago del invitado, quien lo invitó recibe dias_auto días (una sola vez por invitado).
create or replace function public.cfx_ref_al_pagar() returns trigger
language plpgsql security definer set search_path = '' as $$
declare r public.cfx_referidos; d int := coalesce(((select valor from public.cfx_config where clave = 'referidos') ->> 'dias_auto')::int, 0);
begin
  if new.estado <> 'aprobado' or old.estado = 'aprobado' then return new; end if;
  select * into r from public.cfx_referidos where invitado = new.cuenta and not premiado for update;
  if r.invitado is null then return new; end if;
  update public.cfx_referidos set premiado = true, dias_dados = dias_dados + case when d > 0 then d else 0 end where invitado = r.invitado;
  if d > 0 then
    perform public.cfx_dar_premium(r.invito, 'otro', d);
    perform public.cfx_avisar(r.invito, '🎁 ¡Ganaste ' || d || ' días de Premium!', coalesce(nullif(r.nombre, ''), split_part(r.email, '@', 1)) || ' pagó su Premium gracias a tu invitación.');
  end if;
  return new;
end $$;
drop trigger if exists cfx_ref_al_pagar on public.cfx_pagos;
create trigger cfx_ref_al_pagar after update of estado on public.cfx_pagos for each row execute function public.cfx_ref_al_pagar();
revoke all on function public.cfx_ref_al_pagar() from public, anon, authenticated;
revoke all on function public.cfx_ref_mio(), public.cfx_ref_registrar(text), public.cfx_ref_lista(), public.cfx_ref_premiar(uuid, int, text), public.cfx_ref_config_guardar(int) from public, anon;
grant execute on function public.cfx_ref_mio(), public.cfx_ref_registrar(text), public.cfx_ref_lista(), public.cfx_ref_premiar(uuid, int, text), public.cfx_ref_config_guardar(int) to authenticated;

-- ---------------------------------------------------------------------
-- CodeFix · Socios comunes (lo reparte nucleo/sincronizar.py). Los usan Billetera, Órbita y Estaciona (las otras apps tienen
-- sus propios socios). El socio entra con su correo y administra igual que el admin (cada app lo reconoce en su función de
-- administrador), pero solo el administrador dueño agrega o quita socios (CM → Control → 🤝 Socios). Lo que hace queda en el registro.
-- ---------------------------------------------------------------------
create table if not exists public.cfx_socios (email text primary key check (email = lower(email) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  nombre text not null default '' check (length(nombre) <= 60), creado timestamptz not null default now());
alter table public.cfx_socios enable row level security;
revoke all on public.cfx_socios from anon, authenticated;
create or replace function public.cfx_es_socio() returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (select 1 from public.cfx_socios s join auth.users u on lower(u.email) = s.email where u.id = auth.uid())
$$;
create or replace function public.cfx_socios_lista() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return coalesce((select jsonb_agg(jsonb_build_object('email', s.email, 'nombre', s.nombre, 'creado', s.creado, 'tiene_cuenta', exists (select 1 from auth.users u where lower(u.email) = s.email)) order by s.creado) from public.cfx_socios s), '[]');
end $$;
create or replace function public.cfx_socio_guardar(p_email text, p_nombre text default '', p_si boolean default true) returns void
language plpgsql security definer set search_path = '' as $$
declare e text := lower(trim(p_email));
begin
  perform public.admin_check();
  if public.cfx_es_socio() then raise exception 'Solo el administrador agrega o quita socios'; end if;
  if coalesce(p_si, true) then
    insert into public.cfx_socios (email, nombre) values (e, left(coalesce(trim(p_nombre), ''), 60)) on conflict (email) do update set nombre = excluded.nombre;
    perform public.cfx_anotar('socio', 'agregó a ' || e);
  else
    delete from public.cfx_socios where email = e;
    perform public.cfx_anotar('socio', 'quitó a ' || e);
  end if;
end $$;
revoke all on function public.cfx_es_socio(), public.cfx_socios_lista(), public.cfx_socio_guardar(text, text, boolean) from public, anon;
grant execute on function public.cfx_es_socio(), public.cfx_socios_lista(), public.cfx_socio_guardar(text, text, boolean) to authenticated;

-- ---------------------------------------------------------------------
-- CodeFix · Inventario (igual en las 6 apps; lo usa el Centro de Mando → Apps → Respaldo y limpieza).
--   Muestra las tablas que esta versión ya NO usa (restos de versiones antiguas) con cuántas filas tienen.
--   Nada se borra solo: las vacías se borran con un toque; las que tienen datos piden descargar el respaldo y escribir "sí".
--   cfx_tablas() = las tablas que crea este archivo (la revisa pruebas/inventario.py --verificar).
-- ---------------------------------------------------------------------
create or replace function public.cfx_tablas() returns text[] language sql immutable as $$ select array['public.auditoria', 'public.bicis_usadas', 'public.bloqueos', 'public.caja', 'public.calificaciones', 'public.cfx_analisis', 'public.cfx_anuncio_vistos', 'public.cfx_anuncios', 'public.cfx_bloqueos', 'public.cfx_boleta_cuentas', 'public.cfx_boletas', 'public.cfx_brechas', 'public.cfx_calificaciones', 'public.cfx_cargas', 'public.cfx_carritos', 'public.cfx_chat', 'public.cfx_clave_temporal', 'public.cfx_config', 'public.cfx_consent', 'public.cfx_consent_hist', 'public.cfx_cupones', 'public.cfx_derechos', 'public.cfx_descuentos', 'public.cfx_errores', 'public.cfx_exentos', 'public.cfx_fallas', 'public.cfx_flow_negocio', 'public.cfx_keys', 'public.cfx_legal', 'public.cfx_login_fallos', 'public.cfx_login_qr', 'public.cfx_mensajes', 'public.cfx_modulos_negocio', 'public.cfx_modulos_pruebas', 'public.cfx_mp_avisos', 'public.cfx_mp_neg_cobros', 'public.cfx_mp_neg_sub_pagos', 'public.cfx_mp_neg_subs', 'public.cfx_mp_negocio', 'public.cfx_mp_sub_cobros', 'public.cfx_mp_subs', 'public.cfx_pagos', 'public.cfx_pin', 'public.cfx_pruebas_usadas', 'public.cfx_push_entrega', 'public.cfx_ref_codigos', 'public.cfx_referidos', 'public.cfx_registro', 'public.cfx_reportes', 'public.cfx_salud', 'public.cfx_secretos', 'public.cfx_sellos', 'public.cfx_sellos_cfg', 'public.cfx_socios', 'public.cfx_verificaciones', 'public.cfx_versiones', 'public.comprobantes', 'public.config', 'public.fotos_trabajo', 'public.garantias', 'public.invitaciones', 'public.links_pago', 'public.mensajes', 'public.notificaciones', 'public.pagos', 'public.pasaporte_rastros', 'public.pasaportes', 'public.perfiles', 'public.plan_cobros', 'public.plan_socios', 'public.plan_usos', 'public.planes', 'public.planes_mant', 'public.promos', 'public.proveedores', 'public.push_subs', 'public.repuestos', 'public.reservas', 'public.secretos', 'public.servicios', 'public.talleres', 'public.textos'] $$;
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

-- ---------- Salud (G8): errores de la app en los teléfonos, ping anti-pausa y último respaldo ----------
-- Errores: carga.js manda cada error de JavaScript (agrupado por mensaje + lugar). Se guardan hasta 300 distintos y 30 días.
create table if not exists public.cfx_errores (
  id bigint generated always as identity primary key, firma text not null unique, mensaje text not null, donde text not null default '',
  pagina text not null default '', navegador text not null default '', version text not null default '', veces int not null default 1,
  con_cuenta boolean not null default false, creado timestamptz not null default now(), ultimo timestamptz not null default now());
-- Salud: 'ping' (lo toca GitHub Actions para que Supabase no pause la base) y 'respaldo' (lo anota el respaldo diario).
create table if not exists public.cfx_salud (clave text primary key, valor jsonb not null default '{}', cuando timestamptz not null default now());
-- B13 Carga real: cuánto demora en abrir cada página en los teléfonos (carga.js, 1 vez por página y sesión). Por día y página; 30 días.
create table if not exists public.cfx_cargas (dia date not null default current_date, pagina text not null, veces int not null default 0, ms bigint not null default 0,
  lcp bigint not null default 0, con_lcp int not null default 0, lentas int not null default 0, cache int not null default 0, primary key (dia, pagina));
alter table public.cfx_cargas enable row level security;
revoke all on public.cfx_cargas from anon, authenticated;
alter table public.cfx_errores enable row level security;
alter table public.cfx_salud enable row level security;
revoke all on public.cfx_errores, public.cfx_salud from anon, authenticated;

-- Sin cuenta también (el error puede pasar antes de entrar). Sin captcha: no crea cuentas ni avisa a nadie,
-- se agrupa por firma, tiene tope de filas y de veces, y se borra solo a los 30 días.
create or replace function public.cfx_error_anotar(p_mensaje text, p_donde text default '', p_pagina text default '', p_navegador text default '', p_version text default '')
returns void language plpgsql security definer set search_path = '' as $$
declare m text := left(coalesce(p_mensaje, ''), 300); d text := left(coalesce(p_donde, ''), 600); f text;
begin
  if m = '' then return; end if;
  f := md5(m || '|' || split_part(d, E'\n', 1));
  update public.cfx_errores set veces = least(veces + 1, 1000000), ultimo = now(), pagina = left(coalesce(p_pagina, ''), 200),
    navegador = left(coalesce(p_navegador, ''), 120), version = left(coalesce(p_version, ''), 20), con_cuenta = con_cuenta or auth.uid() is not null
    where firma = f and ultimo < now() - interval '2 seconds';
  if found or exists (select 1 from public.cfx_errores where firma = f) then return; end if;
  delete from public.cfx_errores where ultimo < now() - interval '30 days';
  if (select count(*) from public.cfx_errores) >= 300 then return; end if;
  insert into public.cfx_errores (firma, mensaje, donde, pagina, navegador, version, con_cuenta)
    values (f, m, d, left(coalesce(p_pagina, ''), 200), left(coalesce(p_navegador, ''), 120), left(coalesce(p_version, ''), 20), auth.uid() is not null)
    on conflict (firma) do nothing;
end $$;
grant execute on function public.cfx_error_anotar(text, text, text, text, text) to anon, authenticated;

-- B13: sin cuenta también (la vitrina la abren clientes sin cuenta). Valores acotados, máximo 40 páginas por día y 1 fila por día y página.
create or replace function public.cfx_carga_anotar(p_pagina text, p_ms int, p_lcp int default null, p_cache boolean default false)
returns void language plpgsql security definer set search_path = '' as $$
declare pg text := left(regexp_replace(lower(coalesce(p_pagina, '')), '[^a-z0-9/_.-]', '', 'g'), 60); m int := least(greatest(coalesce(p_ms, 0), 0), 60000);
  l int := least(greatest(coalesce(p_lcp, 0), 0), 60000);
begin
  if pg = '' or m = 0 then return; end if;
  if not exists (select 1 from public.cfx_cargas where dia = current_date and pagina = pg) then
    if (select count(*) from public.cfx_cargas where dia = current_date) >= 40 then return; end if;
    delete from public.cfx_cargas where dia < current_date - 30;
  end if;
  insert into public.cfx_cargas as c (dia, pagina, veces, ms, lcp, con_lcp, lentas, cache)
    values (current_date, pg, 1, m, l, (l > 0)::int, (m > 3000)::int, coalesce(p_cache, false)::int)
    on conflict (dia, pagina) do update set veces = c.veces + 1, ms = c.ms + excluded.ms, lcp = c.lcp + excluded.lcp, con_lcp = c.con_lcp + excluded.con_lcp,
      lentas = c.lentas + excluded.lentas, cache = c.cache + excluded.cache
    where c.veces < 100000;
end $$;
revoke all on function public.cfx_carga_anotar(text, int, int, boolean) from public;
grant execute on function public.cfx_carga_anotar(text, int, int, boolean) to anon, authenticated;

-- Marca de salud (solo la base: GitHub Actions la llama con la conexión del respaldo; ping la usa por dentro).
create or replace function public.cfx_salud_marca(p_clave text, p_valor jsonb default '{}') returns void
language sql security definer set search_path = '' as $$
  insert into public.cfx_salud (clave, valor, cuando) values (left(p_clave, 40), coalesce(p_valor, '{}'), now())
  on conflict (clave) do update set valor = excluded.valor, cuando = now()
$$;
revoke all on function public.cfx_salud_marca(text, jsonb) from public, anon, authenticated;

-- Ping anti-pausa: el plan gratis de Supabase pausa la base tras 7 días sin uso. GitHub Actions (SaaS: salud.yml) lo llama cada día.
create or replace function public.cfx_ping() returns text
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce((select cuando from public.cfx_salud where clave = 'ping'), '-infinity') < now() - interval '10 minutes' then
    perform public.cfx_salud_marca('ping', '{}');
  end if;
  return 'ok';
end $$;
grant execute on function public.cfx_ping() to anon, authenticated;

-- Centro de Mando → Control → 🩺 Salud.
create or replace function public.cfx_salud() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return jsonb_build_object(
    'ping', (select cuando from public.cfx_salud where clave = 'ping'),
    'respaldo', (select valor || jsonb_build_object('cuando', cuando) from public.cfx_salud where clave = 'respaldo'),
    'analisis', (select valor || jsonb_build_object('cuando', cuando) from public.cfx_salud where clave = 'analisis'),
    'carga', coalesce((select jsonb_agg(c order by c.veces desc) from (select pagina, sum(veces)::int veces, (sum(ms) / nullif(sum(veces), 0))::int ms,
        (sum(lcp) / nullif(sum(con_lcp), 0))::int lcp, sum(lentas)::int lentas, sum(cache)::int cache
      from public.cfx_cargas where dia > current_date - 7 group by pagina order by sum(veces) desc limit 20) c), '[]'),
    'errores_24h', (select coalesce(sum(veces), 0) from public.cfx_errores where ultimo > now() - interval '24 hours'),
    'errores', coalesce((select jsonb_agg(to_jsonb(e) - 'firma' order by e.ultimo desc) from (select * from public.cfx_errores order by ultimo desc limit 100) e), '[]'));
end $$;
revoke all on function public.cfx_salud() from public, anon;
grant execute on function public.cfx_salud() to authenticated;

create or replace function public.cfx_errores_borrar(p_id bigint default null) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  perform public.admin_check();
  delete from public.cfx_errores where p_id is null or id = p_id;
  get diagnostics n = row_count;
  perform public.cfx_anotar('errores borrados', case when p_id is null then 'todos (' || n || ')' else '#' || p_id end);
  return n;
end $$;
revoke all on function public.cfx_errores_borrar(bigint) from public, anon;
grant execute on function public.cfx_errores_borrar(bigint) to authenticated;

-- ---------- G38 · 🔔 Alertas al celular del admin (vía Centro de Mando): negocio nuevo y errores nuevos ----------
-- Cada 15 minutos mira lo nuevo desde la última vez (la primera vez solo marca, no avisa de lo viejo). Un aviso por tipo y vuelta.
-- Los pagos ya avisan solos (💳 por revisar / ⚡ aprobado). La caída de una app la ve 🩺 salud diaria (GitHub) y el carrusel de servidores.
create or replace function public.cfx_alertas_revisar() returns int
language plpgsql security definer set search_path = '' as $$
declare v jsonb := (select valor from public.cfx_salud where clave = 'alertas'); h timestamptz := now(); desde timestamptz; cu jsonb := '[]';
        n int := 0; k int; t text;
begin
  if v is null or (v ->> 'desde') is null then perform public.cfx_salud_marca('alertas', jsonb_build_object('desde', h)); return 0; end if;
  desde := (v ->> 'desde')::timestamptz;
  if to_regprocedure('public.cfx_cuentas_app(text,text)') is not null then
    begin execute 'select coalesce(public.cfx_cuentas_app(''negocio'', ''''), ''[]''::jsonb)' into cu; exception when others then cu := '[]'; end;
    select count(*), min(coalesce(nullif(e ->> 'nombre', ''), e ->> 'email')) into k, t from jsonb_array_elements(cu) e
      where (e ->> 'creado')::timestamptz > desde and (e ->> 'creado')::timestamptz <= h;
    if k > 0 then perform public.cfx_al_cm('🆕 Negocio nuevo', coalesce(t, '') || case when k > 1 then ' y ' || (k - 1) || ' más' else '' end, 'negocio'); n := n + 1; end if;
  end if;
  select count(*), min(left(mensaje, 120)) into k, t from public.cfx_errores where creado > desde and creado <= h;
  if k > 0 then perform public.cfx_al_cm('🩺 ' || k || case when k = 1 then ' error nuevo' else ' errores nuevos' end, coalesce(t, ''), 'error'); n := n + 1; end if;
  perform public.cfx_salud_marca('alertas', jsonb_build_object('desde', h));
  return n;
end $$;
revoke all on function public.cfx_alertas_revisar() from public, anon, authenticated;
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'cfx-alertas';
  perform cron.schedule('cfx-alertas', '*/15 * * * *', 'select public.cfx_alertas_revisar()');
exception when others then
  raise notice 'Alertas no programadas (%).', sqlerrm;
end $$;
-- ---------- Módulos enchufables (C19): se prenden y apagan desde el Centro de Mando → Mis aplicaciones → 🧩 Módulos ----------
-- Cada app dice qué módulos tiene con el gancho cfx_modulos_app() → text[] (si no lo tiene: ninguno). Por defecto quedan prendidos.
insert into public.cfx_config (clave, valor) values ('modulos', '{}') on conflict (clave) do nothing;

create or replace function public.cfx_modulos_de_app() returns text[]
language plpgsql stable security definer set search_path = '' as $$
declare r text[];
begin
  if to_regprocedure('public.cfx_modulos_app()') is null then return '{}'; end if;
  execute 'select public.cfx_modulos_app()' into r;
  return coalesce(r, '{}');
end $$;

create or replace function public.cfx_modulo(p_clave text) returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  return p_clave = any(public.cfx_modulos_de_app())
    and coalesce(((select valor from public.cfx_config where clave = 'modulos') ->> p_clave)::boolean, true);
end $$;

-- Para la app (esconde lo apagado): {"chat": true, ...}. Un negocio (o su equipo) ve lo que tiene activo (G19: módulos de pago).
create or replace function public.cfx_modulos() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare n uuid := public.cfx_negocio_cuenta(auth.uid());
begin
  if n is not null and coalesce((public.cfx_venta() ->> 'activo')::boolean, false) then return public.cfx_modulos_de(n); end if;
  return coalesce((select jsonb_object_agg(k, public.cfx_modulo(k)) from unnest(public.cfx_modulos_de_app()) k), '{}');
end $$;

-- Para el Centro de Mando: con nombre y para qué sirve.
create or replace function public.cfx_modulos_admin() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return coalesce((select jsonb_agg(jsonb_build_object('clave', k, 'nombre', coalesce(c.nombre, k), 'detalle', coalesce(c.detalle, ''),
      'activo', public.cfx_modulo(k), 'precio', public.cfx_venta_precio(k),
      'negocios', (select count(*) from public.cfx_modulos_negocio m where m.modulo = k and m.hasta > now())) order by o)
    from unnest(public.cfx_modulos_de_app()) with ordinality u(k, o)
    left join public.cfx_modulos_catalogo() c on c.clave = k), '[]');
end $$;

create or replace function public.cfx_modulo_guardar(p_clave text, p_activo boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_check();
  if not coalesce(p_clave = any(public.cfx_modulos_de_app()), false) then raise exception 'Esta app no tiene ese módulo'; end if;
  insert into public.cfx_config (clave, valor) values ('modulos', jsonb_build_object(p_clave, coalesce(p_activo, true)))
  on conflict (clave) do update set valor = public.cfx_config.valor || excluded.valor;
  perform public.cfx_anotar('módulo', p_clave || case when coalesce(p_activo, true) then ' prendido' else ' apagado' end);
  return public.cfx_modulos_admin();
end $$;

revoke all on function public.cfx_modulos_de_app(), public.cfx_modulo(text) from public, anon, authenticated;
revoke all on function public.cfx_modulos(), public.cfx_modulos_admin(), public.cfx_modulo_guardar(text, boolean) from public, anon;
grant execute on function public.cfx_modulos() to anon, authenticated;
grant execute on function public.cfx_modulos_admin(), public.cfx_modulo_guardar(text, boolean) to authenticated;
-- ---------- Módulos de pago por negocio (G19) ----------
-- Cada negocio compra (o prueba 7 días) los módulos que quiere, sea Free o Premium. Se venden sueltos o en packs
-- (Básico, Crecer, Completo). Si "Vender módulos" está apagado en esta app (Centro de Mando → Apps → 🧩), todo sigue como antes:
-- el módulo prendido sirve a todos. Precio 0 = incluido gratis para todos.
-- Gancho opcional de la app: cfx_negocio_cuenta(uuid) → el negocio de esa cuenta (dueño o su equipo); null = no es negocio.
--                            cfx_es_premium(uuid) → si el negocio tiene Premium (descuento en módulos).
create table if not exists public.cfx_modulos_negocio (
  negocio uuid not null,
  modulo  text not null check (modulo ~ '^[a-z_]{2,30}$'),
  hasta   timestamptz not null,
  origen  text not null default 'pago' check (origen in ('prueba', 'pago', 'regalo')),
  avisado timestamptz,
  creado  timestamptz not null default now(),
  primary key (negocio, modulo)
);
create index if not exists cfx_modulos_negocio_hasta_idx on public.cfx_modulos_negocio (hasta);
create table if not exists public.cfx_modulos_pruebas (
  negocio uuid not null,
  item    text not null,
  creado  timestamptz not null default now(),
  primary key (negocio, item)
);
alter table public.cfx_modulos_negocio enable row level security;
alter table public.cfx_modulos_pruebas enable row level security;
revoke all on public.cfx_modulos_negocio, public.cfx_modulos_pruebas from anon, authenticated;

-- Precios en pesos al mes. Anual = 10 meses (2 de regalo). Premium paga 20 % menos en módulos y packs.
insert into public.cfx_config (clave, valor) values ('modulos_venta', jsonb_build_object(
  'activo', false, 'prueba_dias', 7, 'descuento_premium', 20, 'anual_meses', 10, 'precio', 990, 'precios', '{}'::jsonb, 'links', '{}'::jsonb,
  'packs', jsonb_build_object(
    'basico',   jsonb_build_object('nombre', '🌱 Básico',   'detalle', 'Para que vuelvan a comprarte', 'precio', 1990, 'modulos', jsonb_build_array('cupones', 'sellos', 'calificaciones')),
    'crecer',   jsonb_build_object('nombre', '🚀 Crecer',   'detalle', 'Vende más todos los días', 'precio', 2990, 'destacado', true,
                                   'modulos', jsonb_build_array('cupones', 'sellos', 'calificaciones', 'chat', 'carrito', 'redes', 'estadisticas')),
    'completo', jsonb_build_object('nombre', '💎 Completo', 'detalle', 'Todos los módulos, también los nuevos', 'precio', 3990, 'modulos', '*'))))
on conflict (clave) do nothing;

-- Nombre y para qué sirve cada módulo (lo usan el Centro de Mando y la pantalla 🧩 Módulos del negocio).
create or replace function public.cfx_modulos_catalogo() returns table (clave text, nombre text, detalle text)
language sql immutable as $$
  values ('chat', '💬 Chat', 'Conversa con tus clientes dentro de la app, con límites contra el spam.'),
         ('calificaciones', '⭐ Calificaciones', 'Tus clientes te califican y tú a ellos: más confianza para comprar.'),
         ('cupones', '🏷️ Cupones', 'Crea códigos de descuento para tus clientes.'),
         ('sellos', '🎟️ Tarjeta de sellos', 'Cada compra suma un sello; al completar la meta, premio.'),
         ('carrito', '🛒 Recordar carrito', 'Si un cliente deja productos en el carrito, al día siguiente le llega un aviso.'),
         ('analisis', '🔎 Para vender más', 'Cada noche: clientes en riesgo, productos quietos, stock que se acaba y grupos de clientes.'),
         ('estadisticas', '📈 Estadísticas', 'Ventas, productos que más dejan y gráficos en vivo.'),
         ('equipo', '🧑‍🍳 Mi equipo', 'Suma vendedores y bodega con su propia cuenta y permisos.'),
         ('campanas', '📣 Campañas automáticas', 'Mensajes automáticos a tus clientes: ofertas, cumpleaños y los que hace tiempo no vuelven.'),
         ('redes', '📲 Vender en redes', 'Pedir por WhatsApp, catálogo para Google e Instagram.'),
         ('webhooks', '🔗 Avisos a tu sistema', 'Cada pedido llega firmado a tu sistema o planilla (webhooks).'),
         ('medicion', '📊 Medir anuncios', 'Meta Pixel y Google Analytics en tu tienda: mide qué anuncio te trae ventas.'),
         ('dominio', '🌐 Dominio propio', 'Tu tienda en tu dirección (mitienda.cl) en vez del link de Despega Pyme.'),
         ('reservas', '📅 Reservas', 'Agenda en línea para tus clientes.'),
         ('recordatorios', '⏰ Recordatorios', 'Avisos automáticos antes de cada cita o vencimiento.'),
         -- G53: módulos de agenda (Barbería primero; sirven para cualquier app con reservas).
         ('antifalta', '💳 Anti-falta', 'Abono obligatorio y bloqueo automático para los clientes que reservan y no llegan.'),
         ('espera', '⏳ Lista de espera', 'Si no hay horas, el cliente se anota y le avisamos apenas se libere una.'),
         ('resenas', '⭐ Reseñas en Google', 'Al cliente feliz le pedimos su reseña en Google: más gente te encuentra.'),
         ('portafolio', '🖼️ Portafolio', 'Fotos de tus mejores trabajos en tu página de reservas.'),
         ('giftcards', '🎁 Gift cards', 'Vende tarjetas de regalo con código para canjear en tu negocio.'),
         ('membresia', '🔁 Membresía', 'Plan mensual para tus clientes (ej. 4 cortes al mes): plata segura cada mes.'),
         ('productos', '🛍️ Productos y stock', 'Vende productos en la caja y lleva su stock.'),
         ('agenda_redes', '🤖 Reservas por WhatsApp e Instagram', 'Link y respuestas listas para que reserven desde tus redes.'),
         -- G59: módulos de taller (BiciTaller primero; sirven para cualquier app con órdenes de trabajo).
         ('presupuesto', '✅ Presupuesto por link', 'El cliente aprueba o rechaza cada arreglo desde su celular: sin llamadas ni reclamos.'),
         ('aviso_lista', '🔔 Aviso "bici lista"', 'Al dejarla lista, el cliente recibe el aviso por WhatsApp con el total y el link; si no la retira, se lo recordamos.'),
         ('mantencion', '⏰ Recordatorio de mantención', 'Cada X meses le avisamos al cliente que le toca mantención: vuelve solo.'),
         ('stock', '📦 Repuestos y stock', 'Stock de repuestos que baja solo con cada orden y pedido a tu proveedor por WhatsApp con un toque.'),
         ('certificadas', '🏷️ Bicis usadas certificadas', 'Vende bicis usadas con informe de 50 puntos, fotos y garantía: se publican en tu página y te escriben por WhatsApp.'),
         ('tradein', '🔄 Parte de pago', 'Calculadora: cuánto ofrecer por la bici usada del cliente para que se lleve una nueva o un arreglo.'),
         ('pasaporte', '🪪 Pasaporte de la bici', 'Sticker QR para el cuadro: historial de mantenciones, dueño y aviso de robo. Quien la escanea sabe si es robada.'),
         ('domicilio', '🚐 Mecánico a domicilio', 'El cliente reserva con su dirección (+ recargo de visita); armas la ruta del día y le avisas “Voy en camino”.'),
         ('garantias', '🛡️ Garantías', 'Garantía del trabajo, repuestos o bici usada, con vencimiento: el cliente la ve en su link y la usa en 1 toque.'),
         ('plan_mant', '🔁 Plan de mantención', 'Tus clientes pagan al mes y tienen visitas incluidas y descuento: plata segura cada mes y vuelven siempre.'),
         -- G94: módulos de cobranza (Billetera primero).
         ('acuerdo', '📝 Acuerdo de pago firmado', 'Armas un plan de pago y el cliente lo acepta desde su link con su nombre: queda firmado, con fecha y calendario.'),
         ('contador', '🧮 Link para el contador', 'Un link de solo lectura con ventas, gastos y cobros del mes y su planilla: sin mandar pantallazos.'),
         ('escalonado', '📈 Cobranza escalonada', 'El mensaje de cobro sube de tono solo según los días de atraso: amable → neutral → firme, respetando la ley.'),
         ('gastos_fijos', '🔁 Gastos fijos automáticos', 'Arriendo, luz o sueldos se anotan solos cada mes en tu caja, el día que elijas.'),
         -- G94: módulos de estacionamientos (Estaciona primero).
         ('destacar', '⭐ Destacado en el mapa', 'Tus estacionamientos salen primero y resaltados en el mapa y la lista: más reservas.'),
         ('acceso', '🔑 Control de acceso con QR', 'Cada reserva trae su pase QR: lo escaneas al entrar y salir y ves si está vigente y su patente.'),
         ('descuentos', '🏷️ Descuento por estadía larga', 'Premia a quien reserva más tiempo: un % menos desde las horas, días o meses que elijas.'),
         ('ganancias', '📊 Ganancias y ocupación', 'Cuánto ganaste por mes, ocupación de cada lugar, mejores días y planilla para Excel.'),
         -- G96: módulos de tienda (Despega primero).
         ('suscripciones', '🔁 Compras recurrentes', 'Tu cliente recibe su pedido solo cada semana o cada mes (café, alimento, agua…): venta segura sin tener que pedirla.'),
         ('proveedores', '📦 Stock mínimo y proveedores', 'Te avisa cuando un producto baja de su mínimo y arma el pedido a tu proveedor por WhatsApp con un toque.'),
         -- G96 b: 🏬 sucursales (Despega) y 📣 promos en la app de tus clientes (Despega, Barbería, BiciTaller).
         ('sucursales', '🏬 Sucursales y bodegas', 'Stock separado por local o bodega: vendes en la Caja desde cada sucursal y mueves mercadería entre ellas.'),
         ('promos', '📣 Promo destacada', 'Al abrir la app, tus clientes ven tu oferta en una tarjeta con foto y botón (además de tus ofertas de siempre). Ves cuántos la vieron y la tocaron.'),
         -- G101: 🛒 Mercado Libre (Despega).
         ('mercadolibre', '🛒 Mercado Libre', 'Une tus productos con tus publicaciones de Mercado Libre: vendes allá y se descuenta aquí; cambias el stock aquí y se actualiza allá.'),
         -- G102: 🚚 Courier Chilexpress (Despega).
         ('courier', '🚚 Courier Chilexpress', 'Cotiza el envío y saca la etiqueta de Chilexpress desde el pedido: el código de seguimiento le llega solo a tu cliente.'),
         -- G104: más módulos de cobranza (Billetera).
         ('cuentas_pagar', '📤 Cuentas por pagar', 'Lo que debes a tus proveedores con su vencimiento: te avisamos antes y al pagar queda como gasto en tu caja.'),
         ('cierre_caja', '💵 Cierre de caja', 'Al cerrar cuentas el efectivo y ves al tiro si cuadra, sobra o falta. Queda el historial de cada día.'),
         ('aviso_vence', '🔔 Aviso de vencimiento automático', 'El día antes y el día que vence, a tu cliente le llega el aviso en su celular con su saldo y link para pagar. Solo, respetando la ley.'),
         -- G104: más módulos de estacionamientos (Estaciona).
         ('tarifas', '🌙 Tarifa fin de semana y noche', 'Cobra distinto el sábado, domingo y de noche: un % más (o menos) que se calcula solo al reservar.'),
         ('frecuentes', '🔁 Clientes frecuentes', 'Ve quién te arrienda más y prémialo solo: un % menos desde su reserva número N. Vuelven siempre.'),
         ('calendario', '📅 Cerrar fechas', 'Cierra días por vacaciones o uso propio: nadie puede reservar esas fechas y la ficha lo muestra.'),
         ('avisame', '🔔 Lista de espera', 'Si tu lugar está ocupado, la gente se anota y le avisamos apenas lo marques disponible: no pierdes al próximo cliente.')
$$;

create or replace function public.cfx_venta() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce((select valor from public.cfx_config where clave = 'modulos_venta'), '{}'::jsonb)
$$;
-- Precio al mes de un módulo o pack (0 = incluido gratis).
create or replace function public.cfx_venta_precio(p_item text) returns int
language sql stable security definer set search_path = '' as $$
  select coalesce((v #>> array['packs', p_item, 'precio'])::int, (v #>> array['precios', p_item])::int, (v ->> 'precio')::int, 0)
  from (select public.cfx_venta() v) x
$$;
-- ¿Está prendida la venta de módulos en esta app? (si no, todo funciona como antes del G19)
create or replace function public.cfx_venta_on() returns boolean
language sql stable security definer set search_path = '' as $$ select coalesce((public.cfx_venta() ->> 'activo')::boolean, false) $$;
-- ¿Este módulo se vende aparte en esta app? (venta prendida y precio > 0)
create or replace function public.cfx_venta_activa(p_modulo text) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.cfx_venta_on() and p_modulo = any(public.cfx_modulos_de_app()) and public.cfx_venta_precio(p_modulo) > 0
$$;
-- Módulos que trae un pack ('*' = todos los de la app) o el módulo mismo.
create or replace function public.cfx_venta_modulos(p_item text) returns text[]
language plpgsql stable security definer set search_path = '' as $$
declare p jsonb := public.cfx_venta() #> array['packs', p_item];
begin
  if p is null then return case when p_item = any(public.cfx_modulos_de_app()) then array[p_item] else '{}'::text[] end; end if;
  if p ->> 'modulos' = '*' then return public.cfx_modulos_de_app(); end if;
  return array(select x from jsonb_array_elements_text(coalesce(p -> 'modulos', '[]')) x where x = any(public.cfx_modulos_de_app()));
end $$;

-- G74 b · 🎁 Campaña de lanzamiento: {"modulos": [...], "meses": 3, "hasta": "AAAA-MM-DD"} en cfx_venta() -> 'campana'.
-- Activa hasta el día "hasta" incluido (hora de Chile): sin cron, se apaga sola al pasar la fecha.
create or replace function public.cfx_campana() returns jsonb
language sql stable security definer set search_path = '' as $$
  select case when public.cfx_venta_on() and jsonb_typeof(c) = 'object' and (c ->> 'hasta') ~ '^\d{4}-\d{2}-\d{2}$'
    and (c ->> 'hasta')::date >= (now() at time zone 'America/Santiago')::date and coalesce((c ->> 'meses')::int, 0) between 1 and 12
    and jsonb_typeof(c -> 'modulos') = 'array' and jsonb_array_length(c -> 'modulos') > 0 then c end
  from (select public.cfx_venta() -> 'campana' c) x
$$;
create or replace function public.cfx_negocio_cuenta(p_cuenta uuid) returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare n uuid;
begin
  if p_cuenta is null then return null; end if;
  if to_regprocedure('public.cfx_negocio_de_cuenta(uuid)') is not null then execute 'select public.cfx_negocio_de_cuenta($1)' into n using p_cuenta;
  elsif to_regprocedure('public.cfx_analisis_negocio(uuid)') is not null then execute 'select public.cfx_analisis_negocio($1)' into n using p_cuenta;
  else n := p_cuenta; end if;
  return n;
end $$;
-- G95: la cuenta del dueño de un negocio. Gancho opcional de la app: cfx_negocio_dueno_app(uuid) → uuid (Billetera: el negocio no es la cuenta).
create or replace function public.cfx_negocio_dueno(p_negocio uuid) returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare d uuid;
begin
  if p_negocio is null then return null; end if;
  if to_regprocedure('public.cfx_negocio_dueno_app(uuid)') is not null then execute 'select public.cfx_negocio_dueno_app($1)' into d using p_negocio; return d; end if;
  return p_negocio;
end $$;
create or replace function public.cfx_negocio_premium(p_negocio uuid) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare r boolean;
begin
  if p_negocio is null or to_regprocedure('public.cfx_es_premium(uuid)') is null then return false; end if;
  execute 'select public.cfx_es_premium($1)' into r using p_negocio;
  return coalesce(r, false);
end $$;

-- ¿El negocio puede usar el módulo ahora? (prendido en la app + comprado, en prueba, regalado o incluido gratis)
create or replace function public.cfx_modulo_de(p_modulo text, p_negocio uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.cfx_modulo(p_modulo) and (not public.cfx_venta_activa(p_modulo)
    or exists (select 1 from public.cfx_modulos_negocio m where m.negocio = p_negocio and m.modulo = p_modulo and m.hasta > now()))
$$;
create or replace function public.cfx_modulo_mio(p_modulo text) returns boolean
language sql stable security definer set search_path = '' as $$ select public.cfx_modulo_de(p_modulo, public.cfx_negocio_cuenta(auth.uid())) $$;

-- Lo que puede usar cada negocio: {"chat": true, ...}. Para una tienda que ve un cliente.
create or replace function public.cfx_modulos_de(p_negocio uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce((select jsonb_object_agg(k, public.cfx_modulo_de(k, p_negocio)) from unnest(public.cfx_modulos_de_app()) k), '{}')
$$;

-- Activa (o alarga) los módulos de un item por N días; N <= 0 los quita. Devuelve hasta cuándo.
create or replace function public.cfx_modulos_dar(p_negocio uuid, p_item text, p_dias int, p_origen text default 'pago') returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare k text; h timestamptz; mx timestamptz;
begin
  if p_negocio is null or cardinality(public.cfx_venta_modulos(p_item)) = 0 then raise exception 'Módulo no válido'; end if;
  foreach k in array public.cfx_venta_modulos(p_item) loop
    if coalesce(p_dias, 0) <= 0 then delete from public.cfx_modulos_negocio where negocio = p_negocio and modulo = k; continue; end if;
    insert into public.cfx_modulos_negocio as m (negocio, modulo, hasta, origen) values (p_negocio, k, now() + make_interval(days => p_dias), p_origen)
    on conflict (negocio, modulo) do update set hasta = greatest(m.hasta, now()) + make_interval(days => p_dias),
      origen = case when excluded.origen = 'prueba' then m.origen else excluded.origen end, avisado = null
    returning hasta into h;
    mx := greatest(mx, h);
  end loop;
  return mx;
end $$;

-- G53: ¿el plan del negocio ya trae este módulo? (ej. Barbería: Premium incluye los 3 primeros). Gancho opcional de cada app:
-- cfx_modulo_plan_app(text, uuid) → boolean. Sin gancho: ninguno viene en el plan.
create or replace function public.cfx_modulo_plan(p_modulo text, p_negocio uuid) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare r boolean;
begin
  if p_negocio is null or to_regprocedure('public.cfx_modulo_plan_app(text,uuid)') is null then return false; end if;
  execute 'select public.cfx_modulo_plan_app($1, $2)' into r using p_modulo, p_negocio;
  return coalesce(r, false);
end $$;

-- ¿Este negocio puede activar gratis este módulo con la campaña? (una vez por módulo)
create or replace function public.cfx_campana_puede(p_modulo text, p_negocio uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_negocio is not null and public.cfx_campana() is not null and public.cfx_campana() -> 'modulos' ? p_modulo
    and public.cfx_modulo(p_modulo) and public.cfx_venta_activa(p_modulo) and not public.cfx_modulo_plan(p_modulo, p_negocio)
    and not exists (select 1 from public.cfx_modulos_pruebas p where p.negocio = p_negocio and p.item = 'campana:' || p_modulo)
$$;

-- Pantalla 🧩 Módulos del negocio: catálogo, precios (con su descuento Premium), lo que tiene y hasta cuándo.
create or replace function public.cfx_modulos_tienda() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := public.cfx_venta(); n uuid := public.cfx_negocio_cuenta(auth.uid()); dn uuid := public.cfx_negocio_dueno(public.cfx_negocio_cuenta(auth.uid())); pre boolean; d int; am int;
begin
  if n is null then raise exception 'Solo para negocios'; end if;
  pre := public.cfx_negocio_premium(n);
  d := case when pre then greatest(0, least(90, coalesce((v ->> 'descuento_premium')::int, 0))) else 0 end;
  am := greatest(1, least(12, coalesce((v ->> 'anual_meses')::int, 10)));
  return jsonb_build_object('activo', coalesce((v ->> 'activo')::boolean, false), 'premium', pre, 'descuento', d, 'anual_meses', am,
    'descuento_pro', case when pre then 0 else greatest(0, least(90, coalesce((v ->> 'descuento_premium')::int, 0))) end,
    'prueba_dias', coalesce((v ->> 'prueba_dias')::int, 7), 'dueno', dn = auth.uid(),
    'campana', (select jsonb_build_object('meses', (c ->> 'meses')::int, 'hasta', c ->> 'hasta') from (select public.cfx_campana() c) x where c is not null),
    'prueba_pack', exists (select 1 from public.cfx_modulos_pruebas p where p.negocio = n and p.item like 'pack:%') or public.cfx_prueba_usada(dn, 'pack'),  -- G95: por correo
    'modulos', coalesce((select jsonb_agg(jsonb_build_object('clave', k, 'nombre', coalesce(c.nombre, k), 'detalle', coalesce(c.detalle, ''),
        'precio', round(public.cfx_venta_precio(k) * (100 - d) / 100.0)::int, 'lista', public.cfx_venta_precio(k),
        'vende', public.cfx_venta_activa(k), 'activo', public.cfx_modulo_de(k, n) or public.cfx_modulo_plan(k, n), 'plan', public.cfx_modulo_plan(k, n),
        'hasta', m.hasta, 'origen', m.origen, 'regalo', public.cfx_campana_puede(k, n), 'prueba_usada', exists (select 1 from public.cfx_modulos_pruebas p where p.negocio = n and p.item = k) or public.cfx_prueba_usada(dn, k),
        'links', v #> array['links', k]) order by o)
      from unnest(public.cfx_modulos_de_app()) with ordinality u(k, o)
      left join public.cfx_modulos_catalogo() c on c.clave = k
      left join public.cfx_modulos_negocio m on m.negocio = n and m.modulo = k
      where public.cfx_modulo(k)), '[]'),
    'packs', coalesce((select jsonb_agg(jsonb_build_object('clave', p.key, 'nombre', p.value ->> 'nombre', 'detalle', coalesce(p.value ->> 'detalle', ''),
        'destacado', coalesce((p.value ->> 'destacado')::boolean, false), 'modulos', to_jsonb(public.cfx_venta_modulos(p.key)),
        'precio', round(coalesce((p.value ->> 'precio')::int, 0) * (100 - d) / 100.0)::int, 'lista', coalesce((p.value ->> 'precio')::int, 0),
        'suelto', (select coalesce(sum(public.cfx_venta_precio(x)), 0) from unnest(public.cfx_venta_modulos(p.key)) x),
        'links', v #> array['links', p.key]) order by coalesce((p.value ->> 'precio')::int, 0))
      from jsonb_each(coalesce(v -> 'packs', '{}')) p where cardinality(public.cfx_venta_modulos(p.key)) > 0), '[]'));
end $$;

-- Probar gratis: cada módulo una vez, y un solo pack por negocio. Solo el dueño. G95: también una vez por CORREO (cfx_pruebas_usadas, no se borra).
-- prueba_dias = 0 → sin prueba gratis.
create or replace function public.cfx_modulo_probar(p_item text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v jsonb := public.cfx_venta(); n uuid := public.cfx_negocio_cuenta(auth.uid()); pack boolean := (public.cfx_venta() #> array['packs', p_item]) is not null;
        dias int := least(30, coalesce((v ->> 'prueba_dias')::int, 7)); h timestamptz;
begin
  if n is null or public.cfx_negocio_dueno(n) is distinct from auth.uid() then raise exception 'Solo el dueño del negocio'; end if;
  if dias <= 0 then raise exception 'La prueba gratis no está disponible ahora'; end if;
  if not coalesce((v ->> 'activo')::boolean, false) or cardinality(public.cfx_venta_modulos(p_item)) = 0 then raise exception 'Módulo no válido'; end if;
  if pack and exists (select 1 from public.cfx_modulos_pruebas where negocio = n and item like 'pack:%') then raise exception 'Ya usaste la prueba gratis de un pack'; end if;
  if not pack and exists (select 1 from public.cfx_modulos_pruebas where negocio = n and item = p_item) then raise exception 'Ya usaste la prueba gratis de este módulo'; end if;
  if public.cfx_prueba_usada(auth.uid(), case when pack then 'pack' else p_item end) then
    raise exception '%', case when pack then 'Ya usaste la prueba gratis de un pack con este correo' else 'Ya usaste la prueba gratis de este módulo con este correo' end; end if;
  if not pack and public.cfx_modulo_de(p_item, n) then raise exception 'Ya tienes este módulo activo'; end if;
  insert into public.cfx_modulos_pruebas (negocio, item) values (n, case when pack then 'pack:' || p_item else p_item end);
  perform public.cfx_prueba_marcar(auth.uid(), case when pack then 'pack' else p_item end);
  -- La prueba no alarga lo que ya está pagado: solo prende lo que no tiene.
  insert into public.cfx_modulos_negocio as m (negocio, modulo, hasta, origen)
  select n, k, now() + make_interval(days => dias), 'prueba' from unnest(public.cfx_venta_modulos(p_item)) k
  on conflict (negocio, modulo) do update set hasta = greatest(m.hasta, excluded.hasta), origen = case when m.hasta > now() then m.origen else 'prueba' end, avisado = null;
  select max(hasta) into h from public.cfx_modulos_negocio where negocio = n and modulo = any(public.cfx_venta_modulos(p_item));
  perform public.cfx_anotar('módulo', 'prueba ' || p_item || ' · ' || n);
  return jsonb_build_object('ok', true, 'hasta', h);
end $$;

-- G74 b: el dueño toca 🎁 Activar → queda al tiro con el módulo N meses (origen 'regalo'). Una vez por módulo y negocio.
create or replace function public.cfx_modulo_campana(p_modulo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n uuid := public.cfx_negocio_cuenta(auth.uid()); c jsonb := public.cfx_campana(); h timestamptz;
begin
  if n is null or public.cfx_negocio_dueno(n) is distinct from auth.uid() then raise exception 'Solo el dueño del negocio'; end if;
  if c is null then raise exception 'La campaña ya terminó'; end if;
  if not public.cfx_campana_puede(p_modulo, n) then
    raise exception '%', case when exists (select 1 from public.cfx_modulos_pruebas p where p.negocio = n and p.item = 'campana:' || p_modulo)
      then 'Ya activaste este regalo' else 'Este módulo no está en la campaña' end;
  end if;
  insert into public.cfx_modulos_pruebas (negocio, item) values (n, 'campana:' || p_modulo);
  insert into public.cfx_modulos_negocio as m (negocio, modulo, hasta, origen)
  values (n, p_modulo, now() + make_interval(months => (c ->> 'meses')::int), 'regalo')
  on conflict (negocio, modulo) do update set hasta = greatest(m.hasta, now()) + make_interval(months => (c ->> 'meses')::int), origen = 'regalo', avisado = null
  returning hasta into h;
  perform public.cfx_anotar('módulo', 'campaña ' || p_modulo || ' · ' || n);
  return jsonb_build_object('ok', true, 'hasta', h);
end $$;

-- Aviso 3 días antes de que venza (7 días si es regalo, G74 b; una vez por vencimiento). Lo corre el cron diario.
create or replace function public.cfx_modulos_avisar() returns int
language plpgsql security definer set search_path = '' as $$
declare r record; c int := 0;
begin
  for r in select m.negocio, min(m.hasta) hasta, string_agg(coalesce(k.nombre, m.modulo), ', ' order by m.modulo) nombres
           from public.cfx_modulos_negocio m left join public.cfx_modulos_catalogo() k on k.clave = m.modulo
           where m.avisado is null and m.hasta between now() and now() + case when m.origen = 'regalo' then interval '7 days' else interval '3 days' end
           group by m.negocio limit 500 loop
    perform public.cfx_avisar(r.negocio, '🧩 Tus módulos vencen pronto', left(r.nombres, 120) || ' · vence el ' ||
      to_char(r.hasta at time zone 'America/Santiago', 'DD/MM') || '. Renuévalos en Ajustes → 🧩 Módulos y no pierdes nada.');
    update public.cfx_modulos_negocio set avisado = now() where negocio = r.negocio and avisado is null
      and hasta between now() and now() + case when origen = 'regalo' then interval '7 days' else interval '3 days' end;
    c := c + 1;
  end loop;
  return c;
end $$;

-- Al borrar un negocio (lo llama la app): sus módulos y sus pruebas.
create or replace function public.cfx_modulos_borrar(p_negocio uuid) returns void
language sql security definer set search_path = '' as $$
  delete from public.cfx_modulos_negocio where negocio = p_negocio;
  delete from public.cfx_modulos_pruebas where negocio = p_negocio;
$$;

-- ---------- Centro de Mando ----------
create or replace function public.cfx_venta_admin() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return jsonb_build_object('config', public.cfx_venta(), 'app', to_jsonb(public.cfx_modulos_de_app()),
    'catalogo', (select coalesce(jsonb_agg(jsonb_build_object('clave', c.clave, 'nombre', c.nombre)), '[]') from public.cfx_modulos_catalogo() c where c.clave = any(public.cfx_modulos_de_app())),
    'activos', (select count(distinct negocio) from public.cfx_modulos_negocio where hasta > now() and origen = 'pago'),
    'pruebas', (select count(distinct negocio) from public.cfx_modulos_negocio where hasta > now() and origen = 'prueba'),
    'campana_on', public.cfx_campana() is not null,
    'campana_usos', (select count(distinct negocio) from public.cfx_modulos_pruebas where item like 'campana:%'),
    'negocios', coalesce((select jsonb_agg(x order by x.hasta) from (
      select m.negocio, coalesce((select u.email from auth.users u where u.id = m.negocio), '') email, min(m.hasta) hasta,
        jsonb_agg(jsonb_build_object('modulo', m.modulo, 'hasta', m.hasta, 'origen', m.origen) order by m.modulo) modulos
      from public.cfx_modulos_negocio m where m.hasta > now() - interval '30 days' group by m.negocio limit 300) x), '[]'));
end $$;

create or replace function public.cfx_venta_guardar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v jsonb := public.cfx_venta(); l record; u record;
begin
  perform public.admin_check();
  if jsonb_typeof(p) <> 'object' then raise exception 'Datos no válidos'; end if;
  v := v || jsonb_strip_nulls(p - 'packs' - 'precios' - 'links' - 'campana')
         || jsonb_build_object('precios', coalesce(p -> 'precios', v -> 'precios', '{}'),   -- llegan completos desde el CM
                               'links', coalesce(p -> 'links', v -> 'links', '{}'),
                               'packs', coalesce(p -> 'packs', v -> 'packs', '{}'));
  if p ? 'campana' then  -- G74 b: null o {} = terminar la campaña ahora
    if coalesce((p #>> '{campana,fin}')::boolean, false) then  -- ⏹️ Terminar hoy: la fecha pasa a ayer (queda el historial)
      if jsonb_typeof(v -> 'campana') = 'object' then
        v := jsonb_set(v, '{campana,hasta}', to_jsonb(to_char((now() at time zone 'America/Santiago')::date - 1, 'YYYY-MM-DD')));
      end if;
    else v := v - 'campana'; end if;
    if jsonb_typeof(p -> 'campana') = 'object' and p -> 'campana' <> '{}'::jsonb and not (p -> 'campana' ? 'fin') then
      if coalesce(p #>> '{campana,meses}', '') !~ '^\d{1,2}$' or (p #>> '{campana,meses}')::int not between 1 and 12 then raise exception 'Meses de regalo: de 1 a 12'; end if;
      if coalesce(p #>> '{campana,hasta}', '') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Elige la fecha de término'; end if;
      if (p #>> '{campana,hasta}')::date < (now() at time zone 'America/Santiago')::date or (p #>> '{campana,hasta}')::date > (now() at time zone 'America/Santiago')::date + 366 then
        raise exception 'La fecha de término va de hoy a un año más'; end if;
      if jsonb_typeof(p #> '{campana,modulos}') <> 'array' or not exists (select 1 from jsonb_array_elements_text(p #> '{campana,modulos}') x where x = any(public.cfx_modulos_de_app())) then
        raise exception 'Elige al menos un módulo'; end if;
      v := v || jsonb_build_object('campana', jsonb_build_object('meses', (p #>> '{campana,meses}')::int, 'hasta', p #>> '{campana,hasta}',
        'modulos', (select jsonb_agg(distinct x) from jsonb_array_elements_text(p #> '{campana,modulos}') x where x = any(public.cfx_modulos_de_app()))));
    end if;
  end if;
  if coalesce((v ->> 'precio')::numeric, 0) not between 0 and 1000000 or coalesce((v ->> 'descuento_premium')::numeric, 0) not between 0 and 90
     or coalesce((v ->> 'prueba_dias')::numeric, 7) not between 0 and 30 or coalesce((v ->> 'anual_meses')::numeric, 10) not between 1 and 12 then
    raise exception 'Revisa los números: precio de 0 a 1.000.000, descuento de 0 a 90 %%, prueba de 0 a 30 días, anual de 1 a 12 meses';
  end if;
  for l in select key, value from jsonb_each(coalesce(v -> 'precios', '{}')) loop
    if jsonb_typeof(l.value) <> 'number' or l.value::numeric not between 0 and 1000000 then raise exception 'Precio no válido: %', l.key; end if;
  end loop;
  for l in select key, value from jsonb_each(coalesce(v -> 'links', '{}')) loop
    for u in select key, value from jsonb_each_text(case when jsonb_typeof(l.value) = 'object' then l.value else '{}' end) loop
      if coalesce(u.value, '') <> '' and u.value !~ '^https://[^ ]+$' then raise exception 'El link de % debe empezar con https://', l.key; end if;
    end loop;
  end loop;
  update public.cfx_config set valor = v where clave = 'modulos_venta';
  perform public.cfx_anotar('módulos', 'venta ' || case when coalesce((v ->> 'activo')::boolean, false) then 'prendida' else 'apagada' end);
  return public.cfx_venta_admin();
end $$;

-- Regalar o quitar (p_dias = 0) un módulo o pack a un negocio por su correo.
create or replace function public.cfx_modulo_regalar(p_email text, p_item text, p_dias int) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid; n uuid; h timestamptz;
begin
  perform public.admin_check();
  select id into u from auth.users where lower(email) = lower(trim(coalesce(p_email, '')));
  if u is null then raise exception 'No hay una cuenta con ese correo en esta app'; end if;
  n := public.cfx_negocio_cuenta(u);
  if n is null then raise exception 'Esa cuenta no es un negocio'; end if;
  if coalesce(p_dias, 0) not between 0 and 3660 then raise exception 'De 0 a 3660 días'; end if;
  h := public.cfx_modulos_dar(n, p_item, p_dias, 'regalo');
  if h is not null then perform public.cfx_avisar(n, '🎁 Te regalamos un módulo', coalesce((select c.nombre from public.cfx_modulos_catalogo() c where c.clave = p_item), public.cfx_venta() #>> array['packs', p_item, 'nombre'], p_item) ||
    ' activo hasta el ' || to_char(h at time zone 'America/Santiago', 'DD/MM/YYYY') || '.'); end if;
  perform public.cfx_anotar('módulo', case when h is null then 'quitó ' else 'regaló ' || p_dias || ' días de ' end || p_item || ' a ' || lower(trim(p_email)));
  return public.cfx_venta_admin();
end $$;

revoke all on function public.cfx_modulos_catalogo(), public.cfx_venta(), public.cfx_venta_on(), public.cfx_venta_precio(text), public.cfx_venta_activa(text), public.cfx_venta_modulos(text),
  public.cfx_negocio_cuenta(uuid), public.cfx_negocio_dueno(uuid), public.cfx_negocio_premium(uuid), public.cfx_modulo_plan(text, uuid), public.cfx_modulo_de(text, uuid), public.cfx_modulo_mio(text),
  public.cfx_modulos_dar(uuid, text, int, text), public.cfx_modulos_avisar(), public.cfx_modulos_borrar(uuid),
  public.cfx_campana(), public.cfx_campana_puede(text, uuid) from public, anon, authenticated;
revoke all on function public.cfx_modulos_de(uuid), public.cfx_modulos_tienda(), public.cfx_modulo_probar(text), public.cfx_modulo_campana(text), public.cfx_venta_admin(),
  public.cfx_venta_guardar(jsonb), public.cfx_modulo_regalar(text, text, int) from public, anon;
grant execute on function public.cfx_modulos_de(uuid) to anon, authenticated;
grant execute on function public.cfx_modulos_tienda(), public.cfx_modulo_probar(text), public.cfx_modulo_campana(text), public.cfx_venta_admin(), public.cfx_venta_guardar(jsonb),
  public.cfx_modulo_regalar(text, text, int) to authenticated;
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'cfx-modulos';
  perform cron.schedule('cfx-modulos', '17 13 * * *', 'select public.cfx_modulos_avisar()');
exception when others then
  raise notice 'Aviso de módulos por vencer no programado (%).', sqlerrm;
end $$;
-- ---------- Chat entre personas (C14): las mismas reglas en todas las apps (módulo 'chat') ----------
-- Reglas: hasta N mensajes seguidos sin respuesta (el gancho decide N; null = sin límite, p. ej. el admin), 100 al día,
-- bloquear (ninguno de los dos escribe), reportar (le llega al admin) y borrar la conversación (para los dos).
-- Ganchos que pone cada app que usa el chat (y 'chat' en cfx_modulos_app()):
--   cfx_chat_puede(a, b) boolean         ¿a puede escribirle a b?
--   cfx_chat_seguidos(a, b) int          mensajes seguidos sin respuesta (null = sin límite)
--   cfx_chat_quien(u) jsonb              {"nombre": ..., "rol": ...} para la lista y los reportes
--   cfx_chat_aviso(para, de, texto) void push al que recibe (con el link a la conversación)
--   cfx_chat_suspender(u) void           el admin suspende una cuenta reportada
create table if not exists public.cfx_mensajes (
  id      uuid primary key default gen_random_uuid(),
  de      uuid not null references auth.users (id) on delete cascade,
  para    uuid not null references auth.users (id) on delete cascade,
  texto   text not null check (char_length(texto) between 1 and 1000),
  creado  timestamptz not null default now(),
  leido   timestamptz
);
create index if not exists cfx_mensajes_par_idx on public.cfx_mensajes (least(de, para), greatest(de, para), creado desc);
create index if not exists cfx_mensajes_para_idx on public.cfx_mensajes (para) where leido is null;
create index if not exists cfx_mensajes_de_idx on public.cfx_mensajes (de, creado);
create index if not exists cfx_mensajes_creado_idx on public.cfx_mensajes (creado);
create table if not exists public.cfx_bloqueos (
  quien   uuid not null references auth.users (id) on delete cascade,
  a       uuid not null references auth.users (id) on delete cascade,
  creado  timestamptz not null default now(),
  primary key (quien, a)
);
create table if not exists public.cfx_reportes (
  id        uuid primary key default gen_random_uuid(),
  quien     uuid not null references auth.users (id) on delete cascade,
  a         uuid not null references auth.users (id) on delete cascade,
  mensaje   uuid references public.cfx_mensajes (id) on delete set null,
  motivo    text not null,
  extracto  text not null default '',
  resuelto  boolean not null default false,
  creado    timestamptz not null default now()
);
alter table public.cfx_mensajes enable row level security;
alter table public.cfx_bloqueos enable row level security;
alter table public.cfx_reportes enable row level security;
revoke all on public.cfx_mensajes, public.cfx_bloqueos, public.cfx_reportes from anon, authenticated;

create or replace function public.cfx_msg_listo() returns uuid
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Inicia sesión primero'; end if;
  if not public.cfx_modulo('chat') then raise exception 'El chat no está disponible en esta app'; end if;
  return auth.uid();
end $$;

create or replace function public.cfx_msg_bloqueado(p_uno uuid, p_otro uuid) returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  return exists (select 1 from public.cfx_bloqueos x where (x.quien = p_uno and x.a = p_otro) or (x.quien = p_otro and x.a = p_uno));
end $$;

-- Cuántos me quedan seguidos con "otro": {"restantes": n, "limite": n} (null = sin límite).
create or replace function public.cfx_msg_restantes(p_otro uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare u uuid := public.cfx_msg_listo(); lim int := public.cfx_chat_seguidos(u, p_otro); n int;
begin
  if lim is null then return jsonb_build_object('restantes', null, 'limite', null); end if;
  select count(*) into n from public.cfx_mensajes m where m.de = u and m.para = p_otro
    and m.creado > coalesce((select max(x.creado) from public.cfx_mensajes x where x.de = p_otro and x.para = u), '-infinity');
  return jsonb_build_object('restantes', greatest(0, lim - n), 'limite', lim);
end $$;

-- Enviar: {"ok": true, "id", "restantes"} o {"ok": false, "error"}.
create or replace function public.cfx_msg_enviar(p_para uuid, p_texto text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := public.cfx_msg_listo(); t text := trim(coalesce(p_texto, '')); lim int; r jsonb; i uuid;
begin
  if t = '' then return jsonb_build_object('ok', false, 'error', 'Escribe un mensaje'); end if;
  if char_length(t) > 1000 then return jsonb_build_object('ok', false, 'error', 'Máximo 1000 caracteres por mensaje'); end if;
  if p_para is null or not coalesce(public.cfx_chat_puede(u, p_para), false) then
    return jsonb_build_object('ok', false, 'error', 'No puedes escribirle a esta cuenta');
  end if;
  lim := public.cfx_chat_seguidos(u, p_para);
  -- G19: con el chat a la venta, el negocio de la conversación debe tenerlo (con soporte siempre se puede).
  if lim is not null and public.cfx_chat_seguidos(p_para, u) is not null and public.cfx_venta_activa('chat') then
    if public.cfx_negocio_cuenta(u) is not null and not public.cfx_modulo_de('chat', public.cfx_negocio_cuenta(u)) then
      return jsonb_build_object('ok', false, 'error', 'El chat es un módulo. Actívalo en Ajustes → 🧩 Módulos');
    end if;
    if public.cfx_negocio_cuenta(p_para) is not null and not public.cfx_modulo_de('chat', public.cfx_negocio_cuenta(p_para)) then
      return jsonb_build_object('ok', false, 'error', 'Esta tienda no tiene chat. Escríbele por WhatsApp');
    end if;
  end if;
  if lim is not null then
    if public.cfx_msg_bloqueado(u, p_para) then return jsonb_build_object('ok', false, 'error', 'La conversación está bloqueada'); end if;
    if (public.cfx_msg_restantes(p_para) ->> 'restantes')::int <= 0 then
      return jsonb_build_object('ok', false, 'error', case when lim = 1
        then 'Envías 1 mensaje a la vez. Espera la respuesta para escribir de nuevo.'
        else 'Ya enviaste ' || lim || ' mensajes seguidos. Espera la respuesta para escribir de nuevo.' end);
    end if;
    if (select count(*) from public.cfx_mensajes where de = u and creado > now() - interval '1 day') >= 100 then
      return jsonb_build_object('ok', false, 'error', 'Llegaste al máximo de 100 mensajes por día');
    end if;
  end if;
  insert into public.cfx_mensajes (de, para, texto) values (u, p_para, t) returning id into i;
  perform public.cfx_chat_aviso(p_para, u, t);
  r := public.cfx_msg_restantes(p_para);
  return jsonb_build_object('ok', true, 'id', i, 'restantes', r -> 'restantes');
end $$;

-- Mis conversaciones: [{otro, nombre, rol, ultimo, ultimo_at, mio, no_leidos, bloqueado}] (las 100 más recientes).
create or replace function public.cfx_msg_lista() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare u uuid := public.cfx_msg_listo();
begin
  return coalesce((with z as (select case when m.de = u then m.para else m.de end as otro, m.texto, m.creado, m.de = u as mio
                               from public.cfx_mensajes m where m.de = u or m.para = u),
                          l as (select distinct on (otro) * from z order by otro, creado desc),
                          t as (select * from l order by creado desc limit 100)
    select jsonb_agg(jsonb_build_object('otro', t.otro, 'nombre', coalesce(q.v ->> 'nombre', 'Cuenta'), 'rol', coalesce(q.v ->> 'rol', ''),
      'ultimo', t.texto, 'ultimo_at', t.creado, 'mio', t.mio,
      'no_leidos', (select count(*) from public.cfx_mensajes x where x.de = t.otro and x.para = u and x.leido is null),
      'bloqueado', exists (select 1 from public.cfx_bloqueos b where b.quien = u and b.a = t.otro)) order by t.creado desc)
    from t cross join lateral (select public.cfx_chat_quien(t.otro) as v) q), '[]');
end $$;

create or replace function public.cfx_msg_sin_leer() returns int
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not public.cfx_modulo('chat') then return 0; end if;
  return (select count(*)::int from public.cfx_mensajes where para = auth.uid() and leido is null);
end $$;

-- Una conversación (las últimas 200; marca como leídos los recibidos): [{id, mio, texto, creado, leido}].
create or replace function public.cfx_msg_hilo(p_otro uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := public.cfx_msg_listo();
begin
  update public.cfx_mensajes set leido = now() where de = p_otro and para = u and leido is null;
  return coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'mio', m.de = u, 'texto', m.texto, 'creado', m.creado, 'leido', m.leido) order by m.creado)
    from (select * from public.cfx_mensajes x where (x.de = u and x.para = p_otro) or (x.de = p_otro and x.para = u)
          order by x.creado desc limit 200) m), '[]');
end $$;

create or replace function public.cfx_msg_bloquear(p_otro uuid, p_bloquear boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare u uuid := public.cfx_msg_listo();
begin
  if p_otro is null or p_otro = u then raise exception 'Cuenta no válida'; end if;
  if p_bloquear then insert into public.cfx_bloqueos (quien, a) values (u, p_otro) on conflict do nothing;
  else delete from public.cfx_bloqueos where quien = u and a = p_otro; end if;
end $$;

create or replace function public.cfx_msg_reportar(p_mensaje uuid, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := public.cfx_msg_listo(); m public.cfx_mensajes;
begin
  select * into m from public.cfx_mensajes where id = p_mensaje and para = u;
  if m.id is null then return jsonb_build_object('ok', false, 'error', 'Mensaje no encontrado'); end if;
  if (select count(*) from public.cfx_reportes where quien = u and creado > now() - interval '1 day') >= 10 then
    return jsonb_build_object('ok', false, 'error', 'Máximo 10 reportes por día');
  end if;
  insert into public.cfx_reportes (quien, a, mensaje, motivo, extracto)
  values (u, m.de, m.id, left(coalesce(nullif(trim(p_motivo), ''), 'Sin motivo'), 300), left(m.texto, 300));
  perform public.cfx_avisar_admin('🚩 Nuevo reporte en el chat', left(m.texto, 100));
  return jsonb_build_object('ok', true);
end $$;

-- Borra la conversación completa (para los dos).
create or replace function public.cfx_msg_borrar(p_otro uuid) returns int
language plpgsql security definer set search_path = '' as $$
declare u uuid := public.cfx_msg_listo(); n int;
begin
  delete from public.cfx_mensajes where (de = u and para = p_otro) or (de = p_otro and para = u);
  get diagnostics n = row_count;
  return n;
end $$;

-- Administrador: reportes sin resolver y resolverlos (descartar o suspender a la cuenta reportada).
create or replace function public.cfx_msg_reportes() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'motivo', r.motivo, 'extracto', r.extracto, 'creado', r.creado,
      'quien', coalesce(public.cfx_chat_quien(r.quien) ->> 'nombre', ''), 'a', coalesce(public.cfx_chat_quien(r.a) ->> 'nombre', ''),
      'quien_email', (select email from auth.users where id = r.quien), 'a_email', (select email from auth.users where id = r.a)) order by r.creado desc)
    from public.cfx_reportes r where not r.resuelto), '[]');
end $$;

create or replace function public.cfx_msg_resolver(p_id uuid, p_suspender boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare r public.cfx_reportes;
begin
  perform public.admin_check();
  update public.cfx_reportes set resuelto = true where id = p_id and not resuelto returning * into r;
  if r.id is null then raise exception 'El reporte ya fue atendido'; end if;
  if p_suspender then perform public.cfx_chat_suspender(r.a); end if;
  perform public.cfx_anotar('reporte chat', case when p_suspender then 'suspendida ' else 'descartado ' end || coalesce((select email from auth.users where id = r.a), ''));
end $$;

revoke all on function public.cfx_msg_listo(), public.cfx_msg_bloqueado(uuid, uuid) from public, anon, authenticated;
revoke all on function public.cfx_msg_restantes(uuid), public.cfx_msg_enviar(uuid, text), public.cfx_msg_lista(), public.cfx_msg_sin_leer(),
  public.cfx_msg_hilo(uuid), public.cfx_msg_bloquear(uuid, boolean), public.cfx_msg_reportar(uuid, text), public.cfx_msg_borrar(uuid),
  public.cfx_msg_reportes(), public.cfx_msg_resolver(uuid, boolean) from public, anon;
grant execute on function public.cfx_msg_restantes(uuid), public.cfx_msg_enviar(uuid, text), public.cfx_msg_lista(), public.cfx_msg_sin_leer(),
  public.cfx_msg_hilo(uuid), public.cfx_msg_bloquear(uuid, boolean), public.cfx_msg_reportar(uuid, text), public.cfx_msg_borrar(uuid),
  public.cfx_msg_reportes(), public.cfx_msg_resolver(uuid, boolean) to authenticated;
-- ---------- Calificaciones en dos direcciones (C15): el cliente califica al negocio y el negocio al cliente (módulo 'calificaciones') ----------
-- Una calificación por "ref" (pedido, reserva, arriendo…) y por lado. Estrellas 1-5 y comentario opcional (300).
-- Gancho que pone cada app que las usa (y 'calificaciones' en cfx_modulos_app()):
--   cfx_calif_ref(ref, u) jsonb   quién califica esa ref: {"ref": text, "negocio": uuid, "cliente": uuid|null, "cliente_ref": text|null, "de_negocio": bool}
--                                 ("ref" = la referencia de verdad, p. ej. el id del pedido cuando llega su token)
--                                 o {"error": "..."} (no existe, aún no se puede, no es tuyo). u puede ser null (invitado con token).
-- Para mostrar: cfx_calif_negocio(n) y cfx_calif_cliente(c, ref) → {"promedio", "total"}; cfx_calif_hecha(ref, de_negocio).
-- Si el módulo está apagado no se califica, los promedios vuelven null y cfx_calif_hecha dice true (no aparece "Califica").
create table if not exists public.cfx_calificaciones (
  ref          text not null,
  de_negocio   boolean not null,
  negocio_id   uuid not null,
  cliente_id   uuid references auth.users (id) on delete set null,
  cliente_ref  text,
  estrellas    int not null check (estrellas between 1 and 5),
  comentario   text not null default '' check (char_length(comentario) <= 300),
  creado       timestamptz not null default now(),
  primary key (ref, de_negocio)
);
create index if not exists cfx_calif_negocio_idx on public.cfx_calificaciones (negocio_id) where not de_negocio;
create index if not exists cfx_calif_cliente_idx on public.cfx_calificaciones (cliente_id) where de_negocio;
create index if not exists cfx_calif_cref_idx on public.cfx_calificaciones (cliente_ref) where de_negocio and cliente_ref is not null;
alter table public.cfx_calificaciones enable row level security;
revoke all on public.cfx_calificaciones from anon, authenticated;

-- Calificar: {"ok": true} o {"ok": false, "error"}.
create or replace function public.cfx_calificar(p_ref text, p_estrellas int, p_comentario text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r jsonb;
begin
  if not public.cfx_modulo('calificaciones') then return jsonb_build_object('ok', false, 'error', 'Las calificaciones no están disponibles'); end if;
  if p_estrellas is null or p_estrellas < 1 or p_estrellas > 5 then return jsonb_build_object('ok', false, 'error', 'Elige de 1 a 5 estrellas'); end if;
  if coalesce(trim(p_ref), '') = '' then return jsonb_build_object('ok', false, 'error', 'No encontrado'); end if;
  r := public.cfx_calif_ref(p_ref, auth.uid());
  if r is null or r ? 'error' or r ->> 'negocio' is null then return jsonb_build_object('ok', false, 'error', coalesce(r ->> 'error', 'No encontrado')); end if;
  if not public.cfx_modulo_de('calificaciones', (r ->> 'negocio')::uuid) then return jsonb_build_object('ok', false, 'error', 'Las calificaciones no están disponibles'); end if;
  insert into public.cfx_calificaciones (ref, de_negocio, negocio_id, cliente_id, cliente_ref, estrellas, comentario)
  values (coalesce(r ->> 'ref', p_ref), coalesce((r ->> 'de_negocio')::boolean, false), (r ->> 'negocio')::uuid, (r ->> 'cliente')::uuid,
          nullif(left(r ->> 'cliente_ref', 60), ''), p_estrellas, left(trim(coalesce(p_comentario, '')), 300))
  on conflict (ref, de_negocio) do nothing;
  if not found then return jsonb_build_object('ok', false, 'error', 'Ya fue calificado'); end if;
  return jsonb_build_object('ok', true);
end $$;

-- ¿Ya calificó ese lado? (con el módulo apagado: true, para no pedirlo)
create or replace function public.cfx_calif_hecha(p_ref text, p_de_negocio boolean) returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.cfx_modulo('calificaciones') then return true; end if;
  if public.cfx_venta_activa('calificaciones') and not coalesce(public.cfx_modulo_de('calificaciones', (public.cfx_calif_ref(p_ref, auth.uid()) ->> 'negocio')::uuid), false) then return true; end if;
  return exists (select 1 from public.cfx_calificaciones where ref = p_ref and de_negocio = p_de_negocio);
end $$;

-- Lo que los clientes dicen del negocio.
create or replace function public.cfx_calif_negocio(p_negocio uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.cfx_modulo_de('calificaciones', p_negocio) then return null; end if;
  return (select jsonb_build_object('promedio', round(avg(estrellas), 1), 'total', count(*))
          from public.cfx_calificaciones where negocio_id = p_negocio and not de_negocio);
end $$;

-- Lo que los negocios dicen del cliente (por su cuenta o, si es invitado, por su referencia: teléfono…).
create or replace function public.cfx_calif_cliente(p_cliente uuid, p_cliente_ref text default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.cfx_modulo_mio('calificaciones') or (p_cliente is null and coalesce(p_cliente_ref, '') = '') then return null; end if;
  return (select jsonb_build_object('promedio', round(avg(estrellas), 1), 'total', count(*))
          from public.cfx_calificaciones where de_negocio
            and ((p_cliente is not null and cliente_id = p_cliente) or (p_cliente is null and cliente_ref = p_cliente_ref)));
end $$;

-- Al borrar un negocio o una ref (lo llama la app).
create or replace function public.cfx_calif_borrar(p_negocio uuid, p_ref text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.cfx_calificaciones where negocio_id = p_negocio and (p_ref is null or ref = p_ref);
end $$;

revoke all on function public.cfx_calif_hecha(text, boolean), public.cfx_calif_negocio(uuid), public.cfx_calif_cliente(uuid, text),
  public.cfx_calif_borrar(uuid, text) from public, anon, authenticated;
revoke all on function public.cfx_calificar(text, int, text) from public;
grant execute on function public.cfx_calificar(text, int, text) to anon, authenticated;
-- ---------- Cupones del negocio y tarjeta de sellos (C16): módulos 'cupones' y 'sellos' ----------
-- OJO: no son los cupones del Premium (cfx_cupones / cfx_cupon_ver, los crea el admin). Estos los crea cada negocio para SUS clientes.
-- Ganchos que pone cada app que los usa (y 'cupones' / 'sellos' en cfx_modulos_app()):
--   cfx_fid_dueno(u) uuid                  negocio que administra la cuenta u (null = no es negocio)
--   cfx_fid_activo(negocio, modulo) bool   ¿el plan del negocio incluye ese módulo? (p. ej. solo Pro)
--   cfx_fid_cliente(u, negocio) bool       ¿u es cliente de ese negocio? (ve sus sellos y prueba cupones)
--   cfx_sellos_aviso(negocio, cliente, premio) void   push al cliente que completó la tarjeta
-- La app usa, dentro de sus funciones: cfx_desc_pct + cfx_desc_usar (al crear el pedido), cfx_sello_sumar (al entregar)
-- y cfx_sellos_cfg_de (para mostrar la tarjeta). cfx_fid_borrar al borrar un negocio.
create table if not exists public.cfx_descuentos (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null,
  codigo      text not null check (codigo ~ '^[A-Z0-9]{3,20}$'),
  porcentaje  int not null check (porcentaje between 1 and 90),
  hasta       date,
  activo      boolean not null default true,
  usos        int not null default 0,
  creado      timestamptz not null default now(),
  unique (owner_id, codigo)
);
create table if not exists public.cfx_sellos_cfg (
  owner_id  uuid primary key,
  meta      int not null check (meta between 2 and 30),
  premio    text check (char_length(premio) <= 80),
  creado    timestamptz not null default now()
);
create table if not exists public.cfx_sellos (
  negocio_id  uuid not null,
  cliente_id  uuid not null references auth.users (id) on delete cascade,
  cantidad    int not null default 0,
  premios     int not null default 0,
  actualizado timestamptz not null default now(),
  primary key (negocio_id, cliente_id)
);
create index if not exists cfx_sellos_cliente_idx on public.cfx_sellos (cliente_id);
alter table public.cfx_descuentos enable row level security;
alter table public.cfx_sellos_cfg enable row level security;
alter table public.cfx_sellos enable row level security;
revoke all on public.cfx_descuentos, public.cfx_sellos_cfg, public.cfx_sellos from anon, authenticated;

create or replace function public.cfx_desc_codigo(p_codigo text) returns text
language sql immutable set search_path = '' as $$ select upper(regexp_replace(coalesce(p_codigo, ''), '[^A-Za-z0-9]', '', 'g')) $$;

-- El negocio de la cuenta, si el módulo está prendido y su plan lo incluye.
create or replace function public.cfx_fid_mio(p_modulo text) returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare n uuid;
begin
  if not public.cfx_modulo(p_modulo) then
    raise exception '% no está disponible en esta app', case p_modulo when 'cupones' then 'Los cupones' else 'La tarjeta de sellos' end;
  end if;
  n := public.cfx_fid_dueno(auth.uid());
  if n is null then raise exception 'Solo el negocio'; end if;
  if public.cfx_venta_on() then
    if not public.cfx_modulo_de(p_modulo, n) then
      raise exception '% Actívalo en Ajustes → 🧩 Módulos', case p_modulo when 'cupones' then 'Los cupones son un módulo.' else 'La tarjeta de sellos es un módulo.' end;
    end if;
  elsif not coalesce(public.cfx_fid_activo(n, p_modulo), false) then
    raise exception '% de la versión Pro', case p_modulo when 'cupones' then 'Los cupones son' else 'La tarjeta de sellos es' end;
  end if;
  return n;
end $$;

-- ¿El negocio puede usar el módulo ahora? (prendido + su plan)
create or replace function public.cfx_fid_ok(p_negocio uuid, p_modulo text) returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  if p_negocio is null or not public.cfx_modulo(p_modulo) then return false; end if;
  if public.cfx_venta_on() then return public.cfx_modulo_de(p_modulo, p_negocio); end if;
  return coalesce(public.cfx_fid_activo(p_negocio, p_modulo), false);
end $$;

-- ---------- Cupones ----------
create or replace function public.cfx_desc_guardar(p_codigo text, p_porcentaje int, p_hasta date) returns void
language plpgsql security definer set search_path = '' as $$
declare n uuid := public.cfx_fid_mio('cupones'); c text := public.cfx_desc_codigo(p_codigo);
begin
  if length(c) < 3 or length(c) > 20 then raise exception 'El código debe tener entre 3 y 20 letras o números'; end if;
  if p_porcentaje is null or p_porcentaje < 1 or p_porcentaje > 90 then raise exception 'El descuento debe ser entre 1 y 90 por ciento'; end if;
  if (select count(*) from public.cfx_descuentos where owner_id = n) >= 50
     and not exists (select 1 from public.cfx_descuentos where owner_id = n and codigo = c) then raise exception 'Máximo 50 cupones'; end if;
  insert into public.cfx_descuentos (owner_id, codigo, porcentaje, hasta) values (n, c, p_porcentaje, p_hasta)
  on conflict (owner_id, codigo) do update set porcentaje = excluded.porcentaje, hasta = excluded.hasta, activo = true;
end $$;

create or replace function public.cfx_desc_borrar(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.cfx_descuentos where id = p_id and owner_id = public.cfx_fid_dueno(auth.uid());
end $$;

-- Mis cupones: [{id, codigo, porcentaje, hasta, activo, usos}]
create or replace function public.cfx_desc_lista() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare n uuid := public.cfx_fid_mio('cupones');
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'codigo', c.codigo, 'porcentaje', c.porcentaje, 'hasta', c.hasta,
    'activo', c.activo, 'usos', c.usos) order by c.creado desc) from public.cfx_descuentos c where c.owner_id = n), '[]');
end $$;

-- Porcentaje de un cupón vigente (null = no sirve). Interna: la app la usa al armar el pedido.
create or replace function public.cfx_desc_pct(p_negocio uuid, p_codigo text) returns int
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.cfx_fid_ok(p_negocio, 'cupones') then return null; end if;
  return (select c.porcentaje from public.cfx_descuentos c
          where c.owner_id = p_negocio and c.codigo = public.cfx_desc_codigo(p_codigo) and c.activo and (c.hasta is null or c.hasta >= current_date));
end $$;

-- Suma un uso (la app la llama cuando el pedido ya quedó guardado).
create or replace function public.cfx_desc_usar(p_negocio uuid, p_codigo text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.cfx_descuentos set usos = usos + 1 where owner_id = p_negocio and codigo = public.cfx_desc_codigo(p_codigo);
end $$;

-- El cliente prueba un cupón: devuelve el porcentaje o avisa que no sirve.
create or replace function public.cfx_desc_validar(p_negocio uuid, p_codigo text) returns int
language plpgsql stable security definer set search_path = '' as $$
declare pct int;
begin
  if not public.cfx_modulo('cupones') then raise exception 'Cupón no válido o vencido'; end if;
  if not coalesce(public.cfx_fid_cliente(auth.uid(), p_negocio), false) then raise exception 'Sin permiso'; end if;
  pct := public.cfx_desc_pct(p_negocio, p_codigo);
  if pct is null then raise exception 'Cupón no válido o vencido'; end if;
  return pct;
end $$;

-- ---------- Tarjeta de sellos ----------
-- El negocio la arma (meta 2-30 y premio) o la apaga (meta null).
create or replace function public.cfx_sellos_guardar(p_meta int, p_premio text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n uuid;
begin
  if p_meta is null then
    n := public.cfx_fid_dueno(auth.uid());
    if n is null then raise exception 'Solo el negocio'; end if;
    delete from public.cfx_sellos_cfg where owner_id = n;
    return null;
  end if;
  n := public.cfx_fid_mio('sellos');
  if p_meta < 2 or p_meta > 30 then raise exception 'La tarjeta debe tener entre 2 y 30 sellos'; end if;
  insert into public.cfx_sellos_cfg (owner_id, meta, premio) values (n, p_meta, nullif(left(trim(coalesce(p_premio, '')), 80), ''))
  on conflict (owner_id) do update set meta = excluded.meta, premio = excluded.premio;
  return public.cfx_sellos_cfg_de(n);
end $$;

-- La tarjeta del negocio {meta, premio} (null = no tiene, módulo apagado o su plan no la incluye).
create or replace function public.cfx_sellos_cfg_de(p_negocio uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.cfx_fid_ok(p_negocio, 'sellos') then return null; end if;
  return (select jsonb_build_object('meta', c.meta, 'premio', c.premio) from public.cfx_sellos_cfg c where c.owner_id = p_negocio);
end $$;

-- Mis sellos en un negocio: {cantidad, premios, meta, premio} o null.
create or replace function public.cfx_sellos_mios(p_negocio uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare c jsonb := public.cfx_sellos_cfg_de(p_negocio);
begin
  if c is null then return null; end if;
  if not coalesce(public.cfx_fid_cliente(auth.uid(), p_negocio), false) then return null; end if;
  return c || coalesce((select jsonb_build_object('cantidad', s.cantidad, 'premios', s.premios) from public.cfx_sellos s
                        where s.negocio_id = p_negocio and s.cliente_id = auth.uid()), jsonb_build_object('cantidad', 0, 'premios', 0));
end $$;

-- Suma un sello (al entregar una compra). Al llegar a la meta: vuelve a 0, suma un premio y avisa. Devuelve {cantidad, premio} o null.
create or replace function public.cfx_sello_sumar(p_negocio uuid, p_cliente uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c jsonb := public.cfx_sellos_cfg_de(p_negocio); s public.cfx_sellos;
begin
  if c is null or p_cliente is null then return null; end if;
  insert into public.cfx_sellos (negocio_id, cliente_id, cantidad) values (p_negocio, p_cliente, 1)
  on conflict (negocio_id, cliente_id) do update set cantidad = public.cfx_sellos.cantidad + 1, actualizado = now() returning * into s;
  if s.cantidad >= (c ->> 'meta')::int then
    update public.cfx_sellos set cantidad = 0, premios = premios + 1 where negocio_id = p_negocio and cliente_id = p_cliente;
    perform public.cfx_sellos_aviso(p_negocio, p_cliente, c ->> 'premio');
    return jsonb_build_object('cantidad', 0, 'premio', true);
  end if;
  return jsonb_build_object('cantidad', s.cantidad, 'premio', false);
end $$;

-- Al borrar un negocio (lo llama la app): sus cupones, su tarjeta y los sellos de sus clientes.
create or replace function public.cfx_fid_borrar(p_negocio uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.cfx_descuentos where owner_id = p_negocio;
  delete from public.cfx_sellos_cfg where owner_id = p_negocio;
  delete from public.cfx_sellos where negocio_id = p_negocio;
end $$;

revoke all on function public.cfx_desc_codigo(text), public.cfx_fid_mio(text), public.cfx_fid_ok(uuid, text), public.cfx_desc_pct(uuid, text),
  public.cfx_desc_usar(uuid, text), public.cfx_sellos_cfg_de(uuid), public.cfx_sello_sumar(uuid, uuid), public.cfx_fid_borrar(uuid)
  from public, anon, authenticated;
revoke all on function public.cfx_desc_guardar(text, int, date), public.cfx_desc_borrar(uuid), public.cfx_desc_lista(), public.cfx_desc_validar(uuid, text),
  public.cfx_sellos_guardar(int, text), public.cfx_sellos_mios(uuid) from public, anon;
grant execute on function public.cfx_desc_guardar(text, int, date), public.cfx_desc_borrar(uuid), public.cfx_desc_lista(), public.cfx_desc_validar(uuid, text),
  public.cfx_sellos_guardar(int, text), public.cfx_sellos_mios(uuid) to authenticated;
-- ---------- 🛒 Carrito y 🚚 despacho (C17) ----------
-- Carrito guardado en la nube (para recordarle al cliente lo que dejó) y el cálculo del despacho por comuna y al resto de Chile (2.58).
-- Ganchos que pone cada app que lo usa (y 'carrito' en cfx_modulos_app() para el recordatorio):
--   cfx_carrito_puede(u, negocio) bool           ¿u puede guardar carrito en ese negocio? (es su cliente, puede comprar)
--   cfx_carrito_aviso(cliente, negocio, n) bool  manda el recordatorio (push); false = no corresponde (plan, vacaciones…)
-- La app usa: cfx_carrito_vaciar (al crear el pedido), cfx_carritos_recordar (pg_cron, cada hora), cfx_carrito_borrar (al borrar una cuenta).
-- Despacho (sin tabla: cada app guarda su { retiro, gratis_desde, zonas: [{comuna, precio}] } donde quiera):
--   cfx_despacho_limpio(p) → la misma config revisada (o error claro) · cfx_despacho_costo(cfg, entrega, direccion, monto) → {costo, comuna} o {error}
create table if not exists public.cfx_carritos (
  cliente     uuid not null references auth.users (id) on delete cascade,
  negocio     uuid not null,
  items       jsonb not null default '[]'::jsonb,
  actualizado timestamptz not null default now(),
  avisado     timestamptz,
  primary key (cliente, negocio)
);
create index if not exists cfx_carritos_negocio_idx on public.cfx_carritos (negocio);
create index if not exists cfx_carritos_aviso_idx on public.cfx_carritos (actualizado) where avisado is null;
alter table public.cfx_carritos enable row level security;
revoke all on public.cfx_carritos from anon, authenticated;

-- El cliente guarda su carrito (hasta 50 productos). Vacío = se borra.
create or replace function public.cfx_carrito_guardar(p_negocio uuid, p_items jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare l jsonb := '[]'::jsonb; it jsonb; ok boolean := false;
begin
  if auth.uid() is null or p_negocio is null or to_regprocedure('public.cfx_carrito_puede(uuid,uuid)') is null then return; end if;
  execute 'select public.cfx_carrito_puede($1, $2)' into ok using auth.uid(), p_negocio;
  if not coalesce(ok, false) or jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array' then return; end if;
  for it in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) limit 50 loop
    continue when jsonb_typeof(it) <> 'object' or coalesce(it ->> 'clave', '') = '';
    l := l || jsonb_build_object('clave', left(it ->> 'clave', 60), 'cant', least(greatest(coalesce((it ->> 'cant')::int, 1), 1), 99), 'nombre', left(it ->> 'nombre', 80));
  end loop;
  if jsonb_array_length(l) = 0 then
    delete from public.cfx_carritos where cliente = auth.uid() and negocio = p_negocio;
  else
    insert into public.cfx_carritos (cliente, negocio, items) values (auth.uid(), p_negocio, l)
    on conflict (cliente, negocio) do update set items = excluded.items, actualizado = now(), avisado = null
      where public.cfx_carritos.items is distinct from excluded.items;
  end if;
end $$;

create or replace function public.cfx_carrito_vaciar(p_cliente uuid, p_negocio uuid) returns void
language sql security definer set search_path = '' as $$ delete from public.cfx_carritos where cliente = p_cliente and negocio = p_negocio $$;
create or replace function public.cfx_carrito_borrar(p_cuenta uuid) returns void
language sql security definer set search_path = '' as $$ delete from public.cfx_carritos where cliente = p_cuenta or negocio = p_cuenta $$;

-- Cada hora: carritos sin pedir de hace más de 20 horas (y menos de 4 días) reciben UN aviso, de 10 a 20 h de Chile.
create or replace function public.cfx_carritos_recordar() returns int
language plpgsql security definer set search_path = '' as $$
declare r record; n int := 0; ok boolean; h int := extract(hour from now() at time zone 'America/Santiago');
begin
  if h < 10 or h > 20 or not public.cfx_modulo('carrito') or to_regprocedure('public.cfx_carrito_aviso(uuid,uuid,integer)') is null then return 0; end if;
  for r in select * from public.cfx_carritos where avisado is null and actualizado < now() - interval '20 hours' and actualizado > now() - interval '4 days' limit 500 loop
    if not public.cfx_modulo_de('carrito', r.negocio) then  -- G19: la tienda no tiene el módulo (no se vuelve a revisar)
      update public.cfx_carritos set avisado = now() where cliente = r.cliente and negocio = r.negocio; continue;
    end if;
    execute 'select public.cfx_carrito_aviso($1, $2, $3)' into ok using r.cliente, r.negocio, jsonb_array_length(r.items);
    update public.cfx_carritos set avisado = now() where cliente = r.cliente and negocio = r.negocio;
    if coalesce(ok, false) then n := n + 1; end if;
  end loop;
  return n;
end $$;

-- ---------- Despacho por comuna ----------
create or replace function public.cfx_comuna_norm(t text) returns text
language sql immutable set search_path = '' as $$ select lower(trim(translate(coalesce(t, ''), 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun'))) $$;

create or replace function public.cfx_despacho_limpio(p jsonb) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare z jsonb; l jsonb := '[]'::jsonb; vistas text[] := '{}'; rm text;
begin
  if jsonb_typeof(p) is distinct from 'object' then raise exception 'Datos no válidos'; end if;
  for z in select * from jsonb_array_elements(case when jsonb_typeof(p -> 'zonas') = 'array' then p -> 'zonas' else '[]'::jsonb end) loop
    if coalesce(trim(z ->> 'comuna'), '') = '' then continue; end if;
    if length(z ->> 'comuna') > 40 then raise exception 'Nombre de comuna muy largo'; end if;
    if coalesce((z ->> 'precio')::numeric, -1) not between 0 and 200000 then raise exception 'El despacho a % debe costar entre $0 y $200.000', z ->> 'comuna'; end if;
    if public.cfx_comuna_norm(z ->> 'comuna') = any (vistas) then raise exception 'La comuna % está repetida', z ->> 'comuna'; end if;
    vistas := vistas || public.cfx_comuna_norm(z ->> 'comuna');
    l := l || jsonb_build_object('comuna', trim(z ->> 'comuna'), 'precio', round((z ->> 'precio')::numeric));
  end loop;
  if jsonb_array_length(l) > 80 then raise exception 'Máximo 80 comunas'; end if;
  -- Resto de Chile (regiones y comunas que no están en la lista): 'no' | 'fijo' (un precio) | 'por_pagar' (lo paga quien recibe al courier).
  -- G102 b 'courier' = la app cotiza con el courier (Despega: Chilexpress); precio = respaldo si el courier no responde (0 = por pagar).
  rm := coalesce(nullif(p #>> '{resto,modo}', ''), 'no');
  if rm not in ('no', 'fijo', 'por_pagar', 'courier') then raise exception 'Elige cómo despachas al resto de Chile'; end if;
  if rm = 'fijo' and coalesce((p #>> '{resto,precio}')::numeric, -1) not between 0 and 200000 then raise exception 'El despacho al resto de Chile debe costar entre $0 y $200.000'; end if;
  if rm = 'courier' and coalesce((p #>> '{resto,precio}')::numeric, 0) not between 0 and 200000 then raise exception 'El precio de respaldo debe ser entre $0 y $200.000'; end if;
  if not coalesce((p ->> 'retiro')::boolean, true) and jsonb_array_length(l) = 0 and rm = 'no' then raise exception 'Activa el retiro en tienda o agrega al menos una comuna de despacho'; end if;
  if coalesce((p ->> 'gratis_desde')::numeric, 0) not between 0 and 10000000 then raise exception 'Monto de despacho gratis no válido'; end if;
  return jsonb_build_object('retiro', coalesce((p ->> 'retiro')::boolean, true), 'gratis_desde', round(coalesce((p ->> 'gratis_desde')::numeric, 0)), 'zonas', l,
    'resto', jsonb_build_object('modo', rm, 'precio', case when rm in ('fijo', 'courier') then round(coalesce((p #>> '{resto,precio}')::numeric, 0)) else 0 end));
end $$;

-- La comuna va al final de la dirección ("…, Ñuñoa"). Sin zonas ni resto de Chile: se coordina con el negocio ($0 aquí).
-- Comuna fuera de la lista: con resto 'fijo' cobra ese precio; con 'por_pagar' $0 y por_pagar = true (lo paga quien recibe); con 'courier' la app cotiza (G102 b).
create or replace function public.cfx_despacho_costo(p_cfg jsonb, p_entrega text, p_direccion text, p_monto numeric) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare c jsonb := coalesce(p_cfg, '{}'::jsonb); com text; z jsonb; rm text := coalesce(nullif(p_cfg #>> '{resto,modo}', ''), 'no'); orig text;
  gratis boolean := coalesce((p_cfg ->> 'gratis_desde')::numeric, 0) > 0 and p_monto >= (p_cfg ->> 'gratis_desde')::numeric;
begin
  if p_entrega is distinct from 'despacho' or (jsonb_array_length(coalesce(c -> 'zonas', '[]'::jsonb)) = 0 and rm = 'no') then return jsonb_build_object('costo', 0, 'comuna', null); end if;
  orig := left(trim(regexp_replace(coalesce(p_direccion, ''), '^.*,', '')), 60);
  com := public.cfx_comuna_norm(orig);
  select e into z from jsonb_array_elements(coalesce(c -> 'zonas', '[]'::jsonb)) e where public.cfx_comuna_norm(e ->> 'comuna') = com limit 1;
  if z is null then
    if com = '' or position(',' in coalesce(p_direccion, '')) = 0 then return jsonb_build_object('error', 'Escribe la dirección y la comuna de despacho'); end if;
    if rm = 'fijo' then return jsonb_build_object('comuna', orig, 'costo', case when gratis then 0 else greatest(0, coalesce((c #>> '{resto,precio}')::numeric, 0)) end); end if;
    if rm = 'por_pagar' then return jsonb_build_object('comuna', orig, 'costo', 0, 'por_pagar', true); end if;
    -- 'courier': la app reemplaza el costo con la tarifa (cotizar = true). Si la app no cotiza, vale el respaldo (o por pagar si es $0).
    if rm = 'courier' then return jsonb_build_object('comuna', orig, 'cotizar', not gratis, 'respaldo', greatest(0, coalesce((c #>> '{resto,precio}')::numeric, 0)),
      'costo', case when gratis then 0 else greatest(0, coalesce((c #>> '{resto,precio}')::numeric, 0)) end,
      'por_pagar', not gratis and coalesce((c #>> '{resto,precio}')::numeric, 0) = 0); end if;
    return jsonb_build_object('error', 'Esta tienda no despacha a esa comuna. Elige otra comuna o retiro en tienda.');
  end if;
  return jsonb_build_object('comuna', z ->> 'comuna', 'costo', case when gratis then 0 else greatest(0, coalesce((z ->> 'precio')::numeric, 0)) end);
end $$;

-- G96 🛒 Carritos olvidados (módulo 'carrito'): el negocio ve quién dejó productos sin pedir y le escribe por WhatsApp con un toque.
-- Gancho de la app: cfx_carrito_contacto_app(cliente uuid, negocio uuid) → {"nombre", "tel"} (null = no mostrar a ese cliente).
alter table public.cfx_carritos add column if not exists wa_at timestamptz;
create or replace function public.cfx_carritos_mios() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare n uuid := public.cfx_negocio_cuenta(auth.uid()); r record; c jsonb; out jsonb := '[]'::jsonb;
begin
  if n is null then raise exception 'Solo para negocios'; end if;
  if not public.cfx_modulo_de('carrito', n) then raise exception '🛒 Recordar carrito es un módulo 🧩: actívalo en Más → Mi plan y módulos'; end if;
  if to_regprocedure('public.cfx_carrito_contacto_app(uuid,uuid)') is null then return out; end if;
  for r in select * from public.cfx_carritos where negocio = n and actualizado > now() - interval '14 days' order by actualizado desc limit 100 loop
    execute 'select public.cfx_carrito_contacto_app($1, $2)' into c using r.cliente, n;
    continue when c is null;
    out := out || jsonb_build_object('cliente', r.cliente, 'nombre', c ->> 'nombre', 'tel', c ->> 'tel', 'items', r.items,
      'actualizado', r.actualizado, 'avisado', r.avisado, 'wa_at', r.wa_at);
  end loop;
  return out;
end $$;
-- Al tocar 💬 WhatsApp queda anotado (para no escribirle dos veces).
create or replace function public.cfx_carrito_wa(p_cliente uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare n uuid := public.cfx_negocio_cuenta(auth.uid());
begin
  if n is null or not public.cfx_modulo_de('carrito', n) then raise exception 'Sin permiso'; end if;
  update public.cfx_carritos set wa_at = now() where negocio = n and cliente = p_cliente;
end $$;
revoke all on function public.cfx_carritos_mios(), public.cfx_carrito_wa(uuid) from public, anon;
grant execute on function public.cfx_carritos_mios(), public.cfx_carrito_wa(uuid) to authenticated;
revoke all on function public.cfx_carrito_vaciar(uuid, uuid), public.cfx_carrito_borrar(uuid), public.cfx_carritos_recordar(), public.cfx_comuna_norm(text),
  public.cfx_despacho_limpio(jsonb), public.cfx_despacho_costo(jsonb, text, text, numeric) from public, anon, authenticated;
revoke all on function public.cfx_carrito_guardar(uuid, jsonb) from public, anon;
grant execute on function public.cfx_carrito_guardar(uuid, jsonb) to authenticated;
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'cfx-carritos';
  perform cron.schedule('cfx-carritos', '23 * * * *', 'select public.cfx_carritos_recordar()');
exception when others then
  raise notice 'Recordatorio de carritos no programado (%).', sqlerrm;
end $$;
-- ---------- 🧹 Limpieza (C18): una sola lista para el Centro de Mando → Mis aplicaciones → ↻ → 🧹 Respaldo y limpieza ----------
-- Lo del núcleo (claves "n_…") se borra solo cada noche si la limpieza automática está prendida (por defecto sí).
-- Lo propio de cada app viene del gancho cfx_limpieza_app() → [{clave, titulo, detalle, filas}] y cfx_limpiar_app(clave) → int
-- (la app ya lo borra sola con su propio horario; aquí se puede borrar a mano).
create index if not exists cfx_registro_creado_idx on public.cfx_registro (creado);
create index if not exists cfx_errores_ultimo_idx on public.cfx_errores (ultimo);
insert into public.cfx_config (clave, valor) values ('limpieza_auto', 'true') on conflict (clave) do nothing;

create or replace function public.cfx_limpieza_nucleo() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  return jsonb_build_array(
    jsonb_build_object('clave', 'n_registro', 'titulo', 'Registro de cambios', 'detalle', 'Más de 180 días.', 'auto', true,
      'filas', (select count(*) from public.cfx_registro where creado < now() - interval '180 days')),
    jsonb_build_object('clave', 'n_errores', 'titulo', 'Errores de la app', 'detalle', 'Sin repetirse hace más de 30 días.', 'auto', true,
      'filas', (select count(*) from public.cfx_errores where ultimo < now() - interval '30 days')),
    jsonb_build_object('clave', 'n_reportes', 'titulo', 'Reportes del chat ya revisados', 'detalle', 'Más de 90 días.', 'auto', true,
      'filas', (select count(*) from public.cfx_reportes where resuelto and creado < now() - interval '90 days')),
    jsonb_build_object('clave', 'n_carritos', 'titulo', 'Carritos abandonados', 'detalle', 'Sin tocar hace más de 30 días.', 'auto', true,
      'filas', (select count(*) from public.cfx_carritos where actualizado < now() - interval '30 days')));
end $$;

create or replace function public.cfx_limpiar_nucleo(p_clave text) returns int
language plpgsql security definer set search_path = '' as $$
declare n int := 0;
begin
  if p_clave = 'n_registro' then delete from public.cfx_registro where creado < now() - interval '180 days';
  elsif p_clave = 'n_errores' then delete from public.cfx_errores where ultimo < now() - interval '30 days';
  elsif p_clave = 'n_reportes' then delete from public.cfx_reportes where resuelto and creado < now() - interval '90 days';
  elsif p_clave = 'n_carritos' then delete from public.cfx_carritos where actualizado < now() - interval '30 days';
  else return 0; end if;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.cfx_limpieza() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare a jsonb := '[]';
begin
  perform public.admin_check();
  if to_regprocedure('public.cfx_limpieza_app()') is not null then
    execute 'select public.cfx_limpieza_app()' into a;
  end if;
  return public.cfx_limpieza_nucleo() || coalesce(a, '[]');
end $$;

create or replace function public.cfx_limpiar(p_clave text) returns int
language plpgsql security definer set search_path = '' as $$
declare n int := 0;
begin
  perform public.admin_check();
  if p_clave like 'n\_%' then
    if not exists (select 1 from jsonb_array_elements(public.cfx_limpieza_nucleo()) x where x ->> 'clave' = p_clave) then raise exception 'Opción no válida'; end if;
    n := public.cfx_limpiar_nucleo(p_clave);
  elsif to_regprocedure('public.cfx_limpiar_app(text)') is not null then
    execute 'select public.cfx_limpiar_app($1)' into n using p_clave;
  else raise exception 'Opción no válida'; end if;
  perform public.cfx_anotar('limpieza', p_clave || ': ' || coalesce(n, 0) || ' borrados');
  return coalesce(n, 0);
end $$;

-- Cada noche (pg_cron 'cfx-limpieza'): borra lo del núcleo marcado "auto" y anota cuánto.
create or replace function public.cfx_limpieza_auto() returns int
language plpgsql security definer set search_path = '' as $$
declare x jsonb; n int := 0;
begin
  if not coalesce(((select valor from public.cfx_config where clave = 'limpieza_auto') #>> '{}')::boolean, true) then return 0; end if;
  for x in select * from jsonb_array_elements(public.cfx_limpieza_nucleo()) loop
    if (x ->> 'auto')::boolean and (x ->> 'filas')::int > 0 then n := n + public.cfx_limpiar_nucleo(x ->> 'clave'); end if;
  end loop;
  insert into public.cfx_salud (clave, valor, cuando) values ('limpieza', jsonb_build_object('filas', n), now())
  on conflict (clave) do update set valor = excluded.valor, cuando = excluded.cuando;
  if n > 0 then perform public.cfx_anotar('limpieza automática', n || ' filas viejas borradas'); end if;
  return n;
end $$;

-- Interruptor del Centro de Mando: { activo, ultima, filas }.
create or replace function public.cfx_limpieza_auto_ver() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return jsonb_build_object('activo', coalesce(((select valor from public.cfx_config where clave = 'limpieza_auto') #>> '{}')::boolean, true),
    'ultima', (select cuando from public.cfx_salud where clave = 'limpieza'), 'filas', (select (valor ->> 'filas')::int from public.cfx_salud where clave = 'limpieza'));
end $$;
create or replace function public.cfx_limpieza_auto_guardar(p_activo boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_check();
  insert into public.cfx_config (clave, valor) values ('limpieza_auto', to_jsonb(coalesce(p_activo, true)))
  on conflict (clave) do update set valor = excluded.valor;
  perform public.cfx_anotar('limpieza automática', case when coalesce(p_activo, true) then 'prendida' else 'apagada' end);
  return public.cfx_limpieza_auto_ver();
end $$;

revoke all on function public.cfx_limpieza_nucleo(), public.cfx_limpiar_nucleo(text), public.cfx_limpieza_auto() from public, anon, authenticated;
revoke all on function public.cfx_limpieza(), public.cfx_limpiar(text), public.cfx_limpieza_auto_ver(), public.cfx_limpieza_auto_guardar(boolean) from public, anon;
grant execute on function public.cfx_limpieza(), public.cfx_limpiar(text), public.cfx_limpieza_auto_ver(), public.cfx_limpieza_auto_guardar(boolean) to authenticated;
do $$
begin
  if to_regprocedure('public.cfx_limpieza_app()') is not null then revoke all on function public.cfx_limpieza_app() from public, anon, authenticated; end if;
  if to_regprocedure('public.cfx_limpiar_app(text)') is not null then revoke all on function public.cfx_limpiar_app(text) from public, anon, authenticated; end if;
end $$;
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'cfx-limpieza';
  perform cron.schedule('cfx-limpieza', '40 7 * * *', 'select public.cfx_limpieza_auto()');
exception when others then
  raise notice 'Limpieza automática no programada (%).', sqlerrm;
end $$;

-- ---------- Analítica (E24 · E25 · E27): el análisis nocturno lo hace Python en GitHub Actions (SaaS: analisis.yml + analisis/analisis.py) ----------
-- 1) Python lee cfx_analisis_datos() con la conexión del respaldo (solo la base: nadie con cuenta puede llamarla).
-- 2) Calcula tendencias de la app (CM → 📊 Analítica) y, por negocio, clientes que dejaron de comprar y productos quietos (E27).
-- 3) Lo devuelve con cfx_analisis_guardar(): una fila 'app' y una por negocio en cfx_analisis.
-- Ganchos de cada app (opcionales; sin ellos hay solo números generales):
--   cfx_analisis_datos_app() → {ventas: [{n, c, f, m, l: [[clave, cant]]}], clientes: {c: {nombre, tel}}, productos: [{n, k, nombre, stock, creado}],
--                               negocios: [{id, nombre, creado, ingreso}]}
--   cfx_analisis_negocio(u) → uuid del negocio que ve ese usuario (null: ninguno). Módulo 'analisis' (🧩 en el CM).
create table if not exists public.cfx_analisis (clave text primary key, datos jsonb not null default '{}', calculado timestamptz not null default now());
alter table public.cfx_analisis enable row level security;
revoke all on public.cfx_analisis from anon, authenticated;

create or replace function public.cfx_analisis_datos() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare a jsonb; d date := (now() at time zone 'America/Santiago')::date;
begin
  if to_regprocedure('public.cfx_analisis_datos_app()') is not null then execute 'select public.cfx_analisis_datos_app()' into a; end if;
  return jsonb_build_object('hoy', d, 'modulo', public.cfx_modulo('analisis'),
    'usuarios', (select jsonb_build_object('total', count(*),
        'activos7', count(*) filter (where last_sign_in_at > now() - interval '7 days'),
        'activos30', count(*) filter (where last_sign_in_at > now() - interval '30 days'),
        'dias', coalesce((select jsonb_object_agg(x.f, x.n) from (select (created_at at time zone 'America/Santiago')::date f, count(*) n from auth.users
          where created_at > now() - interval '61 days' and deleted_at is null group by 1) x), '{}'))
      from auth.users where deleted_at is null),
    'ingresos', coalesce((select jsonb_object_agg(x.f, x.m) from (select (coalesce(resuelto, creado) at time zone 'America/Santiago')::date f, sum(monto) m
      from public.cfx_pagos where estado = 'aprobado' and coalesce(resuelto, creado) > now() - interval '61 days' and coalesce(resuelto, creado) >= public.cfx_ingresos_desde() group by 1) x), '{}'),
    'premium', (select count(distinct cuenta) from public.cfx_pagos where estado = 'aprobado' and coalesce(resuelto, creado) > now() - interval '30 days'),
    'previo', coalesce((select jsonb_object_agg(clave, datos -> 'mov') from public.cfx_analisis where clave <> 'app' and datos ? 'mov'), '{}'),
    'app', a);
end $$;

create or replace function public.cfx_analisis_guardar(p jsonb) returns int
language plpgsql security definer set search_path = '' as $$
declare n int := 0; k text; v jsonb;
begin
  if jsonb_typeof(p -> 'app') = 'object' then
    insert into public.cfx_analisis (clave, datos, calculado) values ('app', p -> 'app', now())
    on conflict (clave) do update set datos = excluded.datos, calculado = now();
  end if;
  delete from public.cfx_analisis where clave <> 'app' and not (coalesce(p -> 'negocios', '{}') ? clave);
  for k, v in select * from jsonb_each(coalesce(p -> 'negocios', '{}')) loop
    insert into public.cfx_analisis (clave, datos, calculado) values (k, v, now())
    on conflict (clave) do update set datos = excluded.datos, calculado = now();
    n := n + 1;
  end loop;
  perform public.cfx_salud_marca('analisis', jsonb_build_object('negocios', n, 'run', coalesce(p ->> 'run', '')));
  return n;
end $$;
revoke all on function public.cfx_analisis_datos(), public.cfx_analisis_guardar(jsonb) from public, anon, authenticated;

-- Centro de Mando → 📊 Analítica.
create or replace function public.cfx_analisis_app() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return (select datos || jsonb_build_object('calculado', calculado) from public.cfx_analisis where clave = 'app');
end $$;
revoke all on function public.cfx_analisis_app() from public, anon;
grant execute on function public.cfx_analisis_app() to authenticated;

-- Para el negocio (E27): sus clientes en riesgo y productos quietos (sin la foto interna del stock).
create or replace function public.cfx_analisis_mio() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare n uuid;
begin
  if auth.uid() is null or not public.cfx_modulo('analisis') or to_regprocedure('public.cfx_analisis_negocio(uuid)') is null then return null; end if;
  execute 'select public.cfx_analisis_negocio($1)' into n using auth.uid();
  if n is null or not public.cfx_modulo_de('analisis', n) then return null; end if;
  return (select (datos - 'mov') || jsonb_build_object('calculado', calculado) from public.cfx_analisis where clave = n::text);
end $$;
revoke all on function public.cfx_analisis_mio() from public, anon;
grant execute on function public.cfx_analisis_mio() to authenticated;

-- ---------- G32 d · 🔑 Entrar con QR (núcleo): el celular con sesión aprueba y el computador entra sin escribir la clave ----------
-- 1) El computador (sin cuenta) pide un código: cfx_qr_crear → { token (va en el QR), codigo (6 letras para escribir), secreto (solo el PC) }.
-- 2) El celular con sesión lo abre o lo escribe: cfx_qr_ver muestra qué computador es → "Sí, entrar" = cfx_qr_aprobar.
-- 3) El computador pregunta cada 2 s (cfx_qr_estado). Aprobado → la Edge Function (clave de servidor) canjea UNA vez (cfx_qr_canjear)
--    y devuelve un enlace mágico de un solo uso; el computador lo usa y queda con sesión. Vence a los 2 minutos.
create table if not exists public.cfx_login_qr (
  token       text primary key,
  codigo      text not null,
  secreto     text not null,              -- sha256 del secreto (el secreto real solo lo tiene el computador)
  equipo      text,
  user_id     uuid references auth.users(id) on delete cascade,
  aprobado_at timestamptz,
  usado_at    timestamptz,
  created_at  timestamptz not null default now()
);
create index if not exists cfx_login_qr_codigo on public.cfx_login_qr (codigo);
alter table public.cfx_login_qr enable row level security;
revoke all on public.cfx_login_qr from anon, authenticated;

create or replace function public.cfx_qr_crear(p_equipo text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare t text; c text; s text; L text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; b bytea; i int;
begin
  delete from public.cfx_login_qr where created_at < now() - interval '10 minutes';
  if (select count(*) from public.cfx_login_qr where created_at > now() - interval '2 minutes') > 300 then
    return jsonb_build_object('ok', false, 'error', 'Muchos intentos. Espera un minuto.');
  end if;
  t := encode(extensions.gen_random_bytes(18), 'hex');
  s := encode(extensions.gen_random_bytes(24), 'hex');
  loop
    b := extensions.gen_random_bytes(6); c := '';
    for i in 0..5 loop c := c || substr(L, 1 + get_byte(b, i) % length(L), 1); end loop;
    exit when not exists (select 1 from public.cfx_login_qr where codigo = c and usado_at is null);
  end loop;
  insert into public.cfx_login_qr (token, codigo, secreto, equipo)
  values (t, c, encode(extensions.digest(s, 'sha256'), 'hex'), left(nullif(regexp_replace(coalesce(p_equipo, ''), '[^[:alnum:] ·.()-]', '', 'g'), ''), 60));
  return jsonb_build_object('ok', true, 'token', t, 'codigo', c, 'secreto', s, 'vence', 120);
end $$;
grant execute on function public.cfx_qr_crear(text) to anon, authenticated;

-- p = token del QR o el código de 6 letras. Solo códigos de menos de 2 minutos, sin aprobar.
create or replace function public.cfx_qr_buscar(p text) returns public.cfx_login_qr
language sql stable security definer set search_path = '' as $$
  select * from public.cfx_login_qr
  where (token = lower(trim(p)) or codigo = upper(regexp_replace(coalesce(p, ''), '[^A-Za-z0-9]', '', 'g')))
    and created_at > now() - interval '2 minutes' and aprobado_at is null and usado_at is null
  order by created_at desc limit 1 $$;
revoke all on function public.cfx_qr_buscar(text) from public, anon, authenticated;

create or replace function public.cfx_qr_ver(p text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare q public.cfx_login_qr := public.cfx_qr_buscar(p);
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Primero inicia sesión en este celular'); end if;
  if q.token is null then return jsonb_build_object('ok', false, 'error', 'El código venció o no existe. En el computador toca "Otro código".'); end if;
  return jsonb_build_object('ok', true, 'equipo', coalesce(q.equipo, 'Computador'),
    'segundos', greatest(0, 120 - extract(epoch from now() - q.created_at)::int));
end $$;
revoke all on function public.cfx_qr_ver(text) from public, anon;
grant execute on function public.cfx_qr_ver(text) to authenticated;

-- El computador pregunta: esperando | aprobado | vencido (con su secreto: nadie más puede preguntar).
create or replace function public.cfx_qr_estado(p_token text, p_secreto text) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce((select case when usado_at is not null then 'vencido'
                               when aprobado_at is not null and aprobado_at > now() - interval '2 minutes' then 'aprobado'
                               when aprobado_at is null and created_at > now() - interval '2 minutes' then 'esperando'
                               else 'vencido' end
    from public.cfx_login_qr where token = p_token and secreto = encode(extensions.digest(coalesce(p_secreto, ''), 'sha256'), 'hex')), 'vencido') $$;
grant execute on function public.cfx_qr_estado(text, text) to anon, authenticated;


-- ---------- G32 f · 🔒 3 claves malas: no se bloquea la cuenta, solo la clave y el QR; se entra con el enlace al correo (gratis) ----------
-- Se cuenta por correo (exista o no la cuenta: no revela nada). Al entrar con el enlace (amr otp/magiclink) se desbloquea.
create table if not exists public.cfx_login_fallos (
  email      text primary key,
  fallos     int not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.cfx_login_fallos enable row level security;
revoke all on public.cfx_login_fallos from anon, authenticated;

create or replace function public.cfx_login_bloqueado(p_email text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select fallos >= 3 from public.cfx_login_fallos where email = lower(trim(coalesce(p_email, '')))), false) $$;
grant execute on function public.cfx_login_bloqueado(text) to anon, authenticated;

-- Clave mala → suma 1 y responde si quedó bloqueada (y cuántos intentos quedan).
create or replace function public.cfx_login_fallo(p_email text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare e text := lower(trim(coalesce(p_email, ''))); n int;
begin
  if e !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return jsonb_build_object('ok', false); end if;
  delete from public.cfx_login_fallos where updated_at < now() - interval '30 days';
  insert into public.cfx_login_fallos (email, fallos) values (e, 1)
  on conflict (email) do update set fallos = least(public.cfx_login_fallos.fallos + 1, 99), updated_at = now()
  returning fallos into n;
  return jsonb_build_object('ok', true, 'bloqueado', n >= 3, 'quedan', greatest(0, 3 - n));
end $$;
grant execute on function public.cfx_login_fallo(text) to anon, authenticated;

-- Con sesión: clave correcta (sin bloqueo) o entró por el enlace del correo → contador a cero. 'estaba' = venía bloqueada (ofrecer cambiar la clave).
create or replace function public.cfx_login_desbloquear() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare e text := lower(coalesce(auth.jwt() ->> 'email', '')); f int; enlace boolean;
begin
  if auth.uid() is null or e = '' then return jsonb_build_object('ok', false); end if;
  enlace := exists (select 1 from jsonb_array_elements(coalesce(auth.jwt() -> 'amr', '[]'::jsonb)) a where a ->> 'method' in ('otp', 'magiclink', 'email/signup', 'recovery'));
  select fallos into f from public.cfx_login_fallos where email = e;
  if f is null then return jsonb_build_object('ok', true, 'estaba', false); end if;
  if f >= 3 and not enlace then return jsonb_build_object('ok', false, 'bloqueado', true); end if;
  delete from public.cfx_login_fallos where email = e;
  return jsonb_build_object('ok', true, 'estaba', f >= 3);
end $$;
revoke all on function public.cfx_login_desbloquear() from public, anon;
grant execute on function public.cfx_login_desbloquear() to authenticated;

-- Aprobar (celular) y canjear (solo la Edge Function, clave de servidor: marca el código usado UNA vez y entrega el correo).
-- El QR también queda cerrado mientras la cuenta esté protegida.
create or replace function public.cfx_qr_aprobar(p text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare q public.cfx_login_qr := public.cfx_qr_buscar(p);
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Primero inicia sesión en este celular'); end if;
  if public.cfx_login_bloqueado(auth.jwt() ->> 'email') then return jsonb_build_object('ok', false, 'error', '🔒 Tu cuenta está protegida por 3 claves malas. Entra en el computador con el enlace de tu correo.'); end if;
  if q.token is null then return jsonb_build_object('ok', false, 'error', 'El código venció o no existe. En el computador toca "Otro código".'); end if;
  update public.cfx_login_qr set user_id = auth.uid(), aprobado_at = now() where token = q.token and aprobado_at is null;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.cfx_qr_aprobar(text) from public, anon;
grant execute on function public.cfx_qr_aprobar(text) to authenticated;

create or replace function public.cfx_qr_canjear(p_token text, p_secreto text) returns text
language plpgsql security definer set search_path = '' as $$
declare u uuid; m text;
begin
  update public.cfx_login_qr set usado_at = now()
  where token = p_token and secreto = encode(extensions.digest(coalesce(p_secreto, ''), 'sha256'), 'hex')
    and aprobado_at is not null and aprobado_at > now() - interval '2 minutes' and usado_at is null
  returning user_id into u;
  if u is null then return null; end if;
  m := (select email from auth.users where id = u);
  if public.cfx_login_bloqueado(m) then return null; end if;
  return m;
end $$;
revoke all on function public.cfx_qr_canjear(text, text) from public, anon, authenticated;
grant execute on function public.cfx_qr_canjear(text, text) to service_role;

-- ---------- Seguridad (A7): lo que puede hacer alguien sin cuenta (anon) y los buckets de archivos ----------
-- Va al final del núcleo: así alcanza a todas las funciones de la app.
-- 1) En Supabase anon recibe permiso para TODA función nueva ("revoke ... from public" no se lo quita). Las que lo primero que hacen es
--    exigir ser admin igual fallarían: se les quita el permiso a anon (no cambia nada para quien tiene cuenta).
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as fn from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')
      and p.prolang = (select oid from pg_language where lanname = 'plpgsql')
      and substring(lower(p.prosrc) from '\mbegin\M(.*)$') ~ ('^\s*perform\s+' || regexp_replace(lower('public.admin_check()'), '([().])', '\\\1', 'g') || '\s*;')
  loop
    execute 'revoke execute on function ' || f.fn || ' from public, anon';
  end loop;
end $$;
revoke execute on function public.cfx_anotar(text, text) from public, anon;

-- 2) Buckets públicos (se ven con su dirección): solo fotos y de hasta 5 MB, si la app no puso otro límite.
update storage.buckets set file_size_limit = 5242880 where public and file_size_limit is null;
update storage.buckets set allowed_mime_types = array['image/webp', 'image/jpeg', 'image/png'] where public and allowed_mime_types is null;

-- 3) Revisión para el Centro de Mando → Control → 🛡️ Seguridad.
create or replace function public.cfx_seguridad() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return jsonb_build_object(
    'sin_rls', coalesce((select jsonb_agg(c.relname order by c.relname) from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity
        and (has_table_privilege('anon', c.oid, 'select') or has_table_privilege('anon', c.oid, 'insert,update,delete'))), '[]'),
    'anon_escribe', coalesce((select jsonb_agg(p.tablename || ' · ' || lower(p.cmd) order by p.tablename) from pg_policies p
      where p.schemaname = 'public' and p.cmd <> 'SELECT' and (p.roles @> '{anon}' or p.roles @> '{public}')), '[]'),
    'anon_lee', coalesce((select jsonb_agg(distinct p.tablename) from pg_policies p
      where p.schemaname = 'public' and p.cmd in ('SELECT', 'ALL') and (p.roles @> '{anon}' or p.roles @> '{public}')), '[]'),
    'funciones_anon', coalesce((select jsonb_agg(p.proname order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.prokind = 'f' and p.prosecdef and has_function_privilege('anon', p.oid, 'execute')), '[]'),
    'buckets', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'publico', b.public, 'mb', round(b.file_size_limit / 1048576.0, 1),
        'tipos', b.allowed_mime_types,
        'anon_lista', exists (select 1 from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects'
          and p.cmd in ('SELECT', 'ALL') and (p.roles @> '{anon}' or p.roles @> '{public}'))) order by b.id) from storage.buckets b), '[]'),
    'humano', public.cfx_humano() - 'site_key' || jsonb_build_object('activo', coalesce(public.cfx_humano() ->> 'site_key', '') <> ''));
end $$;
revoke all on function public.cfx_seguridad() from public, anon;
grant execute on function public.cfx_seguridad() to authenticated;

-- G87 C · 🔑 Clave temporal: la cuenta que crea el admin (o a la que le restablece la clave) debe crear su clave al entrar.
-- Solo guarda el correo (nunca la clave). El admin la marca; la persona la borra al guardar su clave nueva.
create table if not exists public.cfx_clave_temporal (email text primary key, creado timestamptz not null default now());
alter table public.cfx_clave_temporal enable row level security;
revoke all on public.cfx_clave_temporal from anon, authenticated;
create or replace function public.cfx_clave_temporal_marcar(p_email text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_check();
  if coalesce(p_email, '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Correo no válido'; end if;
  insert into public.cfx_clave_temporal (email) values (lower(trim(p_email))) on conflict (email) do update set creado = now();
  perform public.cfx_anotar('clave temporal', lower(trim(p_email)));
end $$;
create or replace function public.cfx_clave_debo() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.cfx_clave_temporal t join auth.users u on lower(u.email) = t.email where u.id = auth.uid())
$$;
create or replace function public.cfx_clave_cambiada() returns void
language sql security definer set search_path = '' as $$
  delete from public.cfx_clave_temporal where email = (select lower(email) from auth.users where id = auth.uid())
$$;
revoke all on function public.cfx_clave_temporal_marcar(text), public.cfx_clave_debo(), public.cfx_clave_cambiada() from public, anon;
grant execute on function public.cfx_clave_temporal_marcar(text), public.cfx_clave_debo(), public.cfx_clave_cambiada() to authenticated;
-- ---------- G33 🌐 Dominio de CodeFix (núcleo 2.69, se puede volver a correr) ----------
-- El CM (Control → 🌐 Dominio) arma los dominios en Cloudflare y le guarda a cada app su dirección: ej. https://despega.codefix.cl/
-- "activo" = Cloudflare ya lo sirve. Mientras no esté activo (o vacío) todo sigue en workers.dev como hoy.
-- Público (no es secreto): las apps lo usan para armar links, QR y correos.
insert into public.cfx_config (clave, valor) values ('sitio', '{"dominio": "", "url": "", "activo": false}') on conflict (clave) do nothing;
create or replace function public.cfx_sitio() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce((select valor from public.cfx_config where clave = 'sitio'), '{"dominio": "", "url": "", "activo": false}'::jsonb) $$;
revoke all on function public.cfx_sitio() from public;
grant execute on function public.cfx_sitio() to anon, authenticated;
-- Dirección de la app para correos y links del servidor: null si no hay dominio activo (se usa la de siempre).
create or replace function public.cfx_sitio_url() returns text
language sql stable security definer set search_path = '' as $$
  select case when (valor->>'activo')::boolean and coalesce(valor->>'url', '') <> '' then valor->>'url' end
  from public.cfx_config where clave = 'sitio' $$;
revoke all on function public.cfx_sitio_url() from public;
grant execute on function public.cfx_sitio_url() to anon, authenticated;
create or replace function public.cfx_sitio_guardar(p_dominio text, p_url text, p_activo boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare d text := nullif(lower(trim(regexp_replace(coalesce(p_dominio, ''), '^https?://|/.*$|\.$', '', 'gi'))), '');
        u text := nullif(lower(trim(coalesce(p_url, ''))), '');
begin
  perform public.admin_check();
  if d is not null and (d !~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,24}$' or length(d) > 80) then raise exception 'Escribe solo el dominio, ej: codefix.cl'; end if;
  if u is not null and (u !~ '^https://([a-z0-9-]+\.)+[a-z]{2,24}/$' or d is null or right(u, length(d) + 1) <> d || '/') then raise exception 'Dirección no válida'; end if;
  insert into public.cfx_config (clave, valor) values ('sitio', jsonb_build_object('dominio', coalesce(d, ''), 'url', coalesce(u, ''), 'activo', d is not null and u is not null and coalesce(p_activo, false)))
    on conflict (clave) do update set valor = excluded.valor;
  return public.cfx_sitio();
end $$;
revoke all on function public.cfx_sitio_guardar(text, text, boolean) from public, anon;
grant execute on function public.cfx_sitio_guardar(text, text, boolean) to authenticated;
-- ---------- G61 a · 📲 Push insistente (núcleo): cada aviso se reenvía hasta que el celular confirma que llegó ----------
-- La función de la app (enviar/servidor) anota cada envío por dispositivo (cfx_push_anotar) con un "grupo" (= el aviso).
-- El service worker, al recibirlo, confirma (cfx_push_recibido) → se cortan los reenvíos de ese aviso en TODOS los dispositivos.
-- Sin confirmación se reenvía a los 1, 2, 5, 10, 15 y 30 min y luego cada 1 h, hasta 48 h (más es spam: Google/Apple lo bloquean).
-- Abrir la app también corta lo pendiente de ese celular (cfx_push_abri). Suscripción muerta (404/410) → cfx_push_muerto.
create table if not exists public.cfx_push_entrega (
  id          bigserial primary key,
  grupo       uuid not null,
  endpoint    text not null,
  p256dh      text not null,
  auth        text not null,
  payload     text not null,
  intentos    int not null default 0,
  proximo     timestamptz not null default now() + interval '1 minute',
  recibido_at timestamptz,
  created_at  timestamptz not null default now(),
  unique (grupo, endpoint)
);
create index if not exists cfx_push_entrega_prox on public.cfx_push_entrega (proximo) where recibido_at is null;
create index if not exists cfx_push_entrega_end on public.cfx_push_entrega (endpoint);
alter table public.cfx_push_entrega enable row level security;
revoke all on public.cfx_push_entrega from anon, authenticated;

-- p_lista: [{ grupo, endpoint, p256dh, auth, payload }] (solo la función de la app, con la clave de servidor)
create or replace function public.cfx_push_anotar(p_lista jsonb) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  insert into public.cfx_push_entrega (grupo, endpoint, p256dh, auth, payload)
  select (x->>'grupo')::uuid, x->>'endpoint', x->>'p256dh', x->>'auth', x->>'payload'
  from jsonb_array_elements(coalesce(p_lista, '[]'::jsonb)) x
  where x->>'grupo' ~ '^[0-9a-f-]{36}$' and coalesce(x->>'endpoint', '') like 'https://%'
  on conflict (grupo, endpoint) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.cfx_push_anotar(jsonb) from public, anon, authenticated;
grant execute on function public.cfx_push_anotar(jsonb) to service_role;

-- Lo que toca reenviar ahora (y deja agendado el siguiente intento). Limpia lo viejo.
create or replace function public.cfx_push_tomar(p_max int default 200) returns setof public.cfx_push_entrega
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.cfx_push_entrega where created_at < now() - interval '50 hours' or recibido_at < now() - interval '1 day';
  return query
  update public.cfx_push_entrega e set intentos = e.intentos + 1,
    proximo = now() + case e.intentos when 0 then interval '1 minute' when 1 then interval '3 minutes' when 2 then interval '5 minutes'
      when 3 then interval '5 minutes' when 4 then interval '15 minutes' else interval '1 hour' end
  where e.id in (select x.id from public.cfx_push_entrega x where x.recibido_at is null and x.proximo <= now() and x.created_at > now() - interval '48 hours'
                 order by x.proximo limit greatest(1, least(coalesce(p_max, 200), 500)) for update skip locked)
  returning e.*;
end $$;
revoke all on function public.cfx_push_tomar(int) from public, anon, authenticated;
grant execute on function public.cfx_push_tomar(int) to service_role;

-- El service worker confirma que llegó (el grupo es un uuid al azar que solo viaja cifrado en el aviso).
create or replace function public.cfx_push_recibido(p_grupo uuid) returns boolean
language sql security definer set search_path = '' as $$
  with u as (update public.cfx_push_entrega set recibido_at = now() where grupo = p_grupo and recibido_at is null returning 1)
  select count(*) > 0 from u;
$$;
grant execute on function public.cfx_push_recibido(uuid) to anon, authenticated;

-- Abrir la app en un celular = ya vio sus avisos: se corta lo pendiente de ese celular (y de esos avisos en los otros).
create or replace function public.cfx_push_abri(p_endpoint text) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  update public.cfx_push_entrega set recibido_at = now()
  where recibido_at is null and grupo in (select grupo from public.cfx_push_entrega where endpoint = p_endpoint and recibido_at is null);
  get diagnostics n = row_count;
  return n;
end $$;
grant execute on function public.cfx_push_abri(text) to anon, authenticated;

-- Suscripción dada de baja (404/410): no se reintenta más a ese celular.
create or replace function public.cfx_push_muerto(p_endpoint text) returns void
language sql security definer set search_path = '' as $$ delete from public.cfx_push_entrega where endpoint = p_endpoint; $$;
revoke all on function public.cfx_push_muerto(text) from public, anon, authenticated;
grant execute on function public.cfx_push_muerto(text) to service_role;

-- ---------------------------------------------------------------------
-- 🧾 Boleta SII del núcleo (G92, desde Despega): el negocio guarda sus datos de emisor y emite la boleta de una venta.
--   Manual: la emite gratis en el SII y anota el N° (folio). Automática: con su API key de OpenFactura (Haulmer) la boleta
--   electrónica (tipo 39, precios con IVA) sale sola. La API key queda solo en la base (al dueño se le muestran 4 caracteres).
--   Gancho por app: cfx_boleta_negocio_app(p_dueno) → negocio de quien llama (null = sin permiso). Cada app lo redefine DESPUÉS
--   de este bloque; el de aquí no da permiso a nadie. Los montos SIEMPRE salen de la base (la app manda solo la venta: ref).
--   Despega mantiene su boleta_* propia (pedidos de la tienda online).
-- ---------------------------------------------------------------------
create table if not exists public.cfx_boleta_cuentas (
  negocio_id uuid primary key,
  modo       text not null default 'manual' check (modo in ('manual', 'openfactura')),
  apikey     text,
  rut        text not null,
  razon      text not null,
  giro       text not null,
  direccion  text not null,
  comuna     text not null,
  auto       boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.cfx_boleta_cuentas enable row level security;
revoke all on public.cfx_boleta_cuentas from anon, authenticated;
create table if not exists public.cfx_boletas (
  negocio_id uuid not null,
  ref        text not null check (ref ~ '^[A-Za-z0-9_:-]{4,80}$'),
  total      numeric not null default 0,
  folio      text,
  url        text,
  error      text,
  intentos   int not null default 0,
  created_at timestamptz not null default now(),
  primary key (negocio_id, ref)
);
alter table public.cfx_boletas enable row level security;
revoke all on public.cfx_boletas from anon, authenticated;

do $$ begin
  if not exists (select 1 from pg_proc where proname = 'cfx_boleta_negocio_app' and pronamespace = 'public'::regnamespace) then
    execute 'create function public.cfx_boleta_negocio_app(p_dueno boolean) returns uuid language sql stable as $f$ select null::uuid $f$';
  end if;
end $$;

-- RUT normal '12345678-5' o null (dígito verificador con cfx_rut_ok).
create or replace function public.cfx_rut_normal(p text) returns text
language sql immutable set search_path = '' as $$
  select case when public.cfx_rut_ok(r) and r ~ '^[0-9]{7,8}[0-9K]$' then ltrim(left(r, -1), '0') || '-' || right(r, 1) end
  from (select upper(regexp_replace(coalesce(p, ''), '[^0-9kK]', '', 'g')) r) x
$$;

create or replace function public.cfx_boleta_estado() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare n uuid := public.cfx_boleta_negocio_app(false); d boolean := public.cfx_boleta_negocio_app(true) is not null; b public.cfx_boleta_cuentas;
begin
  if n is null then return jsonb_build_object('puede', false); end if;
  select * into b from public.cfx_boleta_cuentas where negocio_id = n;
  return jsonb_build_object('puede', true, 'dueno', d, 'conectado', b.negocio_id is not null, 'modo', coalesce(b.modo, 'manual'), 'rut', b.rut, 'razon', b.razon,
    'giro', b.giro, 'direccion', b.direccion, 'comuna', b.comuna, 'auto', coalesce(b.auto, true), 'fin', case when d then right(b.apikey, 4) end);
end $$;

-- El dueño guarda sus datos (p null = quitar). apikey vacía mantiene la anterior.
create or replace function public.cfx_boleta_guardar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  n uuid := public.cfx_boleta_negocio_app(true); md text := coalesce(p ->> 'modo', 'manual'); rt text := public.cfx_rut_normal(p ->> 'rut');
  k text := nullif(regexp_replace(coalesce(p ->> 'apikey', ''), '\s', '', 'g'), ''); t text;
begin
  if n is null then raise exception 'Solo el dueño del negocio'; end if;
  if p is null then delete from public.cfx_boleta_cuentas where negocio_id = n; return public.cfx_boleta_estado(); end if;
  if md not in ('manual', 'openfactura') then raise exception 'Modo no válido'; end if;
  if rt is null then raise exception 'RUT no válido: revisa el número y el dígito verificador'; end if;
  foreach t in array array['razon', 'giro', 'direccion', 'comuna'] loop
    if length(trim(coalesce(p ->> t, ''))) < 2 then
      raise exception 'Falta %', case t when 'razon' then 'la razón social' when 'giro' then 'el giro' when 'direccion' then 'la dirección' else 'la comuna' end;
    end if;
  end loop;
  if k is not null and k !~ '^[A-Za-z0-9_-]{16,120}$' then raise exception 'Esa no parece una API key de OpenFactura'; end if;
  if md = 'openfactura' and k is null and not exists (select 1 from public.cfx_boleta_cuentas where negocio_id = n and apikey is not null) then
    raise exception 'Pega tu API key de OpenFactura';
  end if;
  insert into public.cfx_boleta_cuentas (negocio_id, modo, apikey, rut, razon, giro, direccion, comuna, auto)
  values (n, md, k, rt, left(trim(p ->> 'razon'), 100), left(trim(p ->> 'giro'), 80), left(trim(p ->> 'direccion'), 70), left(trim(p ->> 'comuna'), 20), coalesce((p ->> 'auto')::boolean, true))
  on conflict (negocio_id) do update set modo = excluded.modo, apikey = coalesce(excluded.apikey, public.cfx_boleta_cuentas.apikey), rut = excluded.rut, razon = excluded.razon,
    giro = excluded.giro, direccion = excluded.direccion, comuna = excluded.comuna, auto = excluded.auto, updated_at = now();
  return public.cfx_boleta_estado();
end $$;

-- Boleta tipo 39 en el formato de OpenFactura. items = [{ nombre, cant, subtotal }]; si suman más que el total, la diferencia va como descuento.
create or replace function public.cfx_boleta_dte(p_items jsonb, p_total numeric, c public.cfx_boleta_cuentas) returns jsonb
language plpgsql stable set search_path = '' as $$
declare det jsonb := '[]'::jsonb; l jsonb; n int := 0; suma numeric := 0; m numeric; q numeric; tot numeric := round(p_total); neto numeric; d numeric;
begin
  for l in select * from jsonb_array_elements(coalesce(p_items, '[]')) loop
    exit when n >= 59;
    q := greatest(coalesce((l ->> 'cant')::numeric, 1), 1); m := round(coalesce((l ->> 'subtotal')::numeric, 0));
    if m <= 0 then continue; end if;
    n := n + 1; suma := suma + m;
    det := det || jsonb_build_object('NroLinDet', n, 'NmbItem', left(coalesce(nullif(trim(l ->> 'nombre'), ''), 'Producto'), 80), 'QtyItem', q, 'PrcItem', round(m / q, 2), 'MontoItem', m);
  end loop;
  if suma < tot then n := n + 1; det := det || jsonb_build_object('NroLinDet', n, 'NmbItem', 'Otros', 'QtyItem', 1, 'PrcItem', tot - suma, 'MontoItem', tot - suma); suma := tot; end if;
  d := suma - tot; neto := round(tot / 1.19);
  return jsonb_build_object('response', jsonb_build_array('FOLIO', 'SELF_SERVICE'), 'dte', jsonb_build_object(
    'Encabezado', jsonb_build_object(
      'IdDoc', jsonb_build_object('TipoDTE', 39, 'Folio', 0, 'FchEmis', to_char(now() at time zone 'America/Santiago', 'YYYY-MM-DD'), 'IndServicio', 3),
      'Emisor', jsonb_build_object('RUTEmisor', c.rut, 'RznSocEmisor', c.razon, 'GiroEmisor', c.giro, 'DirOrigen', c.direccion, 'CmnaOrigen', c.comuna),
      'Receptor', jsonb_build_object('RUTRecep', '66666666-6'),
      'Totales', jsonb_build_object('MntNeto', neto, 'IVA', tot - neto, 'MntTotal', tot)),
    'Detalle', det) || case when d > 0 then jsonb_build_object('DscRcgGlobal', jsonb_build_array(
      jsonb_build_object('NroLinDR', 1, 'TpoMov', 'D', 'GlosaDR', 'Descuento', 'TpoValor', '$', 'ValorDR', d))) else '{}'::jsonb end);
end $$;

create or replace function public.cfx_of_api(p_key text, p_cuerpo jsonb, p_idem text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare st int; c text;
begin
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '15');
  execute 'select status, content from extensions.http(row($1, $2, $3, $4, $5)::extensions.http_request)' into st, c
    using 'POST', 'https://api.haulmer.com/v2/dte/document',
          array[row('apikey', p_key)::extensions.http_header, row('Idempotency-Key', p_idem)::extensions.http_header], 'application/json', p_cuerpo::text;
  return jsonb_build_object('status', st, 'body', case when c ~ '^\s*[\{\[]' then c::jsonb end);
exception when others then
  return jsonb_build_object('status', 0, 'error', sqlerrm);
end $$;

-- Interna (la llama la función de cada app, que ya revisó el permiso y armó los ítems DESDE LA BASE).
-- p_folio = N° anotado a mano (modo manual); null = OpenFactura. Una boleta por venta: si ya tiene folio, la devuelve.
create or replace function public.cfx_boleta_crear(p_negocio uuid, p_ref text, p_items jsonb, p_total numeric, p_folio text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c public.cfx_boleta_cuentas; b public.cfx_boletas; r jsonb; f text; e text; fm text := nullif(regexp_replace(coalesce(p_folio, ''), '\D', '', 'g'), '');
begin
  if p_negocio is null or p_ref !~ '^[A-Za-z0-9_:-]{4,80}$' then raise exception 'Venta no válida'; end if;
  select * into b from public.cfx_boletas where negocio_id = p_negocio and ref = p_ref;
  if b.folio is not null and (b.url is not null or fm is null) then return jsonb_build_object('ok', true, 'folio', b.folio, 'url', b.url); end if;
  if round(coalesce(p_total, 0)) < 1 then raise exception 'La venta no tiene monto'; end if;
  select * into c from public.cfx_boleta_cuentas where negocio_id = p_negocio;
  if fm is not null or c.negocio_id is null or c.modo <> 'openfactura' then
    if fm is null then return jsonb_build_object('ok', false, 'manual', true, 'error', 'Escribe el N° (folio) de la boleta del SII'); end if;
    if length(fm) > 10 then raise exception 'El N° de boleta tiene hasta 10 dígitos'; end if;
    insert into public.cfx_boletas (negocio_id, ref, total, folio) values (p_negocio, p_ref, round(p_total), fm)
    on conflict (negocio_id, ref) do update set folio = excluded.folio, total = excluded.total, error = null;
    return jsonb_build_object('ok', true, 'folio', fm);
  end if;
  if c.apikey is null then raise exception 'Pega tu API key de OpenFactura en 🧾 Boleta SII'; end if;
  r := public.cfx_of_api(c.apikey, public.cfx_boleta_dte(p_items, p_total, c), 'cfx-' || p_negocio::text || '-' || p_ref);
  f := nullif(coalesce(r #>> '{body,FOLIO}', r #>> '{body,folio}'), '');
  if coalesce((r ->> 'status')::int, 0) in (200, 201) and f is not null then
    insert into public.cfx_boletas (negocio_id, ref, total, folio, url) values (p_negocio, p_ref, round(p_total), left(f, 20),
      case when r #>> '{body,SELF_SERVICE,url}' ~ '^https://[^\s"<>]+$' then left(r #>> '{body,SELF_SERVICE,url}', 500) end)
    on conflict (negocio_id, ref) do update set folio = excluded.folio, url = excluded.url, total = excluded.total, error = null
    returning * into b;
    return jsonb_build_object('ok', true, 'folio', b.folio, 'url', b.url);
  end if;
  e := left(coalesce(case when (r ->> 'status')::int = 0 then 'No se pudo conectar con OpenFactura' end,
                     r #>> '{body,error,message}', r #>> '{body,message}', 'OpenFactura respondió ' || coalesce(r ->> 'status', '?')), 200);
  if (r ->> 'status')::int in (401, 403) then e := 'OpenFactura no aceptó la API key'; end if;
  insert into public.cfx_boletas (negocio_id, ref, total, error, intentos) values (p_negocio, p_ref, round(p_total), e, 1)
  on conflict (negocio_id, ref) do update set error = excluded.error, intentos = public.cfx_boletas.intentos + 1;
  return jsonb_build_object('ok', false, 'error', e);
end $$;
revoke all on function public.cfx_boleta_crear(uuid, text, jsonb, numeric, text), public.cfx_of_api(text, jsonb, text) from public, anon, authenticated;
revoke all on function public.cfx_boleta_estado(), public.cfx_boleta_guardar(jsonb) from public, anon;
grant execute on function public.cfx_boleta_estado(), public.cfx_boleta_guardar(jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- CodeFix · 📣 Anuncios (G93 · G87 D). Solo promos PROPIAS (de CodeFix a quienes usan las apps), nunca publicidad de terceros.
--   CM → Control → 📣 Anuncios: Campaña → Conjuntos (a quién) → Anuncios (título, texto, imagen, botón). Se publican en cada app elegida.
--   En la app: tarjeta con ✕ (no vuelve a salir a esa persona) · cuenta vistas, clics y cierres (1 vez por persona).
-- ---------------------------------------------------------------------
create table if not exists public.cfx_anuncios (
  id uuid primary key, campana uuid not null, campana_nombre text not null default '' check (length(campana_nombre) <= 60),
  conjunto text not null default '' check (length(conjunto) <= 60),
  publico text not null default 'todos' check (publico in ('todos', 'negocios', 'clientes', 'premium', 'gratis')),
  titulo text not null check (length(titulo) between 1 and 80), texto text not null default '' check (length(texto) <= 240),
  imagen text not null default '' check (length(imagen) <= 90000 and (imagen = '' or imagen ~ '^https://' or imagen ~ '^data:image/(png|jpeg|webp);base64,')),
  boton text not null default '' check (length(boton) <= 30),
  link text not null default '' check (length(link) <= 500 and (link = '' or link ~ '^(https://|/|#)')),
  desde date, hasta date, activo boolean not null default true, orden int not null default 0, creado timestamptz not null default now());
create index if not exists cfx_anuncios_campana_idx on public.cfx_anuncios (campana);
create table if not exists public.cfx_anuncio_vistos (
  anuncio uuid not null references public.cfx_anuncios (id) on delete cascade, cuenta uuid not null,
  visto timestamptz not null default now(), clic timestamptz, cerrado timestamptz, primary key (anuncio, cuenta));
-- G96 b 📣 Promos del negocio a SUS clientes: misma tabla, con negocio (null = de CodeFix). Solo las ven sus clientes (gancho de la app).
alter table public.cfx_anuncios add column if not exists negocio uuid;
create index if not exists cfx_anuncios_negocio_idx on public.cfx_anuncios (negocio) where negocio is not null;
alter table public.cfx_anuncios enable row level security;
alter table public.cfx_anuncio_vistos enable row level security;
revoke all on public.cfx_anuncios, public.cfx_anuncio_vistos from anon, authenticated;

-- Publicar una campaña completa en ESTA app: reemplaza sus anuncios (los que ya no vienen se borran). Solo admin.
create or replace function public.cfx_anuncios_publicar(p_campana uuid, p_nombre text, p_lista jsonb) returns int
language plpgsql security definer set search_path = '' as $$
declare a jsonb; n int := 0; ids uuid[] := '{}';
begin
  perform public.admin_check();
  if p_campana is null or jsonb_typeof(coalesce(p_lista, 'null')) <> 'array' or jsonb_array_length(p_lista) > 30 then raise exception 'Datos no válidos'; end if;
  for a in select * from jsonb_array_elements(p_lista) loop
    ids := ids || (a ->> 'id')::uuid;
    insert into public.cfx_anuncios as x (id, campana, campana_nombre, conjunto, publico, titulo, texto, imagen, boton, link, desde, hasta, activo, orden)
    values ((a ->> 'id')::uuid, p_campana, left(trim(coalesce(p_nombre, '')), 60), left(trim(coalesce(a ->> 'conjunto', '')), 60), coalesce(nullif(a ->> 'publico', ''), 'todos'),
            left(trim(coalesce(a ->> 'titulo', '')), 80), left(trim(coalesce(a ->> 'texto', '')), 240), trim(coalesce(a ->> 'imagen', '')), left(trim(coalesce(a ->> 'boton', '')), 30),
            trim(coalesce(a ->> 'link', '')), nullif(a ->> 'desde', '')::date, nullif(a ->> 'hasta', '')::date, coalesce((a ->> 'activo')::boolean, true), n)
    on conflict (id) do update set campana = excluded.campana, campana_nombre = excluded.campana_nombre, conjunto = excluded.conjunto, publico = excluded.publico,
      titulo = excluded.titulo, texto = excluded.texto, imagen = excluded.imagen, boton = excluded.boton, link = excluded.link, desde = excluded.desde,
      hasta = excluded.hasta, activo = excluded.activo, orden = excluded.orden
    where x.campana = p_campana;
    n := n + 1;
  end loop;
  delete from public.cfx_anuncios where campana = p_campana and not (id = any (ids));
  perform public.cfx_anotar('anuncios', 'Campaña "' || left(coalesce(p_nombre, ''), 60) || '": ' || n || ' anuncio(s)');
  return n;
end $$;

-- Quitar una campaña de ESTA app (se borran sus anuncios y contadores). Solo admin.
create or replace function public.cfx_anuncios_quitar(p_campana uuid) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  perform public.admin_check();
  delete from public.cfx_anuncios where campana = p_campana; get diagnostics n = row_count;
  perform public.cfx_anotar('anuncios', 'Campaña quitada (' || n || ')');
  return n;
end $$;

-- Resultados por anuncio en ESTA app (vistas, clics, cierres = personas distintas). Solo admin.
create or replace function public.cfx_anuncios_admin() returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform public.admin_check();
  return coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'campana', a.campana, 'titulo', a.titulo, 'activo', a.activo,
    'vistas', (select count(*) from public.cfx_anuncio_vistos v where v.anuncio = a.id),
    'clics', (select count(*) from public.cfx_anuncio_vistos v where v.anuncio = a.id and v.clic is not null),
    'cierres', (select count(*) from public.cfx_anuncio_vistos v where v.anuncio = a.id and v.cerrado is not null)) order by a.creado) from public.cfx_anuncios a where a.negocio is null), '[]');
end $$;

-- G96 b 📣 PROMOS DEL NEGOCIO. Gancho de cada app que tiene clientes con cuenta (y 'promos' en cfx_modulos_app()):
--   cfx_promo_negocios_app(u) jsonb   [{"n": negocio, "nombre": "Barbería Juan"}] de los que u es cliente (sin gancho: ninguno).
-- Módulo 'promos' (con la venta de módulos apagada: Premium). Máx. 3 activas y 10 guardadas por negocio. Validado aquí.
create or replace function public.cfx_promo_negocios(u uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r jsonb;
begin
  if u is null or to_regprocedure('public.cfx_promo_negocios_app(uuid)') is null then return '[]'; end if;
  execute 'select public.cfx_promo_negocios_app($1)' into r using u;
  return case when jsonb_typeof(r) = 'array' then r else '[]' end;
end $$;
create or replace function public.cfx_promos_puede(n uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select n is not null and case when public.cfx_venta_on() and 'promos' = any (public.cfx_modulos_de_app()) then public.cfx_modulo_de('promos', n)
    else public.cfx_negocio_premium(n) end
$$;
-- El negocio de quien llama, solo si es el dueño (null si no).
create or replace function public.cfx_promo_mi_negocio() returns uuid
language sql stable security definer set search_path = '' as $$
  select n from (select public.cfx_negocio_cuenta(auth.uid()) n) x where n is not null and public.cfx_negocio_dueno(n) = auth.uid()
$$;
create or replace function public.cfx_promos_mias() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare n uuid := public.cfx_promo_mi_negocio();
begin
  if n is null then raise exception 'Solo el dueño del negocio'; end if;
  return jsonb_build_object('puede', public.cfx_promos_puede(n), 'lista', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'titulo', a.titulo, 'texto', a.texto,
    'imagen', a.imagen, 'boton', a.boton, 'link', a.link, 'desde', a.desde, 'hasta', a.hasta, 'activo', a.activo,
    'vistas', (select count(*) from public.cfx_anuncio_vistos v where v.anuncio = a.id),
    'clics', (select count(*) from public.cfx_anuncio_vistos v where v.anuncio = a.id and v.clic is not null),
    'cierres', (select count(*) from public.cfx_anuncio_vistos v where v.anuncio = a.id and v.cerrado is not null)) order by a.creado desc)
    from public.cfx_anuncios a where a.negocio = n), '[]'));
end $$;
create or replace function public.cfx_promo_guardar(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare n uuid := public.cfx_promo_mi_negocio(); i uuid := nullif(p ->> 'id', '')::uuid; r uuid; act boolean := coalesce((p ->> 'activo')::boolean, true);
  lk text := trim(coalesce(p ->> 'link', '')); de date := nullif(p ->> 'desde', '')::date; ha date := nullif(p ->> 'hasta', '')::date;
begin
  if n is null then raise exception 'Solo el dueño del negocio'; end if;
  if not public.cfx_promos_puede(n) then raise exception '📣 Promo destacada es un módulo 🧩: actívalo en Mi plan y módulos'; end if;
  if length(trim(coalesce(p ->> 'titulo', ''))) = 0 then raise exception 'Escribe el título de la promo'; end if;
  if lk <> '' and lk !~ '^https://' then raise exception 'El link debe partir con https://'; end if;
  if ha is not null and de is not null and ha < de then raise exception 'La fecha de término es antes del inicio'; end if;
  if i is null and (select count(*) from public.cfx_anuncios where negocio = n) >= 10 then raise exception 'Máximo 10 promos guardadas: borra alguna'; end if;
  if act and (select count(*) from public.cfx_anuncios where negocio = n and activo and id is distinct from i) >= 3 then raise exception 'Máximo 3 promos activas a la vez: pausa alguna'; end if;
  if i is null then
    insert into public.cfx_anuncios (id, campana, negocio, publico, titulo, texto, imagen, boton, link, desde, hasta, activo)
    values (gen_random_uuid(), gen_random_uuid(), n, 'clientes', left(trim(p ->> 'titulo'), 80), left(trim(coalesce(p ->> 'texto', '')), 240), trim(coalesce(p ->> 'imagen', '')),
            case when lk = '' then '' else left(trim(coalesce(nullif(p ->> 'boton', ''), 'Ver')), 30) end, lk, de, ha, act) returning id into r;
  else
    update public.cfx_anuncios set titulo = left(trim(p ->> 'titulo'), 80), texto = left(trim(coalesce(p ->> 'texto', '')), 240), imagen = trim(coalesce(p ->> 'imagen', '')),
      boton = case when lk = '' then '' else left(trim(coalesce(nullif(p ->> 'boton', ''), 'Ver')), 30) end, link = lk, desde = de, hasta = ha, activo = act
    where id = i and negocio = n returning id into r;
    if r is null then raise exception 'Promo no encontrada'; end if;
  end if;
  return r;
end $$;
create or replace function public.cfx_promo_borrar(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare n uuid := public.cfx_promo_mi_negocio();
begin
  if n is null then raise exception 'Solo el dueño del negocio'; end if;
  delete from public.cfx_anuncios where id = p_id and negocio = n;
end $$;
revoke all on function public.cfx_promo_negocios(uuid), public.cfx_promos_puede(uuid), public.cfx_promo_mi_negocio() from public, anon, authenticated;
revoke all on function public.cfx_promos_mias(), public.cfx_promo_guardar(jsonb), public.cfx_promo_borrar(uuid) from public, anon;
grant execute on function public.cfx_promos_mias(), public.cfx_promo_guardar(jsonb), public.cfx_promo_borrar(uuid) to authenticated;

-- Lo que ve la persona: anuncios activos, vigentes, de su público y que no cerró (máx. 3). La app no los pide para admin/socio.
create or replace function public.cfx_anuncios_ver() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid(); hoy date := (now() at time zone 'America/Santiago')::date;
begin
  if u is null then return '[]'; end if;
  -- G96 b: + 📣 promos de los negocios de los que es cliente (con el nombre del negocio en 'de'), después de las de CodeFix.
  return coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'titulo', a.titulo, 'texto', a.texto, 'imagen', a.imagen, 'boton', a.boton, 'link', a.link, 'de', a.de) order by a.k, a.orden, a.creado)
    from (select a.*, case when a.negocio is null then 0 else 1 end k, (select x ->> 'nombre' from jsonb_array_elements(ng) x where x ->> 'n' = a.negocio::text limit 1) de
          from public.cfx_anuncios a, (select public.cfx_promo_negocios(u) ng) g
          where a.activo and (a.desde is null or a.desde <= hoy) and (a.hasta is null or a.hasta >= hoy)
            and not exists (select 1 from public.cfx_anuncio_vistos v where v.anuncio = a.id and v.cuenta = u and v.cerrado is not null)
            and (case when a.negocio is null then a.publico = 'todos' or u in (select d from public.cfx_destinatarios(a.publico) d)
                      else exists (select 1 from jsonb_array_elements(ng) x where x ->> 'n' = a.negocio::text) and public.cfx_promos_puede(a.negocio) end)
          order by case when a.negocio is null then 0 else 1 end, a.orden, a.creado limit 3) a), '[]');
end $$;

-- Marca vista / clic / cierre (una fila por persona y anuncio: no se infla contando de nuevo).
create or replace function public.cfx_anuncio_marcar(p_id uuid, p_que text) returns void
language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid();
begin
  if u is null or p_que not in ('vista', 'clic', 'cierre') or not exists (select 1 from public.cfx_anuncios where id = p_id) then return; end if;
  insert into public.cfx_anuncio_vistos (anuncio, cuenta) values (p_id, u) on conflict do nothing;
  if p_que = 'clic' then update public.cfx_anuncio_vistos set clic = coalesce(clic, now()) where anuncio = p_id and cuenta = u;
  elsif p_que = 'cierre' then update public.cfx_anuncio_vistos set cerrado = coalesce(cerrado, now()) where anuncio = p_id and cuenta = u; end if;
end $$;
revoke all on function public.cfx_anuncios_publicar(uuid, text, jsonb), public.cfx_anuncios_quitar(uuid), public.cfx_anuncios_admin(), public.cfx_anuncios_ver(), public.cfx_anuncio_marcar(uuid, text) from public, anon;
grant execute on function public.cfx_anuncios_publicar(uuid, text, jsonb), public.cfx_anuncios_quitar(uuid), public.cfx_anuncios_admin(), public.cfx_anuncios_ver(), public.cfx_anuncio_marcar(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- G98 ⚡ MERCADO PAGO PROPIO DE CADA NEGOCIO (cobrar a SUS clientes: abonos, arriendos, órdenes…). La plata llega directo al negocio.
--   El dueño pega su Access Token una vez (cfx_mp_neg_guardar; nadie lo puede leer después, ni el equipo ni la app).
--   La app crea un cobro con cfx_mp_neg_cobro(negocio, ref, título, monto, volver, vence) → url de Mercado Pago.
--   Al volver (cfx_mp_neg_revisar(ref)) o cada 1 min (cron 'cfx-mp-neg') la BASE consulta a Mercado Pago: aprobado + CLP + monto
--   completo + n° de pago usado 1 sola vez → marca el cobro pagado y llama al gancho de la app cfx_mp_neg_pagado_app(ref, pago, monto).
--   ref = '<tipo>:<id>' (ej. 'reserva:uuid'); la app decide qué hacer al pagarse (agendar, extender, etc.).
--   Despega tiene su propio mp_cuentas (pedidos) desde antes: no se toca.
-- ---------------------------------------------------------------------
create table if not exists public.cfx_mp_negocio (
  negocio    uuid primary key,
  token      text not null,
  nick       text,
  activo     boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.cfx_mp_negocio enable row level security;
revoke all on public.cfx_mp_negocio from anon, authenticated;

create table if not exists public.cfx_mp_neg_cobros (
  id         uuid primary key default gen_random_uuid(),
  negocio    uuid not null,
  ref        text not null,
  titulo     text,
  monto      int not null check (monto > 0),
  vence      timestamptz,
  pago       text unique,
  pagado_at  timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists cfx_mp_neg_cobros_ref on public.cfx_mp_neg_cobros (ref, created_at desc);
create index if not exists cfx_mp_neg_cobros_pend on public.cfx_mp_neg_cobros (created_at) where pago is null;
alter table public.cfx_mp_neg_cobros enable row level security;
revoke all on public.cfx_mp_neg_cobros from anon, authenticated;

-- El negocio de quien llama, solo si es el dueño (null si no).
create or replace function public.cfx_mp_neg_mio() returns uuid
language sql stable security definer set search_path = '' as $$
  select n from (select public.cfx_negocio_cuenta(auth.uid()) n) x where n is not null and public.cfx_negocio_dueno(n) = auth.uid()
$$;

-- G107: "cobro automático" = su ⚡ Mercado Pago O su 💳 Flow (Webpay). cfx_mp_neg_mp = solo Mercado Pago (suscripciones G106).
create table if not exists public.cfx_flow_negocio (
  negocio    uuid primary key,
  apikey     text not null,
  secret     text not null,
  sandbox    boolean not null default false,
  activo     boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.cfx_flow_negocio enable row level security;
revoke all on public.cfx_flow_negocio from anon, authenticated;
alter table public.cfx_mp_neg_cobros add column if not exists medio text not null default 'mp';
alter table public.cfx_mp_neg_cobros add column if not exists volver text;

create or replace function public.cfx_mp_neg_mp(p_negocio uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.cfx_mp_negocio where negocio = p_negocio and activo)
$$;
create or replace function public.cfx_flow_neg_on(p_negocio uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.cfx_flow_negocio where negocio = p_negocio and activo)
$$;
create or replace function public.cfx_mp_neg_activo(p_negocio uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.cfx_mp_neg_mp(p_negocio) or public.cfx_flow_neg_on(p_negocio)
$$;
-- Para la pantalla del cliente: qué botones mostrar.
create or replace function public.cfx_mp_neg_medios(p_negocio uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('mp', public.cfx_mp_neg_mp(p_negocio), 'flow', public.cfx_flow_neg_on(p_negocio))
$$;

create or replace function public.cfx_mp_neg_estado() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('dueno', n is not null, 'conectado', m.negocio is not null, 'activo', coalesce(m.activo, false), 'nick', m.nick, 'fin', right(m.token, 4))
  from (select public.cfx_mp_neg_mio() n) x left join public.cfx_mp_negocio m on m.negocio = x.n
$$;

-- El dueño conecta (token), activa/pausa (p_activo) o desconecta (sin token y p_activo null).
create or replace function public.cfx_mp_neg_guardar(p_token text, p_activo boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n uuid := public.cfx_mp_neg_mio(); tk text := nullif(regexp_replace(coalesce(p_token, ''), '\s', '', 'g'), ''); r jsonb;
begin
  if n is null then raise exception 'Solo el dueño del negocio'; end if;
  if tk is null then
    if p_activo is null then delete from public.cfx_mp_negocio where negocio = n;
    else
      update public.cfx_mp_negocio set activo = p_activo, updated_at = now() where negocio = n;
      if not found and p_activo then raise exception 'Pega tu Access Token de Mercado Pago'; end if;
    end if;
    return public.cfx_mp_neg_estado();
  end if;
  if tk !~ '^(APP_USR|TEST)-[A-Za-z0-9-]{20,}$' or length(tk) > 300 then raise exception 'Ese no es un Access Token: empieza con APP_USR-'; end if;
  r := public.cfx_mp_api(tk, 'GET', '/users/me');
  if coalesce((r ->> 'status')::int, 0) = 0 then raise exception 'No se pudo conectar con Mercado Pago. Intenta de nuevo.'; end if;
  if (r ->> 'status')::int <> 200 then raise exception 'Mercado Pago no aceptó el token: copia el Access Token de producción'; end if;
  insert into public.cfx_mp_negocio (negocio, token, nick, activo)
  values (n, tk, left(coalesce(r #>> '{body,nickname}', r #>> '{body,email}', ''), 80), coalesce(p_activo, true))
  on conflict (negocio) do update set token = excluded.token, nick = excluded.nick, activo = excluded.activo, updated_at = now();
  return public.cfx_mp_neg_estado();
end $$;

-- La app pide el cobro (solo desde sus funciones; no se llama directo). Devuelve { ok, url } o { ok: false, error }.
-- G107: p_medio 'mp' | 'flow' (null = Mercado Pago si está, si no Flow).
drop function if exists public.cfx_mp_neg_cobro(uuid, text, text, int, text, timestamptz);
create or replace function public.cfx_mp_neg_cobro(p_negocio uuid, p_ref text, p_titulo text, p_monto int, p_volver text, p_vence timestamptz default null, p_medio text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare tk text; c public.cfx_mp_neg_cobros; r jsonb; v text := left(coalesce(p_volver, ''), 500);
        md text := coalesce(p_medio, case when public.cfx_mp_neg_mp(p_negocio) then 'mp' else 'flow' end);
begin
  if md = 'flow' then return public.cfx_flow_neg_cobro(p_negocio, p_ref, p_titulo, p_monto, p_volver, p_vence); end if;
  select token into tk from public.cfx_mp_negocio where negocio = p_negocio and activo;
  if tk is null then return jsonb_build_object('ok', false, 'error', 'Este negocio no tiene Mercado Pago activo'); end if;
  if coalesce(p_monto, 0) < 1 then return jsonb_build_object('ok', false, 'error', 'Monto no válido'); end if;
  if p_vence is not null and p_vence < now() + interval '1 minute' then return jsonb_build_object('ok', false, 'error', 'Se pasó el tiempo para pagar'); end if;
  if exists (select 1 from public.cfx_mp_neg_cobros where ref = p_ref and pago is not null) then return jsonb_build_object('ok', false, 'error', 'Esto ya está pagado'); end if;
  if v !~ '^https://[^\s"<>]+$' then v := null; end if;
  insert into public.cfx_mp_neg_cobros (negocio, ref, titulo, monto, vence) values (p_negocio, left(p_ref, 120), left(coalesce(p_titulo, 'Pago'), 120), p_monto, p_vence)
  returning * into c;
  r := public.cfx_mp_api(tk, 'POST', '/checkout/preferences', jsonb_build_object(
    'items', jsonb_build_array(jsonb_build_object('id', c.id, 'title', c.titulo, 'quantity', 1, 'currency_id', 'CLP', 'unit_price', c.monto)),
    'external_reference', c.id::text,
    'payment_methods', jsonb_build_object('excluded_payment_types', jsonb_build_array(jsonb_build_object('id', 'ticket'))))
    || public.cfx_mp_notif('n:' || c.id::text)
    || case when p_vence is null then '{}'::jsonb else jsonb_build_object('expires', true,
         'expiration_date_to', to_char(p_vence at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS".000+00:00"')) end
    || case when v is null then '{}'::jsonb else jsonb_build_object('back_urls', jsonb_build_object('success', v, 'pending', v, 'failure', v), 'auto_return', 'approved') end);
  if coalesce((r ->> 'status')::int, 0) not in (200, 201) or r #>> '{body,init_point}' is null then
    delete from public.cfx_mp_neg_cobros where id = c.id;
    return jsonb_build_object('ok', false, 'error', 'Mercado Pago no respondió. Intenta de nuevo o usa otro medio de pago.');
  end if;
  return jsonb_build_object('ok', true, 'url', r #>> '{body,init_point}');
end $$;

-- Pregunta a Mercado Pago por UN cobro; si está aprobado (CLP, monto completo, n° no usado) lo marca y llama al gancho de la app.
create or replace function public.cfx_mp_neg_confirmar(p_id uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare c public.cfx_mp_neg_cobros; tk text; r jsonb; pg jsonb;
begin
  select * into c from public.cfx_mp_neg_cobros where id = p_id for update skip locked;
  if c.id is null then return false; end if;
  if c.pago is not null then return true; end if;
  if c.medio = 'flow' then return public.cfx_flow_neg_confirmar(c); end if;  -- G107
  select token into tk from public.cfx_mp_negocio where negocio = c.negocio;
  if tk is null then return false; end if;
  r := public.cfx_mp_api(tk, 'GET', '/v1/payments/search?sort=date_created&criteria=desc&external_reference=' || c.id::text);
  select e into pg from jsonb_array_elements(coalesce(r #> '{body,results}', '[]'::jsonb)) e
  where e ->> 'status' = 'approved' and e ->> 'external_reference' = c.id::text
    and coalesce(e ->> 'currency_id', 'CLP') = 'CLP' and (e ->> 'transaction_amount')::numeric >= c.monto
    and not exists (select 1 from public.cfx_mp_neg_cobros u where u.pago = left(e ->> 'id', 40)) limit 1;
  if pg is null then return false; end if;
  update public.cfx_mp_neg_cobros set pago = left(pg ->> 'id', 40), pagado_at = now() where id = c.id;
  if to_regprocedure('public.cfx_mp_neg_pagado_app(text, text, integer)') is not null then
    execute 'select public.cfx_mp_neg_pagado_app($1, $2, $3)' using c.ref, left(pg ->> 'id', 40), c.monto;
  end if;
  return true;
end $$;

-- Al volver de Mercado Pago: revisa los cobros de esa referencia (la app lo llama dentro de su propia función, con su control de acceso).
create or replace function public.cfx_mp_neg_revisar(p_ref text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare i uuid;
begin
  if exists (select 1 from public.cfx_mp_neg_cobros where ref = p_ref and pago is not null) then return true; end if;
  for i in select id from public.cfx_mp_neg_cobros where ref = p_ref and pago is null and created_at > now() - interval '3 days' order by created_at desc limit 5 loop
    if public.cfx_mp_neg_confirmar(i) then return true; end if;
  end loop;
  return false;
end $$;

create or replace function public.cfx_mp_neg_pagado(p_ref text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.cfx_mp_neg_cobros where ref = p_ref and pago is not null)
$$;

-- Cada 1 min: cobros abiertos de los últimos 2 días (por si la persona no volvió a la página).
create or replace function public.cfx_mp_neg_revisar_pendientes() returns int
language plpgsql security definer set search_path = '' as $$
declare i uuid; n int := 0;
begin
  for i in select id from public.cfx_mp_neg_cobros c where pago is null and created_at > now() - interval '2 days'
             and (vence is null or vence > now() - interval '30 minutes')
             and not exists (select 1 from public.cfx_mp_neg_cobros p where p.ref = c.ref and p.pago is not null)
           order by created_at desc limit 40 loop
    if public.cfx_mp_neg_confirmar(i) then n := n + 1; end if;
  end loop;
  delete from public.cfx_mp_neg_cobros where pago is null and created_at < now() - interval '30 days';
  return n;
end $$;

-- ---------------------------------------------------------------------
-- G107 💳 FLOW PROPIO DE CADA NEGOCIO (Webpay débito/crédito, transferencia y MACH; la plata llega a SU cuenta Flow).
--   Mismo molde que su Mercado Pago: el dueño pega API Key + Secret Key 1 vez (nadie las lee después). El cobro va en
--   cfx_mp_neg_cobros (medio 'flow'), se confirma con getStatusByCommerceId (pagado + CLP + monto completo + n° de Flow 1 vez)
--   al volver, con el aviso de Flow (función ?cfx_mp=n:<id>) y con el cron 'cfx-mp-neg' → mismo gancho cfx_mp_neg_pagado_app.
--   Flow exige el correo de quien paga: el de la persona con sesión; si no hay (invitado), el del dueño (le llega el recibo).
-- ---------------------------------------------------------------------
create or replace function public.cfx_flow_neg_cfg(p_negocio uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('apikey', apikey, 'secret', secret, 'sandbox', sandbox) from public.cfx_flow_negocio where negocio = p_negocio
$$;

create or replace function public.cfx_flow_neg_cobro(p_negocio uuid, p_ref text, p_titulo text, p_monto int, p_volver text, p_vence timestamptz default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare f jsonb; c public.cfx_mp_neg_cobros; r jsonb; v text := left(coalesce(p_volver, ''), 500); n text; em text;
begin
  if not public.cfx_flow_neg_on(p_negocio) then return jsonb_build_object('ok', false, 'error', 'Este negocio no tiene Webpay (Flow) activo'); end if;
  f := public.cfx_flow_neg_cfg(p_negocio);
  if coalesce(p_monto, 0) < 350 then return jsonb_build_object('ok', false, 'error', 'Webpay cobra desde $350. Usa otro medio de pago.'); end if;
  if p_vence is not null and p_vence < now() + interval '1 minute' then return jsonb_build_object('ok', false, 'error', 'Se pasó el tiempo para pagar'); end if;
  if exists (select 1 from public.cfx_mp_neg_cobros where ref = p_ref and pago is not null) then return jsonb_build_object('ok', false, 'error', 'Esto ya está pagado'); end if;
  if v !~ '^https://[^\s"<>]+$' then v := null; end if;
  select email into em from auth.users where id = auth.uid();
  if coalesce(em, '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then select email into em from auth.users where id = public.cfx_negocio_dueno(p_negocio); end if;
  if coalesce(em, '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return jsonb_build_object('ok', false, 'error', 'Falta un correo para Webpay. Usa otro medio de pago.'); end if;
  insert into public.cfx_mp_neg_cobros (negocio, ref, titulo, monto, vence, medio, volver)
  values (p_negocio, left(p_ref, 120), left(coalesce(p_titulo, 'Pago'), 120), p_monto, p_vence, 'flow', v) returning * into c;
  n := public.cfx_mp_notif('n:' || c.id::text) ->> 'notification_url';
  if n is null and v is null then
    delete from public.cfx_mp_neg_cobros where id = c.id;
    return jsonb_build_object('ok', false, 'error', 'Webpay no está listo en esta app. Usa otro medio de pago.');
  end if;
  r := public.cfx_flow_api('POST', '/payment/create', jsonb_build_object('commerceOrder', c.id::text, 'subject', c.titulo,
    'currency', 'CLP', 'amount', c.monto::text, 'email', lower(em), 'paymentMethod', '9',
    'urlConfirmation', coalesce(n, v), 'urlReturn', coalesce(n || '&cfx_volver=1', v))
    || case when p_vence is null then '{}'::jsonb else jsonb_build_object('timeout', greatest(120, least(86400, extract(epoch from p_vence - now())::int))::text) end, f);
  if coalesce((r ->> 'status')::int, 0) <> 200 or coalesce(r #>> '{body,url}', '') !~ '^https://' or coalesce(r #>> '{body,token}', '') = '' then
    delete from public.cfx_mp_neg_cobros where id = c.id;
    return jsonb_build_object('ok', false, 'error', 'Webpay (Flow) no respondió. Intenta de nuevo o usa otro medio de pago.');
  end if;
  return jsonb_build_object('ok', true, 'url', (r #>> '{body,url}') || '?token=' || public.cfx_url_cod(r #>> '{body,token}'));
end $$;

create or replace function public.cfx_flow_neg_confirmar(c public.cfx_mp_neg_cobros) returns boolean
language plpgsql security definer set search_path = '' as $$
declare f jsonb := public.cfx_flow_neg_cfg(c.negocio); r jsonb; b jsonb; nro text;
begin
  if f is null then return false; end if;
  r := public.cfx_flow_api('GET', '/payment/getStatusByCommerceId', jsonb_build_object('commerceId', c.id::text), f);
  b := r -> 'body';
  if coalesce((r ->> 'status')::int, 0) <> 200 or b is null or coalesce((b ->> 'status')::int, 0) <> 2 or b ->> 'commerceOrder' is distinct from c.id::text
     or coalesce(b ->> 'currency', 'CLP') <> 'CLP' or coalesce((b ->> 'amount')::numeric, 0) < c.monto or coalesce(b ->> 'flowOrder', '') = '' then return false; end if;
  nro := 'flow:' || left(b ->> 'flowOrder', 34);
  if exists (select 1 from public.cfx_mp_neg_cobros u where u.pago = nro) then return false; end if;
  update public.cfx_mp_neg_cobros set pago = nro, pagado_at = now() where id = c.id;
  if to_regprocedure('public.cfx_mp_neg_pagado_app(text, text, integer)') is not null then
    execute 'select public.cfx_mp_neg_pagado_app($1, $2, $3)' using c.ref, nro, c.monto;
  end if;
  return true;
end $$;

create or replace function public.cfx_flow_neg_estado() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('dueno', n is not null, 'conectado', f.negocio is not null, 'activo', coalesce(f.activo, false), 'sandbox', coalesce(f.sandbox, false), 'fin', right(f.apikey, 4))
  from (select public.cfx_mp_neg_mio() n) x left join public.cfx_flow_negocio f on f.negocio = x.n
$$;

-- El dueño conecta (llaves), activa/pausa (p_activo) o desconecta (sin llaves y p_activo null).
create or replace function public.cfx_flow_neg_guardar(p_apikey text, p_secret text, p_activo boolean, p_sandbox boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n uuid := public.cfx_mp_neg_mio(); k text := nullif(regexp_replace(coalesce(p_apikey, ''), '\s', '', 'g'), '');
        sc text := nullif(regexp_replace(coalesce(p_secret, ''), '\s', '', 'g'), ''); r jsonb;
begin
  if n is null then raise exception 'Solo el dueño del negocio'; end if;
  if k is null and sc is null then
    if p_activo is null then delete from public.cfx_flow_negocio where negocio = n;
    else
      update public.cfx_flow_negocio set activo = p_activo, updated_at = now() where negocio = n;
      if not found and p_activo then raise exception 'Pega tu API Key y tu Secret Key de Flow'; end if;
    end if;
    return public.cfx_flow_neg_estado();
  end if;
  if k is null or sc is null then raise exception 'Pega las 2 llaves: API Key y Secret Key'; end if;
  if k !~ '^[A-Za-z0-9-]{20,80}$' then raise exception 'Esa no parece una API Key de Flow (Integración → API Keys)'; end if;
  if sc !~ '^[A-Za-z0-9]{20,100}$' then raise exception 'Esa no parece una Secret Key de Flow'; end if;
  r := public.cfx_flow_api('GET', '/payment/getStatusByCommerceId', jsonb_build_object('commerceId', 'cfx-prueba'),
    jsonb_build_object('apikey', k, 'secret', sc, 'sandbox', coalesce(p_sandbox, false)));
  if coalesce((r ->> 'status')::int, 0) = 0 then raise exception 'No se pudo conectar con Flow. Intenta de nuevo.'; end if;
  if (r ->> 'status')::int in (401, 403) then raise exception 'Flow no aceptó las llaves: cópialas de nuevo (¿son de producción o de pruebas?)'; end if;
  insert into public.cfx_flow_negocio (negocio, apikey, secret, sandbox, activo) values (n, k, sc, coalesce(p_sandbox, false), coalesce(p_activo, true))
  on conflict (negocio) do update set apikey = excluded.apikey, secret = excluded.secret, sandbox = excluded.sandbox, activo = excluded.activo, updated_at = now();
  return public.cfx_flow_neg_estado();
end $$;

revoke all on function public.cfx_flow_neg_cfg(uuid), public.cfx_flow_neg_cobro(uuid, text, text, int, text, timestamptz), public.cfx_flow_neg_confirmar(public.cfx_mp_neg_cobros) from public, anon, authenticated;
revoke all on function public.cfx_flow_neg_estado(), public.cfx_flow_neg_guardar(text, text, boolean, boolean) from public, anon;
grant execute on function public.cfx_flow_neg_estado(), public.cfx_flow_neg_guardar(text, text, boolean, boolean) to authenticated;

revoke all on function public.cfx_mp_neg_mio(), public.cfx_mp_neg_activo(uuid), public.cfx_mp_neg_cobro(uuid, text, text, int, text, timestamptz, text),
  public.cfx_mp_neg_mp(uuid), public.cfx_flow_neg_on(uuid), public.cfx_mp_neg_medios(uuid),
  public.cfx_mp_neg_confirmar(uuid), public.cfx_mp_neg_revisar(text), public.cfx_mp_neg_pagado(text), public.cfx_mp_neg_revisar_pendientes() from public, anon, authenticated;
revoke all on function public.cfx_mp_neg_estado(), public.cfx_mp_neg_guardar(text, boolean) from public, anon;
grant execute on function public.cfx_mp_neg_estado(), public.cfx_mp_neg_guardar(text, boolean) to authenticated;
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'cfx-mp-neg';
  perform cron.schedule('cfx-mp-neg', '* * * * *', 'select public.cfx_mp_neg_revisar_pendientes()');
exception when others then
  raise notice 'Revisión de Mercado Pago de los negocios no programada (%).', sqlerrm;
end $$;

-- ---------------------------------------------------------------------
-- G106 ⚡ PAGO AUTOMÁTICO CON TARJETA (suscripción "preapproval" de Mercado Pago, con el MP PROPIO del negocio).
--   La persona autoriza su tarjeta 1 vez en Mercado Pago; MP la cobra sola cada mes, sin que nadie toque nada.
--   La app crea la suscripción con cfx_mp_neg_suscribir(negocio, ref, título, monto, correo, volver, inicio) → url de MP.
--   La BASE pregunta a MP (al volver y con el cron 'cfx-mp-neg'): estado de la suscripción + cobros aprobados (CLP, monto
--   completo, cada cobro 1 sola vez) → gancho de la app cfx_mp_neg_sub_app(ref, evento, pago, monto); evento = 'activa' | 'cobro' | 'cancelada'.
--   cfx_mp_neg_sub_cancelar(ref) la apaga EN Mercado Pago (si MP no responde, no se marca: se reintenta).
-- ---------------------------------------------------------------------
create table if not exists public.cfx_mp_neg_subs (
  id          uuid primary key default gen_random_uuid(),
  negocio     uuid not null,
  ref         text not null,
  titulo      text,
  monto       int not null check (monto > 0),
  preapproval text unique,
  estado      text not null default 'pendiente' check (estado in ('pendiente', 'activa', 'pausada', 'cancelada')),
  cobros      int not null default 0,
  ultimo_at   timestamptz,
  revisado_at timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists cfx_mp_neg_subs_ref on public.cfx_mp_neg_subs (ref, created_at desc);
create index if not exists cfx_mp_neg_subs_viva on public.cfx_mp_neg_subs (revisado_at) where estado <> 'cancelada';
alter table public.cfx_mp_neg_subs enable row level security;
revoke all on public.cfx_mp_neg_subs from anon, authenticated;

create table if not exists public.cfx_mp_neg_sub_pagos (
  id    text primary key,          -- n° del cobro autorizado de MP (1 sola vez)
  sub   uuid not null,
  pago  text,
  monto int not null,
  at    timestamptz not null default now()
);
alter table public.cfx_mp_neg_sub_pagos enable row level security;
revoke all on public.cfx_mp_neg_sub_pagos from anon, authenticated;

create or replace function public._cfx_mp_neg_sub_gancho(p_ref text, p_evento text, p_pago text, p_monto int) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if to_regprocedure('public.cfx_mp_neg_sub_app(text, text, text, integer)') is not null then
    execute 'select public.cfx_mp_neg_sub_app($1, $2, $3, $4)' using p_ref, p_evento, p_pago, p_monto;
  end if;
end $$;

-- La app pide la suscripción (solo desde sus funciones). Devuelve { ok, url } o { ok: false, error }.
create or replace function public.cfx_mp_neg_suscribir(p_negocio uuid, p_ref text, p_titulo text, p_monto int, p_email text, p_volver text, p_inicio timestamptz default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare tk text; s public.cfx_mp_neg_subs; r jsonb; v text := left(coalesce(p_volver, ''), 500); m text := lower(trim(coalesce(p_email, '')));
  ini timestamptz := greatest(coalesce(p_inicio, now()), now() + interval '5 minutes');
begin
  select token into tk from public.cfx_mp_negocio where negocio = p_negocio and activo;
  if tk is null then return jsonb_build_object('ok', false, 'error', 'Este negocio no tiene Mercado Pago activo'); end if;
  if coalesce(p_monto, 0) < 1 then return jsonb_build_object('ok', false, 'error', 'Monto no válido'); end if;
  if m !~ '^[^@\s"<>]+@[^@\s"<>]+\.[a-z]{2,}$' or length(m) > 120 then return jsonb_build_object('ok', false, 'error', 'Escribe el correo de tu cuenta de Mercado Pago'); end if;
  if v !~ '^https://[^\s"<>]+$' then return jsonb_build_object('ok', false, 'error', 'Falta la dirección de regreso'); end if;
  if exists (select 1 from public.cfx_mp_neg_subs where ref = p_ref and estado in ('activa', 'pausada')) then
    return jsonb_build_object('ok', false, 'error', 'Ya tienes el pago automático');
  end if;
  update public.cfx_mp_neg_subs set estado = 'cancelada', updated_at = now() where ref = p_ref and estado = 'pendiente';  -- intento anterior sin autorizar
  insert into public.cfx_mp_neg_subs (negocio, ref, titulo, monto) values (p_negocio, left(p_ref, 120), left(coalesce(p_titulo, 'Pago mensual'), 120), p_monto)
  returning * into s;
  r := public.cfx_mp_api(tk, 'POST', '/preapproval', jsonb_build_object(
    'reason', s.titulo, 'external_reference', s.id::text, 'payer_email', m, 'back_url', v, 'status', 'pending',
    'auto_recurring', jsonb_build_object('frequency', 1, 'frequency_type', 'months', 'currency_id', 'CLP', 'transaction_amount', s.monto,
      'start_date', to_char(ini at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS".000+00:00"'))));
  if coalesce((r ->> 'status')::int, 0) not in (200, 201) or r #>> '{body,init_point}' is null or r #>> '{body,id}' is null then
    delete from public.cfx_mp_neg_subs where id = s.id;
    return jsonb_build_object('ok', false, 'error', coalesce('Mercado Pago: ' || left(r #>> '{body,message}', 160), 'Mercado Pago no respondió. Intenta de nuevo.'));
  end if;
  update public.cfx_mp_neg_subs set preapproval = left(r #>> '{body,id}', 60), revisado_at = now() where id = s.id;
  return jsonb_build_object('ok', true, 'url', r #>> '{body,init_point}');
end $$;

-- Pregunta a MP por UNA suscripción: estado + cobros nuevos. Devuelve cuántos cobros nuevos encontró.
create or replace function public.cfx_mp_neg_sub_revisar(p_id uuid) returns int
language plpgsql security definer set search_path = '' as $$
declare s public.cfx_mp_neg_subs; tk text; r jsonb; e jsonb; nuevo text; n int := 0;
begin
  select * into s from public.cfx_mp_neg_subs where id = p_id for update skip locked;
  if s.id is null or s.preapproval is null or s.estado = 'cancelada' then return 0; end if;
  select token into tk from public.cfx_mp_negocio where negocio = s.negocio;
  if tk is null then return 0; end if;
  update public.cfx_mp_neg_subs set revisado_at = now() where id = s.id;
  r := public.cfx_mp_api(tk, 'GET', '/preapproval/' || s.preapproval);
  if coalesce((r ->> 'status')::int, 0) = 200 then
    nuevo := case r #>> '{body,status}' when 'authorized' then 'activa' when 'paused' then 'pausada' when 'cancelled' then 'cancelada' else s.estado end;
    if nuevo <> s.estado then
      update public.cfx_mp_neg_subs set estado = nuevo, updated_at = now() where id = s.id;
      if nuevo in ('activa', 'cancelada') then perform public._cfx_mp_neg_sub_gancho(s.ref, nuevo, null, s.monto); end if;
    end if;
  end if;
  r := public.cfx_mp_api(tk, 'GET', '/authorized_payments/search?preapproval_id=' || s.preapproval);
  for e in select x from jsonb_array_elements(coalesce(r #> '{body,results}', '[]'::jsonb)) x
           where coalesce(x #>> '{payment,status}', '') = 'approved' and coalesce(x ->> 'preapproval_id', s.preapproval) = s.preapproval
             and coalesce(x ->> 'currency_id', 'CLP') = 'CLP' and coalesce((x ->> 'transaction_amount')::numeric, 0) >= s.monto
             and x ->> 'id' is not null loop
    insert into public.cfx_mp_neg_sub_pagos (id, sub, pago, monto) values (left(e ->> 'id', 40), s.id, left(e #>> '{payment,id}', 40), s.monto)
    on conflict do nothing;
    if found then
      n := n + 1;
      update public.cfx_mp_neg_subs set cobros = cobros + 1, ultimo_at = now(), estado = case when estado = 'pendiente' then 'activa' else estado end, updated_at = now() where id = s.id;
      perform public._cfx_mp_neg_sub_gancho(s.ref, 'cobro', left(coalesce(e #>> '{payment,id}', e ->> 'id'), 40), s.monto);
    end if;
  end loop;
  return n;
end $$;

-- La app revisa las suscripciones de una referencia (al volver de MP), dentro de su propia función con su control de acceso.
create or replace function public.cfx_mp_neg_sub_revisar_ref(p_ref text) returns int
language plpgsql security definer set search_path = '' as $$
declare i uuid; n int := 0;
begin
  for i in select id from public.cfx_mp_neg_subs where ref = p_ref and estado <> 'cancelada' order by created_at desc limit 3 loop
    n := n + public.cfx_mp_neg_sub_revisar(i);
  end loop;
  return n;
end $$;

-- Lo que la app muestra: la suscripción viva más nueva de esa referencia (o null).
create or replace function public.cfx_mp_neg_sub_ver(p_ref text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('estado', estado, 'monto', monto, 'cobros', cobros, 'ultimo', ultimo_at, 'desde', created_at)
  from public.cfx_mp_neg_subs where ref = p_ref and estado <> 'cancelada' order by created_at desc limit 1
$$;

-- Apaga en Mercado Pago todas las suscripciones vivas de esa referencia. false = MP no respondió (no se marca; se reintenta).
create or replace function public.cfx_mp_neg_sub_cancelar(p_ref text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare s public.cfx_mp_neg_subs; tk text; r jsonb; todo boolean := true;
begin
  for s in select * from public.cfx_mp_neg_subs where ref = p_ref and estado <> 'cancelada' for update loop
    select token into tk from public.cfx_mp_negocio where negocio = s.negocio;
    if s.preapproval is not null and tk is not null then
      r := public.cfx_mp_api(tk, 'PUT', '/preapproval/' || s.preapproval, jsonb_build_object('status', 'cancelled'));
      if coalesce((r ->> 'status')::int, 0) not in (200, 201) and coalesce(r #>> '{body,status}', '') <> 'cancelled' then todo := false; continue; end if;
    end if;
    update public.cfx_mp_neg_subs set estado = 'cancelada', updated_at = now() where id = s.id;
  end loop;
  return todo;
end $$;

-- Cron: pendientes (cada 1 min, 2 días; después se dan por abandonadas) · vivas (cada 30 min).
create or replace function public.cfx_mp_neg_subs_revisar() returns int
language plpgsql security definer set search_path = '' as $$
declare i uuid; n int := 0;
begin
  update public.cfx_mp_neg_subs set estado = 'cancelada', updated_at = now() where estado = 'pendiente' and created_at < now() - interval '2 days' and cobros = 0;
  for i in select id from public.cfx_mp_neg_subs where estado <> 'cancelada' and preapproval is not null
             and (revisado_at is null or revisado_at < now() - case when estado = 'pendiente' then interval '1 minute' else interval '30 minutes' end)
           order by revisado_at nulls first limit 30 loop
    n := n + public.cfx_mp_neg_sub_revisar(i);
  end loop;
  return n;
end $$;

revoke all on function public._cfx_mp_neg_sub_gancho(text, text, text, int), public.cfx_mp_neg_suscribir(uuid, text, text, int, text, text, timestamptz),
  public.cfx_mp_neg_sub_revisar(uuid), public.cfx_mp_neg_sub_revisar_ref(text), public.cfx_mp_neg_sub_ver(text), public.cfx_mp_neg_sub_cancelar(text),
  public.cfx_mp_neg_subs_revisar() from public, anon, authenticated;
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'cfx-mp-neg-subs';
  perform cron.schedule('cfx-mp-neg-subs', '* * * * *', 'select public.cfx_mp_neg_subs_revisar()');
exception when others then
  raise notice 'Revisión de pagos automáticos no programada (%).', sqlerrm;
end $$;
-- <<< CFX núcleo

-- G95 🎁 Prueba por botón: los talleres de antes ya partieron con días de Premium de regalo → su correo queda anotado (no se borra).
-- Una sola vez (al actualizar la base): después, cada taller nuevo parte FREE con su botón.
do $$ begin
  if not exists (select 1 from public.cfx_config where clave = 'g95_pruebas') then
    insert into public.cfx_pruebas_usadas (hash, item)
    select public.cfx_hash_correo(p.email), 'pro' from public.perfiles p join public.talleres t on t.owner_id = p.id
    where p.rol = 'taller' and nullif(btrim(p.email), '') is not null
    on conflict do nothing;
    insert into public.cfx_config (clave, valor) values ('g95_pruebas', 'true'::jsonb) on conflict do nothing;
  end if;
end $$;

-- G59 🧩 Packs de BiciTaller: los de fábrica del núcleo son de tienda (aquí saldrían más caros que sueltos) → sin packs por ahora.
-- Solo si siguen los de fábrica: si Josué ya los cambió en el Centro de Mando, no se tocan.
update public.cfx_config set valor = jsonb_set(valor, '{packs}', '{}'::jsonb)
where clave = 'modulos_venta' and valor #>> '{packs,crecer,modulos,4}' = 'carrito';

-- G65 🏭 Servicios de fábrica: todo taller parte con los trabajos más pedidos (solo ajusta precios). FREE opera completo (G39) → 40 servicios.
update public.planes set limites = jsonb_set(limites, '{servicios}', '40') where codigo = 'taller_free' and (limites ->> 'servicios')::int = 5;
update public.planes set beneficios = '["Página de reservas con tu logo y colores", "Hasta 30 reservas online al mes", "40 servicios y 1 promoción", "Abono con comprobante y agenda con bloqueos", "Órdenes de trabajo y calificaciones"]'::jsonb
where codigo = 'taller_free' and beneficios = '["Página de reservas con tu logo y colores", "Hasta 30 reservas online al mes", "5 servicios y 1 promoción", "Abono con comprobante y agenda con bloqueos", "Órdenes de trabajo y calificaciones"]'::jsonb;

-- Lista de fábrica (nombre, precio, minutos, descripción, adicional). Agrega solo los que faltan (por nombre) y hasta el límite del plan.
create or replace function public.taller_fabrica_agregar(tid uuid) returns int
language plpgsql security definer set search_path = '' as $$
declare lim int := coalesce((public.limite_taller(tid, 'servicios'))::int, 40); n int; agregados int := 0; x record;
begin
  select count(*) into n from public.servicios where taller_id = tid;
  for x in select * from (values
    (1, 'Mantención básica', 25000, 60, 'Ajuste de frenos y cambios, lubricación de cadena y revisión general.', false),
    (2, 'Mantención completa', 45000, 120, 'Lavado, engrase de rodamientos, ajuste completo de frenos y cambios.', false),
    (3, 'Mantención full (desarme total)', 70000, 240, 'Se desarma toda la bici: limpieza, engrase y armado completo.', false),
    (4, 'Revisión y diagnóstico', 5000, 20, 'Te decimos qué tiene tu bici y cuánto sale arreglarla.', false),
    (5, 'Lavado y lubricado', 12000, 45, 'Lavado completo de la bici y lubricación de la transmisión.', false),
    (6, 'Reparación de pinchazo', 5000, 20, 'Parche o cambio de cámara (cámara aparte).', false),
    (7, 'Ajuste de frenos', 8000, 30, 'Frenos V-brake, mecánicos o hidráulicos.', false),
    (8, 'Purga de frenos hidráulicos', 15000, 45, 'Por freno. Cambio de líquido y sangrado.', false),
    (9, 'Ajuste de cambios', 8000, 30, 'Cambio delantero y trasero.', false),
    (10, 'Cambio de cables y fundas', 12000, 45, 'Mano de obra (cables y fundas aparte).', false),
    (11, 'Centrado de rueda', 10000, 40, 'Rueda descentrada o con rayos sueltos.', false),
    (12, 'Armado de rueda', 30000, 120, 'Rayado completo de una rueda (rayos aparte).', false),
    (13, 'Instalación tubeless', 12000, 40, 'Por rueda. Cinta, válvula y líquido aparte.', false),
    (14, 'Mantención de horquilla', 30000, 90, 'Cambio de aceite y retenes de la suspensión delantera.', false),
    (15, 'Mantención de amortiguador', 30000, 90, 'Suspensión trasera.', false),
    (16, 'Ajuste de dirección', 8000, 30, 'Juego o ruido en la dirección.', false),
    (17, 'Ajuste de pedalier', 10000, 40, 'Juego o ruido en el eje del pedalier.', false),
    (18, 'Armado de bici nueva', 35000, 120, 'Bici en caja: armado, ajuste y prueba.', false),
    (19, 'Revisión bici eléctrica', 30000, 60, 'Motor, batería, cableado, frenos y cambios.', false),
    (20, 'Cambio de cadena', 5000, 15, 'Mano de obra (cadena aparte).', true),
    (21, 'Cambio de pastillas de freno', 6000, 20, 'Mano de obra por freno (pastillas aparte).', true),
    (22, 'Cambio de neumático o cámara', 4000, 15, 'Mano de obra por rueda.', true),
    (23, 'Instalación de accesorios', 5000, 20, 'Luces, portabultos, guardabarros, parrilla…', true)
  ) as f(o, nombre, precio, minutos, descr, adic) order by o loop
    exit when n >= lim;
    if not exists (select 1 from public.servicios s where s.taller_id = tid and lower(s.nombre) = lower(x.nombre)) then
      insert into public.servicios (taller_id, nombre, precio, duracion_min, descripcion, adicional, orden)
      values (tid, x.nombre, x.precio, x.minutos, x.descr, x.adic, x.o);
      n := n + 1; agregados := agregados + 1;
    end if;
  end loop;
  return agregados;
end $$;
revoke all on function public.taller_fabrica_agregar(uuid) from public, anon, authenticated;

-- Taller nuevo → ya viene con los servicios de fábrica.
create or replace function public.talleres_fabrica_tg() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.taller_fabrica_agregar(new.id);
  return new;
end $$;
drop trigger if exists talleres_fabrica on public.talleres;
create trigger talleres_fabrica after insert on public.talleres for each row execute function public.talleres_fabrica_tg();

-- El dueño puede volver a traer los que borró (Más → Servicios → ✨ Servicios de fábrica).
create or replace function public.taller_servicios_fabrica() returns int
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.mi_taller();
begin
  if tid is null or not public.es_dueno(tid) then raise exception 'Solo el dueño del taller'; end if;
  return public.taller_fabrica_agregar(tid);
end $$;
revoke all on function public.taller_servicios_fabrica() from public, anon;
grant execute on function public.taller_servicios_fabrica() to authenticated;

-- Talleres que todavía no tienen ningún servicio: se les cargan una sola vez.
do $$ declare t record; begin
  for t in select id from public.talleres x where not exists (select 1 from public.servicios s where s.taller_id = x.id) loop
    perform public.taller_fabrica_agregar(t.id);
  end loop;
end $$;

-- =====================================================================
-- G74a 🧾 Orden rápida, presupuesto y Caja/Mostrador (FREE)
-- =====================================================================
-- Orden sin hora (cliente que llega al mesón): queda 🚲 Recibida, sin abono. p_presupuesto = abre como presupuesto.
create or replace function public.taller_orden_nueva(p_nombre text, p_telefono text, p_bici text, p_nota text, p_presupuesto boolean) returns uuid
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); c public.talleres; ahora timestamp; nid uuid;
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  if trim(coalesce(p_nombre, '')) = '' then raise exception 'Escribe el nombre del cliente'; end if;
  select * into c from public.talleres where id = tid;
  ahora := now() at time zone c.zona;
  insert into public.reservas (taller_id, servicio_nombre, precio, fecha, hora, hora_fin, nombre, telefono, tel_norm, bici, nota, origen, estado,
    abono_monto, abono_estado, historial, items, total)
  values (tid, case when coalesce(p_presupuesto, false) then 'Presupuesto' else 'Orden de trabajo' end, 0, ahora::date,
    date_trunc('minute', ahora)::time, date_trunc('minute', ahora)::time + make_interval(mins => c.bloque_min),
    left(trim(p_nombre), 80), left(trim(coalesce(p_telefono, '')), 30), public.tel_norm(p_telefono), left(trim(coalesce(p_bici, '')), 120),
    left(trim(coalesce(p_nota, '')), 500), 'taller', 'recibida', 0, 'sin_abono', public.historial_mas('[]', 'recibida'), '[]'::jsonb, 0)
  returning id into nid;
  return nid;
end $$;
revoke all on function public.taller_orden_nueva(text, text, text, text, boolean) from public, anon;
grant execute on function public.taller_orden_nueva(text, text, text, text, boolean) to authenticated;

-- Caja: cada cobro (venta de mostrador o cobro de una orden) con su medio de pago.
create table if not exists public.caja (
  id         uuid primary key default gen_random_uuid(),
  taller_id  uuid not null references public.talleres (id) on delete cascade,
  fecha      date not null,
  medio      text not null check (medio in ('efectivo', 'transferencia', 'tarjeta')),
  total      int not null default 0 check (total >= 0),
  items      jsonb not null default '[]',
  nombre     text not null default '',
  reserva_id uuid references public.reservas (id) on delete set null,
  stock      boolean not null default false,
  por        uuid,
  created_at timestamptz not null default now()
);
create index if not exists caja_taller_fecha_idx on public.caja (taller_id, fecha);
create unique index if not exists caja_reserva_idx on public.caja (reserva_id) where reserva_id is not null;
alter table public.caja enable row level security;
-- G91 🧾 N° (folio) de la boleta del SII de cada cobro (la boleta automática con OpenFactura llega con el núcleo, Bloque 2).
alter table public.caja add column if not exists boleta text;
alter table public.caja drop constraint if exists caja_boleta_chk;
alter table public.caja add constraint caja_boleta_chk check (boleta is null or boleta ~ '^[0-9]{1,10}$');

create or replace function public.caja_hoy(tid uuid) returns date
language sql stable security definer set search_path = '' as $$ select (now() at time zone t.zona)::date from public.talleres t where t.id = tid $$;
revoke all on function public.caja_hoy(uuid) from public, anon, authenticated;

-- 🛒 Venta de mostrador (sin orden): repuestos/accesorios/servicios. Baja el stock si tiene 📦.
create or replace function public.taller_caja_vender(p_items jsonb, p_medio text, p_nombre text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); its jsonb; tot int; st boolean; nid uuid; bajos text;
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  if p_medio not in ('efectivo', 'transferencia', 'tarjeta') then raise exception 'Elige cómo pagó'; end if;
  if jsonb_typeof(p_items) <> 'array' then raise exception 'Ítems no válidos'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('nombre', left(trim(i ->> 'nombre'), 100), 'cant', greatest(coalesce((i ->> 'cant')::int, 1), 1),
    'precio', greatest(coalesce((i ->> 'precio')::int, 0), 0))), '[]') into its
  from jsonb_array_elements(p_items) i where trim(coalesce(i ->> 'nombre', '')) <> '';
  if jsonb_array_length(its) = 0 then raise exception 'Agrega lo que vendiste'; end if;
  if jsonb_array_length(its) > 50 then raise exception 'Máximo 50 ítems por venta'; end if;
  select coalesce(sum((i ->> 'cant')::int * (i ->> 'precio')::int), 0) into tot from jsonb_array_elements(its) i;
  st := public.taller_tiene('stock');
  insert into public.caja (taller_id, fecha, medio, total, items, nombre, stock, por)
  values (tid, public.caja_hoy(tid), p_medio, tot, its, left(trim(coalesce(p_nombre, '')), 80), st, auth.uid()) returning id into nid;
  if st then
    with uso as (select lower(trim(i ->> 'nombre')) n, sum((i ->> 'cant')::int) c from jsonb_array_elements(its) i group by 1),
    bajo as (
      update public.repuestos p set stock = greatest(p.stock - u.c, 0), updated_at = now()
      from uso u where p.taller_id = tid and lower(trim(p.nombre)) = u.n
      returning p.nombre, p.stock, p.minimo, p.stock + u.c antes)
    select string_agg(nombre, ', ') into bajos from bajo where minimo > 0 and stock <= minimo and antes > minimo;
    if bajos is not null then
      perform public.avisar_taller(tid, '📦 Se está acabando: ' || left(bajos, 80), 'Toca para armar el pedido a tu proveedor', '/taller/#mas/stock');
    end if;
  end if;
  return nid;
end $$;

-- 💵 Cobrar una orden lista (o ya entregada sin cobrar): a pagar = total − abono. Si estaba lista, queda 🎉 entregada.
create or replace function public.taller_caja_cobrar(p_reserva uuid, p_medio text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); r public.reservas; monto int;
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  if p_medio not in ('efectivo', 'transferencia', 'tarjeta') then raise exception 'Elige cómo pagó'; end if;
  select * into r from public.reservas where id = p_reserva and taller_id = tid for update;
  if r.id is null then raise exception 'Orden no encontrada'; end if;
  if r.estado not in ('lista', 'completada') then raise exception 'Primero deja la bici ✅ Lista'; end if;
  if exists (select 1 from public.caja where reserva_id = r.id) then raise exception 'Esta orden ya está cobrada'; end if;
  monto := greatest(coalesce(r.total, 0) - case when r.abono_estado in ('pagado', 'aplicado') then coalesce(r.abono_monto, 0) else 0 end, 0);
  insert into public.caja (taller_id, fecha, medio, total, items, nombre, reserva_id, por)
  values (tid, public.caja_hoy(tid), p_medio, monto, coalesce(r.items, '[]'), left(r.nombre || coalesce(nullif(' · 🚲 ' || r.bici, ' · 🚲 '), ''), 80), r.id, auth.uid());
  if r.estado = 'lista' then perform public.taller_estado(r.id, 'completada'); end if;
  return jsonb_build_object('monto', monto);
end $$;

-- 🧾 Caja del día: cobros, total por medio y órdenes por cobrar.
create or replace function public.taller_caja(p_fecha date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); f date;
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  f := coalesce(p_fecha, public.caja_hoy(tid));
  return jsonb_build_object('fecha', f, 'hoy', public.caja_hoy(tid),
    'cobros', (select coalesce(jsonb_agg(jsonb_build_object('id', k.id, 'medio', k.medio, 'total', k.total, 'items', k.items, 'nombre', k.nombre,
        'reserva', k.reserva_id, 'hora', to_char(k.created_at at time zone t.zona, 'HH24:MI'), 'at', k.created_at, 'boleta', k.boleta, 'boleta_url', k.boleta_url,
        'tel', (select r.telefono from public.reservas r where r.id = k.reserva_id)) order by k.created_at desc), '[]')
      from public.caja k join public.talleres t on t.id = k.taller_id where k.taller_id = tid and k.fecha = f),
    'medios', (select jsonb_build_object('efectivo', coalesce(sum(total) filter (where medio = 'efectivo'), 0),
        'transferencia', coalesce(sum(total) filter (where medio = 'transferencia'), 0), 'tarjeta', coalesce(sum(total) filter (where medio = 'tarjeta'), 0),
        'total', coalesce(sum(total), 0), 'n', count(*))
      from public.caja where taller_id = tid and fecha = f),
    'por_cobrar', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'nombre', r.nombre, 'bici', r.bici, 'estado', r.estado,
        'a_pagar', greatest(coalesce(r.total, 0) - case when r.abono_estado in ('pagado', 'aplicado') then coalesce(r.abono_monto, 0) else 0 end, 0)) order by r.lista_at nulls last), '[]')
      from public.reservas r where r.taller_id = tid and (r.estado = 'lista' or (r.estado = 'completada' and r.completada_at > now() - interval '3 days'))
        and not exists (select 1 from public.caja k where k.reserva_id = r.id)));
end $$;

-- Anular un cobro equivocado (solo el dueño): devuelve el stock si la venta lo bajó.
create or replace function public.taller_caja_anular(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.mi_taller(); k public.caja;
begin
  if tid is null or not public.es_dueno(tid) then raise exception 'Solo el dueño puede anular un cobro'; end if;
  delete from public.caja where id = p_id and taller_id = tid returning * into k;
  if k.id is null then raise exception 'Cobro no encontrado'; end if;
  if k.stock then
    update public.repuestos p set stock = p.stock + u.c, updated_at = now()
    from (select lower(trim(i ->> 'nombre')) n, sum((i ->> 'cant')::int) c from jsonb_array_elements(k.items) i group by 1) u
    where p.taller_id = tid and lower(trim(p.nombre)) = u.n;
  end if;
end $$;
-- G91 🧾 Anotar (o quitar, con '') el N° de la boleta del SII de un cobro: todo el equipo.
create or replace function public.taller_caja_boleta(p_id uuid, p_folio text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); f text := nullif(regexp_replace(coalesce(p_folio, ''), '\D', '', 'g'), '');
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  if f is not null and length(f) > 10 then raise exception 'El N° de boleta tiene hasta 10 dígitos'; end if;
  update public.caja set boleta = f where id = p_id and taller_id = tid;
  if not found then raise exception 'Cobro no encontrado'; end if;
  return jsonb_build_object('ok', true, 'boleta', f);
end $$;
revoke all on function public.taller_caja_boleta(uuid, text) from public, anon;
grant execute on function public.taller_caja_boleta(uuid, text) to authenticated;
-- G92 🧾 Boleta SII del núcleo (nucleo/sql/boleta.sql): gancho = el taller de quien llama (p_dueno: solo el dueño configura).
create or replace function public.cfx_boleta_negocio_app(p_dueno boolean) returns uuid
language sql stable security definer set search_path = '' as $$
  select t from (select public.taller_de(auth.uid()) t) x where t is not null and (not p_dueno or public.es_dueno(t))
$$;
alter table public.caja add column if not exists boleta_url text;
-- Emite (OpenFactura) o anota (p_folio, manual) la boleta de un cobro. Los montos salen de la base. Todo el equipo.
create or replace function public.taller_caja_boleta_sii(p_id uuid, p_folio text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.cfx_boleta_negocio_app(false); k public.caja; r jsonb;
begin
  if tid is null then raise exception 'Sin acceso'; end if;
  select * into k from public.caja where id = p_id and taller_id = tid for update;
  if k.id is null then raise exception 'Cobro no encontrado'; end if;
  r := public.cfx_boleta_crear(tid, 'caja-' || k.id::text,
    (select coalesce(jsonb_agg(jsonb_build_object('nombre', i ->> 'nombre', 'cant', greatest(coalesce((i ->> 'cant')::numeric, 1), 1),
      'subtotal', greatest(coalesce((i ->> 'cant')::numeric, 1), 1) * greatest(coalesce((i ->> 'precio')::numeric, 0), 0))), '[]') from jsonb_array_elements(k.items) i),
    k.total, p_folio);
  if (r ->> 'ok')::boolean then update public.caja set boleta = case when r ->> 'folio' ~ '^[0-9]{1,10}$' then r ->> 'folio' end, boleta_url = r ->> 'url' where id = k.id; end if;
  return r;
end $$;
-- ⚡ Automática: con OpenFactura y "Emitir sola al cobrar", cada cobro nuevo sale con boleta. Si falla, el cobro queda igual
-- (se reintenta con 🧾 → ⚡ Emitir en la Caja).
create or replace function public.taller_caja_boleta_auto() returns trigger
language plpgsql security definer set search_path = '' as $$
declare r jsonb;
begin
  if new.total < 1 or not exists (select 1 from public.cfx_boleta_cuentas c where c.negocio_id = new.taller_id and c.modo = 'openfactura' and c.auto and c.apikey is not null) then return null; end if;
  begin
    r := public.cfx_boleta_crear(new.taller_id, 'caja-' || new.id::text,
      (select coalesce(jsonb_agg(jsonb_build_object('nombre', i ->> 'nombre', 'cant', greatest(coalesce((i ->> 'cant')::numeric, 1), 1),
        'subtotal', greatest(coalesce((i ->> 'cant')::numeric, 1), 1) * greatest(coalesce((i ->> 'precio')::numeric, 0), 0))), '[]') from jsonb_array_elements(new.items) i),
      new.total, null);
    if (r ->> 'ok')::boolean then
      update public.caja set boleta = case when r ->> 'folio' ~ '^[0-9]{1,10}$' then r ->> 'folio' end, boleta_url = r ->> 'url' where id = new.id;
    end if;
  exception when others then null;
  end;
  return null;
end $$;
drop trigger if exists caja_boleta_auto on public.caja;
create trigger caja_boleta_auto after insert on public.caja for each row execute function public.taller_caja_boleta_auto();
revoke all on function public.cfx_boleta_negocio_app(boolean), public.taller_caja_boleta_sii(uuid, text) from public, anon;
grant execute on function public.taller_caja_boleta_sii(uuid, text) to authenticated;
revoke all on function public.taller_caja_vender(jsonb, text, text), public.taller_caja_cobrar(uuid, text), public.taller_caja(date), public.taller_caja_anular(uuid) from public, anon;
grant execute on function public.taller_caja_vender(jsonb, text, text), public.taller_caja_cobrar(uuid, text), public.taller_caja(date), public.taller_caja_anular(uuid) to authenticated;

-- ============ G74c ⭐ Módulo Reseñas en Google ============
-- El dueño pega el link de Google (Maps → tu negocio → Pedir reseñas). Se puede guardar siempre (para no perderlo),
-- pero solo se le muestra al cliente si el taller tiene el módulo 'resenas' (reserva_calificar).
create or replace function public.taller_google_guardar(p_link text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare tid uuid := public.taller_de(auth.uid()); l text := nullif(trim(coalesce(p_link, '')), '');
begin
  if tid is null or not public.es_dueno(tid) then raise exception 'Solo el dueño del taller puede cambiar esto'; end if;
  if l is not null and l !~ '^https://[^ <>"]+$' then raise exception 'El link de Google debe empezar con https://'; end if;
  update public.talleres set google_resenas = left(l, 300) where id = tid;
  return jsonb_build_object('ok', true, 'google_resenas', left(l, 300));
end $$;
revoke all on function public.taller_google_guardar(text) from public, anon;
grant execute on function public.taller_google_guardar(text) to authenticated;

-- G98 ⚡ ABONO CON EL MERCADO PAGO DEL TALLER (núcleo mp_negocio.sql): el dueño lo conecta en Más → 💳 Abono.
-- El cliente toca "⚡ Pagar abono con Mercado Pago" en /r/ → al confirmarlo la BASE con Mercado Pago, la reserva queda CONFIRMADA sola.
-- G107: p_medio 'mp' | 'flow' (💳 Webpay con el Flow del taller); null = el que tenga.
drop function if exists public.reserva_mp_pagar(text, text);
create or replace function public.reserva_mp_pagar(p_token text, p_volver text, p_medio text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r public.reservas; c public.talleres; x jsonb;
begin
  select * into r from public.reservas where token = p_token and length(p_token) >= 20;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'Reserva no encontrada'); end if;
  r := public.reserva_estado_vencido(r);
  if r.estado <> 'por_pagar' or r.abono_monto < 1 then return jsonb_build_object('ok', false, 'error', 'Esta reserva ya no espera el abono'); end if;
  select * into c from public.talleres where id = r.taller_id;
  x := public.cfx_mp_neg_cobro(c.owner_id, 'reserva:' || r.id, left('Abono ' || coalesce(c.nombre, 'taller') || ' · ' || to_char(r.fecha, 'DD/MM') || ' ' || to_char(r.hora, 'HH24:MI'), 120),
                               r.abono_monto, p_volver, r.expira_at, case when p_medio in ('mp', 'flow') then p_medio end);
  if (x ->> 'ok')::boolean then update public.reservas set mp_desde = coalesce(mp_desde, now()) where id = r.id; end if;
  return x;
end $$;
create or replace function public.reserva_mp_revisar(p_token text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r public.reservas;
begin
  select * into r from public.reservas where token = p_token and length(p_token) >= 20;
  if r.id is not null and r.mp_desde is not null and r.estado = 'por_pagar' then perform public.cfx_mp_neg_revisar('reserva:' || r.id); end if;
  return public.reserva_ver(p_token);
end $$;
-- Gancho del núcleo: Mercado Pago confirmó el abono. Si la hora ya se había liberado → abono por devolver (el taller lo ve y avisa).
create or replace function public.cfx_mp_neg_pagado_app(p_ref text, p_pago text, p_monto int) returns void
language plpgsql security definer set search_path = '' as $$
declare r public.reservas;
begin
  if p_ref !~ '^reserva:[0-9a-f-]{36}$' then return; end if;
  select * into r from public.reservas where id = substr(p_ref, 9)::uuid for update;
  if r.id is null or r.mp_pago is not null then return; end if;
  if r.estado = 'por_pagar' then
    update public.reservas set estado = 'confirmada', abono_estado = 'pagado', mp_pago = p_pago, comprobante_at = now(), expira_at = null,
      historial = public.historial_mas(historial, 'confirmada'), updated_at = now() where id = r.id;
    perform public.avisar(r.cliente_id, '✅ Reserva confirmada', to_char(r.fecha, 'DD/MM') || ' ' || to_char(r.hora, 'HH24:MI') || case when p_pago like 'flow:%' then ' · 💳 abono pagado con Webpay' else ' · ⚡ abono pagado con Mercado Pago' end, '/r/?t=' || r.token);
    perform public.avisar_taller(r.taller_id, case when p_pago like 'flow:%' then '💳 Abono pagado con Webpay' else '⚡ Abono pagado con Mercado Pago' end, r.nombre || ' · ' || to_char(r.fecha, 'DD/MM') || ' ' ||
      to_char(r.hora, 'HH24:MI') || ' · $' || p_monto || ' · reserva confirmada', '/taller/#reservas');
  else
    update public.reservas set mp_pago = p_pago, abono_estado = 'devolver', updated_at = now() where id = r.id;
    perform public.avisar_taller(r.taller_id, '⚡ Abono que llegó tarde', r.nombre || ' pagó $' || p_monto || case when p_pago like 'flow:%' then ' por Webpay' else ' por Mercado Pago' end || ' cuando la hora ya estaba libre: devuélvelo.', '/taller/#reservas');
  end if;
end $$;
revoke all on function public.cfx_mp_neg_pagado_app(text, text, int) from public, anon, authenticated;
revoke all on function public.reserva_mp_pagar(text, text, text), public.reserva_mp_revisar(text) from public;
grant execute on function public.reserva_mp_pagar(text, text, text), public.reserva_mp_revisar(text) to anon, authenticated;
-- =====================================================================
--  BiciTaller · Tareas automáticas (pégalo en Supabase → SQL Editor → Run,
--  DESPUÉS de schema.sql y de crear la función "servidor").
--   · Cada 5 minutos: libera horas sin pago, recordatorios, avisos de vencimiento, limpieza diaria.
--   · Cada minuto: envía por push los avisos nuevos de la campanita.
-- =====================================================================
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

select cron.unschedule(jobid) from cron.job where jobname in ('bt-tareas', 'bt-push');

select cron.schedule('bt-tareas', '*/5 * * * *', $$ select public.tareas_periodicas(); $$);

-- v2.0: la app ya no se actualiza apenas se publica: llega a los usuarios cuando la liberas (Admin → Actualizar, o Centro de Mando → Apps).
insert into public.config (clave, valor) values ('version_liberada', '"2.7"') on conflict (clave) do nothing;

-- =====================================================================
-- Actualización automática (núcleo CodeFix): cada 10 minutos la base revisa GitHub (rama main).
--   · Si hay una base nueva (version.json), descarga y ejecuta este mismo instalar.sql (no borra datos).
--   · Si solo cambió la app, la libera para que los celulares se actualicen solos.
--   Si algo falla no cambia nada y lo reintenta en la siguiente vuelta. Hay que correr este archivo UNA vez.
-- =====================================================================
create or replace function public.auto_actualizar() returns text
language plpgsql security definer set search_path = '' as $f$
declare
  base constant text := 'https://raw.githubusercontent.com/CodeFixService/Taller/main/';
  marca text := '?t=' || extract(epoch from now())::bigint; j jsonb; v_bd text; v_app text; codigo text; lib text;
  re constant text := '^[0-9]+(\.[0-9]+)*$';
begin
  execute 'select content from extensions.http_get($1)' into codigo using base || 'version.json' || marca;
  j := codigo::jsonb; v_bd := j ->> 'bd'; v_app := j ->> 'version';
  if v_bd ~ re and coalesce((public.db_version())::text, '0') ~ re and string_to_array(v_bd, '.')::int[] > string_to_array(coalesce((public.db_version())::text, '0'), '.')::int[] then
    execute 'select content from extensions.http_get($1)' into codigo using base || 'supabase/instalar.sql' || marca;
    if codigo is null or length(codigo) < 1000 then return 'instalar.sql no disponible'; end if;
    execute codigo;
    return 'base actualizada a ' || (public.db_version())::text;
  end if;
  return 'al día';
exception when others then
  return 'sin cambios: ' || sqlerrm;
end $f$;
revoke execute on function public.auto_actualizar() from public, anon, authenticated;
do $$
begin
  create extension if not exists http with schema extensions;
  perform cron.unschedule(jobid) from cron.job where jobname = 'cfx-auto';
  perform cron.schedule('cfx-auto', '*/10 * * * *', 'select public.auto_actualizar()');
exception when others then
  raise notice 'Actualización automática no activada (%). Activa pg_cron en Supabase y vuelve a correr este archivo.', sqlerrm;
end $$;

-- G99 a ⚡ Dónde avisa Mercado Pago (núcleo cfx_mp_notif): esta misma función "servidor".
create or replace function public.cfx_mp_aviso_url_app() returns text language sql immutable as $f$ select 'https://iwvjthcmufirbnotgixi.supabase.co/functions/v1/servidor' $f$;
revoke all on function public.cfx_mp_aviso_url_app() from public, anon, authenticated;

select cron.schedule('bt-push', '* * * * *', $$
  select net.http_post(
    url := 'https://iwvjthcmufirbnotgixi.supabase.co/functions/v1/servidor',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml3dmp0aGNtdWZpcmJub3RnaXhpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIwMDU1MjMsImV4cCI6MjEwNzU4MTUyM30.54Hc89HlUejofX3knvL4nXDNCphsrZeQG7m50jEIlfw"}'::jsonb,
    body := '{}'::jsonb)
$$);
