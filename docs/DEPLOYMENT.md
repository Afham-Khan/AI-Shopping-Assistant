# Deploying Zelora for free (beginner guide)

This guide puts Zelora on the internet without paying anything and without a credit card. It is written for Windows
and PowerShell. Every command can be copied as it is; things you must replace are written in `<angle brackets>`.

Last checked: 17 November 2026. Free plans change often, so a "Verified" note below means "I read the provider's own
page on that date", and "Not verified" means exactly that.

## 0. Read this first

### The four pieces

| Piece | What it does | Where it lives | Cost |
| --- | --- | --- | --- |
| Database | products, users, orders, AI vectors | **Neon** (free PostgreSQL) | free, no card |
| API (backend) | the Node.js server with the AI | **your laptop**, shown to the world by a **Cloudflare quick tunnel** (or Render, see C2) | free, no account |
| Website | the Flutter web app | **Vercel** (static files) | free |
| Android app | the same app as an APK | installed by hand on a phone | free |

```
phone / browser --> Vercel (website) --> https://something.trycloudflare.com --> your laptop (API) --> Neon (database)
```

### Why the API is not on a "real" free server

The plan was a free always-on host. I checked each one on 17 Nov 2026:

| Host | Result |
| --- | --- |
| **Hugging Face Spaces** (Docker) | **Not possible.** Their docs say Docker Spaces "require a paid plan to create: PRO for personal accounts" ([Spaces overview](https://huggingface.co/docs/hub/spaces-overview)), and forum threads show free accounts being asked to add billing to create one. Second blocker: Spaces can only open outgoing connections on ports 80, 443 and 8080, but Postgres uses 5432, so a Space could not reach Neon anyway. |
| **Koyeb** | Not possible. Its pricing page lists no free compute instance, only a free Postgres. |
| **Render** | Their own docs do **not** say a card is needed for a free web service, but you told me it asked for one, and old community threads say the `render.yaml` "Blueprint" flow asks for payment info. So it is only an optional path, see C2. |
| **Fly.io, Railway** | Reported (by Render's own comparison article, so treat it as marketing) to need a card or to give only a small trial credit. Not checked further. |
| **Laptop + Cloudflare quick tunnel** | **Works.** Cloudflare's docs: quick tunnels need no account and no domain. This is the main path of this guide. |

The honest consequence: **the API is online only while your laptop runs it.** That is fine for a presentation and
for testing with friends, and section G explains how to run presentation day safely. The website (Vercel) and the
database (Neon) are online all the time.

### What you need installed

- Node.js 20 or newer (`node -v`; 22 is what we use) and Git. 
- A GitHub account (you have it), a Neon account and a Vercel account (you have it). Sign in to Neon and Vercel with
  "Continue with GitHub", no card is asked for.
- Flutter 3.47 is needed only on the machine that builds the Android APK (Daniyal's), and for building the website
  by hand. The GitHub Action builds the website for you.

PowerShell first-timer warning: Windows may refuse `npm` tools that come as `.ps1` scripts ("running scripts is
disabled on this system"). In this guide Vercel is always called `vercel.cmd` and our script is started with
`powershell -ExecutionPolicy Bypass -File ...`, which avoids the problem without changing any Windows setting.

---

## A. Create the free database on Neon

1. Open <https://neon.com> and click **Sign up**, then **Continue with GitHub**.
2. Click **New project** (or **Create project**). Name it `zelora`. Keep the default Postgres version. For **Region**
   pick the one nearest to you (Singapore if it is offered, otherwise Frankfurt). Click **Create**.
3. On the project page click the **Connect** button. In the dialog:
   - Branch `main` (production), Database `neondb`, Role `neondb_owner`.
   - Switch **Connection pooling** **off**. The host in the string must then *not* contain `-pooler`. (Zelora keeps
     at most 5 connections open, so the direct connection is plenty and avoids pooler surprises.)
   - Click **Show password**, then copy the **connection string**. It looks like
     `postgresql://neondb_owner:xxxx@ep-something-123456.ap-southeast-1.aws.neon.tech/neondb?sslmode=require`
4. Paste it into a password manager or a private note. **It contains your database password. Never put it in a
   chat, a screenshot or a Git commit.**

Verified on Neon's pricing page: the Free plan is permanent ("not a trial; no credit card required"), 1 GB of storage
per project, 100 compute-hours per project per month, and the database **suspends itself after 5 minutes without
use** (the first query after that takes a moment longer while it wakes up). Our database is about 16 MB.

## B. Fill the database from your laptop (run once)

This creates the tables, loads the demo shop (194 products, users, orders, reviews) and builds the AI search index.

```powershell
cd "C:\Users\dell\Desktop\WEB DEVP\Flutter\cartwise\backend"
npm install
$env:DATABASE_URL = '<paste the Neon connection string here, keep the single quotes>'
$env:ADMIN_PASSWORD = '<choose a long password for the admin account>'
npm run deploy:init
```

(If your project folder is somewhere else, change the first line.)

What it does, in order: **migrate** (create tables), **seed** (data, with `IMAGE_MODE=cdn` so product pictures stay on
`https://cdn.dummyjson.com/...`), **ai:index** (MiniLM text vectors for search, and the CLIP picture index for
Snap & Find). The first run downloads the AI models (about 23 MB, and about 150 MB for CLIP) into `backend\.cache`.

- On my laptop against a local database: migrate 6 s, seed 8 s, text index 57 s. Against Neon over the internet
  expect several minutes, and a few more for the CLIP picture index (I did not measure the CLIP step).
- You can run it again at any time; every step is safe to repeat.
- To skip Snap & Find's picture index: `npm run deploy:init -- --skip-visual`.
- `ADMIN_PASSWORD` matters: the seed would otherwise use the default admin password that is public in this
  repository. Without `ADMIN_PASSWORD`, `deploy:init` on a hosted database creates the admin account *locked*
  (nobody can log in as admin), which is also safe. The admin account can change prices and stock.

When it finishes, open Neon > **Tables**: `products` should show 194 rows.

The demo shopper for presentations is created by the same step: **demo@cartwise.app / Demo@1234** (it has orders, a
wishlist and a cart). Running the seed again resets this password to the same value.

## C. Run the API and make it reachable

### C1. Laptop + Cloudflare quick tunnel (main path)

**One time setup**

1. Install the tunnel program: `winget install --id Cloudflare.cloudflared` (the package exists, I checked).
   Close PowerShell and open it again, then `cloudflared --version` should print a version.
2. Create the settings file:
   ```powershell
   cd "C:\Users\dell\Desktop\WEB DEVP\Flutter\cartwise\backend"
   Copy-Item production.env.example .env.production
   notepad .env.production
   ```
   Fill in `DATABASE_URL` (the Neon string from step A) and the two secrets. Make each secret with
   `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"` (run it twice, paste the results).
   Leave `CORS_ORIGINS` for step E. `.env.production` is ignored by Git; never commit it.

**Every time you want the API online** (two PowerShell windows, keep both open)

Window 1, the API:
```powershell
cd "C:\Users\dell\Desktop\WEB DEVP\Flutter\cartwise\backend"
npm run start:prod
```
Wait for `Cartwise API running on http://localhost:5000/api/v1 (database ep-....neon.tech/neondb)`.

Window 2, the tunnel:
```powershell
cloudflared tunnel --url http://localhost:5000
```
After a few seconds it prints a line with an address like `https://random-words-here.trycloudflare.com`. **That is
your public API address.** Test it in a third window (note `curl.exe`, plain `curl` is something else in PowerShell):
```powershell
curl.exe https://random-words-here.trycloudflare.com/api/v1/health
```
It must answer `{"success":true,"data":{"status":"ok",...}}`.

Good to know (verified in Cloudflare's docs): quick tunnels have **no uptime guarantee**, handle up to 200 requests
at the same moment, and **the address is new every time you start the tunnel**. If your network blocks the
tunnel, try `cloudflared tunnel --protocol http2 --url http://localhost:5000`. Keep the laptop plugged in and stop it
from sleeping (Settings > System > Power & sleep > "When plugged in, PC goes to sleep after" > Never).

Measured on my laptop: the API needs about 170 MB of memory with the text AI, about 350 MB once Snap & Find's CLIP
model is loaded, and up to about 500 MB while it builds the picture index. A laptop does not care.

### C2. Optional: Render free web service (only if Render lets you in without a card)

Skip this unless you have tried it and Render accepted you without payment details. Create the service by hand
(**New > Web Service**), not with a Blueprint file (there is no `render.yaml` in this repo on purpose).

| Setting | Value |
| --- | --- |
| Repository / branch | `Afham-Khan/AI-Shopping-Assistant`, branch `main` |
| Root Directory | `backend` |
| Runtime | Node |
| Build Command | `npm ci --omit=dev && npm run ai:prefetch` |
| Start Command | `node server.js` |
| Instance type | Free (512 MB RAM) |
| Health Check Path | `/api/v1/health` |

Environment variables: everything in `backend/production.env.example`, but **`AI_VISUAL=off`** (CLIP is too big for
512 MB), and leave out `PORT` (Render sets it). Verified in Render's docs: a free service goes to sleep after 15
minutes without traffic and needs about a minute to wake on the next request; you get 750 free hours a month. Not
verified: that files downloaded during the build (the AI models) are still there at run time. If the service runs
out of memory, set `AI_EMBEDDINGS=tfidf`.

The service address (`https://<name>.onrender.com`) is stable, so on Render the website never needs a rebuild.

### C3. Any other host that runs Docker

`backend/Dockerfile` builds a ready image (non-root user, models downloaded at build time, the trained intent model
included, port 7860 unless the host sets `PORT`). I could not run Docker on this machine, so it is **not tested**:

```powershell
docker build -t zelora-api backend
docker run -p 7860:7860 -e DATABASE_URL='...' -e JWT_ACCESS_SECRET='...' -e JWT_REFRESH_SECRET='...' -e CORS_ORIGINS='https://your-project.vercel.app' zelora-api
```
Use `--build-arg AI_VISUAL=off` for hosts with less than 1 GB of RAM.

---

## D. Build the website and put it on Vercel

The website is a Flutter web app. Vercel's build machines have no Flutter, so the app is built on GitHub (an "Action")
or on your laptop, and only the finished files are uploaded.

The API address is **baked into the build**. Give it the address from step C. With the quick tunnel the address
changes every time, so the website must be rebuilt (about 5-10 minutes in the Action) whenever you restart the
tunnel. That is the price of having no card.

### D1. Create the Vercel project and collect three values (once)

```powershell
npm install -g vercel
vercel.cmd login
```
`vercel.cmd login` opens a browser: choose **Continue with GitHub**. Then create an empty project **outside** the
repository, so Vercel does not try to build Flutter from Git:

```powershell
mkdir $env:TEMP\zelora-vercel
cd $env:TEMP\zelora-vercel
vercel.cmd link
```
Answer: *Set up?* **Y**, *Which scope?* your account, *Link to existing project?* **N**, *Project name?* `zelora`
(if the name is taken, add a few letters), *Code directory?* press Enter (the wording of the questions can differ a
little between CLI versions). Then show the values:

```powershell
Get-Content .vercel\project.json
```
Write down `orgId` and `projectId`. The third value is a token: on <https://vercel.com/account/tokens> click
**Create Token**, name it `github-actions`, pick an expiry, **Create**, and copy it now (it is shown only once).

Do **not** import the GitHub repository in the Vercel dashboard ("Add New > Project"). Vercel would try to build it on
every push and fail. If you already did, open the project > **Settings > Git > Disconnect**.

If, after deploying, the site asks visitors to log in to Vercel, open the project > **Settings > Deployment
Protection** and set Vercel Authentication to disabled for production (not verified how your dashboard words it).

### D2. Recommended: the GitHub Action

The workflow file is `.github/workflows/deploy-web.yml`. It installs Flutter 3.47, builds, and uploads `build/web`.

1. On GitHub open the repository > **Settings > Secrets and variables > Actions**.
2. Tab **Secrets** > **New repository secret**, three times: `VERCEL_TOKEN`, `VERCEL_ORG_ID` (the `orgId`),
   `VERCEL_PROJECT_ID` (the `projectId`).
3. Tab **Variables** > **New repository variable**: `API_BASE_URL` = your API address, for example
   `https://random-words-here.trycloudflare.com` (no slash at the end, no `/api/v1`).
4. Open the **Actions** tab > **Deploy web to Vercel** > **Run workflow**. You can type a different API address in the
   box (handy after a tunnel restart, no need to touch the variable).
5. When the run is green (about 5-10 minutes), the website is at `https://zelora.vercel.app` (or the name you chose).

It also runs by itself whenever `main` changes something under `mobile/`. The **Run workflow** button only appears
once the workflow file is on the default branch, so use D3 until the pull request in section J is merged.

### D3. Alternative: build and upload from your laptop

Needs Flutter on this machine and, on 8 GB of RAM, closing Chrome and Android Studio first.

```powershell
cd "C:\Users\dell\Desktop\WEB DEVP\Flutter\cartwise\mobile"
$env:VERCEL_ORG_ID = '<orgId>'
$env:VERCEL_PROJECT_ID = '<projectId>'
powershell -ExecutionPolicy Bypass -File .\tool\build_web_prod.ps1 -ApiBaseUrl https://random-words-here.trycloudflare.com -Deploy
```
The script runs `flutter build web --release --dart-define=API_BASE_URL=...`, copies `vercel.json` into `build\web` and
uploads it (it asks you to log in with `vercel.cmd login` if you have not). Without `-Deploy` it only builds; upload
later with `cd build\web` then `vercel.cmd deploy --prod` (set the two `$env:` lines first).

### D4. Not recommended: let Vercel build Flutter itself

Possible in theory (Project Settings > Root Directory `mobile`; Install Command that downloads the Flutter SDK with
`git clone https://github.com/flutter/flutter.git -b 3.47.5 --depth 1`; Build Command `flutter build web --release
--dart-define=API_BASE_URL=$API_BASE_URL`; Output Directory `build/web`). **Not tested**, it adds minutes to every
build, and it needs the repository connected to Vercel. The Action in D2 is simpler.

### What the web build already does for slow phones

Release mode minifies the code and removes unused icons from the font. `web/index.html` shows the Zelora logo with a
bobbing animation and three dots, drawn with a few lines of CSS (under 3 KB, no external fonts) until Flutter paints
its first frame. `vercel.json` makes every unknown address open the app (so refreshing `/product/12` works) and makes
the browser re-check `index.html`, `main.dart.js` and `flutter_bootstrap.js` on every visit; only the icons are cached
for a week. (Flutter does not put hashes in its file names, so a long cache on the other files would serve stale
code after a deploy.) CanvasKit and the Google fonts come from Google's CDN, which the page opens a connection to early.

## E. Tell the API which website may call it (CORS)

Browsers only let a website call an API that names it. Take the website address from D (for example
`https://zelora.vercel.app`, no slash at the end), put it into `backend\.env.production`:

```
CORS_ORIGINS=https://zelora.vercel.app
```
and restart window 1 (`Ctrl+C`, then `npm run start:prod`). Several websites: separate them with commas. `https://*.vercel.app`
allows all your preview deployments. If `CORS_ORIGINS` is missing in production, the API blocks every other website and
prints a warning at start (the Android app does not care about CORS). Check it:

```powershell
curl.exe -i -H "Origin: https://zelora.vercel.app" https://random-words-here.trycloudflare.com/api/v1/health
```
The answer must contain `Access-Control-Allow-Origin: https://zelora.vercel.app`.

## F. Smoke test checklist

Open the website on your laptop **and** on a phone (mobile data, not your home Wi-Fi). Press `F12` > **Console** on the
laptop and watch for red errors.

- [ ] `https://<tunnel>/api/v1/health` answers `ok`.
- [ ] The website shows the logo loader, then the home screen. The footer line says "Store online".
- [ ] Product pictures appear (they come from cdn.dummyjson.com; a few seconds of delay is normal).
- [ ] Sign in with `demo@cartwise.app` / `Demo@1234`.
- [ ] Search "wireless earbuds" and open a product.
- [ ] Ask the assistant: "gift for my mom under 5000" and get a reply with products.
- [ ] Compare two products; add one to the cart; open the cart.
- [ ] Place an order (cash on delivery) and see it under Orders.
- [ ] Snap & Find: upload a photo of a shoe or phone (needs `AI_VISUAL=on` and the picture index from step B).
- [ ] Refresh the page while on a product page: it must reopen that product, not a 404.
- [ ] No red CORS or network errors in the Console.

## G. Presentation day

The API depends on your laptop and the tunnel address changes every start, so **plan the order of things**:

1. **The day before:** do the whole smoke test (F) on the real Wi-Fi at the venue if you can. Write the demo steps on
   paper. Record a 2-minute screen video of the demo as a last resort.
2. **Two hours before:** plug in the laptop, turn off sleep, close everything heavy. Start window 1 (API) and window 2
   (tunnel). **Copy the new tunnel address.**
3. **Deploy the website for that address** (D2 with the address typed in the box). It takes 5-10 minutes, so do not
   leave it to the last moment.
4. **30 minutes before:** update `CORS_ORIGINS` only if the Vercel address changed (it normally does not), open the
   website on a phone, sign in with the demo account, and ask the assistant one question. That also wakes the free
   database (it sleeps after 5 minutes) and warms up the AI.
5. **Two minutes before:** open `.../api/v1/health` once more. On Render (C2) this step is the "wake up" call: a
   sleeping free service needs about a minute, so open its health address two minutes before you start.
6. Use the demo account **demo@cartwise.app / Demo@1234**. If someone changed its state, `npm run db:seed` with
   `DATABASE_URL` set restores the demo password.

**Fallbacks, in this order**

1. The tunnel died: Ctrl+C in window 2, start it again, run the Action with the new address (or use 2.).
2. Quick fix without a rebuild: the website was built with a fixed address, so it cannot be changed in the app. For
   the **Android app built without a fixed address** (section I), open Settings > Server address and type the new one.
3. The venue Wi-Fi blocks the tunnel: use your phone's hotspot for the laptop.
4. Everything online fails: run it all locally. In `backend`: `npm run dev` (uses `.env`, the local database). In
   `mobile`: `flutter run -d chrome`. For a phone on the same Wi-Fi, build the APK pointing at the laptop's address
   (`http://192.168.x.x:5000`, see `ipconfig`).
5. Last resort: the screen video.

Also: the assistant works fully offline. A Gemini key (`LLM_PROVIDER=gemini` in `backend\.env`) only polishes the
wording, and the app silently falls back to its own replies if the free quota is used up.

## H. Costs and limits (the honest list)

Everything below is **free and needs no card**. Nothing is "unlimited":

| Service | What you get | What can bite you |
| --- | --- | --- |
| Neon Free (verified) | 1 GB per project, 100 compute-hours per project per month, never expires | the database sleeps after 5 idle minutes (a slower first request); if compute-hours run out it pauses until the next month |
| Cloudflare quick tunnel (verified) | free, no account | new address every start, no uptime promise, 200 simultaneous requests, "for testing and development, not production" |
| Vercel Hobby | free static hosting for the website | 100 deployments a day and a 45 minute build limit (verified); Hobby is meant for personal, non-commercial use (not verified here) |
| GitHub Actions | the build runs there | free for public repositories; private repositories get a monthly allowance of free minutes (not verified); one build is roughly 5-10 minutes |
| cdn.dummyjson.com | the product pictures | a free third-party service; it answers with a rate limit header of 100 requests per short window, so a very fast scroll can show a few empty pictures. It sends `Access-Control-Allow-Origin: *`, which Flutter web needs (verified). If it ever goes away, run `npm run images:cache` locally to keep copies, they are about 31 MB |
| Gemini (optional) | free key for nicer chat wording | free quota; the app falls back to local replies |
| Render (optional, C2) | 512 MB, 750 hours/month | sleeps after 15 minutes, about 1 minute to wake (verified) |

The sign-up "OTP" (verification code) emails are not sent unless you fill in `SMTP_*`; without it the code is printed in
the API window. Fine for a demo.

## I. Android APK (for Daniyal's machine, with Android Studio)

Needs Flutter 3.47 and the Android SDK from Android Studio (`flutter doctor` must be green for Android).

**Option 1, address baked in** (use it when the API has a stable address, for example on Render):
```powershell
cd "<path>\cartwise\mobile"
flutter build apk --release --dart-define=API_BASE_URL=https://<your-api-address>
```

**Option 2, address typed in the app** (use it with the quick tunnel, whose address keeps changing):
```powershell
flutter build apk --release
```
Then, in the app: on the sign-in screen tap "Can't reach the store · check server address" (or Profile > Settings),
open **Server address**, type the current tunnel address, **Save**, and press **Test connection**. With Option 1 this
field is locked on purpose.

The file is `mobile\build\app\outputs\flutter-apk\app-release.apk`. To install it:
- copy it to the phone (USB cable, Google Drive, WhatsApp "document"), open it, and allow "Install unknown apps" for
  the app you opened it from; or
- with USB debugging on: `adb install -r build\app\outputs\flutter-apk\app-release.apk`.

The release build is signed with the debug key (see `android/app/build.gradle.kts`), which is fine for installing by
hand but not for the Play Store. The phone's launch screen now shows the Zelora logo on the soft blue wash (Android 12 and
newer use the system splash screen, older versions a drawable). I did not build the APK, so that part is **not tested on a device**.

## J. Pull request: staging into main

The branches are `main` (what is deployed) <- `staging` <- `feature/backend`, `feature/frontend`. The Action deploys
whenever `main` changes under `mobile/`.

1. Make sure everything is committed on `staging` and pushed:
   ```powershell
   cd "C:\Users\dell\Desktop\WEB DEVP\Flutter\cartwise"
   git status
   git push origin staging
   ```
2. Check the quality gates on your laptop: in `backend` run `npm test` (all green), in `mobile` run `flutter analyze`
   (no issues) and `flutter test`.
3. On GitHub: **Pull requests > New pull request**, base `main`, compare `staging`. Title
   "Release: deployment setup and assistant improvements". In the description list what changed (deployment files,
   Neon support, CORS, loading screens) and what you tested.
4. Ask one teammate to review. Use **Create a merge commit** (the history already uses merge commits).
5. Before merging, add the secrets and the `API_BASE_URL` variable from D2, otherwise the workflow stops at its first
   step (harmless, just a red cross). After the merge it starts by itself because `mobile/` changed. Watch it in the
   Actions tab. From now on the **Run workflow** button also works.
6. Nothing in this PR deploys the API or touches the database; those are steps B and C, run by a person.

If you use the GitHub command line: `gh pr create --base main --head staging --title "Release: ..." --fill`.

---

## Appendix 1: environment variables

| Name | Used by | Meaning |
| --- | --- | --- |
| `DATABASE_URL` | API, deploy:init, migrations | Neon connection string; replaces the `DB_*` values. Ignored when `NODE_ENV=test` |
| `DB_SSL` | API | `true`/`false` forces TLS; by default TLS is used when the URL has `sslmode=require` |
| `DB_POOL_MAX` | API | connections per process, default 5 |
| `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` | API | local database, used when there is no `DATABASE_URL` |
| `TEST_DATABASE_URL` | tests | only if you really want the tests on a remote database |
| `NODE_ENV` | API | `production` on a deployed API (stricter CORS, refuses weak JWT secrets) |
| `PORT` | API | default 5000 (7860 in the Docker image) |
| `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET` | API | two different random strings of 24+ characters |
| `CORS_ORIGINS` | API | allowed website addresses, comma separated, `*` inside an entry matches one subdomain |
| `IMAGE_MODE` | seed, images:cache | `cdn` (default in production or with `DATABASE_URL`) or `local` |
| `ADMIN_PASSWORD` | seed | password of `admin@zelora.app` on a hosted database |
| `AI_EMBEDDINGS` | API, ai:index | `neural` (MiniLM) or `tfidf` (no model download, less memory) |
| `AI_VISUAL` | API, ai:index | `off` skips CLIP: Snap & Find answers "unavailable", everything else works |
| `LLM_PROVIDER`, `GEMINI_API_KEY`, `GEMINI_MODEL` | API | optional nicer wording, see `backend/.env.example` |
| `SMTP_*`, `MAIL_FROM` | API | optional real emails |
| `API_BASE_URL` | Flutter build | `--dart-define`; GitHub repo variable for the Action |
| `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID` | GitHub Action, `-Deploy` | Vercel access |

## Appendix 2: when something goes wrong

| What you see | Probable cause and fix |
| --- | --- |
| `npm run deploy:init` says `DATABASE_URL is not set` | set it in the same PowerShell window you run the command in |
| `password authentication failed` / `ENOTFOUND` | the string was copied wrong or the internet is down; copy it again from Neon > Connect |
| `The API refuses to start: needs real secrets` | fill `JWT_ACCESS_SECRET` and `JWT_REFRESH_SECRET` in `.env.production` |
| Website loads but "Can't reach the store" | the tunnel/API is not running, or the website was built with an old tunnel address: rebuild (D2) |
| Red `CORS` error in the browser console | `CORS_ORIGINS` must equal the website address exactly (`https://`, no slash); restart the API |
| `vercel : ... running scripts is disabled` | type `vercel.cmd` instead of `vercel` |
| Product pictures missing | cdn.dummyjson.com is slow or limiting; reload. Check `IMAGE_MODE` (a database cached with `images:cache` needs the seed with `IMAGE_MODE=cdn`) |
| Snap & Find says unavailable | `AI_VISUAL=off`, or the picture index is missing: run `npm run deploy:init` again without `--skip-visual` |
| Cloudflare answers 502/1033 | the API (window 1) is not running, or the tunnel was restarted and the address changed |
| Action fails at "Check the settings" | a secret or the `API_BASE_URL` variable is missing (step D2) |

## Appendix 3: what I could not verify

- A real deploy to Neon, Vercel and GitHub Actions: I made no accounts and deployed nothing. The workflow YAML parses
  and the Vercel path patterns compile, but neither ran.
- `npm run deploy:init` ran for real against a scratch local PostgreSQL (with TLS off); the TLS branch for Neon was
  checked only by unit-style checks of the connection settings.
- The Docker image, the Android splash screens, the iOS launch screen and the build on Vercel's machines.
- Whether Render accepts you without a card, and whether its build output (the downloaded AI models) survives to run time.
- How long the CLIP step takes against Neon.
