// Edge Function "gestione-utenti": il responsabile crea utenti e reimposta i PIN dall'app.
// Usa la chiave di servizio che Supabase mette a disposizione delle funzioni: non va mai nell'app.
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });

function chiaveServizio(): string {
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacy) return legacy;
  const nuove = Deno.env.get("SUPABASE_SECRET_KEYS") || "";
  if (nuove.trim().startsWith("{")) {
    const o = JSON.parse(nuove);
    return o.default || Object.values(o)[0] as string;
  }
  return nuove;
}

const RUOLI = ["operatore", "lettore", "admin"];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, chiaveServizio(), { auth: { persistSession: false } });
    const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    const { data: { user }, error: eu } = await admin.auth.getUser(token);
    if (eu || !user) return json({ error: "Accesso non valido: rientra nell'app." }, 401);
    const { data: io } = await admin.from("profili").select("ruolo,attivo").eq("id", user.id).single();
    if (!io || io.ruolo !== "admin" || !io.attivo) return json({ error: "Solo il responsabile può gestire gli utenti." }, 403);

    const b = await req.json();
    const pin = String(b.pin ?? "");
    if (!/^\d{6,12}$/.test(pin)) return json({ error: "Il PIN deve avere da 6 a 12 cifre." }, 400);

    if (b.azione === "crea") {
      const nome = String(b.nome ?? "").trim().toLowerCase();
      const ruolo = String(b.ruolo ?? "operatore");
      const dominio = String(b.domain ?? "").trim();
      if (!/^[a-z0-9._-]{2,30}$/.test(nome)) return json({ error: "Nome utente: 2-30 caratteri, solo lettere minuscole, numeri, punto, trattino." }, 400);
      if (!RUOLI.includes(ruolo)) return json({ error: "Ruolo non valido." }, 400);
      if (!/^[a-z0-9.-]+\.[a-z]{2,}$/i.test(dominio)) return json({ error: "Dominio non valido in config.js." }, 400);
      const { data, error } = await admin.auth.admin.createUser({ email: `${nome}@${dominio}`, password: pin, email_confirm: true });
      if (error) return json({ error: /already|exists|registered/i.test(error.message) ? "Esiste già un utente con questo nome." : error.message }, 400);
      const { error: ep } = await admin.from("profili").upsert({ id: data.user.id, nome, ruolo, attivo: true });
      if (ep) return json({ error: ep.message }, 500);
      return json({ ok: true });
    }

    if (b.azione === "pin") {
      const id = String(b.id ?? "");
      if (!/^[0-9a-f-]{36}$/i.test(id)) return json({ error: "Utente non valido." }, 400);
      const { error } = await admin.auth.admin.updateUserById(id, { password: pin });
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    return json({ error: "Azione sconosciuta." }, 400);
  } catch (e) {
    return json({ error: String((e as Error)?.message || e) }, 500);
  }
});
