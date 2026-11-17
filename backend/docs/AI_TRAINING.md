# Training Zel, the Zelora AI assistant

This guide is for whoever "trains the AI". You don't need a machine-learning background: most of the work is
adding example sentences, running one command, and checking the numbers.

Everything runs **offline** on our own server. There is no paid AI service. A free Gemini key is optional
(see the last section).

---

## 1. How Zel works (the pipeline)

```
 shopper types: "sasta mobile chahiye 30k tak 📱"
        │
        ▼
 ┌──────────────────────────────┐
 │ 1. NORMALIZER  nlu/normalizer│  lower-case, emojis -> words (📱 -> phone), Roman Urdu -> English
 │                              │  (sasta -> cheap, chahiye -> want, "30k tak" -> "upto 30k"), typo fixes
 └──────────────┬───────────────┘
                ▼
 ┌──────────────────────────────┐
 │ 2. ENTITIES    nlu/entities  │  budget (Rs 30,000), category (smartphones), brand, colour, gender,
 │                              │  recipient (mom), occasion, features, "the second one", ...
 └──────────────┬───────────────┘
                ▼
 ┌──────────────────────────────┐   ┌───────────────────────────────────────────────┐
 │ 3. CLASSIFIER  nlu/classifier│   │ 3b. SCOPE RULES  nlu/scope.js                 │
 │  trained model -> intent +   │   │  safety (crisis, swearing), noise (gibberish, │
 │  confidence (0..1)           │   │  "50000", "???"), off-topic topic, store-FAQ  │
 │  e.g. product_search 0.93    │   │  topic, questions about Zel, vague shopping   │
 └──────────────┬───────────────┘   └───────────────────────┬───────────────────────┘
                └───────────────┬───────────────────────────┘
                                ▼
 ┌──────────────────────────────────────────────────────────┐
 │ 4. DIALOGUE MANAGER  dialogue/manager.js                  │
 │  picks the final intent using the model + rules + chat    │
 │  memory (what was shown before, pending questions)        │
 └──────────────┬───────────────────────────────────────────┘
                ▼
 ┌──────────────────────────────┐     ┌────────────────────────────┐
 │ 5. RETRIEVAL  retrieval/*    │     │ store FAQ   dialogue/faq.js │
 │  search 194 products by      │     │ off-topic   dialogue/       │
 │  keywords (BM25) + meaning   │     │   offscope.js               │
 │  (embeddings)                │     │ glossary    concepts.js     │
 └──────────────┬───────────────┘     └──────────────┬─────────────┘
                ▼                                    │
 ┌──────────────────────────────┐                    │
 │ 6. RANKING  ranking/*        │                    │
 │  fit, rating, price, your    │                    │
 │  taste -> "why this pick"    │                    │
 └──────────────┬───────────────┘                    │
                ▼                                    ▼
 ┌──────────────────────────────────────────────────────────┐
 │ 7. REPLY  dialogue/nlg.js -> text + product cards + chips │
 │  (optional: free LLM polishes wording / answers general   │
 │   questions; facts and prices always come from step 5)    │
 └──────────────────────────────────────────────────────────┘
```

All AI code is in `backend/api/modules/ai/engine/`.

### The intents (what the model can recognise)

| Intent | Example | Handled by |
|---|---|---|
| `product_search`, `recommendation`, `budget_query` | "gaming laptop under 300k" | search + ranking |
| `refine_cheaper`, `refine_premium`, `refine_filter`, `show_more` | "cheaper", "only samsung" | search with memory |
| `compare`, `product_info`, `add_to_cart`, `similar` ... | "compare the first two" | product handlers |
| `gift_suggestion`, `bundle`, `deals` | "gift for my sister" | gift / bundle builders |
| `order_status`, `cart_help`, `return_policy` | "where is my order" | your account data |
| `greeting`, `goodbye`, `thanks`, `help`, `small_talk` | "hi", "tell me a joke" | short replies |
| **`store_info`** | "do you deliver to Lahore", "payment methods", "any coupons" | `dialogue/faq.js` (real delivery/shipping/payment rules) |
| **`out_of_scope`** | "who won the match", "write my essay", "weather?" | `dialogue/offscope.js` (honest, redirects to shopping) |
| **`about_assistant`** | "who made you", "are you ChatGPT", "how do you work" | `dialogue/offscope.js` |
| **`feelings`** | "I'm sad", "main udaas hoon", "I passed my exams!" | kind reply (+ helpline for crisis messages) |
| **`abuse`** | "you are useless", swearing | polite boundary + redirect |

Bold intents were added for "unexpected questions". Two extra routes come from rules, not the model:
`concept` (glossary: "what does RAM mean", "difference between iPad and tablet") and `fallback`
(gibberish, emoji-only, odd numbers: Zel asks a clarifying question with category buttons).

---

## 2. Where the training data is

`backend/api/modules/ai/training/data/intents.json`

```json
{
  "intents": {
    "greeting": ["hi", "hello", "assalam o alaikum", ...],
    "store_info": ["do you deliver to lahore", "cod hai", ...],
    ...
  }
}
```

Each intent is just a list of example messages. The model learns from these examples. There are about
1,870 examples across 26 intents.

The trained model is saved to `backend/api/modules/ai/training/models/intent-model.json` (don't edit it by hand).

---

## 3. Adding examples (the main "training" job)

1. Open `intents.json` and find the intent.
2. Add new examples as lower-case strings. Good examples are **how real people type**:
   - different wordings: "how long is delivery", "how many days to deliver", "when will it arrive"
   - Roman Urdu: "delivery kitne din mein hoti hai", "kab tak aayega"
   - typos: "delivry time", "paymnt methods"
   - short and long versions: "cod?", "do you offer cash on delivery for all orders"
3. Rules of thumb:
   - Keep **at least 40 examples per intent** (the tests check this). 60-90 is better.
   - Never put the **same sentence in two intents**: the model gets confused.
   - Keep intents balanced: one intent with 300 examples and another with 40 skews the model.
   - Personal vs general matters: "where is **my** order" -> `order_status`; "how long is delivery" -> `store_info`.
4. Run training (next section) and check accuracy didn't drop.

### Adding a brand-new intent

1. Add `"my_new_intent": [ ...at least 40 examples... ]` to `intents.json`.
2. Add a handler in `dialogue/manager.js`: either a function in `HANDLERS` (needs database/products) or a
   short reply in `STATIC`. Without a handler the message falls back to "I'm not sure I followed".
3. If the intent's replies shouldn't rename the chat, add it to `NON_TOPICAL` in `controllers/ai.controller.js`.
4. Optional: add helpful "cue words" for the intent to `CUE_GROUPS` in `nlu/classifier.js`.
5. Retrain, add a test in `backend/test/ai.scope.test.js`, run `npm test`.

---

## 4. Training and reading the numbers

From `backend/`:

```bash
npm run ai:train
```

It takes a few minutes. Example output:

```
hold-out: logistic regression 91.4% | naive bayes 87.4%
5-fold cv accuracy: 88.7% ± 1.4
Samples: 1870 across 26 intents (train 1496 / test 374)
Test accuracy: 91.4%   macro-F1: 0.9121   ECE: 0.0293   temperature: 1

Per-class          precision  recall  f1     n
  store_info          0.85    1.00   0.92   22
  help                0.71    0.50   0.59   10
  ...
Most frequent confusions (actual -> predicted):
  help -> about_assistant: 3
```

What the numbers mean:

- **Test accuracy**: 20% of the examples are hidden during training and used as a quiz. Must stay **≥ 90%**
  (the command exits with an error below 90%, and the tests fail).
- **5-fold CV**: the same quiz repeated 5 times with different hidden parts, so it's more stable.
- **Per-class recall**: of the real `store_info` messages, how many it got right. Low recall = add more
  varied examples to that intent.
- **Precision**: when it says `store_info`, how often it's right. Low precision = another intent's
  examples look too similar; make them more distinct.
- **Confusions**: which intents get mixed up. Fix by adding examples that show the difference.
- **ECE** (calibration): how honest the confidence numbers are. Under 0.05 is good.

Restart the API afterwards so it loads the new model.

---

## 5. The probe: testing Zel with tricky messages

`backend/scripts/probeAssistant.js` sends ~130 realistic messages through Zel (off-topic, Roman Urdu, typos,
emojis, gibberish, multi-part questions, store questions...) and checks each reply makes sense.

```bash
node scripts/probeAssistant.js            # summary + writes test/ASSISTANT_PROBE.md
node scripts/probeAssistant.js --verbose  # also prints every message, intent, confidence and reply
node scripts/probeAssistant.js --llm      # same, but lets the optional Gemini fallback run
```

`test/ASSISTANT_PROBE.md` shows a before/after table against the saved baseline
(`test/fixtures/assistant-probe-baseline.json`). To add a probe message, add a line to `PROBES` in the
script: `['group', 'message text', check]`, where `check` is a small rule (for example
`all(noProducts, chips, has(/delivery/i))`).

Good workflow: run the probe, find a **no**, add training examples or a rule, retrain, run it again.

---

## 6. Synonyms and Roman Urdu words (the lexicon)

`backend/api/modules/ai/engine/nlu/lexicon.js`

- `ROMAN_URDU`: one word -> English. Add spellings people use:
  `sasta: 'cheap'`, `chahiye: 'want'`. Several spellings of the same word are normal (`chahiye`, `chaiye`, `chahye`).
- `IDIOMS`: multi-word patterns like "30k tak" -> "upto 30k".
- `CATEGORY_SYNONYMS`: words that mean a category: `smartphones: ['phone', 'mobile', 'handset', ...]`.
- `COLORS`, `FEATURES`, `OCCASIONS`, `RECIPIENTS`: same idea for colours, features ("gaming", "waterproof"),
  occasions ("eid", "wedding") and people ("ammi" -> mom).
- `EMOJI_WORDS`: emoji -> word (📱 -> phone, 🎁 -> gift, 😂 -> haha).
- `STOPWORDS`: filler words ignored by search.

Off-topic / FAQ / feelings detection patterns are in `nlu/scope.js` (`OOS_TOPICS`, `FAQ_TOPICS`,
`ABOUT_TOPICS`, `FEELING_TOPICS`). The replies are in `dialogue/offscope.js` and `dialogue/faq.js`. FAQ
answers read delivery days, free-shipping threshold and fees from `backend/helpers/constants.js`, the same
values checkout uses, so change them there and Zel updates automatically.

Lexicon changes take effect after an API restart. If you also changed `intents.json`, retrain first.

---

## 7. Re-indexing products

When products are added or their descriptions change, rebuild the search index (embeddings):

```bash
npm run ai:index
```

The keyword search and catalog reload by themselves; `ai:index` refreshes the "meaning" vectors. Full fresh
setup (database + model + index): `npm run setup`.

---

## 8. Optional: free Gemini fallback

By default Zel is 100% offline. With a free Gemini key, two extra things happen:

1. **General questions** (the `out_of_scope` intent only, e.g. "what is the capital of France") get a short
   answer in Zel's voice: at most 2 sentences, no products, prices or AI-company names, then a nudge back to
   shopping. Weather, news and scores are still "I can't check live info".
2. Product replies get their **wording** polished. Prices, products, delivery and policies always come from the
   local engine; if the LLM adds a number that wasn't in our facts, its text is thrown away.

Setup (in `backend/.env`):

```
LLM_PROVIDER=gemini
GEMINI_API_KEY=<free key from https://aistudio.google.com/apikey>
GEMINI_MODEL=gemini-3.5-flash-lite
```

Restart the API, then open `GET /api/v1/ai/insights`: `llm.enabled` should be `true` and `llm.usedToday`
counts calls.

Safety guard (all in `.env`, defaults shown): `LLM_RATE_PER_MIN=12`, `LLM_DAILY_LIMIT=800`, a 6-hour answer
cache (same question = no new call), and a circuit breaker that skips the LLM for 5 minutes after 3 failures.
Over any limit, on timeout (6 s), bad key or no internet, Zel silently uses the offline reply. Users never see
an error.

`npm test` always runs offline (`test/setup.js` forces `LLM_PROVIDER=none`), and the probe does too unless
you pass `--llm`.

The LLM may also never change which product is the **top pick**: if its rewrite names a different product
first than the first product card, the rewrite is thrown away and the offline reply is used.

---

## 9. Improving recommendations (no coding needed)

This is for when Zel shows the **wrong products**, for example "best running shoes" showing high heels.
You will: (1) write the bad case down as a test, (2) run one command, (3) read the report, and if it is a
product-data problem, (4) fix the product's keywords.

### Step 1: add the bad case to the golden set

Open `backend/api/modules/ai/training/data/ranking-eval.json`. Every line under `"queries"` is one test.
Copy a line that looks similar to your case, paste it at the end of the list (mind the comma between lines)
and change it:

```json
{ "id": "shoes-running-5", "q": "shoes for my morning run", "group": "use-case: running",
  "expectCategories": ["mens-shoes", "womens-shoes"], "mustMatchAny": ["sneaker", "trainer", "running"],
  "mustNotMatch": ["heel", "slipper", "sandal"], "color": null, "gender": null,
  "minPrice": null, "maxPrice": null, "brand": null, "minHits@3": 3 }
```

| Field | What to write |
| --- | --- |
| `id` | a new unique name |
| `q` | exactly what you typed in the app (typos and Roman Urdu are fine) |
| `expectCategories` | category slugs the top 3 must be in, or `null` for any. Slugs: `smartphones`, `laptops`, `tablets`, `mobile-accessories`, `mens-shirts`, `mens-shoes`, `mens-watches`, `tops`, `womens-dresses`, `womens-shoes`, `womens-bags`, `womens-jewellery`, `womens-watches`, `sunglasses`, `beauty`, `fragrances`, `skin-care`, `furniture`, `home-decoration`, `kitchen-accessories`, `groceries`, `sports-accessories`, `motorcycle`, `vehicle` |
| `mustMatchAny` | words a GOOD product has in its title, keywords or specs (`"sneaker"` also matches "sneakers") |
| `mustNotMatch` | words that make a product WRONG for this search (heels for running) |
| `color` | `"red"`, `"black"`, ... if you asked for a colour, else `null` |
| `gender` | `"men"` / `"women"` if you asked for one, else `null` |
| `maxPrice` / `minPrice` | your budget in rupees, else `null` |
| `brand` | e.g. `"Nike"` if you asked for a brand, else `null` |
| `minHits@3` | how many of the first 3 cards must be good (usually 2 or 3) |
| `followUps` | only for chats that ask a question first (gift finder: "What budget?"): e.g. `["no budget", "surprise me"]` |

The schema at the top of the file explains every field again.

### Step 2: run the evaluation

```bash
cd backend
npm run ai:eval -- --only=shoes-running-5   # just your new case, quick
npm run ai:eval                             # everything, writes test/RANKING_EVAL.md
npm run ai:eval -- --failures               # print only the failing cases
```

It uses your local database and takes a few seconds. No app or server needs to be running.

### Step 3: read the report

`backend/test/RANKING_EVAL.md` has the numbers at the top (BEFORE = the old ranking, AFTER = now) and one
row per query with the first 3 product titles and **PASS** or **FAIL** plus the reason:

| Reason in the report | Meaning |
| --- | --- |
| `only 1/3 relevant in top 3` | not enough of the first 3 cards match `mustMatchAny` |
| `#2 mustNotMatch: Red Shoes (heel)` | card 2 contains a forbidden word |
| `#1 color: ... (Black)` | card 1 is the wrong colour although a right-coloured product exists |
| `#3 gender / budget / brand / category` | card 3 breaks that requirement although a better product exists |
| `reply's top pick "X" is not the first card` | the text recommends a different product than the first card |
| `no products returned` | Zel showed nothing (asked a question, or misunderstood the message) |

Numbers: **pass rate** (share of PASS), **precision@3** (how many of the first 3 cards are good) and
**nDCG@5** (is the best product near the top; 1.0 is perfect). Higher is better for all three; violations
should be 0.

If the case fails, tell a developer which line fails. `npm test` now fails on any failing case, so if it can't
be fixed today add `"knownFailure": true` to that line: it stays in the report but doesn't block everyone.
If the catalogue simply has no right product (for example no women's running shoes), the evaluation already
allows for that and won't count it against Zel.

### Step 4: fix product data (keywords, colour, gender)

Often a product is ranked wrong because its data doesn't say what it is. Product data lives in
`backend/data/product-enrichment.json`, one block per product, keyed by the product number from
`backend/data/dummyjson-products.json` (search that file for the title to find it; e.g. `90` = Puma Future
Rider Trainers):

```json
"90": {
  "specs": { "Style": "Retro running", "Heel": "Flat" },
  "highlights": ["..."],
  "color": "White",
  "gender": "men",
  "keywords": ["puma", "trainers", "running shoes", "gym shoes", "joota"]
}
```

- `keywords`: add the words shoppers use ("running shoes", "gym shoes", "office wear", "gift for her").
  Zel reads them to decide what a product **is** (sneaker, heel, slipper, dress, charger...) and what it is
  **for** (running, gym, office, wedding, party, travel, summer...).
- `color`: the main colour. For two colours put both in the title or a `"Colourway": "Red and black"` spec,
  so "red & black" counts as red-ish.
- `gender`: `"men"`, `"women"` or `"unisex"`.

Then reload your **local** database and search index, restart the API and run the evaluation again:

```bash
npm run db:seed     # safe to repeat: updates products, never deletes anything
npm run ai:index    # recompute the "meaning" vectors
npm run ai:eval
```

Never run these against the live (Neon) database yourself; the lead does that when deploying.

For developers: the use-case and product-type word lists are `USE_CASES`, `TYPE_WORDS`, `TYPE_RULES` and
`USE_RULES` in `api/modules/ai/engine/ranking/attributes.js` (e.g. running = sneakers, never heels).

---

## Quick checklist

```bash
# 1. edit api/modules/ai/training/data/intents.json (and/or nlu/lexicon.js)
npm run ai:train                     # accuracy must stay >= 90%
node scripts/probeAssistant.js       # check test/ASSISTANT_PROBE.md
npm run ai:eval                      # recommendation relevance, check test/RANKING_EVAL.md
npm test                             # everything green
# 2. restart the API so it loads the new model
```

## 10. Checking the other AI features (`npm run ai:audit`)

Chat search has its own eval (section 9). Every other AI feature is checked by one audit script: compare, bundle builder, gift finder, complete the look, spec explainer, product Q&A, review summary, similar / bought together, cart insights, Shopping DNA, guided finder, the smart-search wrapper and Snap & Find.

```bash
npm run ai:audit                          # everything (~30 s; Snap & Find loads the image model)
npm run ai:audit -- --no-visual           # skip Snap & Find
npm run ai:audit -- --only gift,bundle    # just some features (does not rewrite the report)
npm run ai:audit -- --verbose             # also print the cases that pass
```

It runs about 270 realistic cases against the local database and only reads from it (carts and shopping histories are faked in memory). Each case is checked the way a shopper would check it. A gift for dad must not be a women's item. "Best value" must not lose to a cheaper, better-rated product. 8 GB RAM must not be called "flagship". "Is it automatic?" on a manual bike must get "No". A cart with a Samsung phone must not be offered an iPhone case.

**Reading the result.** The terminal prints a scorecard, for example `Gift finder 16/16 (100%)`, plus every failing case with its reasons:

```
FAIL dad likes travel, Rs 15,000 → Beats Flex…, Monopod, Party Glasses…
     - novelty "Party Glasses" for a general gift
```

The first line shows the input and the top results. Each `-` line is one problem, written in plain words. The same results go to `test/AI_FEATURE_AUDIT.md`, which shows **BEFORE** (the saved baseline) and **AFTER** (this run) side by side, the failing cases, and a Notes block that you can edit by hand (it is kept when the report is regenerated). Snap & Find also reports recall: how often a cropped, mirrored product photo finds the same product or category.

**When something fails:**
- *Wrong product type, gender or age* (a bedside table as a desk, a girls' dress in an adult look): first check the product's data (category, `gender`, the "Ideal For" spec). The shared rules live in `api/modules/ai/engine/complements.js`.
- *Wrong spec level or wording*: the rules are in `engine/explain.js` (one function per spec).
- *Q&A says "yes" wrongly*: add the feature's words to `FEATURE_WORDS` / `CONTRARY` in `engine/qa.js`.
- *Wrong pros/cons*: add the phrase to `engine/reviews/lexicon.js`.
- *Similar / bought together*: these come from `engine/ranking/recommender.js`.

Then run `npm run ai:audit` again, and `npm test`. To save a new BEFORE snapshot (only after a release, so the comparison stays meaningful), run `npm run ai:audit -- --baseline`.
