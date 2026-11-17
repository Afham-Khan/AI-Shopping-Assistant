import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// Items loaded so far from a paginated endpoint, plus load-more status.
@immutable
class PagedState<T> {
  const PagedState({
    required this.items,
    required this.page,
    required this.totalPages,
    this.total = 0,
    this.meta = const {},
    this.loadingMore = false,
    this.loadMoreError,
  });

  factory PagedState.fromPage(Paginated<T> p) =>
      PagedState(items: p.items, page: p.page, totalPages: p.totalPages, total: p.total, meta: p.meta);

  final List<T> items;
  final int page;
  final int totalPages;
  final int total;

  /// `meta` of the latest page (endpoint extras like `unreadCount`).
  final Map<String, dynamic> meta;
  final bool loadingMore;
  final ApiException? loadMoreError;

  bool get hasMore => page < totalPages;
  bool get isEmpty => items.isEmpty;

  PagedState<T> copyWith({List<T>? items, bool? loadingMore, ApiException? Function()? loadMoreError}) => PagedState(
    items: items ?? this.items,
    page: page,
    totalPages: totalPages,
    total: total,
    meta: meta,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreError: loadMoreError == null ? this.loadMoreError : loadMoreError(),
  );
}

/// Base for infinite-scroll lists: implement [fetch]; call [loadMore] near the end.
///
/// ```dart
/// class OrdersController extends PagedController<OrderSummary> {
///   @override
///   Future<Paginated<OrderSummary>> fetch(int page) => repo.list(filter, page: page);
/// }
/// ```
abstract class PagedController<T> extends AsyncNotifier<PagedState<T>> {
  Future<Paginated<T>> fetch(int page);

  /// Identity used to drop duplicates when pages shift between requests.
  Object idOf(T item);

  @override
  Future<PagedState<T>> build() async => PagedState.fromPage(await fetch(1));

  Future<void> loadMore() async {
    final s = state.value;
    if (s == null || !s.hasMore || s.loadingMore || state.isLoading) return;
    state = AsyncData(s.copyWith(loadingMore: true, loadMoreError: () => null));
    try {
      final next = await fetch(s.page + 1);
      if (!ref.mounted) return;
      final seen = {for (final i in s.items) idOf(i)};
      state = AsyncData(
        PagedState(
          items: [...s.items, ...next.items.where((i) => seen.add(idOf(i)))],
          page: next.page,
          totalPages: next.totalPages,
          total: next.total,
          meta: next.meta,
        ),
      );
    } on ApiException catch (e) {
      if (!ref.mounted) return;
      state = AsyncData(s.copyWith(loadingMore: false, loadMoreError: () => e));
    }
  }

  /// Replaces items locally (e.g. mark as read) without refetching.
  void updateItems(List<T> Function(List<T> items) update) {
    final s = state.value;
    if (s == null) return;
    state = AsyncData(s.copyWith(items: update(s.items)));
  }
}
