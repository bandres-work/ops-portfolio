-- ============================================================
-- LA LUJANETA – EVENT OPS SYSTEM (BOOTSTRAP SQL) – PRO OPERATIVO
-- Supabase Postgres (free tier)
--
-- Incluye:
-- - Modelo de datos núcleo
-- - IDs humanos (public_id) auto-generados
-- - Campos por evento (experiencia, fitness, rol, salida, kit, restricciones)
-- - Alergias en participants
-- - Triggers operativos (kit, checked_in_at, kit_delivered_at, updated_at)
-- - Auditoría (verified_at/by, email_qr_sent_at, etc.)
-- - Índices performance
-- - RLS + roles + policies
-- - Función segura para verificación Ops
-- - Queries fallback (DNI / phone / token)
-- - Evento de prueba
-- ============================================================

-- 0) Extensión para UUID
create extension if not exists "pgcrypto";

-- ============================================================
-- 1) ENUMS BASE (ESTADOS CERRADOS)
-- ============================================================

-- Estado de pago de la inscripción
do $$ begin
  create type public.payment_status as enum (
    'Submitted',      -- Pago registrado pero no verificado
    'Verified',     -- Pago confirmado y aprobado
    'Rejected',     -- Pago rechazado
    'Refunded'      -- Pago devuelto
  );
exception when duplicate_object then null; end $$;

-- Estado de registro del participante
do $$ begin
  create type public.registration_status as enum (
    'Registered',   -- Participante registrado correctamente
    'Cancelled',    -- Inscripción cancelada
    'Blocked'       -- Inscripción bloqueada (por problemas o restricciones)
  );
exception when duplicate_object then null; end $$;

-- Estado de check-in de campo
do $$ begin
  create type public.field_status as enum (
    'NotCheckedIn', -- Participante aún no ha hecho check-in
    'CheckedIn'     -- Participante ha sido chequeado en el evento
  );
exception when duplicate_object then null; end $$;

-- Estado de revisión de pago
do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'payment_review_status'
      and n.nspname = 'public'
  ) then
    create type public.payment_review_status as enum (
      'Submitted',    -- Pago ingresado, pendiente de revisión
      'UnderReview',  -- Pago en proceso de verificación
      'Verified',     -- Pago aprobado
      'Rejected'      -- Pago rechazado
    );
  end if;
end
$$;


-- Resultado de escaneo/check-in
do $$ begin
  create type public.checkin_result as enum (
    'Success',          -- Check-in exitoso
    'NotPaid',          -- Participante no pagó
    'NotFound',         -- Participante no registrado
    'Blocked',          -- Participante bloqueado
    'AlreadyCheckedIn'  -- Participante ya checkeado
  );
exception when duplicate_object then null; end $$;

-- Roles de usuario en la aplicación
do $$ begin
  create type public.user_role as enum (
    'Admin',    -- Acceso completo a todo
    'Ops',      -- Acceso operativo avanzado
    'Staff'     -- Acceso limitado a operaciones de campo
  );
exception when duplicate_object then null; end $$;

-- ============================================================
-- 2) TABLAS NÚCLEO – LA LUJANETA
-- ============================================================

-- 2.1 Participants (identidad estable)
create table if not exists public.participants (
  participant_id uuid primary key default gen_random_uuid(),
  public_id text unique,                        -- ID humano legible
  full_name text not null,
  doc_type text,
  doc_number text,
  birthdate date,
  phone text,
  email text,
  emergency_contact_name text,
  emergency_contact_phone text,
  medical_flag boolean not null default false,  -- true si hay condiciones médicas
  medical_notes text,
  allergies_flag boolean not null default false, -- true si tiene alergias
  allergies_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Índices para búsquedas rápidas
create index if not exists idx_participants_doc_number on public.participants(doc_number);
create index if not exists idx_participants_phone on public.participants(phone);

-- Unicidad de documento (solo si ambos campos existen)
create unique index if not exists uq_participants_doc
on public.participants (doc_type, doc_number)
where doc_type is not null and doc_number is not null;

-- ============================================================
-- 2.2 Events
create table if not exists public.events (
  event_id uuid primary key default gen_random_uuid(),
  event_code text unique not null,   -- código legible del evento
  name text not null,
  start_date date,
  end_date date,
  location text,
  price_amount numeric,
  currency text default 'ARS',
  payment_methods jsonb,             -- lista de métodos disponibles
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ============================================================
-- 2.3 Registrations (relación participant-event)
create table if not exists public.registrations (
  registration_id uuid primary key default gen_random_uuid(),
  participant_id uuid not null references public.participants(participant_id) on delete restrict,
  event_id uuid not null references public.events(event_id) on delete restrict,

  registration_status public.registration_status not null default 'Registered',
  payment_status public.payment_status not null default 'Pending',
  field_status public.field_status not null default 'NotCheckedIn',

  notes_ops text,                    -- notas internas para Ops
  registered_at timestamptz not null default now(),
  checked_in_at timestamptz,
  created_at timestamptz not null default now()
);

-- Evita duplicados: mismo participante no puede registrarse 2 veces en el mismo evento
create unique index if not exists uq_reg_participant_event
on public.registrations(participant_id, event_id);

-- Índices de consulta
create index if not exists idx_reg_event on public.registrations(event_id);
create index if not exists idx_reg_payment on public.registrations(payment_status);

-- ============================================================
-- 2.4 Payments (auditoría de pagos)
create table if not exists public.payments (
  payment_id uuid primary key default gen_random_uuid(),
  registration_id uuid not null references public.registrations(registration_id) on delete cascade,
  method text not null,                -- e.g., 'Cash', 'Transfer', 'MercadoPago'
  amount numeric,
  currency text default 'ARS',
  reference text,                      -- código de transacción
  proof_file_url text,                 -- url del comprobante
  status public.payment_review_status not null default 'Submitted',
  reviewed_by uuid,                    -- user_id que revisó
  reviewed_at timestamptz,
  rejection_reason text,
  created_at timestamptz not null default now()
);

-- Índices para performance
create index if not exists idx_payments_reg on public.payments(registration_id);
create index if not exists idx_payments_status on public.payments(status);
create index if not exists idx_payments_created_at on public.payments(created_at);

-- ============================================================
-- 2.5 Checkins (log de escaneo)
create table if not exists public.checkins (
  checkin_id uuid primary key default gen_random_uuid(),
  registration_id uuid not null references public.registrations(registration_id) on delete cascade,
  scanned_by uuid,                     -- user_id del staff que escaneó
  scanned_at timestamptz not null default now(),
  result public.checkin_result not null,
  device_notes text
);

create index if not exists idx_checkins_reg on public.checkins(registration_id);

-- ============================================================
-- 2.6 Roles (mapeo auth.users → rol)
create table if not exists public.user_roles (
  user_id uuid primary key,            -- vinculado a auth.users.id
  role public.user_role not null default 'Staff',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ============================================================
-- 2.7 QR tokens (QR no contiene datos sensibles)
create table if not exists public.qr_tokens (
  token text primary key,              -- token seguro aleatorio
  participant_id uuid not null references public.participants(participant_id) on delete cascade,
  revoked boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists idx_qr_participant on public.qr_tokens(participant_id);

-- ============================================================
-- 3) IDs HUMANOS (public_id) AUTO-GENERADOS
-- ============================================================

-- Contador anual para public_id
create table if not exists public.id_counters (
  year int primary key,
  counter int not null default 0
);

-- Función para generar public_id secuencial por año
create or replace function public.generate_public_id()
returns trigger
language plpgsql
as $$
declare
  y int := extract(year from now());
  new_counter int;
begin
  -- Inserta el año si no existe
  insert into public.id_counters(year, counter)
  values (y, 0)
  on conflict (year) do nothing;

  -- Incrementa el contador del año actual
  update public.id_counters
  set counter = counter + 1
  where year = y
  returning counter into new_counter;

  -- Genera public_id con formato LJ-YYYY-###### 
  new.public_id := 'LJ-' || y::text || '-' || lpad(new_counter::text, 6, '0');
  return new;
end;
$$;

-- Trigger para asignar public_id automáticamente antes del insert
drop trigger if exists trg_generate_public_id on public.participants;

create trigger trg_generate_public_id
before insert on public.participants
for each row
when (new.public_id is null)
execute function public.generate_public_id();

-- ============================================================
-- 4) CAMPOS POR EVENTO (EXPERIENCIA, FITNESS, ROL, SALIDA, KIT)
-- ============================================================

-- ENUMS por evento
do $$ begin
  create type public.experience_level as enum ('FirstTimer','1-2','3-5','6+');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.fitness_level as enum ('Low','Medium','High');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.event_role as enum ('Participant','Staff','Coordinator','Medical');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.kit_status as enum ('NotEligible','Eligible','Delivered');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.departure_point as enum (
    'Liniers',
    'Ciudadela',
    'Ramos Mejia',
    'Haedo',
    'Moron',
    'Castelar',
    'Ituzaingo',
    'Padua',
    'Merlo',
    'Paso del Rey',
    'Moreno',
    'La Reja',
    'Francisco Alvarez',
    'Pablo Marin',
    'Las Malvinas',
    'General Rodriguez',
    'La Fraternidad',
    'Lezica y Torrezuri',
    'Universidad de Lujan'
  );
exception when duplicate_object then null; end $$;

-- Agrega columnas por evento a registrations
alter table public.registrations
  add column if not exists experience public.experience_level,
  add column if not exists fitness public.fitness_level,
  add column if not exists role public.event_role not null default 'Participant',
  add column if not exists departure public.departure_point,
  add column if not exists kit public.kit_status not null default 'NotEligible',
  add column if not exists restrictions_flag boolean not null default false,
  add column if not exists restrictions_notes text;

-- Índices adicionales para consultas frecuentes
create index if not exists idx_reg_participant on public.registrations(participant_id);
create index if not exists idx_reg_event_payment on public.registrations(event_id, payment_status);
create index if not exists idx_reg_event_field on public.registrations(event_id, field_status);
create index if not exists idx_reg_event_role on public.registrations(event_id, role);


-- ============================================================
-- 5) AUDITORÍA OPERATIVA (PRO)
-- ============================================================

-- Campos adicionales en registrations para auditoría
alter table public.registrations
  add column if not exists payment_verified_at timestamptz,
  add column if not exists payment_verified_by uuid,
  add column if not exists kit_delivered_at timestamptz,
  add column if not exists kit_delivered_by uuid,
  add column if not exists email_qr_sent_at timestamptz;

-- Campo adicional en payments para auditoría
alter table public.payments
  add column if not exists submitted_by uuid;

-- Último uso del token QR
alter table public.qr_tokens
  add column if not exists last_used_at timestamptz;

-- ============================================================
-- 6) TRIGGERS OPERATIVOS CORREGIDOS
-- ============================================================

-- 6.1 updated_at automático en participants
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_participants_updated_at on public.participants;

create trigger trg_participants_updated_at
before update on public.participants
for each row
execute function public.set_updated_at();

-- 6.2 KIT se sincroniza según estado de pago
create or replace function public.sync_kit_status()
returns trigger
language plpgsql
as $$
begin
  -- Pago verificado → habilita kit si aún no fue entregado
  if new.payment_status = 'Verified' then
    if new.kit <> 'Delivered' then
      new.kit := 'Eligible';
    end if;
    new.payment_verified_at := coalesce(new.payment_verified_at, now());
    new.payment_verified_by := coalesce(new.payment_verified_by, auth.uid());
  end if;

  -- Pending/Rechazado → kit no elegible si aún no fue entregado
  if new.payment_status in ('Pending','Rejected') then
    if new.kit <> 'Delivered' then
      new.kit := 'NotEligible';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_sync_kit_status on public.registrations;

create trigger trg_sync_kit_status
before insert or update of payment_status on public.registrations
for each row
execute function public.sync_kit_status();

-- 6.3 CHECK-IN AUTOMÁTICO CON VALIDACIÓN DE PAGO
create or replace function public.sync_checked_in_at()
returns trigger
language plpgsql
as $$
begin
  -- Solo actualizar checked_in_at si field_status cambia a CheckedIn
  if new.field_status = 'CheckedIn' and old.field_status is distinct from new.field_status then

    -- Validación de pago: solo Verified puede hacer check-in
    if new.payment_status <> 'Verified' then
      -- Permitir override solo si rol es Admin
      if public.app_current_role() <> 'Admin' then
        raise exception 'Cannot check-in: Payment not verified for registration %', new.registration_id;
      end if;
    end if;

    -- Registrar check-in
    new.checked_in_at := now();
    new.checked_in_by := coalesce(new.checked_in_by, auth.uid());
  end if;

  return new;
end;
$$;

drop trigger if exists trg_sync_checked_in_at on public.registrations;

create trigger trg_sync_checked_in_at
before update of field_status on public.registrations
for each row
execute function public.sync_checked_in_at();

-- 6.4 KIT DELIVERED AUTOMÁTICO CON AUDITORÍA
create or replace function public.sync_kit_delivered_at()
returns trigger
language plpgsql
as $$
begin
  if new.kit = 'Delivered' and old.kit is distinct from new.kit then
    new.kit_delivered_at := now();
    new.kit_delivered_by := coalesce(new.kit_delivered_by, auth.uid());

    -- Validar permisos: solo Ops/Admin pueden marcar kit como Delivered si no lo hizo el staff
    if auth.uid() <> new.kit_delivered_by and public.app_current_role() not in ('Ops','Admin') then
      raise exception 'Permission denied: Only Ops/Admin can override kit delivery';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_sync_kit_delivered_at on public.registrations;

create trigger trg_sync_kit_delivered_at
before update of kit on public.registrations
for each row
execute function public.sync_kit_delivered_at();


-- ============================================================
-- 7) RLS (PUERTAS Y LLAVES) + ROLES
-- ============================================================

-- 7.1 Activar RLS en todas las tablas sensibles
alter table public.participants enable row level security;
alter table public.events enable row level security;
alter table public.registrations enable row level security;
alter table public.payments enable row level security;
alter table public.checkins enable row level security;
alter table public.qr_tokens enable row level security;
alter table public.user_roles enable row level security;

-- 7.2 Helper: rol actual seguro para policies
create or replace function public.app_current_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role::text
     from public.user_roles
     where user_id = auth.uid()
       and active = true
     limit 1),
    'Staff'
  );
$$;

-- 7.3 POLICIES

-- USER_ROLES: Admin ve todo
drop policy if exists roles_admin_all on public.user_roles;
create policy roles_admin_all
on public.user_roles
for all
using (app_current_role() = 'Admin')
with check (app_current_role() = 'Admin');

-- EVENTS: lectura solo usuarios autenticados
drop policy if exists events_read_authenticated on public.events;
create policy events_read_authenticated
on public.events
for select
using (auth.uid() is not null);

-- PARTICIPANTS: lectura restringida según rol
drop policy if exists participants_read on public.participants;
create policy participants_read
on public.participants
for select
using (app_current_role() in ('Staff','Ops','Admin'));

-- PARTICIPANTS: update solo Ops/Admin
drop policy if exists participants_update_ops_admin on public.participants;
create policy participants_update_ops_admin
on public.participants
for update
using (app_current_role() in ('Ops','Admin'))
with check (app_current_role() in ('Ops','Admin'));

-- REGISTRATIONS: lectura según rol
drop policy if exists registrations_read on public.registrations;
create policy registrations_read
on public.registrations
for select
using (app_current_role() in ('Staff','Ops','Admin'));

-- REGISTRATIONS: update para Staff/Ops/Admin
drop policy if exists registrations_update on public.registrations;
create policy registrations_update
on public.registrations
for update
using (app_current_role() in ('Staff','Ops','Admin'))
with check (app_current_role() in ('Staff','Ops','Admin'));

-- PAYMENTS: solo Ops/Admin lee/escribe
drop policy if exists payments_read_ops_admin on public.payments;
create policy payments_read_ops_admin
on public.payments
for select
using (app_current_role() in ('Ops','Admin'));

drop policy if exists payments_insert_ops_admin on public.payments;
create policy payments_insert_ops_admin
on public.payments
for insert
with check (app_current_role() in ('Ops','Admin'));

drop policy if exists payments_update_ops_admin on public.payments;
create policy payments_update_ops_admin
on public.payments
for update
using (app_current_role() in ('Ops','Admin'))
with check (app_current_role() in ('Ops','Admin'));

-- CHECKINS: insertar Staff/Ops/Admin; leer solo Ops/Admin
drop policy if exists checkins_insert on public.checkins;
create policy checkins_insert
on public.checkins
for insert
with check (app_current_role() in ('Staff','Ops','Admin'));

drop policy if exists checkins_read_ops_admin on public.checkins;
create policy checkins_read_ops_admin
on public.checkins
for select
using (app_current_role() in ('Ops','Admin'));

-- QR_TOKENS: lectura autenticados; update solo Ops/Admin
drop policy if exists qr_tokens_read on public.qr_tokens;
create policy qr_tokens_read
on public.qr_tokens
for select
using (auth.uid() is not null);

drop policy if exists qr_tokens_update_ops_admin on public.qr_tokens;
create policy qr_tokens_update_ops_admin
on public.qr_tokens
for update
using (app_current_role() in ('Ops','Admin'))
with check (app_current_role() in ('Ops','Admin'));


-- ============================================================
-- 8) FUNCIONES DE LECTURA SEGURA (SECURE READ FUNCTIONS)
-- ============================================================

-- 8.1 Participants: lectura segura por participant_id
create or replace function public.get_participant_by_id(p_participant_id uuid)
returns table (
  participant_id uuid,
  public_id text,
  full_name text,
  doc_type text,
  doc_number text,
  phone text
)
language sql
security definer
as $$
  select participant_id, public_id, full_name, doc_type, doc_number, phone
  from public.participants
  where participant_id = p_participant_id
    and app_current_role() in ('Staff','Ops','Admin');
$$;

-- 8.1b Participants: lectura segura general por DNI, teléfono o public_id
create or replace function public.get_participant_secure(
    p_doc_type text,
    p_doc_number text,
    p_phone text,
    p_public_id text
)
returns table(
    participant_id uuid,
    public_id text,
    full_name text,
    doc_type text,
    doc_number text,
    phone text,
    email text,
    medical_flag boolean,
    medical_notes text,
    allergies_flag boolean,
    allergies_notes text,
    created_at timestamptz,
    updated_at timestamptz
)
language sql
security definer
as $$
    select
        participant_id,
        public_id,
        full_name,
        doc_type,
        doc_number,
        phone,
        email,
        medical_flag::boolean,
        medical_notes,
        allergies_flag::boolean,
        allergies_notes,
        created_at,
        updated_at
    from public.participants
    where
        (doc_type = p_doc_type and doc_number = p_doc_number)
        or (phone = p_phone)
        or (public_id = p_public_id)
    and app_current_role() in ('Staff','Ops','Admin');
$$;


-- 8.2 Registrations: lectura segura por registration_id
create or replace function public.get_registration_by_id(p_registration_id uuid)
returns table (
  registration_id uuid,
  participant_id uuid,
  event_id uuid,
  registration_status text,
  payment_status text,
  kit text
)
language sql
security definer
as $$
  select r.registration_id, r.participant_id, r.event_id, r.registration_status, r.payment_status, r.kit
  from public.registrations r
  where r.registration_id = p_registration_id
    and app_current_role() in ('Staff','Ops','Admin');
$$;

-- 8.2b Registration segura general por participant_id o QR token
create or replace function public.get_registration_secure(
    p_participant_id uuid,
    p_token text
)
returns table(
    registration_id uuid,
    participant_id uuid,
    event_id uuid,
    registration_status public.registration_status,
    payment_status public.payment_status,
    field_status public.field_status,
    experience public.experience_level,
    fitness public.fitness_level,
    role public.event_role,
    departure public.departure_point,
    kit public.kit_status,
    restrictions_flag boolean,
    restrictions_notes text,
    registered_at timestamptz,
    checked_in_at timestamptz,
    payment_verified_at timestamptz,
    payment_verified_by uuid,
    kit_delivered_at timestamptz,
    kit_delivered_by uuid,
    email_qr_sent_at timestamptz,
    notes_ops text,
    created_at timestamptz
)
language sql
security definer
as $$
    select
        r.registration_id,
        r.participant_id,
        r.event_id,
        r.registration_status::public.registration_status,
        r.payment_status::public.payment_status,
        r.field_status::public.field_status,
        r.experience::public.experience_level,
        r.fitness::public.fitness_level,
        r.role::public.event_role,
        r.departure::public.departure_point,
        r.kit::public.kit_status,
        r.restrictions_flag::boolean,
        r.restrictions_notes,
        r.registered_at,
        r.checked_in_at,
        r.payment_verified_at,
        r.payment_verified_by,
        r.kit_delivered_at,
        r.kit_delivered_by,
        r.email_qr_sent_at,
        r.notes_ops,
        r.created_at
    from public.registrations r
    left join public.qr_tokens q on q.participant_id = r.participant_id
    where
        (r.participant_id = p_participant_id
        or (q.token = p_token and q.revoked = false))
        and app_current_role() in ('Staff','Ops','Admin');
$$;

-- 8.3 Payments: lectura segura por payment_id
create or replace function public.get_payment_by_id(p_payment_id uuid)
returns table (
  payment_id uuid,
  registration_id uuid,
  amount numeric,
  status text,
  reviewed_at timestamp,
  reviewed_by uuid,
  rejection_reason text
)
language sql
security definer
as $$ 
  select p.payment_id, p.registration_id, p.amount, p.status, p.reviewed_at, p.reviewed_by, p.rejection_reason
  from public.payments p
  join public.registrations r on r.registration_id = p.registration_id
  where p.payment_id = p_payment_id
    and app_current_role() in ('Ops','Admin');
$$;

-- 8.3b Payment segura general por registration_id
create or replace function public.get_payments_secure(
    p_registration_id uuid
)
returns table(
    payment_id uuid,
    registration_id uuid,
    method text,
    amount numeric,
    currency text,
    reference text,
    proof_file_url text,
    status public.payment_review_status,
    reviewed_by uuid,
    reviewed_at timestamptz,
    rejection_reason text,
    submitted_by uuid,
    created_at timestamptz
)
language sql
security definer
as $$
    select
        p.payment_id,
        p.registration_id,
        p.method,
        p.amount,
        p.currency,
        p.reference,
        p.proof_file_url,
        p.status::public.payment_review_status,
        p.reviewed_by,
        p.reviewed_at,
        p.rejection_reason,
        p.submitted_by,
        p.created_at
    from public.payments p
    where p.registration_id = p_registration_id
    and app_current_role() in ('Ops','Admin');
$$;

-- 8.4 Check-ins: lectura segura por registration_id
create or replace function public.get_checkin_by_registration(p_registration_id uuid)
returns table (
  checkin_id uuid,
  registration_id uuid,
  checkin_at timestamptz,
  checked_in_by uuid
)
language sql
security definer
as $$
  select 
    c.checkin_id,
    c.registration_id,
    c.scanned_at as checkin_at,
    c.scanned_by as checked_in_by
  from public.checkins c
  where c.registration_id = p_registration_id
    and app_current_role() in ('Ops','Admin');
$$;

-- 8.5 Listado de eventos activos
create or replace function public.get_active_events()
returns table (
  event_id uuid,
  event_code text,
  name text,
  start_date date,
  end_date date,
  location text,
  price_amount numeric,
  currency text,
  payment_methods jsonb,
  active boolean,
  created_at timestamptz
)
language sql
as $$ 
  select *
  from public.events
  where active = true;
$$;


-- ============================================================
-- 8.6 FUNCIÓN SEGURA OPS: VERIFICAR/RECHAZAR PAGO (ATÓMICO)
-- ============================================================

drop function if exists public.ops_verify_payment(uuid, boolean, text);

create function public.ops_verify_payment(
  p_registration_id uuid,
  p_approved boolean,
  p_reason text default null
)
returns table (
  registration_id uuid,
  payment_status text,
  payment_review_status text
)
language plpgsql
security definer
as $$ 
declare
  v_registration_status public.registrations.registration_status%type;
  v_payment_status public.payments.status%type;
begin
  if app_current_role() not in ('Ops','Admin') then
    raise exception 'Permission denied: Only Ops/Admin can verify payments';
  end if;

  select r.registration_status, p.status
  into v_registration_status, v_payment_status
  from public.registrations r
  join public.payments p on p.registration_id = r.registration_id
  where r.registration_id = p_registration_id;

  if not found then
    raise exception 'Registration ID % does not exist', p_registration_id;
  end if;

  if v_registration_status = 'Blocked' then
    raise exception 'Cannot verify payment for blocked registration %', p_registration_id;
  end if;

  if v_payment_status in ('Verified','Rejected') then
    raise exception 'Payment already processed (%). Use Admin override if necessary', v_payment_status;
  end if;

  if p_approved then
    update public.registrations
      set payment_status = 'Verified',
          payment_verified_at = now(),
          payment_verified_by = auth.uid()
    where registration_id = p_registration_id;

    update public.payments
      set status = 'Verified',
          reviewed_at = now(),
          reviewed_by = auth.uid(),
          rejection_reason = null
    where registration_id = p_registration_id;
  else
    update public.registrations
      set payment_status = 'Rejected'
    where registration_id = p_registration_id;

    update public.payments
      set status = 'Rejected',
          reviewed_at = now(),
          reviewed_by = auth.uid(),
          rejection_reason = coalesce(p_reason,'Rejected by Ops')
    where registration_id = p_registration_id;
  end if;

  return query
    select r.registration_id, r.payment_status, p.status
    from public.registrations r
    join public.payments p on p.registration_id = r.registration_id
    where r.registration_id = p_registration_id;
end;
$$;

-- ============================================================
-- 8.7 FUNCIONES CRÍTICAS – QR / CHECK-IN
-- ============================================================

drop function if exists public.scan_qr(text, uuid);

create function public.scan_qr(
  p_token text,
  p_scanned_by uuid
) returns public.checkin_result
language plpgsql
security definer
as $$ declare
  v_registration_id uuid;
  v_participant_id uuid;
  v_payment_status public.payments.status%type;
  v_field_status public.registrations.field_status%type;
begin
  select participant_id into v_participant_id
  from public.qr_tokens
  where token = p_token and revoked = false
  limit 1;

  if not found then return 'NotFound'; end if;

  select registration_id, payment_status, field_status
  into v_registration_id, v_payment_status, v_field_status
  from public.registrations
  where participant_id = v_participant_id
  limit 1;

  if not found then return 'NotFound'; end if;

  if v_field_status = 'CheckedIn' then return 'AlreadyCheckedIn'; end if;
  if v_payment_status <> 'Verified' and app_current_role() <> 'Admin' then return 'NotPaid'; end if;
  if (select registration_status from public.registrations where registration_id = v_registration_id) = 'Blocked' then return 'Blocked'; end if;

  update public.registrations
  set field_status = 'CheckedIn',
      checked_in_at = now(),
      checked_in_by = p_scanned_by
  where registration_id = v_registration_id;

  insert into public.checkins(registration_id, scanned_by, result)
  values (v_registration_id, p_scanned_by, 'Success');

  update public.qr_tokens
  set last_used_at = now()
  where token = p_token;

  return 'Success';
end;
$$;

-- ============================================================
-- 8.8 TRIGGER AUTOMÁTICO PARA CHECK-IN POR QR
-- ============================================================

drop function if exists public.trg_scan_qr() cascade;

create function public.trg_scan_qr()
returns trigger
language plpgsql
security definer
as $$ 
begin
  perform public.scan_qr(NEW.token, NEW.scanned_by);
  return NEW;
end;
$$;

drop trigger if exists checkin_qr_trigger on public.checkins;

create trigger checkin_qr_trigger
before insert on public.checkins
for each row
execute function public.trg_scan_qr();

-- ============================================================
-- 9) QUERIES FALLBACK (REFERENCIA PARA FRONTEND / SOP)
-- ============================================================

-- 9.1 Verificación por token QR
create or replace view public.v_verify_by_qr as
select
  p.participant_id,
  p.public_id,
  p.full_name,
  r.registration_id,
  r.field_status,
  r.kit,
  e.event_id,
  e.name as event_name,
  e.active as event_active
from qr_tokens qt
join participants p on p.participant_id = qt.participant_id
join registrations r on r.participant_id = p.participant_id
join events e on e.event_id = r.event_id
where qt.revoked = false
  and e.active = true;

-- 9.2 Búsqueda por DNI
create or replace view public.v_verify_by_dni as
select
  p.participant_id,
  p.public_id,
  p.full_name,
  p.doc_type,
  p.doc_number,
  r.registration_id,
  r.field_status,
  r.kit,
  e.event_id,
  e.name as event_name,
  e.active as event_active
from participants p
join registrations r on r.participant_id = p.participant_id
join events e on e.event_id = r.event_id
where e.active = true;

-- 9.3 Búsqueda por teléfono
create or replace view public.v_verify_by_phone as
select
  p.participant_id,
  p.public_id,
  p.full_name,
  p.phone,
  r.registration_id,
  r.field_status,
  r.kit,
  e.event_id,
  e.name as event_name,
  e.active as event_active
from participants p
join registrations r on r.participant_id = p.participant_id
join events e on e.event_id = r.event_id
where e.active = true;

-- 9.4 Query fallback general (por DNI, teléfono o token QR)
create or replace function public.search_registration_fallback(
    p_doc_number text,
    p_phone text,
    p_token text
)
returns table(
    registration_id uuid,
    participant_id uuid,
    event_id uuid,
    full_name text,
    registration_status public.registration_status,
    payment_status public.payment_status,
    field_status public.field_status,
    kit public.kit_status
)
language sql
security definer
as $$
    select r.registration_id, r.participant_id, r.event_id, p.full_name,
           r.registration_status, r.payment_status, r.field_status, r.kit
    from public.registrations r
    join public.participants p on p.participant_id = r.participant_id
    left join public.qr_tokens q on q.participant_id = p.participant_id
    where
        (p.doc_number = p_doc_number)
        or (p.phone = p_phone)
        or (q.token = p_token and q.revoked = false)
    and app_current_role() in ('Staff','Ops','Admin');
$$;


-- ============================================================
-- 10) AUDITORÍA DE OPERACIONES (LOGS)
-- ============================================================

-- 10.1 Tabla de auditoría general
create table if not exists public.audit_log (
  audit_id uuid primary key default gen_random_uuid(),
  table_name text not null,
  action text not null,             -- 'INSERT','UPDATE','DELETE'
  record_id uuid,
  performed_by uuid,
  performed_at timestamptz default now(),
  details jsonb
);

-- 10.2 Trigger function para auditoría
create or replace function public.audit_changes()
returns trigger
language plpgsql
as $$
declare
  v_record_id uuid;
  v_details jsonb;
begin
  if tg_op = 'DELETE' then
    v_record_id := old.*::json->>'id'::uuid;
    v_details := to_jsonb(old);
  else
    v_record_id := new.*::json->>'id'::uuid;
    v_details := to_jsonb(new);
  end if;

  insert into public.audit_log(table_name, action, record_id, performed_by, details)
  values (tg_table_name, tg_op, v_record_id, auth.uid(), v_details);

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

-- 10.3 Triggers de auditoría para tables críticas
-- Payments
drop trigger if exists trg_audit_payments on public.payments;
create trigger trg_audit_payments
after insert or update or delete on public.payments
for each row execute function public.audit_changes();

-- Registrations
drop trigger if exists trg_audit_registrations on public.registrations;
create trigger trg_audit_registrations
after insert or update or delete on public.registrations
for each row execute function public.audit_changes();

-- Checkins
drop trigger if exists trg_audit_checkins on public.checkins;
create trigger trg_audit_checkins
after insert or update or delete on public.checkins
for each row execute function public.audit_changes();

-- ============================================================
-- 11) EVENTO DE PRUEBA (NO DUPLICA SI YA EXISTE)
-- ============================================================

insert into events (
  event_code,
  name,
  start_date,
  end_date,
  location,
  price_amount,
  currency,
  payment_methods,
  active
)
values (
  'LUJANETA-TEST-2026',
  'Lujaneta Test Event',
  '2026-02-15',
  '2026-02-15',
  'Buenos Aires',
  0,
  'ARS',
  '{"alias":"tu-alias","notes":"Pago por transferencia"}'::jsonb,
  true
)
on conflict (event_code) do nothing;
-- ============================================================
-- 12) FUNCIONES DE LECTURA AGREGADA / REPORTES SEGUROS
-- ============================================================

-- 12.1 Listado de pagos pendientes, bloqueados o rechazados
create or replace function public.get_payments_status_report()
returns table (
  registration_id uuid,
  participant_id uuid,
  participant_name text,
  payment_status text,
  registration_status text,
  amount numeric,
  reviewed_at timestamptz,
  reviewed_by uuid,
  rejection_reason text
)
language sql
security definer
as $$
  select 
    r.registration_id,
    r.participant_id,
    p.full_name as participant_name,
    pay.status as payment_status,
    r.registration_status,
    pay.amount,
    pay.reviewed_at,
    pay.reviewed_by,
    pay.rejection_reason
  from public.registrations r
  join public.participants p on p.participant_id = r.participant_id
  join public.payments pay on pay.registration_id = r.registration_id
  where app_current_role() in ('Ops','Admin')
    and pay.status in ('Submitted','Rejected')
  order by pay.status, r.registration_id;
$$;

-- 12.2 Reporte de check-ins por evento y estado de kit
create or replace function public.get_checkin_report_by_event(p_event_id uuid)
returns table (
  registration_id uuid,
  participant_id uuid,
  participant_name text,
  field_status text,
  kit text,
  checkin_at timestamptz,
  checked_in_by uuid
)
language sql
security definer
as $$
  select 
    r.registration_id,
    r.participant_id,
    p.full_name as participant_name,
    r.field_status,
    r.kit,
    c.scanned_at as checkin_at,
    c.scanned_by as checked_in_by
  from public.registrations r
  join public.participants p on p.participant_id = r.participant_id
  left join public.checkins c on c.registration_id = r.registration_id
  where r.event_id = p_event_id
    and app_current_role() in ('Ops','Admin')
  order by r.field_status, r.registration_id;
$$;

-- 12.3 Estadísticas de inscripción vs pagos por evento
create or replace function public.get_event_payment_stats(p_event_id uuid)
returns table (
  total_registrations int,
  total_verified int,
  total_rejected int,
  total_pending int,
  total_checked_in int
)
language sql
security definer
as $$
  select
    count(r.registration_id) as total_registrations,
    count(case when p.status = 'Verified' then 1 end) as total_verified,
    count(case when p.status = 'Rejected' then 1 end) as total_rejected,
    count(case when p.status = 'Submitted' then 1 end) as total_pending,
    count(case when r.field_status = 'CheckedIn' then 1 end) as total_checked_in
  from public.registrations r
  join public.payments p on p.registration_id = r.registration_id
  where r.event_id = p_event_id
    and app_current_role() in ('Ops','Admin');
$$;
