import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/json_utils.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/paged_controller.dart';
import '../../auth/providers/auth_controller.dart';

/// `{ id, type, title, body, data, readAt, createdAt }`.
@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.data = const {},
    this.readAt,
    this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
    id: JsonX.asInt(json['id']),
    type: JsonX.asString(json['type'], 'system'),
    title: JsonX.asString(json['title']),
    body: JsonX.asString(json['body']),
    data: JsonX.asMap(json['data']),
    readAt: JsonX.asDate(json['readAt']),
    createdAt: JsonX.asDate(json['createdAt']),
  );

  final int id;

  /// `order` | `price_drop` | `restock` | `promo` | `ai` | `system`.
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final DateTime? readAt;
  final DateTime? createdAt;

  bool get isUnread => readAt == null;
  int? get orderId => JsonX.asIntOrNull(data['orderId']);
  int? get productId => JsonX.asIntOrNull(data['productId']);
  Map<String, dynamic>? get target => JsonX.asMapOrNull(data['target']);

  /// Price-watch alerts (`price_drop`, `restock`) carry the before/after prices.
  bool get isPriceAlert => type == 'price_drop' || type == 'restock';
  double? get oldPrice => JsonX.asDoubleOrNull(data['oldPrice']);
  double? get newPrice => JsonX.asDoubleOrNull(data['newPrice']);
  double? get dropPercent => JsonX.asDoubleOrNull(data['dropPercent']);
  String? get thumbnail => JsonX.asStringOrNull(data['thumbnail']);

  /// Both prices known and the price really went down.
  bool get hasPriceChange => oldPrice != null && newPrice != null && newPrice! < oldPrice!;

  AppNotification markRead() => AppNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    data: data,
    readAt: readAt ?? DateTime.now(),
    createdAt: createdAt,
  );
}

class NotificationsRepository {
  NotificationsRepository(this._api);

  final ApiClient _api;

  Future<Paginated<AppNotification>> list({int page = 1}) =>
      _api.getPage('/notifications', query: {'page': page, 'limit': 20}, item: AppNotification.fromJson);

  Future<int> unreadCount() =>
      _api.get('/notifications/unread-count', decode: (d) => JsonX.asInt(JsonX.asMap(d)['count']));

  Future<void> markRead(int id) => _api.post<void>('/notifications/$id/read');

  Future<void> markAllRead() => _api.post<void>('/notifications/read-all');
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(apiClientProvider)),
);

/// Unread badge (home app bar). 0 for guests; refetches on login/logout.
/// The notifications screen keeps it in sync via `.set()` / `.refresh()`.
final unreadNotificationsProvider = NotifierProvider<UnreadNotificationsController, int>(
  UnreadNotificationsController.new,
);

class UnreadNotificationsController extends Notifier<int> {
  @override
  int build() {
    if (ref.watch(isAuthenticatedProvider)) Future.microtask(refresh);
    return 0;
  }

  Future<void> refresh() async {
    if (!ref.read(isAuthenticatedProvider)) return;
    try {
      final count = await ref.read(notificationsRepositoryProvider).unreadCount();
      if (ref.mounted) state = count;
    } on ApiException {
      // badge is non-critical
    }
  }

  void set(int count) => state = count < 0 ? 0 : count;
}

/// The notifications list (paginated).
final notificationsProvider = AsyncNotifierProvider.autoDispose<NotificationsController, PagedState<AppNotification>>(
  NotificationsController.new,
);

class NotificationsController extends PagedController<AppNotification> {
  NotificationsRepository get _repo => ref.read(notificationsRepositoryProvider);

  @override
  Future<Paginated<AppNotification>> fetch(int page) async {
    final result = await _repo.list(page: page);
    final unread = result.meta['unreadCount'];
    if (unread != null && ref.mounted) ref.read(unreadNotificationsProvider.notifier).set(JsonX.asInt(unread));
    return result;
  }

  @override
  Object idOf(AppNotification item) => item.id;

  /// Optimistically marks one as read.
  Future<void> markRead(AppNotification n) async {
    if (!n.isUnread) return;
    updateItems((items) => [for (final i in items) i.id == n.id ? i.markRead() : i]);
    final badge = ref.read(unreadNotificationsProvider.notifier);
    badge.set(ref.read(unreadNotificationsProvider) - 1);
    try {
      await _repo.markRead(n.id);
    } on ApiException {
      await badge.refresh();
    }
  }

  Future<void> markAllRead() async {
    final before = state.value?.items;
    updateItems((items) => [for (final i in items) i.markRead()]);
    ref.read(unreadNotificationsProvider.notifier).set(0);
    try {
      await _repo.markAllRead();
    } on ApiException {
      if (before != null) updateItems((_) => before);
      await ref.read(unreadNotificationsProvider.notifier).refresh();
      rethrow;
    }
  }
}
