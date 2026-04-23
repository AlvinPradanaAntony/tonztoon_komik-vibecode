-- Tonztoon Komik
-- Supabase RLS setup for user-library tables
--
-- Jalankan file ini di Supabase SQL Editor setelah migrasi backend selesai.
-- File ini aman dijalankan ulang (idempotent-ish) karena policy lama di-drop dulu.

begin;

-- Optional foreign keys ke auth.users jika schema auth tersedia
do $$
begin
  if exists (
    select 1
    from information_schema.tables
    where table_schema = 'auth' and table_name = 'users'
  ) then
    if not exists (
      select 1 from pg_constraint where conname = 'fk_profiles_user'
    ) then
      alter table public.profiles
        add constraint fk_profiles_user
        foreign key (id) references auth.users(id) on delete cascade;
    end if;

    if not exists (
      select 1 from pg_constraint where conname = 'fk_reader_preferences_user'
    ) then
      alter table public.reader_preferences
        add constraint fk_reader_preferences_user
        foreign key (user_id) references auth.users(id) on delete cascade;
    end if;

    if not exists (
      select 1 from pg_constraint where conname = 'fk_user_bookmarks_user'
    ) then
      alter table public.user_bookmarks
        add constraint fk_user_bookmarks_user
        foreign key (user_id) references auth.users(id) on delete cascade;
    end if;

    if not exists (
      select 1 from pg_constraint where conname = 'fk_user_collections_user'
    ) then
      alter table public.user_collections
        add constraint fk_user_collections_user
        foreign key (user_id) references auth.users(id) on delete cascade;
    end if;

    if not exists (
      select 1 from pg_constraint where conname = 'fk_user_progress_user'
    ) then
      alter table public.user_progress
        add constraint fk_user_progress_user
        foreign key (user_id) references auth.users(id) on delete cascade;
    end if;

    if not exists (
      select 1 from pg_constraint where conname = 'fk_user_history_entries_user'
    ) then
      alter table public.user_history_entries
        add constraint fk_user_history_entries_user
        foreign key (user_id) references auth.users(id) on delete cascade;
    end if;

    if not exists (
      select 1 from pg_constraint where conname = 'fk_user_favorite_scenes_user'
    ) then
      alter table public.user_favorite_scenes
        add constraint fk_user_favorite_scenes_user
        foreign key (user_id) references auth.users(id) on delete cascade;
    end if;

    if not exists (
      select 1 from pg_constraint where conname = 'fk_user_download_entries_user'
    ) then
      alter table public.user_download_entries
        add constraint fk_user_download_entries_user
        foreign key (user_id) references auth.users(id) on delete cascade;
    end if;
  end if;
end $$;

-- Enable and force RLS
alter table public.profiles enable row level security;
alter table public.profiles force row level security;

alter table public.reader_preferences enable row level security;
alter table public.reader_preferences force row level security;

alter table public.user_bookmarks enable row level security;
alter table public.user_bookmarks force row level security;

alter table public.user_collections enable row level security;
alter table public.user_collections force row level security;

alter table public.user_collection_comics enable row level security;
alter table public.user_collection_comics force row level security;

alter table public.user_progress enable row level security;
alter table public.user_progress force row level security;

alter table public.user_history_entries enable row level security;
alter table public.user_history_entries force row level security;

alter table public.user_favorite_scenes enable row level security;
alter table public.user_favorite_scenes force row level security;

alter table public.user_download_entries enable row level security;
alter table public.user_download_entries force row level security;

-- Drop old policies so the script can be rerun safely
drop policy if exists "profiles_select_own" on public.profiles;
drop policy if exists "profiles_insert_own" on public.profiles;
drop policy if exists "profiles_update_own" on public.profiles;
drop policy if exists "profiles_delete_own" on public.profiles;

drop policy if exists "reader_preferences_select_own" on public.reader_preferences;
drop policy if exists "reader_preferences_insert_own" on public.reader_preferences;
drop policy if exists "reader_preferences_update_own" on public.reader_preferences;
drop policy if exists "reader_preferences_delete_own" on public.reader_preferences;

drop policy if exists "user_bookmarks_select_own" on public.user_bookmarks;
drop policy if exists "user_bookmarks_insert_own" on public.user_bookmarks;
drop policy if exists "user_bookmarks_update_own" on public.user_bookmarks;
drop policy if exists "user_bookmarks_delete_own" on public.user_bookmarks;

drop policy if exists "user_collections_select_own" on public.user_collections;
drop policy if exists "user_collections_insert_own" on public.user_collections;
drop policy if exists "user_collections_update_own" on public.user_collections;
drop policy if exists "user_collections_delete_own" on public.user_collections;

drop policy if exists "user_collection_comics_select_own" on public.user_collection_comics;
drop policy if exists "user_collection_comics_insert_own" on public.user_collection_comics;
drop policy if exists "user_collection_comics_update_own" on public.user_collection_comics;
drop policy if exists "user_collection_comics_delete_own" on public.user_collection_comics;

drop policy if exists "user_progress_select_own" on public.user_progress;
drop policy if exists "user_progress_insert_own" on public.user_progress;
drop policy if exists "user_progress_update_own" on public.user_progress;
drop policy if exists "user_progress_delete_own" on public.user_progress;

drop policy if exists "user_history_entries_select_own" on public.user_history_entries;
drop policy if exists "user_history_entries_insert_own" on public.user_history_entries;
drop policy if exists "user_history_entries_update_own" on public.user_history_entries;
drop policy if exists "user_history_entries_delete_own" on public.user_history_entries;

drop policy if exists "user_favorite_scenes_select_own" on public.user_favorite_scenes;
drop policy if exists "user_favorite_scenes_insert_own" on public.user_favorite_scenes;
drop policy if exists "user_favorite_scenes_update_own" on public.user_favorite_scenes;
drop policy if exists "user_favorite_scenes_delete_own" on public.user_favorite_scenes;

drop policy if exists "user_download_entries_select_own" on public.user_download_entries;
drop policy if exists "user_download_entries_insert_own" on public.user_download_entries;
drop policy if exists "user_download_entries_update_own" on public.user_download_entries;
drop policy if exists "user_download_entries_delete_own" on public.user_download_entries;

-- profiles
create policy "profiles_select_own"
on public.profiles
for select
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = id);

create policy "profiles_insert_own"
on public.profiles
for insert
to authenticated
with check ((select auth.uid()) is not null and (select auth.uid()) = id);

create policy "profiles_update_own"
on public.profiles
for update
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = id)
with check ((select auth.uid()) is not null and (select auth.uid()) = id);

create policy "profiles_delete_own"
on public.profiles
for delete
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = id);

-- reader_preferences
create policy "reader_preferences_select_own"
on public.reader_preferences
for select
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "reader_preferences_insert_own"
on public.reader_preferences
for insert
to authenticated
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "reader_preferences_update_own"
on public.reader_preferences
for update
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id)
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "reader_preferences_delete_own"
on public.reader_preferences
for delete
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

-- user_bookmarks
create policy "user_bookmarks_select_own"
on public.user_bookmarks
for select
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "user_bookmarks_insert_own"
on public.user_bookmarks
for insert
to authenticated
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "user_bookmarks_update_own"
on public.user_bookmarks
for update
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id)
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "user_bookmarks_delete_own"
on public.user_bookmarks
for delete
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

-- user_collections
create policy "user_collections_select_own"
on public.user_collections
for select
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "user_collections_insert_own"
on public.user_collections
for insert
to authenticated
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "user_collections_update_own"
on public.user_collections
for update
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id)
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "user_collections_delete_own"
on public.user_collections
for delete
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

-- user_collection_comics
create policy "user_collection_comics_select_own"
on public.user_collection_comics
for select
to authenticated
using (
  exists (
    select 1
    from public.user_collections c
    where c.id = collection_id
      and c.user_id = (select auth.uid())
  )
);

create policy "user_collection_comics_insert_own"
on public.user_collection_comics
for insert
to authenticated
with check (
  exists (
    select 1
    from public.user_collections c
    where c.id = collection_id
      and c.user_id = (select auth.uid())
  )
);

create policy "user_collection_comics_update_own"
on public.user_collection_comics
for update
to authenticated
using (
  exists (
    select 1
    from public.user_collections c
    where c.id = collection_id
      and c.user_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1
    from public.user_collections c
    where c.id = collection_id
      and c.user_id = (select auth.uid())
  )
);

create policy "user_collection_comics_delete_own"
on public.user_collection_comics
for delete
to authenticated
using (
  exists (
    select 1
    from public.user_collections c
    where c.id = collection_id
      and c.user_id = (select auth.uid())
  )
);

-- user_progress
create policy "user_progress_select_own"
on public.user_progress
for select
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "user_progress_insert_own"
on public.user_progress
for insert
to authenticated
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "user_progress_update_own"
on public.user_progress
for update
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id)
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "user_progress_delete_own"
on public.user_progress
for delete
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

-- user_history_entries
create policy "user_history_entries_select_own"
on public.user_history_entries
for select
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "user_history_entries_insert_own"
on public.user_history_entries
for insert
to authenticated
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "user_history_entries_update_own"
on public.user_history_entries
for update
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id)
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "user_history_entries_delete_own"
on public.user_history_entries
for delete
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

-- user_favorite_scenes
create policy "user_favorite_scenes_select_own"
on public.user_favorite_scenes
for select
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "user_favorite_scenes_insert_own"
on public.user_favorite_scenes
for insert
to authenticated
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "user_favorite_scenes_update_own"
on public.user_favorite_scenes
for update
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id)
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "user_favorite_scenes_delete_own"
on public.user_favorite_scenes
for delete
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

-- user_download_entries
create policy "user_download_entries_select_own"
on public.user_download_entries
for select
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "user_download_entries_insert_own"
on public.user_download_entries
for insert
to authenticated
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "user_download_entries_update_own"
on public.user_download_entries
for update
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id)
with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy "user_download_entries_delete_own"
on public.user_download_entries
for delete
to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

-- Optional bootstrap: create public profile + default reader_preferences row when a new auth user is created
do $$
begin
  if exists (
    select 1
    from information_schema.tables
    where table_schema = 'auth' and table_name = 'users'
  ) then
    create or replace function public.handle_new_auth_user_defaults()
    returns trigger
    language plpgsql
    security definer
    set search_path = public
    as $fn$
    begin
      insert into public.profiles (id, display_name)
      values (
        new.id,
        coalesce(
          new.raw_user_meta_data->>'display_name',
          new.raw_user_meta_data->>'full_name',
          new.raw_user_meta_data->>'name'
        )
      )
      on conflict (id) do nothing;

      insert into public.reader_preferences (user_id)
      values (new.id)
      on conflict (user_id) do nothing;
      return new;
    end;
    $fn$;

    drop trigger if exists on_auth_user_created_defaults on auth.users;

    create trigger on_auth_user_created_defaults
      after insert on auth.users
      for each row execute procedure public.handle_new_auth_user_defaults();
  end if;
end $$;

commit;
