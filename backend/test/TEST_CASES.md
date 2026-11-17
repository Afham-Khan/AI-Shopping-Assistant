# Cartwise API — test cases

Run with `npm test` (mocha + supertest against `app.js`, same `cartwise` database as dev).
Tests only create their own users (`test+<timestamp>@cartwise.test`) and rows that belong to them; a global
`afterAll` hook restocks any non-cancelled test orders, deletes the test users (cascade) and recomputes the rating
of any product they reviewed, so seeded data is left as it was.

| ID | Module | Scenario | Expected |
|---|---|---|---|
| GEN-01 | general | `GET /health` | 200, `status: ok` |
| GEN-02 | general | unknown route | 404 envelope `success: false` |
| GEN-03 | general | malformed JSON body | 400 "Malformed JSON body" |
| AUTH-01 | auth | register with mixed-case email | 201, user + accessToken + refreshToken, email lower-cased, no password hash in payload |
| AUTH-02 | auth | register same email again | 409 |
| AUTH-03 | auth | register weak password / bad email / short name | 400 with `errors[].field` |
| AUTH-04 | auth | login with correct credentials | 200, tokens + user |
| AUTH-05 | auth | login wrong password / unknown email | 401 with identical message (no enumeration) |
| AUTH-06 | auth | `GET /auth/me` without token / garbage token | 401 (`INVALID_TOKEN` for garbage) |
| AUTH-07 | auth | `GET /auth/me` with expired token | 401 `code: TOKEN_EXPIRED` |
| AUTH-08 | auth | `GET /auth/me` with valid token | 200 `User` |
| AUTH-09 | auth | refresh rotates tokens | 200, new refresh token differs; new access token works |
| AUTH-10 | auth | replay of a rotated (revoked) refresh token | 401 `TOKEN_REUSED`, and the whole family (latest token) is revoked too |
| AUTH-11 | auth | refresh with unknown token / missing body | 401 / 400 |
| AUTH-12 | auth | logout revokes refresh token | 200, later refresh → 401 |
| AUTH-13 | auth | forgot-password with unknown email | 200 generic message, no mail sent |
| AUTH-14 | auth | forgot-password with known email | 200, one mail with a 6-digit code |
| AUTH-15 | auth | verify-otp wrong code | 400 "Incorrect code. N attempts left" |
| AUTH-16 | auth | verify-otp after 5 wrong attempts, even with the right code | 400 "Too many attempts" |
| AUTH-17 | auth | verify-otp malformed code | 400 validation |
| AUTH-18 | auth | verify-otp correct → reset-password | resetToken issued; password changed; old password fails, new works; old refresh tokens revoked |
| AUTH-19 | auth | reuse the same resetToken | 400 (single use: bound to the previous password hash) |
| AUTH-20 | auth | `POST /auth/demo` | 200, signs in `demo@cartwise.app` |
| USR-01 | users | all `/users/*` without token | 401 |
| USR-02 | users | `PATCH /users/me` name + phone | 200 updated `User` |
| USR-03 | users | `PATCH /users/me` invalid name/phone, empty body | 400 |
| USR-04 | users | `PUT /users/me/preferences` valid | 200, preferences saved, `isOnboarded: true` |
| USR-05 | users | preferences with unknown category / min > max / bad gender | 400 |
| USR-06 | users | change-password wrong current password | 400 |
| USR-07 | users | change-password success | 200; login with new password works |
| USR-08 | users | `GET /users/me/stats` | `{ orders, wishlist, reviews, conversations }` numbers |
| ADR-01 | addresses | first address | 201, `isDefault: true` |
| ADR-02 | addresses | second address with `isDefault: true` | becomes default, previous default unset |
| ADR-03 | addresses | list | default first |
| ADR-04 | addresses | `POST /:id/default` | switches default (exactly one default) |
| ADR-05 | addresses | `PATCH /:id` | updates fields; nulling a required field → 400 |
| ADR-06 | addresses | delete default address | next address promoted to default |
| ADR-07 | addresses | another user PATCH/DELETE/default on my address | 404 |
| ADR-08 | addresses | missing required fields / non-integer id | 400 |
| CAT-01 | catalog | departments | 7 departments, categories nested, productCount = sum of category counts |
| CAT-02 | catalog | category detail | department, brand facets `{name,count}`, priceRange min ≤ max |
| CAT-03 | catalog | unknown category | 404 |
| CAT-04 | catalog | home feed | banners (incl. `assistant` target), departments, flashDeals (discount ≥ 10), trending, topRated, newArrivals, future `dealEndsAt` |
| PRD-01 | products | default list | ProductCard[], meta page/limit/total/totalPages + facets |
| PRD-02 | products | `limit=61`, `sort=bogus`, `minRating=6`, maxPrice < minPrice | 400 |
| PRD-03 | products | category filter | every item in that category, total = category productCount |
| PRD-04 | products | brand filter (comma list) | only those brands; brand facet still lists other brands |
| PRD-05 | products | price range | all prices within range |
| PRD-06 | products | minRating / inStock / onSale / gender | every item satisfies filter |
| PRD-07 | products | sort price_asc / price_desc / rating / discount | correctly ordered |
| PRD-08 | products | pagination page 1 vs 2 | no overlap, same total |
| PRD-09 | products | `q=iphone` full-text | results, first result title contains "iPhone" |
| PRD-10 | products | `q=lipst` (partial word) | ILIKE fallback still finds "Red Lipstick" |
| PRD-15 | products | `q=gaming laptop` (no product has both words) | falls back to any-word match, `meta.relaxedSearch: true`; strict hits carry no flag |
| PRD-11 | products | detail by id and by slug | same product, images[], ratingBreakdown with keys 1-5, specs object, department |
| PRD-12 | products | detail unknown id / slug | 404 |
| PRD-13 | products | `/products/recently-viewed` without token | 401 (route not swallowed by `/:idOrSlug`) |
| PRD-14 | products | view product while authed → recently-viewed | product appears first, view_count incremented |
| RVW-01 | reviews | list reviews | paginated Review[], `meta.summary {average,count,breakdown}` |
| RVW-02 | reviews | sort rating_low | ascending ratings |
| RVW-03 | reviews | create review (no purchase) | 201, `isVerified: false`, user initials |
| RVW-04 | reviews | product rating recomputed | product rating/ratingCount equals summary from reviews |
| RVW-05 | reviews | second review same product | 409 |
| RVW-06 | reviews | comment < 10 chars / rating 6 / no token / unknown product | 400 / 400 / 401 / 404 |
| RVW-07 | reviews | review after a delivered order containing the product | `isVerified: true` |
| SRC-01 | search | suggestions `q=iph` | ≤ 6 products incl. an iPhone, shape `{products,categories,queries}` |
| SRC-02 | search | suggestions `q=lap` | categories include laptops |
| SRC-08 | search | suggestions `q=sam` | title-prefix matches (Samsung…) ranked before keyword-only matches; descriptions ignored |
| SRC-03 | search | suggestions without q | 400 |
| SRC-04 | search | trending | non-empty string[] |
| SRC-05 | search | history requires auth | 401 |
| SRC-06 | search | save history twice + get | distinct, latest first |
| SRC-07 | search | clear history | empty list |
| WSH-01 | wishlist | add product | `{ productId }`, appears in `/ids` and list (with addedAt) |
| WSH-02 | wishlist | add same product again | 200 idempotent, still one entry |
| WSH-03 | wishlist | remove | gone from ids |
| WSH-04 | wishlist | unknown product / bad id / no token | 404 / 400 / 401 |
| CRT-01 | cart | empty cart | zero summary, `freeShippingThreshold: 5000`, coupon null |
| CRT-02 | cart | add item twice | quantities add up, lineTotal = price × qty |
| CRT-03 | cart | add more than stock | capped at stock |
| CRT-04 | cart | add beyond 10 per item / quantity 11 | capped at 10 / 400 |
| CRT-05 | cart | subtotal < 5,000 | shippingFee 250; ≥ 5,000 → 0 |
| CRT-06 | cart | apply WELCOME10 | discount = 10% capped at 2,000; total = subtotal − discount + shipping |
| CRT-07 | cart | FLAT500 below min order | 400 "Add Rs … more" |
| CRT-08 | cart | expired coupon / unknown coupon | 400 expired / 400 invalid |
| CRT-09 | cart | coupon dropped when subtotal falls below min | coupon null after item removal |
| CRT-10 | cart | `PATCH` quantity 0 | item removed; PATCH missing item → 404 |
| CRT-11 | cart | add out-of-stock product | 409 |
| CRT-12 | cart | savings | Σ (compareAt − price) × qty + discount |
| CRT-13 | cart | `DELETE /cart` | empty items, coupon removed |
| CPN-01 | coupons | list | active coupons only (no expired SUMMER25) |
| ORD-01 | orders | checkout with empty cart | 400 |
| ORD-02 | orders | invalid paymentMethod / card without last4 | 400 |
| ORD-03 | orders | another user's address | 404 |
| ORD-04 | orders | checkout happy path | 201 OrderDetail; totals equal cart summary; stock −qty; sold_count +qty; cart cleared; coupon used_count +1; `placed` timeline; notification; estimatedDelivery |
| ORD-05 | orders | quantity above current stock at checkout | 409, nothing changed |
| ORD-06 | orders | list + `status=active` filter | order present with itemCount & previewImages |
| ORD-07 | orders | other user reads / cancels my order | 404 |
| ORD-08 | orders | cancel placed order | status cancelled, stock & sold_count restored, coupon usage restored, timeline + notification |
| ORD-09 | orders | cancel again | 409 |
| ORD-10 | orders | progression: placed 4 min ago | read → `shipped`, timeline confirmed+shipped, notifications created |
| ORD-11 | orders | progression: placed 11 min ago | read → `delivered`, deliveredAt set, cancel → 409 |
| NTF-01 | notifications | list after an order | paginated, contains order notification, `meta.unreadCount` |
| NTF-02 | notifications | mark one read | unread-count decreases |
| NTF-03 | notifications | other user's notification / bad id | 404 / 400 |
| NTF-04 | notifications | read-all | unread-count 0 |
| INT-01 | interactions | guest posts interaction | 200 `null`, nothing stored |
| INT-02 | interactions | authed posts interaction | 200, row stored |
| INT-03 | interactions | type `purchase` / bad productId / unknown product | 400 / 400 / 404 |

## Price watch, admin updates and price history (`test/alerts.test.js`)

Changes one seeded product that nobody (seeded) watches or wishlists, then restores its price, compare-at price, discount, stock
and `updated_at`, and deletes only the `price_history` rows the suite created. Watchers are test users (cascade-deleted).

| ID | Module | Scenario | Expected |
|---|---|---|---|
| PW-U1 | alerts (pure) | drop with an any-drop watcher, a target watcher above the new price and two wishlisters | any-drop watcher + wishlister notified (one row per user), target watcher not; fired watch ids returned |
| PW-U2 | alerts (pure) | new price ≤ target / price rise | target watcher notified ("reached your target"); a rise never notifies |
| PW-U3 | alerts (pure) | stock 0 → 3 | only watchers with `notify_restock` get a `restock` row |
| PW-U4 | alerts (pure) | pricing on drop / rise | old price becomes compare-at with recomputed discount; compare-at cleared when the price rises above it |
| PW-01 | alerts | `/alerts/price-watch` without token | 401 |
| PW-02 | alerts | empty body / negative target / non-boolean notifyRestock / unknown product | 400 / 400 / 400 / 404 |
| PW-03 | alerts | target ≥ current price | 400 on `targetPrice` |
| PW-04 | alerts | create, update, list | 201 then 200, `initialPrice` = price at creation, status summary "above your target" |
| ADM-01 | admin | PATCH as guest / customer | 401 / 403 |
| ADM-02 | admin | empty body / negative price / fractional stock / unknown id | 400 / 400 / 400 / 404 |
| ADM-03 | admin | 5% drop | `changes.price`, compare-at kept, history recorded, only the any-drop watcher gets `price_drop` with `data.productId/newPrice` |
| ADM-04 | admin | drop below the target | both watchers notified, body mentions the target, `lastNotifiedAt` set, `targetReached: true` |
| ADM-05 | admin | stock 0 then 7 | 2 `restock` alerts (opted-in watcher + wishlister), opted-out watcher none, no history row for a stock-only change |
| ADM-06 | admin | demo service path (`npm run demo:price-drop`) | history row with `source: demo`, watchers notified |
| ADM-07 | admin | seeded admin signs in | role `admin` |
| PH-01 | products | `GET /products/:id/price-history?days=365` | seed + admin points oldest first, lowest = latest drop, trend `down`, insight "Lowest price" |
| PH-02 | products | `days=0` / unknown product | 400 / 404 |
| PW-05 | alerts | delete watch twice | 200 then 404, list empty |

## Discover, room and shopping memory (`test/ai.v3.api.test.js`)

| ID | Module | Scenario | Expected |
|---|---|---|---|
| DSC-01 | discover | guest deck `limit=12` | 12 in-stock cards, ≤ 3 per category, not personalized |
| DSC-02 | discover | swipe without token / bad action / unknown product / `limit=0` | 401 / 400 / 404 / 400 |
| DSC-03 | discover | like then pass | like: taste top category = liked item's, `next` has 1-3 similar items, priceAppetite from the liked price; pass: `next: []`, `pass` interaction stored with `source: discover` |
| DSC-04 | discover | bag | product appears in `GET /cart` |
| DSC-05 | discover | deck after swipes; recommendations | swiped items excluded (`excludedRecent ≥ 3`); passed item never recommended; taste has top signals |
| DSC-06 | discover | reels | ≥ 5 departments, each 5-8 in-stock products with headline + subtitle; `perDepartment=20` → 400 |
| ROOM-01 | catalog | `GET /catalog/room` as guest | 7 zones in order, 3 featured each, from the zone's categories |
| ROOM-02 | catalog | signed in with `mens-shirts` interest + gender men | wardrobe personalized, no women's items |
| MEM-01 | users | `GET /users/me/memory` after views, wishlist, AI search, chat | top category smartphones, recent search listed, budget band, readable summary, counts |
| MEM-02 | users | `PUT /users/me/memory` bad body; turn off | 400; recommendations switch to `popularity`; new views and AI searches are not stored; `enabled: false` |
| MEM-03 | users | `DELETE /users/me/memory` | interactions, searches and chat contexts cleared for this user only; wishlist kept; another user's interactions untouched; 401 without token |
