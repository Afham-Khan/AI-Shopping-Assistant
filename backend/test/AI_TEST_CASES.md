# Cartwise AI — test cases

Unit tests (`ai.nlu`, `ai.engine`, `ai.reviews`, `ai.compare`) run without a database. Integration tests (`ai.api`) need the migrated and seeded DB. If the DB is unreachable they skip themselves.

## NLU (`test/ai.nlu.test.js`)

| ID | Scenario | Input | Expected |
|---|---|---|---|
| NLU-01 | Budget "under 50k" | `phones under 50k` | budget `{min:null,max:50000}`, category `smartphones` |
| NLU-02 | Budget in lakh | `gaming laptop under 1.5 lakh` | max `150000`, category `laptops`, feature `gaming` |
| NLU-03 | Range | `phones between 20k and 40k` | `{min:20000,max:40000}` |
| NLU-04 | Dollar conversion | `headphones under $200` | max `56000` (USD × 280) |
| NLU-05 | Comma formats / Rs prefix | `Rs. 25,000 ka phone` | max `25000` |
| NLU-06 | Around | `gift around 10k` | `{min:8000,max:12000,target:10000}` |
| NLU-07 | 1.5L and lac | `bike 2 lac tak`, `under 1.5L` | `200000`, `150000` |
| NLU-08 | Not a budget | `iphone 13`, `16 gb ram`, `5000 mah battery` | budget `null` |
| NLU-09 | Synonyms | `mobile`, `notebook`, `sneakers for men`, `scent`, `sofa`, `makeup` | smartphones, laptops, mens-shoes, fragrances, furniture, beauty |
| NLU-10 | Gendered generic words | `watch for my husband`, `shoes for my sister` | mens-watches + men, womens-shoes + women |
| NLU-11 | Typos | `smartphnoe`, `laptp`, `samsng galxy` | corrected + correct category/brand, `corrections` listed |
| NLU-12 | No false corrections | `see you later`, `take care` | no corrections |
| NLU-13 | Roman Urdu | `sasta mobile chahiye 30k tak` | smartphones, max 30000, sort price_asc |
| NLU-14 | Roman Urdu idioms | `50 hazar se kam joote` | max 50000, shoes |
| NLU-15 | Ordinals | `compare the first two`, `the 3rd`, `last one`, `compare 1 and 3` | `[1,2]`, `[3]`, `[-1]`, `[1,3]` |
| NLU-16 | Negations | `samsung phones not apple`, `no black`, `apple nahi chahiye` | excludeBrands apple (samsung kept), excludeColors black |
| NLU-17 | Recipient → gender | `gift for mom`, `present for my brother` | women/mom, men/brother |
| NLU-18 | Occasion, rating, sort | `perfume for eid 4 stars+ best rated` | occasion eid, minRating 4, sort rating |
| NLU-19 | Kitchen request | `something for my kitchen` | kitchen-accessories, home department |
| NLU-20 | Apple fruit vs brand | `fresh green apples` | no brand |
| NLU-21 | Classifier quality | trained artifact | test accuracy ≥ 0.90, ≥ 15 classes, ≥ 40 samples/class |
| NLU-22 | Intent predictions | 20 representative utterances | expected intent each |
| NLU-23 | Low confidence fallback | `asdfgh qwerty` | confidence < 0.45 |
| NLU-24 | Entity-driven inference | gibberish + `laptop` | product_search |

## Engine (`test/ai.engine.test.js`)

| ID | Scenario | Expected |
|---|---|---|
| ENG-01 | Damerau-Levenshtein transposition | `smartphnoe`/`smartphone` = 1 |
| ENG-02 | Jacobi eigen-decomposition | reconstructs a symmetric matrix; eigenvalues match |
| ENG-03 | BM25 | title match ranks above description-only match |
| ENG-04 | TF-IDF/LSA space | "notebook for games" closest to a gaming laptop doc |
| ENG-05 | Ranker reasons | budget, feature evidence, rating and discount reasons |
| ENG-06 | Budget fit | in-budget > over-budget |
| ENG-07 | MMR | near-duplicates are not all selected |
| ENG-08 | Slot merge | follow-up keeps category; topic change resets; exclusions remove brand |
| ENG-09 | Cheaper / premium refinement | max below median shown / min above median |
| ENG-10 | LLM grounding | rewrite with an invented price is rejected |
| ENG-11 | Finder budget brackets | ascending, cover range, include "No limit" |
| ENG-12 | Finder answers → slots | fashion women shoes → womens-shoes + gender |

## Reviews (`test/ai.reviews.test.js`)

| ID | Scenario | Input | Expected |
|---|---|---|---|
| REV-01 | Positive vs negative | `Great product!` / `Poor quality!` | score > 0 / < 0 |
| REV-02 | Negation | `not good` | negative |
| REV-03 | Intensifier | `very good` > `good` | true |
| REV-04 | Contrast | `looks nice but the battery is terrible` | negative overall |
| REV-05 | Aspects | battery/camera sentences for smartphones | aspects detected |
| REV-06 | Summary | mixed fixture reviews | pros include Camera, cons include Battery life, label, highlights |
| REV-07 | Empty | no reviews | count 0, label Mixed |

## Compare (`test/ai.compare.test.js`)

| ID | Scenario | Expected |
|---|---|---|
| CMP-01 | Unit parsing | `Quad: 64 MP + 8 MP` → 64 mp; `1 TB` → 1024 gb |
| CMP-02 | Rows | Price best = cheapest; RAM best = highest; Weight best = lightest |
| CMP-03 | Verdict | Best value = rating-per-rupee winner, Top rated, Budget pick, Premium pick present |
| CMP-04 | Summary | mentions best value product |

## API integration (`test/ai.api.test.js`, needs seeded DB)

| ID | Scenario | Input | Expected |
|---|---|---|---|
| API-01 | Chat requires auth | POST /ai/chat without token | 401 |
| API-02 | Validation | empty / 501-char message | 400 |
| API-03 | Search turn | `show me smartphones under 100k` | product_search/budget_query, ≤ 6 products all ≤ 100000, match.reasons, suggestions 2–4, conversationId |
| API-04 | Refinement | `cheaper` | refine_cheaper, prices lower than previous median |
| API-05 | Compare by ordinal | `compare the first two` | comparison with 2 products, rows, verdict picks |
| API-06 | Add to cart action | `add the second one to my cart` | action add_to_cart with the 2nd shown productId |
| API-07 | Clarify gift | `I need a gift` | clarify with options; then `mom` → budget clarify; then `Under Rs 15,000` → products ≤ 15000 |
| API-08 | Order status | `where is my order` (fresh user) | answers with no orders |
| API-09 | Conversation list/detail/delete | own conversation | listed, messages persisted with meta, deleted → 404 |
| API-10 | Feedback | thumbs up on assistant msg | 200; insights positive rate not null |
| API-11 | Recommendations guest vs user | GET /ai/recommendations | guest "Trending now"; user with interests → personalized title |
| API-12 | Similar | GET /ai/similar/:id | excludes itself, has reasons |
| API-13 | Bought together | GET /ai/bought-together/:id | non-empty RecommendedProduct[] |
| API-14 | Review summary | GET /ai/review-summary/:id | sentiment label, pros/cons arrays, summary |
| API-15 | Smart search | `red running shoes for women under 15k` | chips include budget, products ≤ 15000; search_history row for authed user |
| API-16 | Search relaxation | `smartphones under 1000` | fallback true, interpretation explains |
| API-17 | Finder | GET flows, POST electronics answers | ≥ 6 flows; products in chosen category |
| API-18 | NLU playground | POST /ai/nlu | intent, confidence, alternatives, entities, tokens, latencyMs |
| API-19 | Insights | GET /ai/insights | intentModel.testAccuracy ≥ 0.9, embeddings mode, llm, stats |
| API-20 | 404s | unknown product / conversation | 404 |

## Phase 2 features — unit (`test/ai.features.test.js`)

| ID | Scenario | Expected |
|---|---|---|
| FEA-01 | Multiple-choice knapsack | total ≤ budget, one item per role, the heavy-weight role gets its best item |
| FEA-02 | Required vs optional roles | required filled; optional skipped when it doesn't fit |
| FEA-03 | Infeasible required set | `null` |
| FEA-04 | Templates + `bundle` intent | ≥ 8 templates; "build me a gaming setup under 400k" → `bundle`; "4 lakh mein" → 400000 |
| FEA-05 | Q&A question parsing | yes/no, lookup, opinion types; RAM / display spec intents |
| FEA-06 | Q&A passages | spec, policy, description sentences, review sentences |
| FEA-07 | CLIP zero-shot | softmax over 100 × cosine sums to 1, picks the closest prompt |
| FEA-08 | Personas | Tech Enthusiast, Smart Saver, Brand Loyalist, Beauty Buff win on their traits |

## Phase 2 features — API (`test/ai.features.api.test.js`, needs seeded DB)

| ID | Scenario | Input | Expected |
|---|---|---|---|
| BND-01 | Bundle | `{ goal: "build me a gaming setup", budget: 700000 }` | template gaming_setup, total ≤ budget, includes a laptop, unique products, reasons, ≤ 2 alternatives |
| BND-02 | Tight budget | home office, 400000 | laptop kept (least important required role demoted first) |
| BND-03 | Validation | budget 10 / gibberish goal | 400 |
| BND-04 | Chat bundle | "build me a gym starter pack" → "Rs 50,000" | clarify then `meta.bundle`, `add_bundle_to_cart` action |
| QA-01 | Spec lookup | "How much RAM does it have?" | answer contains the RAM spec, spec evidence, follow-ups |
| QA-02 | Not in data | "can it fly to the moon?" | "couldn't find that", confidence < 0.4 |
| QA-03 | Catalog facts / errors | "is it in stock?", unknown id, empty body | stock answer, 404, 400 |
| QA-04 | Chat routing | "does the second one have a good camera?" | intent product_question about the 2nd shown product, `meta.qa` |
| CIN-01 | Auth | cart-insights / profile without token | 401 |
| CIN-02 | Empty cart | – | no savings, gap null |
| CIN-03 | Cart optimizer | cheap item, then a flagship phone | free-shipping gap = 5000 − subtotal with fillers ≥ gap; then savings cheaper than originals, complete-the-set non-empty |
| DNA-01 | New user | interests set | "The Fresh Explorer", mentions interests |
| DNA-02 | Active user | wishlists + views on phones/laptops | "The Tech Enthusiast", traits in [0,1] with descriptions |
| VIS-01 | Visual search | product thumbnail upload | same product in top 3, detected category smartphones |
| VIS-02 | Text → image | "red sneakers" | shoes in top 5 |
| VIS-03 | Bad uploads | text file / no file | 400 |
| VIS-04 | Insights | – | `visual.enabled`, `indexedImages` |
