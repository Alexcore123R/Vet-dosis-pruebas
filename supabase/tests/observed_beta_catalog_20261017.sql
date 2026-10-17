-- ISOLATED REHEARSAL ONLY. Selected differences observed by read-only catalog
-- run 39061277899; not a full schema dump or a migration for Supabase.
alter table storage.objects alter column name drop not null;
alter table storage.objects alter column metadata drop not null;
alter table private.rx_artifacts enable row level security;
alter table private.form_artifacts enable row level security;
alter table private.professional_profile_versions enable row level security;
