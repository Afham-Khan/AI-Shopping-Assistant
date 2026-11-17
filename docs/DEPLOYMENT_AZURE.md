# Deploying the Zelora API on Azure App Service (Azure for Students)

This guide puts the **backend with the full AI** (MiniLM neural search + CLIP Snap & Find) on Azure App Service, using
an **Azure for Students** subscription (no credit card). The database stays on the existing **Neon** PostgreSQL in
Singapore; it is already migrated, seeded and indexed, so nothing in this guide runs migrations or the seed.

The Flutter website stays on Vercel (see `docs/DEPLOYMENT.md`, step D). Only its `API_BASE_URL` changes.

The owner's setup used below:

| What | Value |
| --- | --- |
| Resource group | `zelora-rg` |
| App Service (Web App) name | `zelora-api` |
| Publish | Code, Linux, **Node 22 LTS** |
| Region | **Southeast Asia** (Singapore, same city as Neon) |
| Plan | **Basic B1** (1 vCPU, 1.75 GB RAM) |
| Application Insights | enabled |
| Address | `https://zelora-api-<random>.southeastasia-01.azurewebsites.net` (copy yours from the Overview page) |

---

## 0. Why these choices (read once)

* **Azure for Students** gives **$100 credit for 12 months, no credit card**, renewable every year while you are a
  student; when the credit runs out the subscription is disabled unless you choose to upgrade, so it can never bill
  you by surprise. ([offer page](https://azure.microsoft.com/en-us/free/students))
* **Why not the Free F1 plan:** F1 has 1 GB RAM and only **60 CPU minutes per day**, no Always On, and is not meant
  for production ([Linux pricing page](https://azure.microsoft.com/en-us/pricing/details/app-service/linux/)). The
  AI models alone need ~500 MB and every embedding burns CPU, so F1 would run out of CPU minutes during a demo.
* **B1** = 1 core, **1.75 GB RAM**, 10 GB storage. Measured locally in production mode: the API uses **~190 MB** at
  boot, **~200 MB** with MiniLM loaded, **~460-510 MB resident** after Snap & Find has loaded CLIP (peak 533 MB),
  so B1 has more than 1 GB of headroom.
* **Cost:** B1 Linux in Southeast Asia is **$0.018 per hour** (Azure Retail Prices API, Nov 2026), about
  **$13 per month** if it runs 24/7, so **$100 lasts about 7 months**. You pay for the *plan* while it exists, even
  if the app is stopped. To stop spending: delete the resource group, or scale the plan down to F1.
* **Southeast Asia** is the Singapore region, the same city as the Neon database, so each database query is a
  few milliseconds away.
* Student subscriptions only allow a few regions (an "Allowed resource deployment regions" policy, different per
  person). The owner's app was created in Southeast Asia, so it is allowed. If someone else gets a policy error,
  check **Azure Policy > Assignments > Allowed resource deployment regions > Parameters** and pick the allowed region
  nearest to Singapore (East Asia, then Central/South India, Japan East, Korea Central, Australia East).
  ([Microsoft Q&A](https://learn.microsoft.com/answers/a/12297582))

---

## 1. Activate Azure for Students (once)

1. Open <https://azure.microsoft.com/free/students> and click **Start free**.
2. Sign in with (or create) a Microsoft account using your **university email** (the SMIU address), and complete the
   academic verification sent to that email. No card is asked for.
3. When it finishes you land in the [Azure portal](https://portal.azure.com) with a subscription called
   **Azure for Students**.

### Keep an eye on the credit (instead of a budget alert)

Microsoft's Cost Management lists **Azure for Students (MS-AZR-0170P) as not supported**, so the usual "Budgets"
alert may not be available on this subscription
([Cost Management supported offers](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/understand-cost-mgt-data)).
What to do instead:

* Portal search bar > **Education** (the student hub) should show the remaining credit and the end date; otherwise
  **Subscriptions > Azure for Students > Overview**. Check it every week or two. Expect roughly $3 per week for B1.
* When the credit runs out Microsoft emails you to choose pay-as-you-go; if you don't, the subscription and its
  apps are **disabled**, never charged.
* If **Cost Management > Budgets** does open for your subscription, create one anyway: Scope = the subscription,
  Amount = $15 monthly, alerts at 80 % and 100 % to your email.
* Do not create extra plans, VMs or databases in this subscription: everything shares the $100.

---

## 2. Create the Web App (already done by the owner, for reference)

1. Portal > **Create a resource** > **Web App**.
2. **Basics**: Subscription *Azure for Students*; Resource group **Create new** `zelora-rg`; Name `zelora-api`;
   *Secure unique default hostname* on (Azure's default: the address gets a random suffix, e.g.
   `zelora-api-abc123.southeastasia-01.azurewebsites.net`); Publish **Code**; Runtime stack **Node 22 LTS**;
   Operating System **Linux**; Region **Southeast Asia**; Pricing plan: create a new Linux plan, **Basic B1**.
3. **Deployment** tab: **Basic authentication: Enable** (needed for the publish profile used by GitHub Actions).
   Leave *Continuous deployment* disabled: our own workflow file deploys.
4. **Monitoring** tab: Application Insights *Yes* is fine (it adds a small agent; the free 5 GB of logs per month is
   far more than this app writes).
5. **Review + create** > **Create**, then **Go to resource**.

### If Basic authentication was left disabled

The **Download publish profile** button stays greyed out until it is on.

1. App Service `zelora-api` > **Settings > Configuration** > **General settings** tab.
2. **SCM Basic Auth Publishing Credentials** = **On**. (*FTP Basic Auth Publishing Credentials* can stay Off: we
   never use FTP.)
3. **Save** at the top, then **Continue**.

---

## 3. App settings (environment variables)

The exact values are in **`backend/.env.azure.json`** on the lead's laptop (git-ignored, never commit it or paste it
into chat). The same values in `.env` format are in `backend/.env.azure`.

1. App Service > **Settings > Environment variables** > **App settings** tab.
2. Click **Advanced edit**. The box shows a JSON list with Azure's own entries (for example
   `APPLICATIONINSIGHTS_CONNECTION_STRING`, `ApplicationInsightsAgent_EXTENSION_VERSION`). **Keep those.**
3. Add the entries from `backend/.env.azure.json` inside the same `[ ... ]` list (add a comma between entries),
   then **OK**, then **Apply** at the bottom of the page, then **Confirm**. The app restarts.

The format is Azure's ([docs](https://learn.microsoft.com/en-us/azure/app-service/configure-common#edit-app-settings-in-bulk)):

```json
[
  { "name": "NODE_ENV", "value": "production", "slotSetting": false },
  { "name": "AI_CACHE_DIR", "value": "/home/.cache", "slotSetting": false }
]
```

What each setting is (values for the secret ones are only in the git-ignored files):

| Name | Value | Why |
| --- | --- | --- |
| `NODE_ENV` | `production` | production mode; the API refuses to start with weak JWT secrets |
| `DATABASE_URL` | Neon **direct** connection string, ends with `sslmode=require` | the database (TLS on) |
| `JWT_ACCESS_SECRET` | 64-char random | signs access tokens (same as the Render/laptop deploy, so existing logins keep working) |
| `JWT_REFRESH_SECRET` | 64-char random, different | signs refresh tokens |
| `AI_EMBEDDINGS` | `neural` | MiniLM semantic search |
| `AI_VISUAL` | `on` | Snap & Find (CLIP, loads on the first photo search) |
| `AI_CACHE_DIR` | `/home/.cache` | models are downloaded once to persistent storage and survive restarts and redeploys |
| `IMAGE_MODE` | `cdn` | product images come from the public CDN |
| `LLM_PROVIDER` | `gemini` | reply polishing |
| `GEMINI_API_KEY` | your key | |
| `GEMINI_MODEL` | `gemini-3.5-flash-lite` | |
| `CORS_ORIGINS` | `https://*.vercel.app` | lets the Vercel website (and its previews) call the API |
| `SCM_DO_BUILD_DURING_DEPLOYMENT` | `false` | the zip from GitHub Actions is already built (includes `node_modules`); Azure must not run `npm install` again ([docs](https://learn.microsoft.com/en-us/azure/app-service/reference-app-settings)) |
| `WEBSITES_CONTAINER_START_TIME_LIMIT` | `600` | gives the first boot up to 10 minutes instead of 230 s |

Not set on purpose:

* `PORT` / `WEBSITES_PORT`: App Service sets `PORT` itself for the Node image and forwards traffic to it; `server.js`
  already listens on `0.0.0.0:$PORT` ([docs](https://learn.microsoft.com/en-us/azure/app-service/configure-language-nodejs#set-the-port-number)).
  `WEBSITES_PORT` is only for custom containers.
* `WEBSITE_NODE_DEFAULT_VERSION`: Windows only. On Linux the Node version is the stack setting (step 4).
* `DATABASE_URL_POOLED`: only for the Vercel (serverless) deploy. A long-running App Service keeps its own small
  pool (5 connections) on the direct URL.

Optional:

* `AI_VISUAL_WARMUP` = `on`: loads CLIP in the background right after every start, so the first Snap & Find does
  not wait for it (uses the ~300 MB anyway, fine on B1). Turn it on for presentation day, after step 7.

---

## 4. General settings

App Service > **Settings > Configuration**:

1. **Stack settings** tab: Stack **Node**, Version **Node 22 LTS**, **Startup command** `node server.js`. **Save**.
   (Since Node 14 the image does not start PM2 by itself; an explicit command is the clearest. PM2 is optional.)
2. **General settings** tab:
   * **SCM Basic Auth Publishing Credentials**: **On** (see step 2).
   * **Always On**: **On**. Without it the app is unloaded after 20 minutes with no traffic and the next visitor
     waits for a cold start; with it, Azure pings the app every 5 minutes
     ([docs](https://learn.microsoft.com/en-us/azure/app-service/configure-common#configure-general-settings)).
     Available on B1, not on F1.
   * **HTTPS Only**: **On** (HTTP is redirected to HTTPS).
   * **Minimum TLS version**: 1.2 (default).
   * **HTTP version**: 2.0 is fine. **Session affinity**: Off (the API is stateless).
   * **Save** > **Continue**.
3. **Monitoring > Health check**: **Enable**, path `/api/v1/health`, **Save**. Azure pings it every minute; with a
   single instance it only replaces the instance after an hour of failures
   ([docs](https://learn.microsoft.com/en-us/azure/app-service/monitor-instances-health-check)). The API only
   starts listening after it reached the database, so a 200 here means "up and connected".

---

## 5. Connect GitHub (once)

1. App Service > **Overview** > **Download publish profile** (top bar). A `zelora-api.PublishSettings` file
   downloads. It is a password: never commit it, delete it after step 2.
   ([docs](https://learn.microsoft.com/en-us/azure/app-service/deploy-github-actions))
2. GitHub > `Afham-Khan/AI-Shopping-Assistant` > **Settings > Secrets and variables > Actions**:
   * **Secrets** tab > **New repository secret**: Name `AZURE_WEBAPP_PUBLISH_PROFILE`, Value = open the
     `.PublishSettings` file in Notepad, select all, paste. **Add secret**.
   * **Variables** tab > **New repository variable**: Name `AZURE_WEBAPP_NAME`, Value `zelora-api`.
     (The workflow falls back to `zelora-api` if the variable is missing. Always the app **name**, never the URL:
     the random hostname is read from the deploy step automatically.)
3. If you ever reset the publish profile (Overview > *Reset publish profile*), repeat step 1-2.

---

## 6. Deploy

The workflow is `.github/workflows/deploy-api-azure.yml`. It runs on every push to `main` that changes `backend/**`,
and by hand.

What it does: Node 22 on Ubuntu > `npm ci --omit=dev` in `backend/` > removes the Windows/macOS/arm64 ONNX binaries
and the browser-only `onnxruntime-web` > checks that `app.js` loads > downloads MiniLM + CLIP **in CI only** and
fails if either cannot load with these exact `node_modules` > zips `backend/` (without tests, logs, `.env*`,
`.cache`) > deploys with `azure/webapps-deploy@v3` > waits until `/api/v1/health` answers 200 (up to 5 minutes).

The models are **not** inside the zip (they would add ~170 MB to every deploy). The app downloads them once into
`/home/.cache` (persistent) on the first AI request, see Troubleshooting.

First run:

1. The workflow file has to be on `main` (GitHub only offers *Run workflow* for files on the default branch).
   Merge `staging` into `main` with a pull request (see `docs/DEPLOYMENT.md`, step J). The merge itself triggers
   the deploy because it changes `backend/**`.
2. Or by hand: GitHub > **Actions** > **Deploy API to Azure App Service** > **Run workflow** > branch `main` >
   **Run workflow**.
3. Open the run. All steps green = deployed. The last step prints the health URL.

---

## 7. Fill the CLIP vectors on Neon (once, by the lead, after approval)

Neon was indexed with `--skip-visual`, so `product_image_embeddings` is empty and Snap & Find has nothing to match
yet. Run this **once from the laptop** (the CLIP model is already in `backend/.cache`, and the laptop's CPU is much
faster than B1's single core):

```powershell
cd backend
npm run ai:index:visual -- --env .env.neon --yes
```

It writes **only** CLIP vectors (no migration, no seed, no text vectors), skips products that already have one (so
it is safe to re-run after a network error), downloads each thumbnail from the image CDN, and prints
`product_image_embeddings now holds 194/194 vectors`. About 2-4 minutes. Without `--yes` it refuses to write to a
hosted database. On the local database (`npm run ai:index:visual`) it took 68 s for 194 products.

The running API picks the vectors up by itself on the next Snap & Find request (no restart needed).

If nobody runs this and someone uses Snap & Find on the live site, the API starts building the same index itself
on B1's single core (several minutes) and answers "The visual index is still being built" (503) until it is done.

---

## 8. Verify

Replace the address with yours (App Service > Overview > *Default domain*):

```powershell
$api = "https://zelora-api-<random>.southeastasia-01.azurewebsites.net"
curl.exe -s "$api/api/v1/health"
curl.exe -s "$api/api/v1/ai/insights"
```

* health: `{"success":true,"data":{"status":"ok",...}}`
* insights: `"embeddings":{"mode":"neural","model":"Xenova/all-MiniLM-L6-v2",...,"neuralStatus":"ready"}`.
  Right after the very first start it can say `"mode":"tfidf","neuralStatus":"loading"` for up to a minute while
  MiniLM (23 MB) downloads to `/home/.cache`; search still works meanwhile (TF-IDF fallback).
* `"visual":{"enabled":true,"status":"idle","indexedImages":194}` after step 7 (`idle` = CLIP loads on the first
  photo search; `ready` once loaded).

Then in the app: sign in (or *Try demo*), ask the assistant "show me running shoes under 100 dollars" and
"mujhe sasti watch dikhao", and try Snap & Find with a product photo.

---

## 9. Point the website at the new API

1. GitHub > **Settings > Secrets and variables > Actions > Variables** > `API_BASE_URL` > **Edit**: the App Service
   address **without** a trailing slash and **without** `/api/v1`, e.g.
   `https://zelora-api-<random>.southeastasia-01.azurewebsites.net`.
2. **Actions** > **Deploy web to Vercel** > **Run workflow** (or push a change under `mobile/`). The new build calls
   Azure.
3. Android APK: `flutter build apk --release --dart-define=API_BASE_URL=<same address>`.
4. `CORS_ORIGINS=https://*.vercel.app` already allows `https://<project>.vercel.app`. A custom domain must be added
   to `CORS_ORIGINS` (comma separated).

---

## Troubleshooting

**Log stream.** App Service > **Monitoring > Log stream** shows the app's console live. A good start prints
`Cartwise API running on http://localhost:<port>/api/v1 (database ep-....neon.tech/neondb)` (the port is the
internal one Azure assigns through `PORT`, usually 8080; that is normal). Lines like `GET /robots933456.txt 404` are Azure's warm-up probe: ignore them
([docs](https://learn.microsoft.com/en-us/azure/app-service/configure-language-nodejs#ignore-the-robots933456-message-in-logs)).
For older logs: **Advanced Tools > Go** (Kudu) > *Log stream* or `/home/LogFiles`.

**First boot is slow / first AI answers are plain.** On the very first start `/home/.cache` is empty: MiniLM
(23 MB) is downloaded in the background after boot, CLIP (~150 MB) on the first Snap & Find. Locally the first
Snap & Find, including the CLIP download, took ~106 s; afterwards ~0.5-0.8 s. Restarts and redeploys reuse
`/home/.cache` (only the load, ~10-20 s, remains). To check the cache: Kudu (**Advanced Tools > Go**) > **Bash** >
`du -sh /home/.cache/transformers`.

**Snap & Find answers 503.** Either CLIP is still loading (wait a minute, try again; set `AI_VISUAL_WARMUP=on` so
it loads right after boot), or the CLIP vectors are missing on Neon ("The visual index is still being built"):
run step 7. App Service cuts any request at about **230-240 seconds** (load balancer limit, not configurable,
[docs](https://learn.microsoft.com/en-us/troubleshoot/azure/app-service/web-request-times-out-app-service)); if
the very first photo search hits that while CLIP downloads, the model keeps loading in the background and the
next try works.

**"Cannot reach PostgreSQL" / first request after a pause is slow.** Neon's free compute sleeps when idle and needs
a few seconds to wake up. `server.js` retries the database 5 times (2, 4, 6, 8 s) before giving up; Always On plus
the health check keep the API connected so Neon rarely sleeps during the day. If it still fails: check
`DATABASE_URL` (direct string, ends with `sslmode=require`) and that the Neon project is not suspended.

**App does not start, log says `NODE_ENV=production needs real secrets`.** `JWT_ACCESS_SECRET` /
`JWT_REFRESH_SECRET` are missing or shorter than 24 characters: fix them in Environment variables.

**Application Error page / container keeps restarting.** Log stream first. Check the startup command is exactly
`node server.js` and that `SCM_DO_BUILD_DURING_DEPLOYMENT=false` (otherwise Azure re-runs `npm install` and may
break the bundled native binaries).

**Workflow fails at "Check the settings".** The secret `AZURE_WEBAPP_PUBLISH_PROFILE` is missing (step 5).
**Fails at "Deploy" with 401/403.** SCM Basic Auth Publishing Credentials is Off, or the publish profile was reset:
turn it on, download a fresh profile, update the secret.

**Browser shows a CORS error.** The website's origin is not in `CORS_ORIGINS`. Requests without an Origin header
(the Android app, curl, health checks) are never blocked.

**Memory.** App Service > **Diagnose and solve problems** > *Memory* or **Metrics** > *Memory working set*. Expected
~0.5 GB with both models loaded; B1 has 1.75 GB. Application Insights' agent adds a little; it can be switched off
under **Monitoring > Application Insights** if needed.

**Stop spending.** Deleting the resource group `zelora-rg` removes everything (the app, the plan, Application
Insights). Stopping the app alone does **not** stop the B1 charge.

---

## Sources checked (November 2026)

* Azure for Students offer: <https://azure.microsoft.com/en-us/free/students>
* Region policy on student subscriptions: <https://learn.microsoft.com/answers/a/12297582>
* App Service Linux plans (F1/B1 specs): <https://azure.microsoft.com/en-us/pricing/details/app-service/linux/>;
  B1 Linux price per region: Azure Retail Prices API `https://prices.azure.com/api/retail/prices`
* Node.js on App Service Linux (PORT, startup command, PM2, logs):
  <https://learn.microsoft.com/en-us/azure/app-service/configure-language-nodejs>
* GitHub Actions + publish profile: <https://learn.microsoft.com/en-us/azure/app-service/deploy-github-actions>
* Zip deploy (no build by default, 2 GB limit): <https://learn.microsoft.com/en-us/azure/app-service/deploy-zip>
* App settings, Advanced edit, Always On, HTTPS Only: <https://learn.microsoft.com/en-us/azure/app-service/configure-common>
* App settings reference (`SCM_DO_BUILD_DURING_DEPLOYMENT`, `WEBSITES_CONTAINER_START_TIME_LIMIT`, `PORT`, `/home`):
  <https://learn.microsoft.com/en-us/azure/app-service/reference-app-settings>
* Linux FAQ (persistent `/home`, start time limit, `WEBSITES_PORT` only for custom containers):
  <https://learn.microsoft.com/en-us/troubleshoot/azure/app-service/faqs-app-service-linux>
* Health check: <https://learn.microsoft.com/en-us/azure/app-service/monitor-instances-health-check>
* Request timeout: <https://learn.microsoft.com/en-us/troubleshoot/azure/app-service/web-request-times-out-app-service>
* Cost Management supported offers: <https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/understand-cost-mgt-data>
