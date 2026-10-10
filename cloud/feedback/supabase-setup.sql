-- Run once in the Supabase SQL editor. Re-running preserves existing feedback.
-- Only the server's service_role can access drafts, revisions and private files.
begin;

create table if not exists public.aomidori_feedback_drafts (
  owner_id text primary key check (owner_id ~ '^[0-9]{1,20}$'),
  draft jsonb,
  revision uuid not null default pg_catalog.gen_random_uuid(),
  saved_at timestamptz not null default now(),
  check (draft is null or octet_length(draft::text) <= 8388608)
);

create table if not exists public.aomidori_feedback_history (
  revision uuid primary key,
  owner_id text not null references public.aomidori_feedback_drafts(owner_id),
  draft jsonb not null check (octet_length(draft::text) <= 8388608),
  saved_at timestamptz not null default now()
);

alter table public.aomidori_feedback_drafts enable row level security;
alter table public.aomidori_feedback_history enable row level security;
revoke all on public.aomidori_feedback_drafts, public.aomidori_feedback_history
  from public, anon, authenticated;
grant usage on schema public to service_role;
grant select, insert, update on public.aomidori_feedback_drafts to service_role;
grant select, insert on public.aomidori_feedback_history to service_role;

-- Lock the owner row before comparing revisions, including concurrent first saves.
-- The current draft and its historical revision are committed in one transaction.
create or replace function public.aomidori_feedback_save(
  p_owner_id text, p_expected_revision text, p_draft jsonb
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  current_row public.aomidori_feedback_drafts%rowtype;
  next_revision uuid := pg_catalog.gen_random_uuid();
  saved_time timestamptz := pg_catalog.now();
begin
  if p_draft is null or pg_catalog.jsonb_typeof(p_draft) <> 'object'
    or p_draft->>'project' is distinct from 'Aomidori'
    or p_draft->>'schema' is distinct from '1' then
    raise exception 'Documento non valido.' using errcode = '22023';
  end if;
  insert into public.aomidori_feedback_drafts(owner_id) values (p_owner_id)
    on conflict (owner_id) do nothing;
  select * into current_row from public.aomidori_feedback_drafts
    where owner_id = p_owner_id for update;
  if not coalesce(
    (p_expected_revision = 'empty' and current_row.draft is null)
    or (p_expected_revision = current_row.revision::text and current_row.draft is not null),
    false
  ) then
    return null;
  end if;
  update public.aomidori_feedback_drafts
    set draft = p_draft, revision = next_revision, saved_at = saved_time
    where owner_id = p_owner_id;
  insert into public.aomidori_feedback_history(revision, owner_id, draft, saved_at)
    values (next_revision, p_owner_id, p_draft, saved_time);
  return pg_catalog.jsonb_build_object('revision', next_revision, 'saved_at', saved_time);
end;
$$;
revoke all on function public.aomidori_feedback_save(text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.aomidori_feedback_save(text, text, jsonb) to service_role;

-- Originals use immutable hash-based names. MIME and original filename stay in JSON.
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
  values ('aomidori-feedback', 'aomidori-feedback', false, 8388608,
    array['application/octet-stream'])
  on conflict (id) do update set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

commit;
