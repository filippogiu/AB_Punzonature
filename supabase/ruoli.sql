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
