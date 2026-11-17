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

- `context.useBottomNav` (width < 700 & portrait) → bottom bar; otherwise NavigationRail, extended from 1100 px (`context.isDesktop`). `context.isWide` = ≥ 700.
- Wrap page content in `ResponsiveCenter` (max 1200) / `SliverResponsiveCenter` in slivers; forms use `maxWidth: Breakpoints.maxForm` (440).
- Must not overflow at 320 px wide or text scale 2.0 (app clamps at 2.0). Prefer `Wrap`, `Flexible`, `maxLines + ellipsis`. Grid tiles get their height from `ProductCard.compactHeight`, which scales with text size.

## Design tokens

- Colors: `context.colors` (`AppPalette`) — `background, surface, surfaceVariant, border, text, muted, primary, onPrimary, error, sale, success, warning, star, ai, aiSoft, shadow`. Never hard-code hex in features.
- AI accent (`AiGradient`, `colors.ai`) **only on AI surfaces**: assistant, AI badges, recommendations, smart search.
- Spacing `AppSpacing` 4/8/12/16/20/24/32/48 (`AppSpacing.md`, `AppSpacing.gapMd`); page gutter `context.pagePadding`.
- Radii `AppRadii`: 10 inputs/chips/buttons, 14 cards, 20 sheets, pill. Borders over shadows; soft shadow only on floating things.
- Type: Inter via `context.textTheme` — display/headline (tight tracking) → title → body → label. `bodySmall` is already muted.
- Motion `AppDurations` (150/250/400 ms), `AppCurves.standard`. Wrap durations with `context.motion(d)` so reduced-motion users get none. Page transitions are a subtle fade-through (theme-wide).
- Accessibility: tap targets ≥ 44 px, `tooltip`/semantic labels on icon buttons, `Semantics(header: true)` on titles, keyboard submit on the last field.

## Shared widget catalog (`core/widgets/widgets.dart`)

| Widget | Usage |
|---|---|
| `AppButton` | `AppButton(label: 'Pay', onPressed: f, loading: busy, expand: true, icon: Icons.lock)`; `.secondary`, `.ghost`, `.destructive`; `size: AppButtonSize.small/large` |
| `AppTextField` | `AppTextField(label: 'Email', controller: c, prefixIcon: Icons.mail_outline, validator: Validators.email, errorText: e?.fieldError('email'), onSubmitted: (_) => submit())`; `isPassword: true` adds a toggle |
| `FormErrorBanner` | `FormErrorBanner(message: error?.message)` — animated inline error |
| `AppNetworkImage` | `AppNetworkImage(url, width: 64, height: 64, fit: BoxFit.cover, borderRadius: AppRadii.inputAll)` — cached, shimmer, fallback icon, resolves relative URLs. Without `width` it decodes at the laid-out width (memory). `placeholder:` replaces the shimmer (e.g. the thumbnail while a big image loads) |
| `ProductCard` | `ProductCard(product: p)` (grid tile) / `variant: ProductCardVariant.wide` (list row); heart, discount badge, AI match badge, opens product page. Remembers the product in `ProductPreviewCache` on tap (instant detail page). `hero: true` flies the image into the detail gallery — only where a product appears once per screen |
| `ProductGrid` / `SliverProductGrid` | `ProductGrid(products: items)`, `.loading()`, `loadingMore: true`; 2/3/4/5 columns by width; tiles use `hero: true` |
| `ProductRail` | `ProductRail(products: items)` horizontal row, `.loading()` |
| `PriceText` | `PriceText(price, compareAt: was, size: PriceSize.large, showDiscount: true)` — tabular figures |
| `RatingStars` | `RatingStars(4.6, count: 128)` compact · `RatingStars.full(4.6)` five stars |
| `SectionHeader` | `SectionHeader(title: 'Trending', subtitle: '…', leading: AiSparkleIcon(), onSeeAll: f)` |
| `EmptyState` | `EmptyState(icon: Icons.favorite_border, title: 'Nothing saved', message: '…', actionLabel: 'Browse', onAction: f)` |
| `ErrorState` | `ErrorState(error: e, onRetry: f)` — offline errors get a server-address hint |
| `LoadingView` | centered spinner when no skeleton fits |
| `Skeleton*` | `Skeleton(width:, height:)`, `Skeleton.circle(size:)`, `SkeletonText(lines: 3)`, `SkeletonProductCard()`, `SkeletonListTile()`, `SkeletonList(count: 6)` |
| `QuantityStepper` | `QuantityStepper(value: q, onChanged: f, max: 10, loading: busy)`; `min: 0` turns − into delete at 1 |
| `AppBadge` | `AppBadge(count: n, child: Icon(...))`, `AppBadge.dot(show: unread, child: ...)` |
| `ResponsiveCenter` / `SliverResponsiveCenter` | cap content width + gutters |
| `AppSnack` | `AppSnack.success(context, 'Added to cart')`, `.error(context, e)`, `.info(context, 'Removed', actionLabel: 'Undo', onAction: f)` |
| `AiSparkleIcon` / `AiGradientText` / `AiBadge` / `AiGradientBorder` / `AiGradient.mask` | AI accents: `AiBadge(label: '92% match')`, `AiGradientBorder(child: ...)` for AI cards |
| `BottomSheetScaffold` + `showAppBottomSheet` | `showAppBottomSheet(context, builder: (_) => BottomSheetScaffold(title: 'Sort by', footer: AppButton(...), child: ...))` |
| `AppLogo` | brand mark (+ wordmark) |

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
