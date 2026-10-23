-- Read-only evaluator library. Raw rows remain private and never drive calculations.
begin;

create table if not exists vetdosis_reference_staging.reference_display_decisions (
  id text primary key,
  section text not null check (section in ('fisiologia','laboratorio')),
  species text not null,
  parameter text not null,
  min_value text not null,
  max_value text not null,
  unit text not null,
  source_title text not null,
  source_url text not null,
  rationale text not null,
  checked_on date not null,
  review_state text not null check (review_state in ('fuente_contrastada_pendiente_mvz','aprobada_mvz'))
);
alter table vetdosis_reference_staging.reference_display_decisions enable row level security;
revoke all on vetdosis_reference_staging.reference_display_decisions from public, anon, authenticated;

insert into vetdosis_reference_staging.reference_display_decisions
  (id,section,species,parameter,min_value,max_value,unit,source_title,source_url,rationale,checked_on,review_state)
values
  ('merck_dog_rectal_temp_20261023','fisiologia','Canino','Temperatura rectal','37.5','39.2','°C',
   'Merck Veterinary Manual · Normal Rectal Temperature Ranges',
   'https://www.merckvetmanual.com/multimedia/table/normal-rectal-temperature-ranges',
   'La tabla por especie da 37.5–39.2 °C para perro; el lote importado indica 37.5–38.5 °C y atribuye la fuente de manera ambigua. Mostrar ambas hasta revisión MVZ.',
   '2026-10-23','fuente_contrastada_pendiente_mvz'),
  ('merck_cat_rectal_temp_20261023','fisiologia','Felino','Temperatura rectal','38.1','39.2','°C',
   'Merck Veterinary Manual · Normal Rectal Temperature Ranges',
   'https://www.merckvetmanual.com/multimedia/table/normal-rectal-temperature-ranges',
   'La tabla por especie da 38.1–39.2 °C para gato; el lote importado indica 38–39 °C y atribuye la fuente de manera ambigua. Mostrar ambas hasta revisión MVZ.',
   '2026-10-23','fuente_contrastada_pendiente_mvz')
on conflict (id) do nothing;

create or replace function public.reference_review_list(
  p_clinic uuid, p_section text, p_search text default '', p_offset integer default 0, p_limit integer default 50
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if auth.uid() is null or p_section is null or p_section not in ('fisiologia','laboratorio')
    or p_offset is null or p_offset < 0 or p_limit is null or p_limit not between 1 and 50 or length(coalesce(p_search,'')) > 80
    or not exists (select 1 from public.clinic_members m
                   where m.clinic_id=p_clinic and m.user_id=auth.uid() and m.role in ('admin','mvz'))
    or private.permission_effective(p_clinic,auth.uid(),'clinical.read') is null
  then raise exception 'reference_review_access_denied'; end if;

  with raw_values as (
    select r.id::text id, 'fisiologia'::text section,
      d.doc->>'Especie' species, d.doc->>'Parámetro' parameter,
      d.doc->>'Valor mínimo' min_value, d.doc->>'Valor máximo' max_value,
      d.doc->>'Unidad' unit, d.doc->>'Obra' source_title,
      null::text source_url,
      concat_ws(' · ',nullif(d.doc->>'Condiciones/notas',''),
        'Página PDF '||coalesce(d.doc->>'Página PDF','?'),
        'Tabla '||coalesce(d.doc->>'Tabla','?')) notes,
      'pendiente'::text review_state, r.source_filename,
      r.source_sheet, r.source_row, null::text rationale
    from vetdosis_reference_staging.raw_intake_rows r
    cross join lateral (select (r.original_payload->>'Registro literal completo JSON')::jsonb doc) d
    where r.original_payload->>'Tipo'='EXÓTICOS / FISIOLOGÍA'
    union all
    select r.id::text,
      case when r.original_payload->>'Categoría'='Constantes' then 'fisiologia' else 'laboratorio' end,
      r.original_payload->>'Especie', r.original_payload->>'Parámetro',
      r.original_payload->>'Mín.',r.original_payload->>'Máx.',
      r.original_payload->>'Unidad original',r.original_payload->>'Fuente',
      null::text,concat_ws(' · ',nullif(r.original_payload->>'Notas',''),
        case when r.original_payload->>'Otro intervalo'='Sí' then 'El archivo señala otro intervalo' end),
      'pendiente',r.source_filename,r.source_sheet,r.source_row,null::text
    from vetdosis_reference_staging.raw_intake_rows r
    where r.original_payload->>'Categoría' in
      ('Constantes','Hematología','Enzimas','Bioquímica','Metabolitos','Minerales','Endocrinología')
    union all
    select d.id,d.section,d.species,d.parameter,d.min_value,d.max_value,d.unit,
      d.source_title,d.source_url,d.rationale,d.review_state,
      'Fuente externa contrastada',null::text,null::integer,d.rationale
    from vetdosis_reference_staging.reference_display_decisions d
  ), scoped as (
    select v.* from raw_values v where v.section=p_section
      and (coalesce(p_search,'')='' or v.species ilike '%'||p_search||'%'
        or v.parameter ilike '%'||p_search||'%'
        or v.source_title ilike '%'||p_search||'%')
  ), variants as (
    select coalesce(lower(species),'') species_key,coalesce(lower(parameter),'') parameter_key,coalesce(lower(unit),'') unit_key,
      count(distinct coalesce(min_value,'')||'|'||coalesce(max_value,'')) distinct_intervals
    from scoped group by 1,2,3
  ), marked as (
    select s.*,count(*) over(partition by lower(s.species),lower(s.parameter),lower(s.unit)) alternatives,
      v.distinct_intervals
    from scoped s join variants v on v.species_key=coalesce(lower(s.species),'')
      and v.parameter_key=coalesce(lower(s.parameter),'') and v.unit_key=coalesce(lower(s.unit),'')
  ), page as (
    select * from marked order by
      case when review_state='fuente_contrastada_pendiente_mvz' then 0 else 1 end,
      species,parameter,source_row nulls last,id
    limit p_limit offset p_offset
  )
  select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(page) order by
      case when page.review_state='fuente_contrastada_pendiente_mvz' then 0 else 1 end,
      page.species,page.parameter,page.source_row nulls last,page.id),'[]'::jsonb),
      'total',(select count(*) from scoped)) into result from page;
  return result;
end $$;
revoke all on function public.reference_review_list(uuid,text,text,integer,integer) from public,anon,authenticated;
grant execute on function public.reference_review_list(uuid,text,text,integer,integer) to authenticated;
commit;
