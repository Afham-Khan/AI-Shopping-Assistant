# Cartwise — Frontend conventions

Flutter 3.47 · Dart 3.13 · Riverpod 3 · go_router 18 · Dio 5. Runs on Chrome (`flutter run -d chrome`) and Android (emulator reaches the host API at `10.0.2.2:5000`).

> **Import `package:material_ui/material_ui.dart`, never `package:flutter/material.dart`.**
> In Flutter 3.47 Material moved to the `material_ui` package; go_router, google_fonts and Riverpod already use it. Mixing the two gives two incompatible `ThemeData`/`MaterialApp` types. `test/conventions_test.dart` fails if `flutter/material.dart` shows up in `lib/`.

## Folder structure (feature-first)

```
lib/
  main.dart                 # prefs init, ProviderScope (+ retry policy), path URLs on web
  app.dart                  # MaterialApp.router, themes, text-scale clamp, scroll behaviour
  core/
    config/app_config.dart  # base URL (dart-define > Settings > platform default), apiUrl, resolveImage()
    network/                # ApiClient (+ Paginated), AuthInterceptor (refresh), ApiException
    storage/                # sharedPreferencesProvider, StorageKeys, TokenStore
    models/                 # shared models: ProductSummary (API "ProductCard"), NamedRef, ProductMatch, JsonX
    theme/                  # AppColors/AppPalette, AppTheme, spacing/radii/durations/breakpoints, themeModeProvider
    router/                 # routes.dart (all paths + builders), app_router.dart (redirects, shell)
    utils/                  # formatters, validators, debouncer, extensions, category_icons
    widgets/                # shared UI kit — import 'core/widgets/widgets.dart'
  features/<feature>/
    data/                   # <feature>_repository.dart (+ provider), models/
    providers/              # Riverpod providers / notifiers
    presentation/           # screens, widgets/ (private to the feature)
```

Features: `auth`, `shell`, `settings`, `home`, `catalog`, `product`, `search`, `wishlist`, `cart`, `checkout`, `orders`, `notifications`, `profile`, `assistant`, `ai`. Screens that aren't built yet are placeholders using `PlaceholderBody` — replace the body, **keep the class name and constructor** (the router uses them).

## Networking

- Always go through `ref.watch(apiClientProvider)`. Methods return the envelope's `data`, decoded:
  - `get/post/put/patch/delete<T>(path, {query, body, decode})`
  - `getPage<T>(path, {query, item})` → `Paginated<T>` (`items, page, totalPages, hasMore, meta`, `append()` for infinite scroll; `meta['facets']`, `meta['summary']` for extras).
- Failures are always `ApiException(message, statusCode, code, fieldErrors)`. Catch that, never `DioException`. `e.isNetwork`, `e.isNotFound`, `e.fieldError('email')`.
- Query maps drop null/empty values and join lists with commas (`brand: ['apple','samsung']`).
- Auth is automatic: the bearer token is attached, `TOKEN_EXPIRED` triggers one shared refresh and a retry; if refresh fails the session ends and the app switches to guest.
- Images: pass raw API URLs to `AppNetworkImage` — relative `/uploads/...` paths are resolved against the server.
- Money is PKR: `Formatters.price(45999)` → `Rs 45,999`.

## Patterns: repository → provider → screen

```dart
// features/catalog/data/catalog_repository.dart
class CatalogRepository {
  CatalogRepository(this._api);
  final ApiClient _api;

  Future<Paginated<ProductSummary>> products({String? category, String? sort, int page = 1}) =>
      _api.getPage('/products', query: {'category': category, 'sort': sort, 'page': page}, item: ProductSummary.fromJson);

  Future<ProductDetail> product(String idOrSlug) =>
      _api.get('/products/$idOrSlug', decode: (d) => ProductDetail.fromJson(d as Json));
}

final catalogRepositoryProvider = Provider((ref) => CatalogRepository(ref.watch(apiClientProvider)));

// features/product/providers/product_providers.dart
final productDetailProvider = FutureProvider.autoDispose.family<ProductDetail, String>((ref, id) {
  ref.watch(isAuthenticatedProvider); // 👤 endpoints: refetch on login/logout
  return ref.watch(catalogRepositoryProvider).product(id);
});

// screen
ref.watch(productDetailProvider(id)).when(
  data: (p) => ...,
  loading: () => const _DetailSkeleton(),
  error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(productDetailProvider(id))),
);
```

Rules of thumb
- Models are hand-written with `fromJson` using `JsonX` readers (lenient with numbers/strings). No codegen.
- Read-only data → `FutureProvider(.autoDispose/.family)`. Mutable state (cart, chat) → `Notifier`/`AsyncNotifier` with methods that call the repository and update `state`.
- Forms keep local `busy`/`ApiException? error` in a `ConsumerStatefulWidget`; show `FormErrorBanner` for general errors and `errorText: error?.fieldError('x')` per field.
- Failing providers retry only network errors (twice); everything else shows `ErrorState` immediately.
- Comments: short lowercase "why" comments only where non-obvious; small focused widgets.

## Shared state you can use

| Provider | What |
|---|---|
| `authControllerProvider` | `AuthState(status: unknown/authenticated/guest, user)`; `.notifier`: `login`, `register`, `demoLogin`, `logout`, `continueAsGuest`, `refreshUser`, `updateUser(user)`, `savePreferences`, reset-password steps |
| `currentUserProvider`, `isAuthenticatedProvider` | shortcuts |
| `requireAuth(context, ref, message:)` | gate an action; guests get a "Sign in" snackbar that returns them here |
| `wishlistIdsProvider` | `Set<int>` of saved ids; `.notifier.toggle(id)` (optimistic), `.refresh()`; `toggleWishlist(ref, id)` |
| `cartCountProvider` | badge count; after any cart mutation call `.notifier.set(cart.summary.itemCount)` (or `.refresh()`) |
| `themeModeProvider`, `serverUrlProvider`, `appConfigProvider` | appearance, server address, URL helpers |
| `cartProvider` | full `Cart` (empty for guests). `.notifier`: `add(id, quantity:, source:)` → `(cart, message)`, `setQuantity` (optimistic, rollback + rethrow), `remove(id)` → removed line for undo, `restore(line)`, `addAll(lines)`, `applyCoupon(code)`, `removeCoupon()`, `refresh()`, `markEmpty()`. Keeps `cartCountProvider` in sync itself |
| `compareTrayProvider` | up to 4 `ProductSummary` picked for comparison; `.notifier.toggle(p)` → `added/removed/full`, `ids`, `clear()`. Show `CompareTrayBar()` in a screen's `bottomNavigationBar` |
| `unreadNotificationsProvider` | unread badge (0 for guests); `.notifier.refresh()`, `.set(n)` |
| `homeFeedProvider`, `departmentsProvider`, `productListProvider(ProductQuery)`, `productDetailProvider(idOrSlug)`, `topReviewsProvider(id)`, `reviewsProvider((productId:, sort:))` | catalog data (`features/catalog`, `features/product`) |
| `addressesProvider` (`save/delete/setDefault`), `userStatsProvider`, `ordersProvider(OrderFilter)`, `orderDetailProvider(id)` (`cancel()`), `notificationsProvider` (`markRead/markAllRead`), `searchHistoryProvider` (`record/clear`), `wishlistItemsProvider`, `wishlistActionsProvider.moveToCart(id)`, `checkoutControllerProvider.placeOrder(...)` | account / orders / search / checkout |

## Routing

All paths and location builders are in `core/router/routes.dart` (param conventions documented at the top). Navigate with builders: `context.push(Routes.product(id))`, `context.push(Routes.productList(category: 'laptops', title: 'Laptops'))`, `context.go(Routes.home)`.

- Tabs (`/`, `/explore`, `/assistant`, `/cart`, `/account`) live in a `StatefulShellRoute.indexedStack` (state kept per tab). Account sub-pages and assistant history are nested in their tab; everything else opens full-screen above the shell.
- Protected paths are listed in `Routes.protected` → guests are redirected to `/login?from=…` and sent back after sign-in. Sign-in screens never navigate themselves — the router redirects (new users with `isOnboarded == false` go to `/interests` first).
- **Add a screen:** create it in `features/<f>/presentation/`, add a constant (+ builder if it has params) to `Routes`, add a `GoRoute` in `app_router.dart` (inside a branch only if it belongs to that tab), add to `Routes.protected` if it needs auth.

## Responsive layout

- `context.useBottomNav` (width < 700 & portrait) → bottom bar; otherwise the storefront top header (`StoreHeader`, see Design system → Shell). No side rail. `context.isWide` = ≥ 700, `context.isDesktop` = ≥ 1100.
- Wrap page content in `ResponsiveCenter` (max 1200) / `SliverResponsiveCenter` in slivers; forms use `maxWidth: Breakpoints.maxForm` (440).
- Must not overflow at 320 px wide or text scale 2.0 (app clamps at 2.0). Prefer `Wrap`, `Flexible`, `maxLines + ellipsis`. Grid tiles get their height from `ProductCard.compactHeight`, which scales with text size.

## Design system

**Identity — "editorial front, ledger precision".** Zelora looks like a well-edited shop, not a dashboard: solid surfaces with hairline borders, real product photos as the hero, a serif for the editorial voice, a mono for facts, and ONE accent. The assistant has a name and a mark: **Zel**, a single four-point spark (`AiSparkleIcon`).

**Never:** gradients (the `aiGradient` / `brandGradient` getters are flat on purpose), glow, blur / glass, spinning or floating decoration, emoji as icons, loud colored fills, more than one accent in a view, hard-coded hex in features.

### Color (`context.colors` → `AppPalette`; dark is the default theme)

| Token | Dark "tide ink" | Light "paper" | Use |
|---|---|---|---|
| `background` | `#081719` | `#F4F7F4` | page |
| `surface` | `#0D2023` | `#FFFFFF` | cards, sheets, inputs, header |
| `surfaceVariant` | `#13292D` | `#ECF1ED` | hover rows, skeletons, inset panels |
| `surfaceRaised` | `#1A3439` | `#E0E8E3` | kbd chips, tooltips, slider track |
| `border` / `borderStrong` | `#1E383D` / `#30535A` | `#D9E3DD` / `#B5C8BE` | hairline · hover and emphasis |
| `text` / `muted` / `faint` | `#EAF2F0` / `#A4BBB8` / `#6F8A88` | `#10221D` / `#465E56` / `#72887F` | primary · secondary · captions, placeholders |
| `primary` (`primaryHover`, `onPrimary`, `primarySoft`) | `#3DDBA6` (`#62E5BA`, `#04271B`, `#123531`) | `#0A7F60` (`#086B51`, `#FFFFFF`, `#E1F2EC`) | the one accent: primary buttons, active states, eyebrows |
| `ai` / `aiSoft` | = `primary` / `primarySoft` | same | AI surfaces only (named for intent) |
| `sale` (`onSale`, `saleSoft`) | `#F4736C` (`#2B0907`, `#3A2224`) | `#C8372F` (`#FFFFFF`, `#FBE9E7`) | discounts, savings, destructive |
| `warning` / `star` | `#F0B352` | `#A86A09` / `#E09A14` | low stock, ratings |
| `success` · `secondary` (info) · `purple` | `#3BD48F` · `#5AB6EE` · `#C4A0FA` | `#0E8F5B` · `#0F6FC0` · `#6F48D6` | status only |
| `imageWell` / `onImageWell` | `#E7EDEA` / `#10221D` | `#EEF2EF` / `#10221D` | the tile behind product photos |
| `shadowMd` / `shadowLg` | `0 10 28 -10 #000000B3` | `0 10 28 -10 #10231C24` | hovered cards, menus, dialogs only |

- **Image wells are light in both themes.** The catalog photos are transparent cut-outs and many products are black; on a dark well they vanish. Always put product photos on `colors.imageWell` (the `AppNetworkImage` default) and draw anything on top of the well with `onImageWell` / light-theme ink.
- **Accent sparingly.** One primary button per view. Selected chips, nav indicators and segmented buttons use `primarySoft` + accent text, never a solid fill. Links are muted at rest and take the accent on hover.
- **Warm signals:** coral (`sale`) for discount tags, "You save", destructive actions; amber for stars and low stock. Nothing else is warm.
- **Department hues** (`colors.departmentAccent(slug)`): electronics blue, fashion rose, beauty violet, home amber, groceries green, sports orange, automotive teal. Use them as a 2 px top border (`CategoryTopBorderCard`), a 6 px dot, or a small icon tint — never as a fill or text color for body copy.

### Type (`AppType`, `context.textTheme`)

| Voice | Font | Where |
|---|---|---|
| Editorial | **Source Serif 4** — every `display*` and `headline*` style; `AppType.serif(style)` | hero headings, section titles (`SectionHeader`), product name on the detail page, auth titles. Colour one phrase in the accent at most once per screen (`Text.rich`). |
| Interface | **Inter** — `title*`, `body*`, `label*` | everything else; app-bar titles; prices (`PriceText`, tabular figures, "Rs" set lighter) |
| Ledger | **JetBrains Mono** — `AppType.eyebrow(context)`, `AppType.data(context)`, `AppType.mono(style)` | eyebrows, order numbers, SKUs, spec values, timestamps, counters ("01 / 03"), kbd chips, status lines |

Scale: display 46/38/32 · headline 28/24/20 · title 18/16/14 · body 16/14/12 (`bodySmall` is muted) · label 14/12/11. Use `fontFeatures: AppType.tabular` on any number that changes or lines up.

**Eyebrows** (`Eyebrow`): 11 px mono caps, accent colour, one per section, above the heading. Sections on a page are numbered (`Eyebrow('Trending', index: 2)` → `02 — TRENDING`; `SectionHeader(index:, eyebrow:)`). Status eyebrows take a dot (`dot: true`).

### Shape, space, motion

- Radii `AppRadii`: 6 tags / kbd chips · 8 inputs and buttons · 12 cards and dialogs · 16 sheets · pill for chips and status badges.
- Spacing `AppSpacing` 4/8/12/16/20/24/32/48; page gutter `context.pagePadding`; content max 1200 (`ResponsiveCenter`).
- Borders over shadows. A card is `surface` + 1 px `border`; hover = `borderStrong` + `shadowMd`; never a different fill.
- Motion `AppDurations`: 150 hover/press · 250 standard · 300 colour and border transitions · 400 emphasis · 450 sheets (ease-out) · dialogs fade 150 ms + rise 20 px (`showAppDialog`). Always `context.motion(d)` so reduced-motion gets none. No looping decoration: `StatusLine` pulses three times and rests.
- Press feedback: everything tappable settles to ~0.96 (`Pressable`; `AppButton`, `ProductCard`, `CategoryTopBorderCard` already do). Light haptic on commit actions and tab changes.
- Focus is always visible: 1.5 px accent ring on inputs / outlined buttons, ink ring on filled buttons.

### Component habits (follow these on every screen)

- **Toasts** (`AppSnack`): bottom-centre, one at a time (a new one replaces the old), 3 s, first letter capitalised, radius 8 with a 1 px border. Show the server's `message` for success and for error.
- **Loading:** first load = skeletons shaped like the final layout (`SkeletonProductCard`, `SkeletonListTile`…). Refetch / paging = keep the content and dim it to 0.7 (`AnimatedOpacity`), never blank the screen. Buttons show a small spinner, dim to 0.55 and ignore taps (`AppButton(loading:)`).
- **Empty / error** (`EmptyState`, `ErrorState`): soft tinted icon circle, bold title, one muted help line, optional single action. Errors add the technical code small in mono (`HTTP 500`).
- **Forms:** errors only after a field has been touched (`AppTextField` validates on unfocus). On a failed submit call `validateForm(formKey)` — it scrolls to and focuses the first invalid field — and show `FormErrorBanner(message: kFixFieldsMessage)`. Mark required fields with `required: true` (red asterisk). Password fields warn when Caps Lock is on. Enter submits the last field.
- **Destructive actions:** always `ConfirmDialog.show(context, title: 'Remove this address?', confirmLabel: 'Remove', onConfirm: () => repo.delete(id))` — error-tinted icon circle, "This action cannot be undone.", outline Cancel + danger confirm that shows loading.
- **Status badges** (`StatusBadge('Delivered', tone: StatusTone.success)`): soft background, strong text, subtle border, pill.
- **Stats:** `StatBlock.count(count: n, caption: 'Products')` — the number counts up once (1.2 s ease-out, tabular) over a tiny mono caption.
- **Success moments:** `SuccessCheck()` draws its ring and check (order placed, password changed).
- **Avatars:** `AppAvatar(name:, imageUrl:)` — initials on a soft accent tint when there is no photo.
- **Copy:** anything a person might read back (order number, tracking id, version) is tappable: `copyToClipboard(context, value, label: 'Order number')` confirms with a toast; `KeyValueRow(copyable: true)` does it for you.
- **Icon buttons** always have a `tooltip`; titles get `Semantics(header: true)`; tap targets ≥ 44 px.
- **Live data over decoration:** prefer a real number, time or status ("Store online · 38 ms", "Updated just now", "Ends in 02:14:09", "Out for delivery") to an illustration. Use `StatusLine` / `Eyebrow(dot: true)`.
- **Keyboard** (web / desktop): `/` or Ctrl/⌘ K opens the search palette from anywhere (quick links first, then categories and debounced product results; ↑ ↓ ↵ esc), Alt 1–5 switches tabs. Show shortcuts with `KbdChip` only where they really work.

### Voice

Zelora speaks like a good shop assistant: short, direct, sentence case, friendly, never cute. Say what happened, then what to do. No exclamation marks, no "Oops", no emoji. The assistant is **Zel** ("Ask Zel", "Zel reads the reviews so you don't have to"). Examples: "Nothing saved yet" / "Tap the heart on anything you like. It will wait here." · "Can't reach the store" / "Check the server address in Settings." · "Only 3 left" · "You save Rs 4,100".

### Shell

- Phones in portrait (`context.useBottomNav`: width < 700): bottom navigation bar — Home, Explore, Assistant (Zel's spark), Cart (count badge), Account.
- Everything wider (tablet, desktop, web): a sticky storefront header (`StoreHeader`, 64 px, `surface` + bottom hairline, content capped at 1200): logo · Home / Explore / Ask Zel / Deals (current link gets a 2 px accent rule) · search field with `Ctrl K` chips (opens the palette; collapses to an icon below 880 px) · wishlist, notifications (dot), cart (count), account avatar menu. **There is no side rail** — pages get the full width, so lay out wide screens as a storefront (centred max-width content, multi-column grids), not as an admin panel.
- Screens inside a tab must not add their own logo / search / cart app-bar actions on wide layouts (the header has them): gate them with `context.useBottomNav`.

## Shared widget catalog (`core/widgets/widgets.dart`)

| Widget | Usage |
|---|---|
| `AppButton` | `AppButton(label: 'Pay', onPressed: f, loading: busy, expand: true, icon: Icons.lock)`; `.secondary`, `.ghost`, `.destructive`; `size: AppButtonSize.small/large` |
| `AppTextField` | `AppTextField(label: 'Email', required: true, controller: c, prefixIcon: Icons.mail_outline, validator: Validators.email, errorText: e?.fieldError('email'), onSubmitted: (_) => submit())`; `isPassword: true` adds a toggle |
| `FormErrorBanner` | `FormErrorBanner(message: error?.message)` — animated inline error |
| `AppNetworkImage` | `AppNetworkImage(url, width: 64, height: 64, fit: BoxFit.cover, borderRadius: AppRadii.inputAll)` — cached, shimmer, fallback icon, resolves relative URLs. Without `width` it decodes at the laid-out width (memory). `placeholder:` replaces the shimmer (e.g. the thumbnail while a big image loads) |
| `ProductCard` | `ProductCard(product: p)` (grid tile) / `variant: ProductCardVariant.wide` (list row); heart, discount badge, AI match badge, opens product page. Remembers the product in `ProductPreviewCache` on tap (instant detail page). `hero: true` flies the image into the detail gallery — only where a product appears once per screen |
| `ProductGrid` / `SliverProductGrid` | `ProductGrid(products: items)`, `.loading()`, `loadingMore: true`; 2/3/4/5 columns by width; tiles use `hero: true` |
| `ProductRail` | `ProductRail(products: items)` horizontal row, `.loading()` |
| `PriceText` | `PriceText(price, compareAt: was, size: PriceSize.large, showDiscount: true, showSavings: true)` — tabular figures, lighter "Rs", coral discount tag, optional "You save …" line |
| `RatingStars` | `RatingStars(4.6, count: 128)` compact · `RatingStars.full(4.6)` five stars |
| `SectionHeader` | `SectionHeader(title: 'Trending', eyebrow: 'This week', index: 2, subtitle: '…', leading: AiSparkleIcon(), onSeeAll: f)` — serif title; `serif: false` for utility headings in sheets |
| `EmptyState` | `EmptyState(icon: Icons.favorite_border, title: 'Nothing saved yet', message: '…', actionLabel: 'Browse', onAction: f)`; optional `eyebrow`, `detail` (mono line), `accent` (tints the circle), `compact` |
| `ErrorState` | `ErrorState(error: e, onRetry: f)` — offline errors get a server-address hint; shows `HTTP 500`-style code in mono |
| `LoadingView` | centered spinner when no skeleton fits |
| `Skeleton*` | `Skeleton(width:, height:)`, `Skeleton.circle(size:)`, `SkeletonText(lines: 3)`, `SkeletonProductCard()`, `SkeletonListTile()`, `SkeletonList(count: 6)` |
| `QuantityStepper` | `QuantityStepper(value: q, onChanged: f, max: 10, loading: busy)`; `min: 0` turns − into delete at 1 |
| `AppBadge` | `AppBadge(count: n, child: Icon(...))`, `AppBadge.dot(show: unread, child: ...)` |
| `ResponsiveCenter` / `SliverResponsiveCenter` | cap content width + gutters |
| `AppSnack` | `AppSnack.success(context, 'Added to cart')`, `.error(context, e)`, `.info(context, 'Removed', actionLabel: 'Undo', onAction: f)` |
| `AiSparkleIcon` / `AiGradientText` / `AiBadge` / `AiGradientBorder` / `AiGradient.mask` | Zel's accents, all solid (no gradient despite the legacy names): `AiSparkleIcon(size: 18, filled: false)` four-point spark, `AiBadge(label: '92% match')` (solid over photos, `solid: false` on surfaces), `AiGradientBorder(child: ...)` = 1 px accent border + soft tint for AI cards |
| `BottomSheetScaffold` + `showAppBottomSheet` | `showAppBottomSheet(context, builder: (_) => BottomSheetScaffold(title: 'Sort by', footer: AppButton(...), child: ...))` |
| `AppLogo` | brand mark (accent tile with a geometric Z, drawn in code) + serif wordmark; `showWordmark: false`, colour overrides |
| `Eyebrow` | `Eyebrow('Picked for you')`, `Eyebrow('Trending', index: 2)`, `Eyebrow('Store online', dot: true)`, `leading: AiSparkleIcon(size: 11)` |
| `StatBlock` | `StatBlock(value: '4.6', caption: 'Avg rating')` · `StatBlock.count(count: 194, caption: 'Products')` (counts up) · `compact: true` |
| `KeyValueRow` | `KeyValueRow(label: 'Order', value: '#ZL-10482', copyable: true)` — mono value; for order / spec / about tables |
| `KbdChip` | `KbdChip('Ctrl')`, `KbdChip('K')` — only for shortcuts that work |
| `StatusLine` | `StatusLine('Out for delivery', color: colors.warning)` — dot pulses three times, then rests |
| `StatusBadge` | `StatusBadge('Delivered', tone: StatusTone.success, icon: Icons.check_rounded)` — neutral / success / warning / danger / info / accent |
| `DotGridBackground` | `DotGridBackground(child: hero)` — quiet dot grid behind hero panels (`lines: true` for a line grid) |
| `CategoryTopBorderCard` | `CategoryTopBorderCard(accent: colors.departmentAccent(slug), onTap: f, child: ...)` — bordered card with a 2 px coloured top edge |
| `Pressable` | `Pressable(child: card)` — press-scale for custom tappables |
| `CountUp` | `CountUp(1264, style: t.displaySmall)` — 1.2 s ease-out, tabular |
| `SuccessCheck` | `SuccessCheck(size: 64)` — ring + check draw themselves |
| `AppAvatar` | `AppAvatar(name: user.name, imageUrl: user.avatarUrl, size: 40)` — initials fallback |
| `ConfirmDialog` / `showAppDialog` | `await ConfirmDialog.show(context, title: 'Remove item?', confirmLabel: 'Remove', onConfirm: () async {...})` → `bool`; `showAppDialog` for custom dialogs with the app motion |
| `copyToClipboard` | `copyToClipboard(context, order.number, label: 'Order number')` |
| `validateForm` / `kFixFieldsMessage` | `if (!validateForm(_formKey)) { setState(() => _banner = kFixFieldsMessage); return; }` — scrolls to and focuses the first invalid field |

Utilities: `FormReveal.validate(formKey)` (validates, scrolls the first invalid field into view; show `FormReveal.fixFields` in a `FormErrorBanner`), `ProductPreviewCache` (`remember`, `lookup(idOrSlug)`, `heroTag(id)`), `PagedController<T>` / `PagedState<T>` in `core/network/paged_controller.dart` (infinite-scroll base: implement `fetch(page)` + `idOf`, call `loadMore()`; dedupes items; `loadMoreError` for a retry row), `Formatters` (`price`, `priceCompact`, `compact`, `rating`, `discount`, `date`, `dateTime`, `relative`, `plural`), `Validators` (`email`, `password`, `confirmPassword`, `name`, `phone`, `otp`, `required`, `combine`, `strength`), `Debouncer` (search-as-you-type), `CategoryIcons.of(slug)`, extensions (`context.colors/textTheme/isWide/isDesktop/useBottomNav/pagePadding/reduceMotion/motion()`, `'smart-watches'.titleCase`).

## Commerce features

Screens: home, explore, product list, product detail (+ reviews), search, wishlist, cart, checkout (+ success), orders (+ detail), notifications, account (edit profile, addresses + form, change password).

- **Logic lives in controllers/providers**, screens stay presentational: `CartController`, `CheckoutController`, `OrderDetailController.cancel`, `AddressesController`, `NotificationsController`, `SearchHistoryController`, `WishlistActions`.
- **Lists**: pull-to-refresh everywhere; infinite scroll via `loadMore()` when `extentAfter < ~600`; refresh keeps content (Riverpod `isRefreshing`); a new sort/filter keeps the previous products on screen dimmed with a thin progress bar; product lists show `1–24 of 128 results`.
- **Product list filters**: `ProductQuery` (value equality → provider family key). Facets (`brands` with counts, `priceRange`) come from `meta.facets`; active filters show as removable chips with "Reset all". The empty state offers "Ask Zel instead" (assistant with the query).
- **Search**: suggestions debounce 600 ms with a 2-character minimum; a skeleton shows immediately while the debounce is pending. The Smart AI toggle sends the query to `Routes.smartSearchOf`.
- **Destructive actions** use `ConfirmDialog.show(..., onConfirm: () => controller.x())` (delete address, cancel order, sign out, clear search history). Removing cart/wishlist items is instant with an Undo snack instead.
- **Forms** validate after touch (`AppTextField` default) and on submit call `FormReveal.validate`. Server field errors map via `errorText: e?.fieldError('x')`; snacks show the server's `message` when it sends one (cart stock caps, password change).
- **Checkout** sends only `card.last4`; card number formatting, brand detection, Luhn, expiry and CVV checks are in `checkout/presentation/widgets/card_utils.dart`. Pakistani phone check: `validatePkPhone` (address form).
- **Wide layouts** (≥ 900 px): product detail, cart, checkout and order detail switch to two columns with a sticky right panel; explore becomes two-pane.
- AI slots the AI feature owns: `ForYouRail` (home), `ReviewSummaryCard` / `BoughtTogetherRail` / `SimilarProductsRail` (product page), `CartInsightsCard(onCartChanged:)` (cart), routes `productAsk` (`Routes.productAskOf(id)`), `visualSearch`, `bundleBuilder`, `shoppingDna` (protected).
- The assistant route accepts `prompt` (and `q` as an alias): `Routes.assistantWith(prompt: 'Find me…')`.

## AI features (`features/ai`, `features/assistant`)

All AI surfaces render the assistant identity only through the shared `AiSparkleIcon` (wrapped by `AiMark` / `AiAvatar` in `features/ai/presentation/widgets/ai_ui.dart`), so a new mark in `core/widgets` flows everywhere. Solid theme tokens only, no gradients/glows.

**Data**: `AiRepository` (`aiRepositoryProvider`) covers every `/ai/*` endpoint except chat, plus `addToCart`/`removeFromCart`/`cartQuantity` (return the new `itemCount`) and fire-and-forget `track(productId, source:)` (`ai_click`). `AssistantRepository` covers `/ai/chat`, conversations and feedback. Models live in `ai/data/models/ai_models.dart` and `assistant/data/chat_models.dart`; all parse leniently and tolerate extra fields.

**Providers** (`ai/providers/ai_providers.dart`, all autoDispose): `recommendationsProvider`, `similarProductsProvider(id)`, `boughtTogetherProvider(id)`, `reviewSummaryProvider(id)`, `compareProvider(compareKey(ids))`, `smartSearchProvider(q)`, `finderFlowsProvider`, `aiInsightsProvider`, `aiProductProvider(id)`, `cartInsightsProvider` (null for guests/empty cart, refetches when `cartCountProvider` changes), `shoppingProfileProvider`.
Assistant (`assistant/providers/chat_controller.dart`): `chatControllerProvider` (kept alive, reset on login/logout; `send`, `retry(key)`, `open(id)`, `newChat`, `rate(key, ±1)`), `conversationsProvider`, `showReasoningProvider` (persisted, `StorageKeys.aiShowReasoning`).

**Drop-in widgets** (`ai/presentation/widgets/`):

| Widget | Notes |
|---|---|
| `ForYouRail()` | title/subtitle from the API; hidden when empty; inline retry on error |
| `SimilarProductsRail(productId:)` / `BoughtTogetherRail(productId:)` | hidden when empty |
| `ReviewSummaryCard(productId:)` | sentiment gauge, pros/cons with mention counts, quotes, footnote; hidden with 0 reviews |
| `CartInsightsCard(onCartChanged:)` | cheaper swaps (one-tap Swap keeps quantity), complete-the-set, free-shipping gap; collapsible; hidden for guests/empty/nothing useful. Pass `onCartChanged` to reload the cart screen after a swap (badge syncs itself) |
| `AiProductRail` / `SliverAiProductGrid` / `AiProductTile` | product cards + "Why this?" chip → `showWhyThisSheet` (score bar + reasons); taps log `ai_click` with `source` |
| `CompareTable`, `CompareHeaderRow`, `CompareSpecRows`, `VerdictCards` | best value per row highlighted (`bestIndex`) |
| `BundleView(bundle:)` | items by role, swap sheet, budget bar, tips, "Add all to cart" |
| `EntityChipWrap(chips: entityChips(map))` | NLU entities → typed chips (budget/brand/category accents); optional remove |
| `SimpleMarkdown(text)` / `parseMarkdown` | tiny markdown subset (bold/italic/code, bullets, numbered, headings, line breaks) used for AI text |
| `AiCard`, `AiHeader`, `AiThinking`, `AiConfidenceBar`, `ScoreRow`, `AiSuggestionChip`, `AiInlineError`, `SlideFadeIn` | AI building blocks (`ai_ui.dart`) |

Helpers (`ai/presentation/ai_actions.dart`): `openAiProduct(context, ref, id, source:)`, `confirmAddToCart(...)` (confirm dialog → POST /cart/items → badge), `addAllToCart(...)`.

**Screens**: `AssistantScreen` (tab; `?c=` conversation, `?prompt=`/`?q=` auto-send; two panes ≥ 1000 px; guests get an in-tab sign-in prompt, so `/assistant` is no longer in `Routes.protected`), `ConversationsScreen`, `CompareScreen`, `SmartSearchScreen`, `FinderScreen`, `AiLabScreen`, `VisualSearchScreen` (Snap & Find, `image_picker`), `BundleBuilderScreen`, `ProductAskScreen`, `ShoppingDnaScreen`.

Chat action types handled: `view_all` (all query keys passed to `/products`, incl. `minPrice/maxPrice/minRating/gender`), `compare`, `add_to_cart` (confirm), `open_product`, `view_order`, `open_cart`; unknown types are hidden.

## Running

- Web: `flutter run -d chrome` (API at `http://<page host>:5000`). The backend must send CORS headers, including for `/uploads` images.
- Android emulator: run from Android Studio; API defaults to `http://10.0.2.2:5000` (cleartext allowed). Physical device: Settings → Server address → your PC's LAN IP, or `--dart-define=API_BASE_URL=http://192.168.1.5:5000`.
- Checks: `flutter analyze` (must be 0 issues) and `flutter test`.
