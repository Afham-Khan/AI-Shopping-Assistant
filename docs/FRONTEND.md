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

## Responsive layout — mobile app everywhere

- Zelora is a **mobile app on every screen**. Phones get the app full-screen. Anything ≥ 600 px wide (tablet, desktop, web) renders the whole app — every route, dialog, sheet and snackbar — inside a centred **phone-width column (460 px)** with 36 px rounded corners and a soft shadow, floating over the page wash (`AppFrame`, installed once in `MaterialApp.builder`). Inside the column `MediaQuery` reports the column's size, so **every screen lays out exactly as on a phone**: `context.isWide` / `isDesktop` are false, `useBottomNav` is true.
- **Never build a website layout**: no top navbar, no side rail / sidebar, no multi-column storefront. Design every screen for 360–460 px wide; the frame takes care of big screens.
- Wrap page content in `ResponsiveCenter` / `SliverResponsiveCenter` as before (gutter 16 px); forms use `maxWidth: Breakpoints.maxForm`.
- Must not overflow at 320 px wide or text scale 2.0 (app clamps at 2.0). Prefer `Wrap`, `Flexible`, `maxLines + ellipsis`. Grid tiles get their height from `ProductCard.compactHeight`, which scales with text size.

## Design system

**Identity v2 — "airy royal".** A clean, modern, minimal light shopping app: a light blue-white page with a very subtle wash of light from the top, crisp white rounded cards with soft shadows, one confident **royal blue**, dark navy text, slate secondary text, pill buttons and chips, circular white icon buttons, product photos on very light tiles (softly tinted per department), discounts in a vivid coral-red, amber "deal" accents and rating stars, prices in deep navy-blue. Light is the primary theme; dark (Settings → Appearance) is derived from the same hues. The assistant is **Zel** — always written via `AppConfig.assistantName`, never hard-coded — and its mark is the **bag mascot** (`AiMascot`; `AiSparkleIcon` renders it at icon size). No four-point sparkle / star anywhere (it reads as another company's AI).

**Never:** mint / teal (the old palette is gone — legacy `AppColors.mint*` names now point at blue), black-and-white monochrome, glow / neon / glassmorphism / blur, loud gradients, emoji as icons, a website-style top navbar, a side rail or sidebar, hard-coded hex in features, serif or monospace fonts.

### Color (`context.colors` → `AppPalette`; light is the default theme)

| Token | Light (default) | Dark | Use |
|---|---|---|---|
| `background` · `backgroundTop` / `backgroundBottom` | `#F1F4FD` · `#F8FAFF` / `#EAEFFC` | `#0B1020` · `#10172C` / `#0A0E1C` | page wash (`AppBackground`, `colors.backgroundWash`); flat `background` = scrolled-under app bar |
| `surface` | `#FFFFFF` | `#141B2E` | cards, sheets, inputs, bottom bar, circular icon buttons |
| `surfaceVariant` | `#F5F8FE` | `#1A2238` | quiet fills, skeletons, pressed rows, inset panels |
| `surfaceRaised` | `#E8EEFB` | `#222B44` | tracks (slider, progress, step bars), unselected dots |
| `border` / `borderStrong` | `#E1E7F5` / `#C5CFE6` | `#252E47` / `#36415F` | light grey-blue hairline · hover and emphasis |
| `text` / `muted` / `faint` | `#0F172A` / `#556076` / `#636C82` | `#E8ECF6` / `#A3ADC4` / `#8790AB` | navy primary · slate secondary (5.5:1 on the wash) · captions, placeholders (4.6:1 on the wash) |
| `primary` (`primaryHover`, `onPrimary`, `primarySoft`) | **`#1D5BF0`** (`#1648D8`, `#FFFFFF`, `#E7EFFF`) | `#7AA2FF` (`#94B4FF`, `#0A1A3F`, `#1C2850`) | royal blue: primary buttons, active nav, selected chips, links, "See all" |
| `ai` / `aiSoft` | = `primary` / `primarySoft` | same | AI surfaces (named for intent) |
| `sale` (`onSale`, `saleSoft`) | `#D5190B` (`#FFFFFF`, `#FFF1EE`) | `#FF7F6B` | discount pills, "You save", destructive, cart badge (vivid coral-red, 5.3:1 with white) |
| `star` · `warning` · `success` · `secondary` (info) | `#F59E0B` · `#B45309` · `#15803D` · `#0369A1` | `#FBBF24` · `#FBBF24` · `#4ADE80` · `#38BDF8` | ratings · low stock · status · info |
| `imageWell` / `onImageWell` | `#F5F7FC` / `#0F172A` | `#EEF1F8` / `#0F172A` | the very light tile behind product photos (light in both themes); `colors.departmentWell(slug)` tints it 10 % with the department hue (department or category slug; unknown = plain well) |
| `price` | `#0B2A6B` | `#DDE7FF` | amounts (`PriceText`): confident navy-blue, 13:1 on white |
| `deal` (`onDeal`, `dealSoft`, `dealInk`) | `#FFB020` (`#0F172A`, `#FFF4D9`, `#8A4B00`) | `#FBBF24` | warm amber for deal pills / strips: `DealTag`, `StatusTone.deal`. Navy ink on the fill (9.8:1); never amber text on white |

Primary `#1D5BF0` is a touch more saturated than the first v2 blue yet still AA everywhere: 5.5:1 with white text, 4.8–5.0:1 as text on the page wash, 4.8:1 on its own soft tint. `sale`, `muted`, `faint` and `price` are contrast-checked on the whole wash in `test/theme_brightness_test.dart`. Department hues (`colors.departmentAccent(slug)`) are calm mid-tones for small icon tints, 6 px dots or a 10 % tile behind an icon (`colors.departmentSoft(slug)`) — never fills or body text. Brighter does not mean louder: no gradients-as-decoration, glow or glass; the lift comes from crisp white cards, hairlines and shadow.

**Shadows** (always via tokens, never hand-rolled): `colors.shadowSm` resting cards (product cards, `AppCard`, search bar, circle buttons) · `colors.shadowMd` hover / floating (menus, floating bars, photos' controls) · `colors.shadowLg` dialogs and the desktop app frame. All navy-tinted and very soft.

### Type (`context.textTheme`, `AppType`) — one family: **Plus Jakarta Sans**

Chosen with the ui-ux-pro-max font database: a geometric sans with soft, rounded-feeling bowls (the reference's look), popularity rank #13 on Google Fonts, variable 200–800 so one family carries display → caption, and a tall x-height that stays legible at 11–13 px. (Urbanist is classified *Display* — weak for small body text; Outfit is paired with a separate body font in the database; Lexend reads wider and more "educational".)

| Role | Style | Weight |
|---|---|---|
| Screen / hero titles | `displaySmall` 29 · `headlineLarge` 26 | 800 |
| Section titles (`SectionHeader`) | 19 | 800 |
| App-bar titles | `titleMedium` 17 (centred) | 700 |
| Card titles, list titles | `titleSmall` 14 / `bodyMedium` 13.5 | 600 |
| Body | `bodyLarge` 16 · `bodyMedium` 14 · `bodySmall` 12.5 (muted) | 400 |
| Labels, chips, buttons, nav | `labelLarge` 14 · `labelMedium` 12 · `labelSmall` 11 · buttons 15 | 600–700 |
| Prices (`PriceText`) | bold, **tabular figures**, lighter "Rs" | 700 |

- Use `fontFeatures: AppType.tabular` on every number that changes or lines up (prices, counts, order numbers, timers). `AppType.data(context)` is the tabular style for order numbers / SKUs / timestamps.
- `AppType.serif()` / `AppType.mono()` still compile but return Plus Jakarta Sans (heavier / tabular). Don't use them in new code.
- **Eyebrows** (`Eyebrow`): optional 11.5 px bold uppercase blue label above a heading — at most one per section, only when it adds information. No section numbering.

### Shape, space, motion

- Radii `AppRadii`: **8** tags / kbd chips · **14** inputs and small image tiles (`inputAll`) · **18** cards and dialogs (`cardAll`) · **24** sheets (`sheetTop`/`sheetAll`) · **36** desktop app frame · **pill** for every button, chip, badge, search bar and segmented control.
- Spacing `AppSpacing` 4/8/12/16/20/24/32/48; **page gutter 16** (`context.pagePadding`).
- **Cards**: white `surface`, radius 18, `shadowSm`, a barely-there border (`border` at 60 % in light). Hover → `shadowMd`. Never a tinted fill unless selected (`primarySoft` + 1.5 px `primary` border).
- **Product photos** sit on an inset `imageWell` tile (radius 14) inside the white card, with padding around the cut-out.
- Motion `AppDurations`: 150 fast · 180 hover · 250 standard · 300 colour/border · 400 emphasis · 450 sheets. Always `context.motion(d)`. **Hover and press live in `Pressable`** (see the catalog): under a mouse a card lifts 2 px and its shadow goes `shadowSm` → `shadowMd`, a small circle grows 6 %, with the blue hover tint from the theme (`hoverColor`, chips, list tiles, search bar); a press settles to 0.97 (0.98 on big surfaces). Reduced motion keeps the tints and drops all movement. The mascot's idle behaviour is the only looping motion (see `AiMascot`).
- Focus is always visible: 1.6 px blue ring on inputs, 2 px ring on buttons.

### Components (theme defaults — just use the Material widget or the app wrapper)

- **Buttons** (`AppButton`): pill, 50 px tall (40 small / 56 large), 15 px bold. Primary = filled royal blue ("Buy now"); `.secondary` = white with a 1.5 px blue outline and blue label ("Add to cart"); `.ghost` = blue text; `.destructive` = red fill. One filled primary per view.
- **Chips** (`ChoiceChip`/`FilterChip`): white pills with a grey-blue hairline; selected = light-blue tint, 1.5 px blue outline, blue label (the reference's colour/storage chips). No checkmarks.
- **Inputs** (`AppTextField`): white, radius 14, hairline border, blue focus ring, muted prefix icons. **Search** = `AppSearchBar` (white pill, search icon, soft shadow; button mode opens search, field mode types).
- **App bars**: transparent over the wash at rest, solid `background` once content scrolls under, centred bold title. The automatic back / close buttons render as **white circles** (theme `actionIconTheme`). For your own actions use `CircleIconButton` (white circle + `shadowSm`, ≥ 44 px target, badge/dot support).
- **Bottom bar** (`ZeloraNavBar` in the shell): white, 26 px rounded top corners, soft upward shadow; Home · Explore · **Zel** (centre: raised blue circle holding the white bag mascot, happy eyes while open) · Cart (red count badge) · Profile. Active tab = blue icon + bold blue label on a light-blue pill.
- **Badges**: count badges are `sale` red with white text; status badges (`StatusBadge`) are soft-tinted pills.
- **Dialogs / sheets**: white, radius 24 / 24-top, navy-tinted scrim. Toasts (`AppSnack`): navy pill-ish bar (radius 14), white text.
- **Lists in cards**: `AppCard(padding: EdgeInsets.zero, child: Column(children: [ListTile(...), Divider(), ...]))`.

### Component habits (follow these on every screen)

- **Scaffolds are transparent** — the page route paints `AppBackground`. Don't set `backgroundColor` on a `Scaffold` (it would hide the wash); only custom overlays / full-bleed panels outside a page need `AppBackground(child: …)`.
- **Toasts** (`AppSnack`): bottom-centre, one at a time, 3 s, first letter capitalised. Show the server's `message` for success and for error.
- **Loading:** first load = skeletons shaped like the final layout. Refetch / paging = keep content and dim to 0.7. Buttons show a spinner (`AppButton(loading:)`).
- **Empty / error** (`EmptyState`, `ErrorState`): soft tinted icon circle, bold title, one muted help line, optional single action.
- **Stats:** `StatBlock.count(count: n, caption: 'Products')` — the number counts up once (tabular) over a small muted caption.
- **Status badges** (`StatusBadge('Delivered', tone: StatusTone.success)`), **avatars** (`AppAvatar`), **copy** (`copyToClipboard` / `KeyValueRow(copyable: true)`) and **success moments** (`SuccessCheck()`) work as before.
- **Forms:** errors only after a field has been touched; on a failed submit `validateForm(formKey)` + `FormErrorBanner(message: kFixFieldsMessage)`. Required fields `required: true`. Enter submits the last field.
- **Destructive actions:** `ConfirmDialog.show(...)`.
- **Icon buttons** always have a `tooltip`; titles get `Semantics(header: true)`; tap targets ≥ 44 px; icons are Material Rounded/Outlined — never emoji.
- **Keyboard** (web / desktop, a hidden extra): `/` or Ctrl/⌘ K opens the command palette from anywhere, Alt 1–5 switches tabs. Settings lists them; the desktop frame shows a small "Ctrl K to search" hint outside the column.

### Logo (`AppLogo`, `ZeloraWordmark`, `ZeloraMarkPainter`)

- **The Z-bag mark**: a bold geometric white "Z" whose top bar is the rim of a shopping bag, with a rounded bag handle rising from it, on a royal-blue rounded tile (radius 30 %, a whisper of top light). No spark or star. Legible from a 16 px favicon up.
- **Wordmark**: "Zelora" in Plus Jakarta Sans ExtraBold (800), tracking −3.5 %, navy (`colors.text`) or white on blue.
- Usage: `AppLogo(size: 30)` (mark + wordmark) in auth headers / onboarding; `AppLogo(size: 40, showWordmark: false)` for the mark alone; `ZeloraWordmark(size: 20)` for the name alone. Don't recolor the tile except white-on-blue inversion (`tileColor: Colors.white, glyphColor: AppColors.blue`); never stretch, outline, add effects, or place it on a busy photo.
- Icons are generated from the same painter: `flutter test tool/generate_app_icons.dart` writes `web/favicon.png`, `web/icons/*` (incl. maskable + apple-touch) and Android `mipmap-*/ic_launcher*.png` + the adaptive icon XML. Re-run it after changing the mark.

### Assistant name

`AppConfig.assistantName` (currently **"Zel"**) is the only place the name lives. Write `'Ask ${AppConfig.assistantName}'`, never `'Ask Zel'` or `'Zelora AI'` (Zelora is the store; the assistant is Zel). Don't use `Icons.auto_awesome` (sparkle) for AI actions — use `AiSparkleIcon` (the mascot) as the leading widget instead.

### Voice

Zelora speaks like a good shop assistant: short, direct, sentence case, friendly, never cute. Say what happened, then what to do. No exclamation marks, no "Oops", no emoji. The assistant is **Zel** ("Ask Zel", "Zel reads the reviews so you don't have to"). Examples: "Nothing saved yet" / "Tap the heart on anything you like. It will wait here." · "Can't reach the store" / "Check the server address in Settings." · "Only 3 left" · "You save Rs 4,100".

### Shell

- One shell for every screen size: `AppShell` = `Scaffold(body: navigationShell, bottomNavigationBar: ZeloraNavBar(...))`. Tabs: Home (`/`), Explore (`/explore`), Zel (`/assistant`), Cart (`/cart`), Profile (`/account`); each tab keeps its own stack (route paths unchanged).
- There is **no** `StoreHeader`, top navbar or rail any more. Screens own their headers: Home should show the greeting / logo, an `AppSearchBar` and `CircleIconButton`s (notifications, wishlist); other tab roots use the transparent `AppBar` with a centred title. Don't gate header actions on `context.useBottomNav` any more (it is always true).
- On-screen search entry points push `Routes.search`; the keyboard shortcut opens the command palette.

## Shared widget catalog (`core/widgets/widgets.dart`)

| Widget | Usage |
|---|---|
| `AppButton` | `AppButton(label: 'Pay', onPressed: f, loading: busy, expand: true, icon: Icons.lock)` (filled blue pill); `.secondary` (blue outline pill), `.ghost` (blue text), `.destructive`; `size: AppButtonSize.small/large` |
| `AppCard` | `AppCard(child: ...)` white radius-18 card with `shadowSm`; `onTap:` adds press + hover lift (2 px, `shadowMd`, blue tint); `selected: true` = blue outline (pair with `color: colors.primarySoft`); `padding: EdgeInsets.zero` for list groups |
| `CircleIconButton` | `CircleIconButton(icon: Icons.favorite_border_rounded, tooltip: 'Save', onPressed: f)` white circle + soft shadow (app bars, over photos); `badgeCount:`, `dot:`, `filled: false` (quiet tint on white cards), `size:` |
| `AppSearchBar` | `AppSearchBar(onTap: () => context.push(Routes.search))` (button mode) · `AppSearchBar(controller: c, autofocus: true, onChanged: f, onSubmitted: g)` (field) · `trailing: CircleIconButton(...)` |
| `AppBackground` | the page wash; routes already paint it — use only for custom overlays / panels outside a page |
| `AppFrame` | installed in `app.dart`; frames the app in a 460 px column on screens ≥ 600 px (`AppFrame.framed(size)`) |
| `AppTextField` | `AppTextField(label: 'Email', required: true, controller: c, prefixIcon: Icons.mail_outline, validator: Validators.email, errorText: e?.fieldError('email'), onSubmitted: (_) => submit())`; `isPassword: true` adds a toggle |
| `FormErrorBanner` | `FormErrorBanner(message: error?.message)` — animated inline error |
| `AppNetworkImage` | `AppNetworkImage(url, width: 64, height: 64, fit: BoxFit.cover, borderRadius: AppRadii.inputAll)` — cached, shimmer, fallback icon, resolves relative URLs. Without `width` it decodes at the laid-out width (memory). `placeholder:` replaces the shimmer (e.g. the thumbnail while a big image loads) |
| `ProductCard` | `ProductCard(product: p)` (grid tile: white card, inset light image tile, white heart circle, red discount pill, brand · 2-line title · rating · bold price) / `variant: ProductCardVariant.wide` (list row); AI match badge, opens product page. Remembers the product in `ProductPreviewCache` on tap (instant detail page). `hero: true` flies the image into the detail gallery — only where a product appears once per screen |
| `ProductGrid` / `SliverProductGrid` | `ProductGrid(products: items)`, `.loading()`, `loadingMore: true`; 2/3/4/5 columns by width; tiles use `hero: true` |
| `ProductRail` | `ProductRail(products: items)` horizontal row, `.loading()` |
| `PriceText` | `PriceText(price, compareAt: was, size: PriceSize.large, showDiscount: true, showSavings: true)` — bold tabular figures, lighter "Rs", red discount tag, optional "You save …" line |
| `RatingStars` | `RatingStars(4.6, count: 128)` compact · `RatingStars.full(4.6)` five stars |
| `SectionHeader` | `SectionHeader(title: 'Trending', subtitle: '…', leading: AiSparkleIcon(), onSeeAll: f)` — 19 px ExtraBold title, blue "See all"; optional `eyebrow:`; `serif: false` = smaller utility heading for sheets (`index:` is ignored) |
| `EmptyState` | `EmptyState(icon: Icons.favorite_border, title: 'Nothing saved yet', message: '…', actionLabel: 'Browse', onAction: f)`; optional `eyebrow`, `detail` (small tabular line), `accent` (tints the circle), `compact` |
| `ErrorState` | `ErrorState(error: e, onRetry: f)` — offline errors get a server-address hint; shows the `HTTP 500`-style code small |
| `LoadingView` | centered spinner when no skeleton fits |
| `Skeleton*` | `Skeleton(width:, height:)`, `Skeleton.circle(size:)`, `SkeletonText(lines: 3)`, `SkeletonProductCard()`, `SkeletonListTile()`, `SkeletonList(count: 6)` |
| `QuantityStepper` | `QuantityStepper(value: q, onChanged: f, max: 10, loading: busy)`; `min: 0` turns − into delete at 1 |
| `AppBadge` | `AppBadge(count: n, child: Icon(...))`, `AppBadge.dot(show: unread, child: ...)` |
| `ResponsiveCenter` / `SliverResponsiveCenter` | cap content width + gutters |
| `AppSnack` | `AppSnack.success(context, 'Added to cart')`, `.error(context, e)`, `.info(context, 'Removed', actionLabel: 'Undo', onAction: f)` |
| `AiMascot` | the assistant mascot, alive: `AiMascot(size: 56)` idles — a blink every 3–6 s (sometimes two), an occasional glance left / right / up, and every 10–15 s a brief happy squint with a wider smile · `mood: AiMood.thinking` (eyes sweep side to side, small bob — while an answer streams) · `mood: AiMood.happy` (arc eyes, bigger smile, one hop) · `mood: AiMood.listening` + `gaze: Offset(x, y)` (−1…1, +y down; the eyes rest toward the composer and glide when it changes; still blinks) · `color: Colors.white` on blue fills · `outline: true` · `animate: false`. Animates from 20 px (below 28 px: simplified drawing, no smile line); `AiSparkleIcon` stays a static icon. **Cost:** one `AnimationController` per mascot that only runs *during* a beat (a few frames every couple of seconds; the timing comes from `MascotScheduler`, pure Dart), painted by a `CustomPainter` in its own `RepaintBoundary`; everything pauses while off-screen (`TickerMode`, e.g. another tab) or when the app is in the background; reduced motion = static face. Live in the nav bar, the assistant header (it watches the composer while the user types: `ChatInputBar(onTyping:)`), the welcome / guest views and the typing indicator |
| `AiSparkleIcon` / `AiGradientText` / `AiBadge` / `AiGradientBorder` / `AiGradient.mask` | the assistant's accents, all solid blue (no gradient despite the legacy names): `AiSparkleIcon(size: 18, filled: false, color:)` = the static bag mascot at icon size (name kept for old call sites), `AiBadge(label: '92% match')` pill (solid over photos, `solid: false` on surfaces), `AiGradientBorder(child: ...)` = soft blue border + light tint for AI cards |
| `BottomSheetScaffold` + `showAppBottomSheet` | `showAppBottomSheet(context, builder: (_) => BottomSheetScaffold(title: 'Sort by', footer: AppButton(...), child: ...))` |
| `AppLogo` / `ZeloraWordmark` | the Z-bag mark on a royal-blue tile + "Zelora" wordmark (Plus Jakarta Sans 800); `showWordmark: false`; `ZeloraWordmark(size: 20)` alone; see Design system → Logo |
| `Eyebrow` | `Eyebrow('Picked for you')`, `Eyebrow('Store online', dot: true)`, `leading: AiSparkleIcon(size: 11)` — 11.5 px bold uppercase blue (no numbering) |
| `StatBlock` | `StatBlock(value: '4.6', caption: 'Avg rating')` · `StatBlock.count(count: 194, caption: 'Products')` (counts up) · `compact: true` |
| `KeyValueRow` | `KeyValueRow(label: 'Order', value: '#ZL-10482', copyable: true)` — tabular value; for order / spec / about tables |
| `KbdChip` | `KbdChip('Ctrl')`, `KbdChip('K')` — only for shortcuts that work |
| `StatusLine` | `StatusLine('Out for delivery', color: colors.warning)` — dot pulses three times, then rests |
| `StatusBadge` | `StatusBadge('Delivered', tone: StatusTone.success, icon: Icons.check_rounded)` — neutral / success / warning / danger / info / accent |
| `DotGridBackground` | legacy (v1 editorial); avoid in new screens — v2 surfaces are plain white cards on the wash |
| `CategoryTopBorderCard` | `CategoryTopBorderCard(onTap: f, child: ...)` — white soft-shadow card (v2 draws no top edge unless `topBorderWidth: 2`); prefer `AppCard` in new code |
| `Pressable` | `Pressable(child: card)` — the one place hover + press feedback lives. Mouse: `hover: PressableHover.lift` (default, −2 px) / `.grow` (`hoverScale`, default 1.02) / `.none`; any pointer: press scale `scale` (default 0.97; a press that turns into a drag or scroll releases). `Pressable.builder(builder: (context, hovered, pressed) => …)` swaps shadow / tint with the pointer. Already used by `AppCard`, `ProductCard`, `CircleIconButton`, `CategoryTopBorderCard`, `AppSearchBar`, `AppButton`; use it (not hand-rolled `MouseRegion`s) for new tiles, quick actions and category tiles |
| `DealTag` / `StatusTone.deal` | `DealTag('Flash deal')` solid amber pill with navy ink; `StatusBadge('Ends today', tone: StatusTone.deal)` soft amber pill — one per surface, next to (not instead of) the red discount tag |
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

All AI surfaces render the assistant identity only through the shared mascot (`AiMascot` / `AiSparkleIcon`) (wrapped by `AiMark` / `AiAvatar` in `features/ai/presentation/widgets/ai_ui.dart`), so a new mark in `core/widgets` flows everywhere. Solid theme tokens only, no gradients/glows.

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

### Smart shopping features (price watch, outfit, specs, gifts, memory)

| Feature | Where | Notes |
|---|---|---|
| **Price watch / smart wishlist** | `features/wishlist` (data: `price_watch_models/repository`, `providers/price_watch_providers.dart`) | `GET/POST/DELETE /alerts/price-watch`. `priceWatchesProvider` (shared list, empty for guests) and `priceWatchForProvider(productId)`. `showWatchPriceSheet(context, ref, product:)` = target chips (any drop / 5% / 10% / custom, always below today's price) + back-in-stock switch, edit and stop (ConfirmDialog). `PriceWatchBadge` on wishlist tiles ("Watching · target Rs X"). |
| **Price alerts** | `PriceAlertsScreen` at `Routes.priceAlerts` (`/price-alerts`, protected) | Lists watches with the server's status line, edit, "Stop watching" (ConfirmDialog). Entries: Account → Price alerts, wishlist app bar, wishlist note, assistant welcome. |
| **Price history** | `features/product` (`priceHistoryProvider(id)`, `PriceHistoryCard`, `PriceHistoryChart`) | `GET /products/:id/price-history`. Step-line chart you can scrub. Only real recorded changes are drawn; with none it says "Tracking started today" / "Tracking since …" instead of faking a line. |
| **Alert notifications** | `features/notifications` | `price_drop` / `restock` tiles show the product photo and `Rs old → Rs new  -11%`; tap opens the product. `AppNotification.oldPrice/newPrice/dropPercent/thumbnail`. |
| **Complete the look** | `CompleteTheLookSection(product:, departmentSlug:)` (product page) | `GET /ai/complete-look/:id` (`completeLookProvider`). Shown for fashion only (`isFashionProduct`) and only when `kind == "outfit"`; role labels, reasons, add one piece (`quickAddToCart`) or "Add the look" (`addAllToCart`, includes the viewed item). |
| **Spec explainer** | `showSpecExplainerSheet(context, productId:, productTitle:, preloaded:)`, `SpecExplainerBody`, `SpecExplainerCard` (chat) | `GET /ai/explain/:id` (`specExplainerProvider`). "Who it's for" + each spec with plain meaning and a 1–5 `SpecLevelBar`. The chat renders `meta.explain` when present. Product page: a prominent "Explain these specs" card at the top of the Specifications block and an "Explain specs" chip. |
| **Spec sheet** | `features/product/presentation/widgets/specs_section.dart` | `SpecsSection(specs:, onExplain:)`: explain card → **key specs** as a two-column grid of `SpecTile`s (icon, bold value, muted label; one column below 300 px or at large text) → everything else as a label / value list with hairlines ("All specifications", collapsed to 6 rows). `selectKeySpecs` picks up to 6 by `keySpecPriority` (processor, RAM, storage, display, battery, camera … fabric, fit, movement, engine …); `shortSpecValue` shows a long value's headline on the tile while `specsForList` keeps the full text in the list; `SpecIcons.of(name, value:)` maps RAM → memory, Storage → sd card, Display → phone / monitor (by inches), Battery, Camera, Processor → circuit board, Weight → scale, Fabric → texture, Volume → drop … (neutral fallback). `HighlightChips(items:)` shows highlights as check-icon pills. |
| **Compare v2** | `CompareScreen` + `widgets/compare_extras.dart` | "Only show differences" (client-side on `row.differs`), "What do you need it for?" re-queries with `need` (`compareKey(ids, need:)`) and highlights **Best for you** (`forYou`) in the header, a card and the pros/cons. Pros and cons per product from `prosCons`. The previous table stays on screen (dimmed) while a new need loads. |
| **Gift Finder** | `GiftFinderScreen` at `Routes.giftFinder` (`/gift-finder`), controller `giftFinderProvider` | Steps who → occasion → budget → interests with smart defaults (budget per recipient, suggested interests first); `POST /ai/gift`; results = note + cards with reasons. "Ask Zel instead" → `Routes.assistantWith(prompt: giftPrompt(...))`. Entries: assistant welcome, Account → Gift finder. |
| **Snap & Find crop** | `VisualSearchScreen` + `widgets/image_cropper.dart` | After picking a photo the user drags a box ("Select the item") before searching. `cropToPng` cuts the region with `dart:ui` (`PictureRecorder`, max 1024 px side, PNG) so it works on web; "Whole photo" skips the crop; "Adjust selection" returns to it. The 503 `VISUAL_UNAVAILABLE` handling and the describe-it fallback are unchanged. |
| **Shopping memory** | `ShoppingMemoryScreen` at `Routes.memory` (`/account/memory`, protected), `shoppingMemoryProvider` | `GET/PUT/DELETE /users/me/memory`: consent switch (optimistic, rolls back), what Zel learned (server summary lines, categories, brands, price range, recent searches), "Forget everything" (ConfirmDialog → DELETE, then Shopping DNA and picks are refreshed). |
| **Voice** | `chat_input_bar.dart`, `assistant/data/speech_out*.dart`, `readAloudProvider` | The mic detects browsers without speech recognition (shows a struck-through mic and says so once, no repeated errors); recognizer callbacks forward to the live composer. **Read replies aloud** is web only (browser `speechSynthesis` via `package:web`, no plugin): the speaker toggle in the assistant app bar only appears where supported; replies are spoken once when they arrive. The voice comes from `pickVoice` (`speech_voice.dart`, pure Dart, tested): Google UK English Female → Microsoft Aria / Jenny / Zira → Samantha → other pleasant female voices → any voice named "female" → any non-male English voice (natural / neural first). The list is re-read on `voiceschanged` (Chrome fills it late; `SpeechOut.warmUp()` runs when the switch is on). Pitch 1.1, rate 0.95; long replies are queued in sentence-sized pieces (Chrome cuts one long utterance at ~15 s). `speakableText` = `speechTextFromMarkdown` + "Rs 30,000" → "30,000 rupees", "Rs 10k-20k" → "10 thousand to 20 thousand rupees", "-10%" → "10 percent off", "4.6/5" → "4.6 out of 5"; no URLs, emoji or arrows. |

Tests: `test/shopping_models_test.dart` (parsing, targets, crop math, gift controller), `test/shopping_widgets_test.dart` (sheets, cards, screens at 320–400 px and text scale 2.0), `test/api_contract_test.dart` (parsers against real responses saved in `test/fixtures/api/`).

## Signature experiences (Home room, scroll story, Discover)

**Home** (`features/home/presentation/home_screen.dart`) reads top to bottom: greeting + `AskBar` → **Room** (hero) → **ScrollStory** (pick of the week) → Flash deals (`ParallaxDealsRail` + countdown) → `ForYouRail` → `DiscoverEntryCard` → Trending → "More from Zel" (`QuickActions`). The banner carousel and department tiles are no longer on Home (the room's zones are the departments; Explore still lists them).

**Room** (`features/home/presentation/room/`, data in `features/home/data/room_repository.dart`, providers in `features/home/providers/room_providers.dart`)
- `RoomSection` — illustrated room painted in code (`RoomPainter`, colours from `RoomPalette.of(context.colors)`, tokens only). Seven zones (`RoomLayout.zones`, design space 1000 × 880): wardrobe (fashion), desk (electronics), window/driveway (`garage`, automotive), vanity (beauty), shelf (home), kitchen (groceries), gym corner (sports). Featured cut-outs stand on each zone's `slot`.
- Tap a zone or its numbered hotspot → camera glides in (`RoomLayout.viewportFor`), the rest dims (`RoomFocusPainter`), and `RoomTray` slides up (save / add / open, "See all" → `/products?department=`). Hotspots pulse five times then rest; explored zones are persisted (`roomExploredProvider`, "3/7 explored").
- "Build my setup" → `showSetupSheet` (goal + budget) → `POST /ai/bundle` → `roomSetupProvider.place(...)` maps each piece to a zone by category (`RoomLayout.zoneForProduct`, rug if none) and the pieces fly in on staggered arcs while the budget meter fills; "Add all to cart" uses `addAllToCart`.
- Wall clock and day/night light follow the local time (`RoomLayout.nightFactor`, refreshed every 30 s).
- Data: `GET /catalog/room`; on 404 it falls back to `/catalog/departments` + `/products?department=` per zone.

**Scroll story + parallax** (`features/home/presentation/widgets/scroll_story.dart`, `parallax_deals_rail.dart`)
- `ScrollStory(product:)` — the featured cut-out turns (−16° → +9°), lifts and settles as the card crosses the viewport. `ParallaxImage(child:)` drifts an image against the horizontal rail and the page scroll. `viewportProgress(context, scrollable)` gives 0 → 1 across the viewport.

**Discover** (`/discover`, `Routes.discover`; `features/discover/**`; entry cards on Home and Explore)
- `DiscoverScreen`: reels row → `TasteStrip` → `SwipeDeck` → Pass / Bag / Like buttons. Drag (tilts with the drag and the grab point), fling or pass 30 % width (22 % height for up) to commit, otherwise it springs back. Stamps LIKE / PASS / BAG fade in with the drag. Keyboard: ← pass, → like, ↑ bag, Backspace or Ctrl Z undo. Haptics: tick when a drag arms, light impact on commit.
- Like → `POST /discover/swipe` + saved to the wishlist (signed in). Bag → the server adds one to the cart (badge refreshed; falls back to `POST /cart/items` if the endpoint is missing). Pass → negative signal. Undo puts the card back and reverses the wishlist/cart effect.
- Likes/bags inject up to three "Because you liked X" / "Goes with X" cards from the swipe's `next` (fallback `/ai/similar`). The deck refills below five cards.
- Taste: `TasteStrip` (stacked category bar + confidence) and `TastePanel` sheet (shares, price appetite, confidence ticks, signals, counts). Server taste (`GET /discover/taste` on open, then each swipe) wins over the local estimate (`DeckLogic.localTaste`) used for guests.
- Reels: `ReelsRow` circles → `openReels(context, reels, i)` → `ReelsViewer` (segment bars, tap right/left, hold to pause, swipe sideways between departments, drag down or Esc to close, View / Add to cart).
- Pure logic, unit-tested: `DeckLogic` (`swipe`, `undo`, `inject`, `append`, `decide`, `stamp`, `localTaste`), `ReelsCursor` (`next`, `previous`) in `features/discover/data/deck_model.dart`. Shared one-tap actions: `quickAddToCart`, `quickToggleSave`, `openProduct` (`features/discover/presentation/shop_actions.dart`).

**Motion and performance rules used here**
- Scroll-linked motion is paint-only: `Flow` delegates repaint from `ScrollPosition` (no widget rebuilds while scrolling). Camera zoom, deck drag and story progress use `Transform` inside `AnimatedBuilder` / `ValueListenableBuilder`, with the expensive content passed as `child` and wrapped in `RepaintBoundary`. The room illustration repaints only when the minute or theme changes.
- Reduced motion (`context.reduceMotion`): camera and tray jump, no fly-in, no hotspot pulse, no scroll story / parallax transforms, cards leave without the fly animation, reels keep their timer but drop the slow zoom.

## Running

- Web: `flutter run -d chrome` (API at `http://<page host>:5000`). The backend must send CORS headers, including for `/uploads` images.
- Android emulator: run from Android Studio; API defaults to `http://10.0.2.2:5000` (cleartext allowed). Physical device: Settings → Server address → your PC's LAN IP, or `--dart-define=API_BASE_URL=http://192.168.1.5:5000`.
- Checks: `flutter analyze` (must be 0 issues) and `flutter test`. Polish-pass tests: `test/mascot_test.dart` (idle schedule, poses, pause off-screen / reduced motion), `test/pressable_test.dart` (hover lift, press scale, builder, shared surfaces), `test/specs_section_test.dart` (icon map, key-spec picking, layouts at 320–460 px and text scale 2), `test/speech_voice_test.dart` (voice choice, speakable text, chunking), `test/theme_brightness_test.dart` (WCAG contrast, department tints).
