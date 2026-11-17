import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/paged_controller.dart';
import '../data/models/order.dart';
import '../data/orders_repository.dart';

/// Orders for one tab (active / delivered / cancelled), paginated.
final ordersProvider = AsyncNotifierProvider.autoDispose.family<OrdersController, PagedState<OrderSummary>, OrderFilter>(
  OrdersController.new,
);

class OrdersController extends PagedController<OrderSummary> {
  OrdersController(this.filter);

  final OrderFilter filter;

  @override
  Future<Paginated<OrderSummary>> fetch(int page) => ref.read(ordersRepositoryProvider).list(filter, page: page);

  @override
  Object idOf(OrderSummary item) => item.id;
}

/// One order. Reading it advances the demo status on the server, so
/// pull-to-refresh shows progress.
final orderDetailProvider = AsyncNotifierProvider.autoDispose.family<OrderDetailController, OrderDetail, int>(
  OrderDetailController.new,
);

class OrderDetailController extends AsyncNotifier<OrderDetail> {
  OrderDetailController(this.orderId);

  final int orderId;

  @override
  Future<OrderDetail> build() => ref.watch(ordersRepositoryProvider).detail(orderId);

  /// Throws [ApiException] (409 when it can no longer be cancelled).
  Future<void> cancel() async {
    final updated = await ref.read(ordersRepositoryProvider).cancel(orderId);
    if (!ref.mounted) return;
    state = AsyncData(updated);
    // the order moves from Active to Cancelled
    ref.invalidate(ordersProvider);
  }
}
