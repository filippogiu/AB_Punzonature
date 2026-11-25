# App Punzonatura barre — installazione

L'app è fatta di tre pezzi, tutti con piano gratuito:

| Pezzo | Servizio | A cosa serve |
|---|---|---|
| Codice | **GitHub** (repository privato) | conserva i file dell'app e lo storico delle modifiche |
| Pubblicazione | **Netlify** | mette online l'app a un indirizzo tipo `punzonatura.netlify.app` |
| Dati | **Supabase** | database, login con nome + PIN, foto |

La lettura delle etichette avviene nel telefono (OCR), gratis e senza account esterni.

Tempo totale: circa un'ora, da fare dal computer.

---

## 1. Supabase (database e utenti)

1. Vai su **supabase.com** → *Start your project* → registrati (anche con l'account GitHub).
2. **New project**
   - Name: `punzonatura`
   - Database password: scegline una e **conservala**
   - Region: **Central EU (Frankfurt)**, così i dati restano in Europa
   - Piano: **Free**
3. Quando il progetto è pronto, apri **SQL Editor** (menu a sinistra) → *New query* → incolla **tutto** il contenuto del file `supabase/schema.sql` → **Run**. Deve comparire "Success".
4. **Blocca le registrazioni libere**: *Authentication → Sign In / Providers → Email* (o *Settings*) → disattiva **Allow new users to sign up** → Save. Così gli utenti li crei solo tu.
5. **Crea il tuo utente**: *Authentication → Users → Add user → Create new user*
   - Email: `filippo@pz.example.com` (il nome prima della @ è il **nome utente**; non viene mai inviata nessuna email)
   - Password: il tuo **PIN**, almeno **6 cifre**
   - Spunta **Auto Confirm User** → Create user
6. **Diventa responsabile**: torna in *SQL Editor*, esegui:
   ```sql
   update public.profili set ruolo = 'admin' where nome = 'filippo';
   ```
7. Crea allo stesso modo gli utenti dei colleghi (`mario@pz.example.com` + PIN). Entrano come **Operatore**; il ruolo si cambia poi dall'app (*Dati → Utenti*).
8. Prendi i due dati di collegamento: pulsante **Connect** in alto nella pagina del progetto, oppure:
   - **Project URL**: *Integrations → Data API* (es. `https://abcdefgh.supabase.co`; il codice è lo stesso che vedi nella barra degli indirizzi dopo `/project/`)
   - **chiave publishable** (`sb_publishable_…`): *Settings → API Keys*. È pubblica per natura: i dati sono protetti dal login e dalle regole del database. **Non usare mai la chiave secret.**
9. In *Integrations → Data API* controlla che il Data API sia **attivo**.

## 2. GitHub (codice)

1. Vai su **github.com** → registrati.
2. **New repository** → nome `punzonatura` → **Private** → *Create repository*.
3. *uploading an existing file* → trascina **tutti i file e le cartelle** di questo pacchetto (`index.html`, `config.js`, `lib/`, `ocr/`, `supabase/`, ecc.) → *Commit changes*.
4. Apri `config.js` nel repository → matita (*Edit*) → incolla **Project URL** e **chiave** tra gli apici:
   ```js
   url: 'https://abcdefgh.supabase.co',
   key: 'sb_publishable_...',
   ```
   → *Commit changes*.

> In alternativa al punto 3: collega il repository a Claude e carico io i file.

## 3. Netlify (pubblicazione)

1. Vai su **netlify.com** → *Sign up* → **con GitHub**.
2. *Add new site → Import an existing project → GitHub* → autorizza → scegli `punzonatura`.
3. Build command: **vuoto**. Publish directory: **vuoto** (o `/`). → **Deploy**.
4. Dopo un minuto l'app è online. In *Site configuration → Change site name* puoi darle un nome, es. `punzonatura-bz` → `https://punzonatura-bz.netlify.app`.

Da qui in poi ogni modifica salvata su GitHub viene pubblicata da sola.

## 4. Primo utilizzo

1. Apri l'indirizzo Netlify, entra con **nome utente** (`filippo`) e **PIN**.
2. *Dati* → carica l'**export Excel** del gestionale.
3. Controlla le **tolleranze per pressa** e le impostazioni.
4. Sui telefoni dei colleghi: apri l'indirizzo in **Chrome** (Android) o **Safari** (iPhone), entra, poi menu → **Aggiungi a schermata Home**.

## Note

- **Se Supabase rifiuta l'email `@pz.example.com`**: usa un altro dominio (anche quello aziendale: nessuna email viene inviata) e scrivilo in `config.js` alla voce `domain`.

- **Cambio PIN**: ognuno può cambiarlo dall'app (*Cambia PIN*). Se qualcuno lo dimentica: Supabase → *Authentication → Users* → utente → *Reset password* / imposta un nuovo PIN.
- **Disattivare un utente**: *Dati → Utenti* → togli la spunta "Attivo".
- **Registro non modificabile**: le punzonature non si possono cancellare né modificare; si possono solo annullare con motivo (operatore entro 5 minuti, responsabile sempre). Lo impone il database, non solo l'app.
- **Senza rete**: l'app si apre anche offline dopo il primo accesso; le punzonature restano sul telefono e partono quando torna la connessione.
- **Piano gratuito Supabase**: 500 MB di database, 1 GB di foto; il progetto va in pausa dopo **una settimana senza utilizzo** (si riattiva dal sito di Supabase). Nessun backup automatico: esporta ogni tanto il registro in Excel (*Registro → Esporta Excel*).
- **Storico dell'app su Claude**: le punzonature fatte finora sull'app di Claude non vengono copiate automaticamente; si possono importare in un secondo momento.
