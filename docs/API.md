# Cartwise API contract (v1)

Base URL: `http://<host>:5000/api/v1` — web uses `localhost`, Android emulator uses `10.0.2.2`.

## Conventions

- JSON in/out, **camelCase** keys. DB is snake_case; mapping happens in serializers (`backend/helpers/serializers.js`).
- Success: `{ "success": true, "data": <payload>, "meta"?: {...}, "message"?: "..." }`
- Paginated: `meta = { page, limit, total, totalPages, ...extra }`. Query params `page` (1-based), `limit`.
- Error: `{ "success": false, "message": "Human readable", "code"?: "TOKEN_EXPIRED", "errors"?: [{ "field", "message" }] }`
  - 400 validation, 401 auth (`code: TOKEN_EXPIRED` → client refreshes and retries once), 403, 404, 409 conflict.
- Auth: `Authorization: Bearer <accessToken>`. 🔒 = requires auth, 👤 = optional auth (personalizes when present).
- Money: numbers in **PKR** (e.g. `45999`). Client formats as `Rs 45,999`.
- Image URLs: absolute (`https://...`) or server-relative (`/uploads/...`). Client resolves relative URLs against the server origin.
- Timestamps: ISO-8601 strings.

## Shared shapes

```jsonc
// ProductCard
{ "id": 1, "title": "iPhone 13 Pro", "slug": "iphone-13-pro", "brand": "Apple",
  "category": { "id": 3, "name": "Smartphones", "slug": "smartphones" },
  "price": 279999, "compareAtPrice": 309999, "discountPercent": 9.7,
  "rating": 4.6, "ratingCount": 128, "stock": 23, "inStock": true,
  "thumbnail": "/uploads/products/1/thumb.webp", "tags": ["smartphones", "apple"] }

// ProductDetail = ProductCard +
{ "description": "...", "department": { "id": 1, "name": "Electronics", "slug": "electronics" },
  "images": ["..."], "highlights": ["6.1\" Super Retina XDR", "..."],
  "specs": { "RAM": "6 GB", "Storage": "128 GB" },   // ordered key → value strings
  "gender": null, "color": "Graphite", "weight": 0.2, "dimensions": { "width": 7, "height": 14, "depth": 0.7 },
  "warranty": "1 year warranty", "shippingInfo": "Ships in 2 days", "returnPolicy": "7 days return",
  "soldCount": 340, "ratingBreakdown": { "5": 80, "4": 30, "3": 10, "2": 5, "1": 3 } }

// RecommendedProduct = ProductCard + { "match": { "score": 0.87, "reasons": ["Within your Rs 50,000 budget", "Rated 4.6★"] } }

// User
{ "id": 1, "name": "Ali", "email": "ali@x.com", "phone": null, "avatarUrl": null, "role": "customer",
  "preferences": { "interests": ["smartphones"], "budget": { "min": 0, "max": 100000 }, "gender": "men" },
  "isOnboarded": true, "createdAt": "..." }
```

## Health
- `GET /health` → `{ status: "ok", time }`

## Auth (`/auth`)
| Method | Path | Body | Data |
|---|---|---|---|
| POST | `/auth/register` | `{ name, email, password }` (password ≥ 8, letter + number) | `{ user, accessToken, refreshToken }` (201) |
| POST | `/auth/login` | `{ email, password }` | `{ user, accessToken, refreshToken }` |
| POST | `/auth/demo` | – | Signs in the seeded demo account (for presentations) → same as login |
| POST | `/auth/refresh` | `{ refreshToken }` | `{ accessToken, refreshToken }` (rotates; old one revoked) |
| POST | `/auth/logout` | `{ refreshToken }` | `null` |
| POST | `/auth/forgot-password` | `{ email }` | `null` — always 200 (no account enumeration); emails a 6-digit OTP valid 10 min |
| POST | `/auth/verify-otp` | `{ email, otp }` | `{ resetToken }` (short-lived JWT, 15 min); max 5 attempts |
| POST | `/auth/reset-password` | `{ resetToken, password }` | `null` — revokes all refresh tokens |
| GET 🔒 | `/auth/me` | – | `User` |

## Users (`/users`) 🔒
| Method | Path | Body | Data |
|---|---|---|---|
| PATCH | `/users/me` | `{ name?, phone? }` | `User` |
| PUT | `/users/me/preferences` | `{ interests?: string[] (category slugs), budget?: {min,max}, gender?: "men"\|"women"\|"any" }` → also sets `isOnboarded=true` | `User` |
| POST | `/users/me/change-password` | `{ currentPassword, newPassword }` | `null` |
| GET | `/users/me/stats` | – | `{ orders, wishlist, reviews, conversations }` |

## Addresses (`/addresses`) 🔒
- `GET /addresses` → `Address[]` (default first) — `Address = { id, label, fullName, phone, line1, line2, city, province, postalCode, country, isDefault }`
- `POST /addresses` body = Address fields (no id) → `Address` (201). First address becomes default.
- `PATCH /addresses/:id` → `Address`; `DELETE /addresses/:id` → `null`; `POST /addresses/:id/default` → `Address`

## Catalog (`/catalog`)
- `GET /catalog/departments` → `[{ id, name, slug, icon, imageUrl, description, productCount, categories: [{ id, name, slug, imageUrl, productCount }] }]`
- `GET /catalog/categories/:slug` → `{ id, name, slug, description, imageUrl, department: {id,name,slug}, brands: [{ name, count }], priceRange: { min, max } }`
- `GET /catalog/home` 👤 → `{ banners: Banner[], departments: [...same as above without categories], flashDeals: ProductCard[], trending: ProductCard[], topRated: ProductCard[], newArrivals: ProductCard[], dealEndsAt }`
  - `Banner = { id, title, subtitle, imageUrl, ctaLabel, target: { type: "category"|"department"|"search"|"assistant", value }, theme }`

## Products (`/products`)
- `GET /products` 👤 — query: `q, department, category, brand (comma list), minPrice, maxPrice, minRating, inStock=true, onSale=true, gender, sort (relevance|price_asc|price_desc|rating|newest|popular|discount), page, limit(≤60)`
  → `ProductCard[]`, `meta = { page, limit, total, totalPages, facets: { brands: [{ name, count }], priceRange: { min, max } } }`
- `GET /products/:idOrSlug` 👤 → `ProductDetail` (logs a `view` interaction + increments view_count when authed)
- `GET /products/:id/reviews?page&limit&sort=recent|helpful|rating_high|rating_low` → `Review[]` paginated, `meta.summary = { average, count, breakdown }`
  - `Review = { id, rating, title, comment, isVerified, helpfulCount, createdAt, user: { name, initials } }`
- `POST /products/:id/reviews` 🔒 `{ rating 1-5, title?, comment (≥10 chars) }` → `Review` (201). One per user/product (409 otherwise). `isVerified` = user has a delivered order containing it. Recomputes product rating/rating_count.
- `GET /products/recently-viewed` 🔒 → `ProductCard[]` (last 20 distinct)

## Search (`/search`)
- `GET /search/suggestions?q=` 👤 → `{ products: [{ id, title, thumbnail, price }], categories: [{ name, slug }], queries: string[] }` (q ≥ 1 char, ≤ 6 products)
- `GET /search/trending` → `string[]`
- `GET /search/history` 🔒 → `[{ query, createdAt }]` (distinct, latest 10); `POST /search/history` 🔒 `{ query, resultsCount }`; `DELETE /search/history` 🔒 clears own history

## Wishlist (`/wishlist`) 🔒
- `GET /wishlist` → `ProductCard[]` (+ `addedAt`) ; `GET /wishlist/ids` → `number[]`
- `POST /wishlist` `{ productId }` → `{ productId }` (idempotent) ; `DELETE /wishlist/:productId` → `null`

## Cart (`/cart`) 🔒
- `GET /cart` → `Cart`
```jsonc
{ "items": [{ "productId": 1, "product": ProductCard, "quantity": 2, "lineTotal": 559998 }],
  "summary": { "itemCount": 2, "subtotal": 559998, "discount": 0, "shippingFee": 0, "total": 559998,
               "freeShippingThreshold": 5000, "coupon": { "code": "WELCOME10", "description": "..." } | null,
               "savings": 60000 } }
```
- `POST /cart/items` `{ productId, quantity=1 }` (adds to existing qty, caps at stock, max 10) → `Cart`
- `PATCH /cart/items/:productId` `{ quantity }` (0 removes) → `Cart` ; `DELETE /cart/items/:productId` → `Cart` ; `DELETE /cart` → `Cart`
- `POST /cart/coupon` `{ code }` → `Cart` (400 with reason if invalid/min not met) ; `DELETE /cart/coupon` → `Cart`
- Shipping: free when subtotal − discount ≥ 5,000, else Rs 250.

## Coupons
- `GET /coupons` → `[{ code, description, discountType, value, minOrderAmount, maxDiscount, expiresAt }]`

## Orders (`/orders`) 🔒
- `POST /orders` `{ addressId, paymentMethod: "cod"|"card", card?: { last4 } , notes? }` → `OrderDetail` (201). Server recomputes totals from cart, checks stock in a transaction, decrements stock, increments sold_count, records `purchase` interactions, clears cart, increments coupon usage, creates a notification.
- `GET /orders?status=active|delivered|cancelled&page` → `[{ id, orderNumber, status, total, itemCount, placedAt, previewImages: string[] }]`
- `GET /orders/:id` → `OrderDetail = { id, orderNumber, status, paymentMethod, paymentStatus, cardLast4, subtotal, discount, shippingFee, total, couponCode, shippingAddress, notes, placedAt, deliveredAt, cancelledAt, estimatedDelivery, items: [{ productId, title, thumbnail, unitPrice, quantity, lineTotal }], timeline: [{ status, note, createdAt }] }`
- `POST /orders/:id/cancel` → `OrderDetail` (only placed/confirmed; restocks)
- Demo progression: when an order is read, its status advances by elapsed time (confirmed +1 min, shipped +3 min, out_for_delivery +6 min, delivered +10 min), writing history + a notification for each step.

## Notifications (`/notifications`) 🔒
- `GET /notifications?page` → `[{ id, type, title, body, data, readAt, createdAt }]` ; `GET /notifications/unread-count` → `{ count }`
- `POST /notifications/:id/read` → `null` ; `POST /notifications/read-all` → `null`

## Interactions (`/interactions`) 👤
- `POST /interactions` `{ productId, type: view|click|wishlist|cart|ai_click, source? }` → `null` (ignored for guests)

## AI (`/ai`)
Everything runs offline. An optional LLM (`LLM_PROVIDER=gemini|groq`) only rewrites chat wording from the structured result, and only after a grounding check. Fields marked *(added)* extend the original contract. No documented field was removed or renamed.

- `POST /ai/chat` 🔒 `{ message (1-500 chars), conversationId? }` →
```jsonc
{ "conversationId": 12,
  "title": "Gaming Laptops under Rs 300k",                       // (added) current conversation title
  "userMessage": { "id": 40, "role": "user", "content": "...", "createdAt": "..." },
  "message": { "id": 41, "role": "assistant", "content": "Here are 4 gaming laptops under **Rs 300,000** ...", "createdAt": "...",
    "meta": {
      "intent": "product_search", "confidence": 0.93,
      "entities": { "department": "electronics", "category": "laptops", "brands": ["asus"], "budget": { "min": null, "max": 300000 },
                    "gender": null, "color": null, "features": ["gaming"], "minRating": null, "sort": null, "occasion": null, "recipient": null,
                    // (added) "categories": [], "excludeBrands": [], "excludeColors": [], "keywords": [], "ordinals": { "indices": [1,2], "all": false, "pronoun": false } | null
                  },
      "slots": { ... },                         // (added) dialogue state after this turn (same keys as entities)
      "products": RecommendedProduct[],          // 0-6
      "suggestions": ["Show cheaper options", "Only ASUS", "Compare the first two"],   // 2-4 quick-reply chips (send the text back as a message)
      "actions": [{ "type": "view_all", "label": "See all 12 results", "query": { "category": "laptops", "maxPrice": 300000 } },
                  { "type": "compare", "label": "Compare top picks", "productIds": [4, 7] }],
      "comparison": CompareResult | null,
      "clarify": { "question": "Who is the gift for?", "options": ["Mom", "Dad", "Friend"] } | null,
      "bundle": Bundle | null,                   // (added) when intent = bundle
      "qa": { "confidence", "evidence": [...], "followUps": [...] } | null,   // (added) when intent = product_question
      "fallback": false,                         // (added) true when constraints were relaxed
      "nlu": { "source": "model"|"entities"|"low_confidence", "alternatives": [...], "corrections": [{ "from", "to" }], "normalized": "..." },  // (added)
      "source": "local" | "gemini" | "groq", "latencyMs": 84 } } }
```
  - Intents: `greeting, goodbye, thanks, help, small_talk, product_search, recommendation, budget_query, compare, product_info, refine_cheaper, refine_premium, refine_filter, show_more, gift_suggestion, deals, order_status, cart_help, return_policy, add_to_cart, bundle`. The dialogue manager also derives `product_question` (a question about a product shown earlier, answered by grounded Q&A), `similar`, `bought_together` and `fallback`.
  - Action types: `view_all { query }` (params for `GET /products`), `compare { productIds }`, `add_to_cart { productId, quantity }` (the app calls `POST /cart/items` after the user taps), `add_bundle_to_cart { productIds }`, `view_order { orderId }`, `open_cart`.
  - Follow-ups can point at earlier results ("compare the first two", "add the second one to my cart", "does the 3rd have a good camera?"). They resolve against the products shown in the previous assistant turn.
- `GET /ai/conversations` 🔒 → `[{ id, title, lastMessage, updatedAt, createdAt }]` ; `GET /ai/conversations/:id` 🔒 → `{ id, title, createdAt, updatedAt, messages: Message[] }` (assistant messages include `meta`) ; `DELETE /ai/conversations/:id` 🔒 → `null` (404 if not yours)
- `POST /ai/messages/:id/feedback` 🔒 `{ rating: 1 | -1 }` → `null`. Upserts one rating per user and message. 400 for user messages.
- `GET /ai/recommendations?limit=10` 👤 → `{ title, subtitle, strategy: "popularity"|"cold-start-preferences"|"hybrid-personalized", products: RecommendedProduct[] }` (guests → "Trending now")
- `GET /ai/similar/:productId?limit=8` → `RecommendedProduct[]` (embedding nearest neighbours, same category/department first, MMR-diversified)
- `GET /ai/bought-together/:productId?limit=6` → `RecommendedProduct[]` (association rules over orders, carts and wishlists, using support, confidence and lift; falls back to complementary categories)
- `POST /ai/compare` 👤 `{ productIds: [2..4] }` → `CompareResult = { products: ProductDetail[], rows: [{ label, values: string[], bestIndex: number|null }], verdict: { summary, picks: [{ label: "Best value"|"Top rated"|"Premium pick"|"Budget pick", productId, reason }] } }`
- `GET /ai/review-summary/:productId` → `{ reviewCount, sentiment: { score (-1..1), label: "Very positive"|"Positive"|"Mixed"|"Negative" }, pros: [{ aspect, mentions }], cons: [{ aspect, mentions }], summary, highlights: string[] }`
- `GET /ai/search?q=&limit=20` 👤 → `{ interpretation: { text, chips: [{ type, label }], corrections, intent }, entities, products: RecommendedProduct[], total, fallback: boolean, mode: "neural"|"tfidf", latencyMs }`. Chip types: `category, department, brand, budget, feature, color, gender, recipient, occasion, rating, sort, exclude, keyword`. Signed-in searches are saved to `search_history`.
- `POST /ai/nlu` `{ text }` → `{ intent, confidence, alternatives: [{ intent, confidence }], entities, tokens: string[], normalized, corrections, source, latencyMs }` (powers the "AI Lab" screen)
- `GET /ai/finder` → `[{ department, slug, key, title, icon, questions: [{ id, title, type: "single"|"multi"|"budget", options: [{ label, value }] }] }]`. Budget options come from each department's price quartiles; their value looks like `"0-50000"`, `"50000-150000"`, `"150000-"` or `"any"`.
- `POST /ai/finder` 👤 `{ department (slug or key), answers: { [questionId]: value | value[] } }` → `{ summary, products: RecommendedProduct[], total, fallback }`
- `GET /ai/insights` → `{ intentModel: { algorithm, classes: string[], trainingSamples, testAccuracy, trainedAt, macroF1, cvAccuracy, baselineNaiveBayesAccuracy, vocabularySize, calibration }, embeddings: { mode: "neural"|"tfidf", model, dims, indexedProducts, neuralStatus, storedVectors, fallback, lexical }, llm: { provider, model, enabled }, recommender: { signals: string[], algorithms, interactionWeights }, visual: { enabled, status, model, dims, indexedImages }, stats: { conversations, messages, feedbackCount, positiveFeedbackRate }, catalog }`

### AI — advanced features
- `POST /ai/visual-search` 👤 multipart `image` (jpg/png/webp, ≤ 5 MB), `?limit=12` → `{ products: RecommendedProduct[], detected: { category: { slug, name }, confidence, alternatives: [{ slug, p }] }, latencyMs }`. CLIP ViT-B/32 image embeddings with nearest-neighbour search, plus zero-shot category detection from prompt-ensembled text embeddings. CLIP loads on the first request (the first call takes a few seconds). Returns **503** `code: VISUAL_UNAVAILABLE` if the model can't load or the image index is still building. Returns **400** for non-images.
- `GET /ai/visual-search/text?q=&limit=12` → `{ products: RecommendedProduct[], latencyMs }`. CLIP text → image search, for example "something cozy for winter".
- `POST /ai/bundle` 👤 `{ goal: string (2-200), budget: number (≥ 500) }` →
  `Bundle = { title, template, goal, total, budget, remaining, items: [{ role, required, product: RecommendedProduct, alternatives: ProductCard[] (≤2) }], skippedRoles: string[], explanation, savingsTips: string[] }`. The goal is matched to a role template by keywords and embeddings, and the products are chosen by a multiple-choice knapsack (DP) under the budget. Returns 400 when the goal can't be understood. It is also available in chat ("build me a gaming setup under 400k").
- `POST /ai/products/:id/ask` 👤 `{ question (2-300) }` → `{ answer, confidence (0-1), evidence: [{ source: "spec"|"review"|"description", text }], followUps: string[], product: { id, title }, source }`. The answer is extractive and cites the product's specs, description and reviews. If the answer isn't in the data, it says so honestly.
- `GET /ai/cart-insights` 🔒 → `{ savings: [{ productId, alternative: RecommendedProduct, save, reason }], completeTheSet: RecommendedProduct[], freeShippingGap: { remaining, suggestions: ProductCard[] } | null, summary, subtotal }`
- `GET /ai/profile` 🔒 ("Shopping DNA") → `{ persona: { title, description, runnerUp? }, traits: [{ key, label, value (0-1), description }], topCategories: [{ slug, name, share }], topBrands: [{ name, share }], priceBand: { min, max, avg, median }, signals: { views, clicks, wishlist, cart, purchases, searches, chats }, howWeUseIt: string[], lastUpdated }`

## Backend implementation notes (commerce)

Clarifications of behaviour the tables above leave open. All are additive: no documented field was renamed or removed.

- **Error codes**: besides `TOKEN_EXPIRED`, 401s may carry `INVALID_TOKEN` (malformed access token) or `TOKEN_REUSED` (a rotated refresh token was replayed, so every session of that user is revoked and the client must sign in again). Rate-limited auth calls return **429** with `code: RATE_LIMITED`. Limits per IP: login/demo 10 failed attempts per 15 min, register 20 per hour, forgot-password 5 per 15 min, verify-otp 10 per 15 min.
- **Auth**: `resetToken` is single-use (it stops working once the password changes). `verify-otp` messages say how many attempts are left.
- **Products list**: `category` and `brand` accept comma lists. Brands match by name or slug, case-insensitively. `gender=men|women` also includes `unisex` items. If a multi-word `q` matches nothing with all words, the search falls back to any-word matching and adds `meta.relaxedSearch: true`. The brand facet ignores the brand filter and the price range ignores the price filters, so the UI can still show the alternatives.
- **Product detail**: `view_count` goes up on every view. The `view` interaction is logged only for signed-in users.
- **Cart**: mutating cart endpoints can return a `message` (for example "Only 3 can be added (limited stock)"). Quantities are silently capped to current stock. An out-of-stock item stays in the cart with `product.inStock=false` and `lineTotal: 0` and is left out of the totals; checkout then returns 409 until the item is removed. A coupon that stops qualifying (for example the subtotal drops below its minimum) is removed automatically and `summary.coupon` becomes `null`. `POST /cart/items` and `POST /wishlist` accept an optional `source` (analytics).
- **Orders**: cancelling an order that is no longer `placed`/`confirmed` returns **409**. Checkout returns 409 when stock is short, 400 when the cart is empty or the stored coupon no longer qualifies, and 404 for an address that isn't yours. Card orders are `paymentStatus: paid` right away; COD orders become paid on delivery; cancelling a paid order sets it to `refunded`. Order numbers look like `CW-YYMMDD-XXXXXX`. `estimatedDelivery` is placed + 2 days for Karachi/Lahore/Islamabad/Rawalpindi and placed + 4 days elsewhere; it is `deliveredAt` once delivered and `null` when cancelled.
- **Demo progression** only applies to orders placed within the **last 24 hours**. Older seeded orders keep their stored status, so the demo account always shows one `delivered`, one `shipped` and one `placed` order. History entries and notifications are timestamped at the simulated time of each step.
- **Notifications list**: `meta.unreadCount` is also returned.
- **Search history**: `POST /search/history` returns 201 with `data: null`. Queries are stored trimmed and lower-cased, so the history is distinct case-insensitively. `/search/trending` covers the last 30 days of searches that returned results, padded with defaults.
- **Interactions**: `type: purchase` cannot be posted by clients; it is recorded by checkout.
