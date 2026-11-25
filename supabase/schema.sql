-- =====================================================================
--  App Punzonatura barre — schema del database (Supabase)
--  Da eseguire UNA VOLTA nel SQL Editor del progetto Supabase.
--  Si può rieseguire: crea solo ciò che manca.
-- =====================================================================

-- ---------- Profili utente (nome + ruolo) ----------
create table if not exists public.profili (
  id      uuid primary key references auth.users(id) on delete cascade,
  nome    text not null,
  ruolo   text not null default 'operatore' check (ruolo in ('admin','operatore','lettore')),
  attivo  boolean not null default true,
  creato  timestamptz not null default now()
);

-- Ruolo dell'utente collegato (null se non attivo)
create or replace function public.mio_ruolo() returns text
language sql stable security definer set search_path = public as $$
  select ruolo from public.profili where id = auth.uid() and attivo
$$;

-- Ogni utente creato in Authentication riceve un profilo "operatore"
create or replace function public.nuovo_utente() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profili (id, nome) values (new.id, split_part(new.email, '@', 1))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.nuovo_utente();

-- Profili per gli utenti già esistenti (se lo script viene eseguito dopo averli creati)
insert into public.profili (id, nome)
  select id, split_part(email, '@', 1) from auth.users
  on conflict (id) do nothing;

-- ---------- Dati dell'app ----------
create table if not exists public.ordini (
  id text primary key,                 -- ODP
  data jsonb not null,
  aggiornato timestamptz not null default now()
);

create table if not exists public.config (
  id text primary key,                 -- impostazioni, compat, import
  data jsonb not null,
  aggiornato timestamptz not null default now()
);

create table if not exists public.punzonature (
  id text primary key,
  uid uuid not null default auth.uid() references auth.users(id),
  creato timestamptz not null default now(),   -- ora di arrivo sul server
  data jsonb not null
);
create index if not exists punzonature_odp on public.punzonature ((data->>'odp'));
create index if not exists punzonature_ts  on public.punzonature ((data->'tsMs'));

create table if not exists public.controlli (
  id text primary key,
  uid uuid not null default auth.uid() references auth.users(id),
  creato timestamptz not null default now(),
  data jsonb not null
);
create index if not exists controlli_ts on public.controlli ((data->'tsMs'));

-- data di modifica impostata dal server (l'app scarica solo gli ordini cambiati)
create or replace function public.tocca_aggiornato() returns trigger
language plpgsql set search_path = public as $$
begin new.aggiornato := now(); return new; end $$;
drop trigger if exists ordini_aggiornato on public.ordini;
create trigger ordini_aggiornato before insert or update on public.ordini for each row execute function public.tocca_aggiornato();
drop trigger if exists config_aggiornato on public.config;
create trigger config_aggiornato before insert or update on public.config for each row execute function public.tocca_aggiornato();
create index if not exists ordini_aggiornato_idx on public.ordini (aggiornato);

-- ---------- Registro non modificabile ----------
-- Di una punzonatura si possono cambiare solo "annullato" (una volta) e "verifica".
create or replace function public.protezione_punzonature() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.id <> old.id or new.uid <> old.uid or new.creato <> old.creato
     or (new.data - 'annullato' - 'verifica') is distinct from (old.data - 'annullato' - 'verifica') then
    raise exception 'Il registro delle punzonature non si può modificare';
  end if;
  if (new.data -> 'annullato') is distinct from (old.data -> 'annullato') then
    if coalesce(old.data -> 'annullato', 'null'::jsonb) <> 'null'::jsonb then
      raise exception 'Punzonatura già annullata';
    end if;
    if coalesce(public.mio_ruolo(), '') <> 'admin'
       and not (old.uid = auth.uid() and now() - old.creato < interval '5 minutes') then
      raise exception 'Annullamento non consentito: sono passati più di 5 minuti';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists protezione_punzonature on public.punzonature;
create trigger protezione_punzonature before update on public.punzonature
  for each row execute function public.protezione_punzonature();

-- ---------- Regole di accesso (RLS) ----------
alter table public.profili     enable row level security;
alter table public.ordini      enable row level security;
alter table public.config      enable row level security;
alter table public.punzonature enable row level security;
alter table public.controlli   enable row level security;

revoke all on public.profili, public.ordini, public.config, public.punzonature, public.controlli from anon;
grant select, update on public.profili to authenticated;
grant select, insert, update on public.ordini, public.config to authenticated;  -- gli ordini non si cancellano dall'app
grant select, insert, update on public.punzonature to authenticated;
grant select, insert on public.controlli to authenticated;
-- la funzione gestione-utenti usa il ruolo di servizio: nei progetti nuovi va autorizzato esplicitamente
grant usage on schema public to service_role;
grant select, insert, update on public.profili to service_role;
grant select on public.ordini, public.config, public.punzonature, public.controlli to service_role;
revoke execute on function public.nuovo_utente() from public, anon, authenticated;
revoke execute on function public.tocca_aggiornato() from public, anon, authenticated;
revoke execute on function public.protezione_punzonature() from public, anon, authenticated;
revoke execute on function public.mio_ruolo() from public, anon;
grant execute on function public.mio_ruolo() to authenticated;

drop policy if exists profili_lettura on public.profili;
create policy profili_lettura on public.profili for select to authenticated using (true);
drop policy if exists profili_admin on public.profili;
create policy profili_admin on public.profili for update to authenticated
  using (public.mio_ruolo() = 'admin') with check (public.mio_ruolo() = 'admin');

drop policy if exists ordini_lettura on public.ordini;
create policy ordini_lettura on public.ordini for select to authenticated using (public.mio_ruolo() is not null);
drop policy if exists ordini_admin on public.ordini;
create policy ordini_admin on public.ordini for all to authenticated
  using (public.mio_ruolo() = 'admin') with check (public.mio_ruolo() = 'admin');

drop policy if exists config_lettura on public.config;
create policy config_lettura on public.config for select to authenticated using (public.mio_ruolo() is not null);
drop policy if exists config_admin on public.config;
create policy config_admin on public.config for all to authenticated
  using (public.mio_ruolo() = 'admin') with check (public.mio_ruolo() = 'admin');

drop policy if exists punz_lettura on public.punzonature;
create policy punz_lettura on public.punzonature for select to authenticated using (public.mio_ruolo() is not null);
drop policy if exists punz_nuova on public.punzonature;
create policy punz_nuova on public.punzonature for insert to authenticated
  with check (uid = auth.uid() and data->>'uid' = auth.uid()::text and public.mio_ruolo() in ('admin','operatore'));
drop policy if exists punz_modifica on public.punzonature;
create policy punz_modifica on public.punzonature for update to authenticated
  using (public.mio_ruolo() in ('admin','operatore')) with check (public.mio_ruolo() in ('admin','operatore'));
-- nessuna regola di cancellazione: le punzonature non si cancellano

drop policy if exists ctrl_lettura on public.controlli;
create policy ctrl_lettura on public.controlli for select to authenticated using (public.mio_ruolo() is not null);
drop policy if exists ctrl_nuovo on public.controlli;
create policy ctrl_nuovo on public.controlli for insert to authenticated
  with check (uid = auth.uid() and data->>'uid' = auth.uid()::text and public.mio_ruolo() in ('admin','operatore'));

-- ---------- Foto (Storage) ----------
insert into storage.buckets (id, name, public) values ('foto', 'foto', false)
  on conflict (id) do nothing;

drop policy if exists foto_lettura on storage.objects;
create policy foto_lettura on storage.objects for select to authenticated
  using (bucket_id = 'foto' and public.mio_ruolo() is not null);
drop policy if exists foto_caricamento on storage.objects;
create policy foto_caricamento on storage.objects for insert to authenticated
  with check (bucket_id = 'foto' and public.mio_ruolo() in ('admin','operatore'));
-- nessuna modifica o cancellazione delle foto dall'app


-- =====================================================================
--  Ruoli: admin (Responsabile), assistente, referente (Referente valle),
--  operatore, lettore (sola lettura)
-- =====================================================================
alter table public.profili drop constraint if exists profili_ruolo_check;
alter table public.profili add constraint profili_ruolo_check
  check (ruolo in ('admin','assistente','referente','operatore','lettore'));

-- chi può caricare l'export (ordini) e registrare punzonature/verifiche
create or replace function public.puo_aggiornare_dati() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.mio_ruolo() in ('admin','assistente','referente'), false)
$$;
create or replace function public.puo_registrare() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.mio_ruolo() in ('admin','assistente','referente','operatore'), false)
$$;
revoke execute on function public.puo_aggiornare_dati() from public, anon;
revoke execute on function public.puo_registrare() from public, anon;
grant execute on function public.puo_aggiornare_dati() to authenticated;
grant execute on function public.puo_registrare() to authenticated;

-- ordini: export caricato da responsabile, assistente, referente
drop policy if exists ordini_admin on public.ordini;
drop policy if exists ordini_scrittura on public.ordini;
create policy ordini_scrittura on public.ordini for all to authenticated
  using (public.puo_aggiornare_dati()) with check (public.puo_aggiornare_dati());

-- config: impostazioni solo responsabile; la data dell'ultimo export anche gli altri che caricano
drop policy if exists config_admin on public.config;
create policy config_admin on public.config for all to authenticated
  using (public.mio_ruolo() = 'admin') with check (public.mio_ruolo() = 'admin');
drop policy if exists config_import on public.config;
create policy config_import on public.config for all to authenticated
  using (id = 'import' and public.puo_aggiornare_dati()) with check (id = 'import' and public.puo_aggiornare_dati());

-- punzonature: il referente vede solo le proprie
drop policy if exists punz_lettura on public.punzonature;
create policy punz_lettura on public.punzonature for select to authenticated
  using (public.mio_ruolo() is not null and (public.mio_ruolo() <> 'referente' or uid = auth.uid()));
drop policy if exists punz_nuova on public.punzonature;
create policy punz_nuova on public.punzonature for insert to authenticated
  with check (uid = auth.uid() and data->>'uid' = auth.uid()::text and public.puo_registrare());
drop policy if exists punz_modifica on public.punzonature;
create policy punz_modifica on public.punzonature for update to authenticated
  using (public.puo_registrare()) with check (public.puo_registrare());

-- verifiche: il referente vede solo le proprie
drop policy if exists ctrl_lettura on public.controlli;
create policy ctrl_lettura on public.controlli for select to authenticated
  using (public.mio_ruolo() is not null and (public.mio_ruolo() <> 'referente' or uid = auth.uid()));
drop policy if exists ctrl_nuovo on public.controlli;
create policy ctrl_nuovo on public.controlli for insert to authenticated
  with check (uid = auth.uid() and data->>'uid' = auth.uid()::text and public.puo_registrare());

-- foto
drop policy if exists foto_caricamento on storage.objects;
create policy foto_caricamento on storage.objects for insert to authenticated
  with check (bucket_id = 'foto' and public.puo_registrare());
