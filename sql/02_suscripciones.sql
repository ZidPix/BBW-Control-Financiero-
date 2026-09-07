-- ============================================================
-- BBW CONTROL FINANCIERO — Planes mensuales (suscripciones)
-- Cargás el plan una vez y el gasto se devenga solo cada mes.
-- ============================================================

create table public.suscripciones (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null,
  monto       numeric(12,2) not null check (monto > 0),
  cuenta      text not null references public.cuentas(codigo),
  dia_cobro   smallint not null default 1 check (dia_cobro between 1 and 31),
  mes_inicio  date not null,
  mes_fin     date,
  nota        text,
  creado_por  uuid not null references auth.users(id) default auth.uid(),
  creado_en   timestamptz not null default now(),
  constraint suscripciones_meses_ok check (mes_fin is null or mes_fin >= mes_inicio)
);
comment on table public.suscripciones is
  'Cargos fijos mensuales. mes_fin null = vigente. Cancelar = poner mes_fin, nunca borrar.';

-- mes_inicio y mes_fin siempre al dia 1, para comparar meses sin ambiguedad
create or replace function private.normalizar_meses()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.mes_inicio := date_trunc('month', new.mes_inicio)::date;
  if new.mes_fin is not null then
    new.mes_fin := date_trunc('month', new.mes_fin)::date;
  end if;
  return new;
end $$;

create trigger suscripciones_normalizar
  before insert or update on public.suscripciones
  for each row execute function private.normalizar_meses();

alter table public.movimientos
  add column suscripcion_id uuid references public.suscripciones(id) on delete set null,
  add column periodo date;

comment on column public.movimientos.periodo is
  'Mes al que corresponde el cargo automatico (dia 1). Null si se cargo a mano.';

-- Bitacora de devengo: unica fuente de verdad sobre que periodos ya se
-- generaron. Si el admin borra el movimiento, esto impide que reaparezca solo.
create table public.suscripciones_generadas (
  suscripcion_id uuid not null references public.suscripciones(id) on delete cascade,
  periodo        date not null,
  movimiento_id  uuid references public.movimientos(id) on delete set null,
  generado_en    timestamptz not null default now(),
  primary key (suscripcion_id, periodo)
);

create index movimientos_suscripcion_idx
  on public.movimientos (suscripcion_id) where suscripcion_id is not null;

-- ============================================================
-- RLS: los planes son estructura de costos del negocio. Solo admin.
-- ============================================================
alter table public.suscripciones           enable row level security;
alter table public.suscripciones_generadas enable row level security;

create policy suscripciones_admin on public.suscripciones
  for all to authenticated
  using (private.es_admin()) with check (private.es_admin());

create policy suscripciones_generadas_admin on public.suscripciones_generadas
  for all to authenticated
  using (private.es_admin()) with check (private.es_admin());

-- ============================================================
-- Devengo. Una sola sentencia, sin bucles: por cada plan genera
-- los meses que le faltan desde su inicio hasta el mes corriente.
-- Nunca adelanta meses futuros. Idempotente.
-- ============================================================
create or replace function public.generar_cargos_pendientes()
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  n integer := 0;
  mes_actual date := date_trunc('month', current_date)::date;
begin
  if not private.es_admin() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  with pendientes as (
    select
      s.id  as suscripcion_id,
      s.nombre, s.cuenta, s.monto, s.nota, s.creado_por, s.dia_cobro,
      g.mes::date as periodo
    from public.suscripciones s
    cross join lateral generate_series(
      s.mes_inicio::timestamp,
      least(coalesce(s.mes_fin, mes_actual), mes_actual)::timestamp,
      interval '1 month'
    ) as g(mes)
    where not exists (
      select 1 from public.suscripciones_generadas sg
      where sg.suscripcion_id = s.id and sg.periodo = g.mes::date
    )
  ),
  insertados as (
    insert into public.movimientos
      (fecha, cuenta, monto, contraparte, nota, registrado_por, suscripcion_id, periodo)
    select
      -- el dia de cobro, recortado al ultimo dia si el mes es mas corto
      least(
        (p.periodo + (p.dia_cobro - 1) * interval '1 day')::date,
        (p.periodo + interval '1 month' - interval '1 day')::date
      ),
      p.cuenta, p.monto, p.nombre, p.nota, p.creado_por, p.suscripcion_id, p.periodo
    from pendientes p
    returning id, suscripcion_id, periodo
  )
  insert into public.suscripciones_generadas (suscripcion_id, periodo, movimiento_id)
  select i.suscripcion_id, i.periodo, i.id from insertados i;

  get diagnostics n = row_count;
  return n;
end $$;

revoke all     on function public.generar_cargos_pendientes() from public, anon;
grant  execute on function public.generar_cargos_pendientes() to authenticated;

-- ============================================================
-- Vista de planes con lo devengado hasta ahora
-- ============================================================
create view public.v_suscripciones
with (security_invoker = on) as
select
  s.*,
  c.nombre as cuenta_nombre,
  c.grupo,
  (s.mes_fin is null) as vigente,
  (select count(*) from public.suscripciones_generadas sg where sg.suscripcion_id = s.id) as cargos_generados
from public.suscripciones s
join public.cuentas c on c.codigo = s.cuenta;

-- ============================================================
-- v_movimientos ahora expone el origen del cargo, para que la
-- app pueda marcar los automaticos con el chip AUTO.
-- ============================================================
create or replace view public.v_movimientos
with (security_invoker = on) as
select
  m.id, m.fecha, m.cuenta,
  c.nombre as cuenta_nombre,
  c.grupo,
  m.monto, m.contraparte, m.nota,
  m.registrado_por,
  p.nombre as registrado_nombre,
  m.creado_en,
  m.suscripcion_id,
  m.periodo
from public.movimientos m
join public.cuentas  c on c.codigo = m.cuenta
left join public.perfiles p on p.id = m.registrado_por;
