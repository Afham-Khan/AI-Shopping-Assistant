# Zelora — AI Shopping Assistant

Zelora is a mobile shopping app with **Zel**, an AI assistant that recommends products from what you ask for —
in English or Roman-Urdu ("acha phone chahiye 1 lakh tak, camera achi ho"). Built for the Mobile Application
Development course (project: *AI Shopping Assistant — recommends products based on user requirements*).

| Part | Tech | Folder |
|---|---|---|
| Mobile app (Android, iOS, web) | Flutter + Dart, Riverpod, go_router, Dio | [`mobile/`](mobile) |
| API + AI | Node.js, Express 5, knex | [`backend/`](backend) |
| Database | PostgreSQL (local) / Neon (live) | `backend/api/db/migrations` |
| Docs | API contract, frontend conventions, deployment, AI training | [`docs/`](docs), [`backend/docs/`](backend/docs) |

## What the AI does

All of it runs on our own backend — free, offline-capable, answers in ~200 ms. Gemini (free tier) is optional and only
answers truly off-topic questions.

- **Understands requests**: trained intent classifier (softmax logistic regression on TF-IDF n-grams, 26 intents,
  ~91% held-out accuracy) + entity extraction for budget ("1.5 lakh", "50k"), category, brand, gender, features,
  "the second one", "not Apple", Roman-Urdu and typos.
- **Finds and ranks products**: hybrid search (BM25 + MiniLM sentence embeddings) and an explainable ranker — every
  pick shows *why* ("Within your Rs 50,000 budget", "4.6★ from 210 reviews").
- **Conversation**: remembers context ("cheaper", "only Samsung", "compare the first two", "add it to cart").
- **Features**: Snap & Find (CLIP image search that rejects non-product photos), Build my setup / Bundle Builder
  (budget optimisation — knapsack), Compare with "best for your need", review pros/cons, spec explainer, gift finder,
  complete the look, smart cart savings, price watch alerts, Discover swipe deck that learns your taste,
  Shopping DNA, and an **AI Lab** screen that shows the model's accuracy and how it read each sentence.

## Run it locally (Windows)

You need: Flutter 3.47+, Node.js 20+, PostgreSQL 17. Open two terminals in the project folder.

**Terminal 1 — database + API**

```powershell
cd backend
npm install            # first time only
npm run db:start       # starts the project database (port 5433); skip if it says "already running"
npm run dev            # API on http://localhost:5000/api/v1
```

**Terminal 2 — app in Chrome**

```powershell
cd mobile
flutter pub get        # first time only
flutter run -d chrome --web-port 8090
```

Sign in with **Continue with demo account** (`demo@cartwise.app` / `Demo@1234`).

**First time on a new machine** (e.g. a teammate): create `backend/.env` from `backend/.env.example`
(set your own PostgreSQL password/port), then run `npm run setup` once — it creates the database, tables, sample
catalog (194 products), trains the AI and builds the search index.

### Android Studio
Open the `mobile` folder → pick an emulator → Run. The emulator reaches your computer's API at `10.0.2.2:5000`
(already configured). On a real phone on the same Wi-Fi, set the server address in the app: **Profile → Settings →
Server address** → `http://<your-PC-IP>:5000`.

## Live version

- API: Render (free) · Database: Neon (free, Singapore) · Web app: Vercel — steps in [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).
- The free API sleeps after 15 minutes idle: open the app ~2 minutes before a demo so the first request wakes it.
- Snap & Find is off on the free live server (not enough memory); it works when running locally.

## Making changes (git workflow)

`main` = live · `staging` = tested work · `feature/*` = in-progress work.

```powershell
git checkout staging
git pull
git checkout -b feature/my-change      # new branch for your change
# ...edit files...
git add .
git commit -m "feat: describe the change"
git push -u origin feature/my-change
```

Then on GitHub: open a pull request **feature/my-change → staging**, merge it, and when ready a pull request
**staging → main**. Merging into `main` redeploys the API on Render automatically (and the web app via GitHub Actions).

## Tests

```powershell
cd backend; npm test          # 358 API + AI tests (test cases in backend/test/*.md)
cd mobile;  flutter test      # 309 app tests
```

## More docs
- [docs/API.md](docs/API.md) — every endpoint
- [docs/FRONTEND.md](docs/FRONTEND.md) — app structure, design system, widgets
- [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) — going live for free
- [backend/docs/AI_TRAINING.md](backend/docs/AI_TRAINING.md) — how the AI works and how to train it
