import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/widgets/app_snack.dart';
import 'auth_controller.dart';

/// Gate for actions that need an account (wishlist, add to cart, chat…).
///
/// Returns true when signed in. Otherwise shows a snackbar with a
/// "Sign in" action that opens login and returns here afterwards.
///
/// ```dart
/// onPressed: () {
///   if (!requireAuth(context, ref, message: 'Sign in to add items to your cart')) return;
///   ref.read(cartProvider.notifier).add(product.id);
/// }
/// ```
bool requireAuth(BuildContext context, WidgetRef ref, {String message = 'Sign in to continue'}) {
  if (ref.read(authControllerProvider).isAuthenticated) return true;
  final from = GoRouterState.of(context).uri.toString();
  AppSnack.info(
    context,
    message,
    actionLabel: 'Sign in',
    onAction: () => GoRouter.of(context).push(Routes.loginFrom(from)),
  );
  return false;
}
