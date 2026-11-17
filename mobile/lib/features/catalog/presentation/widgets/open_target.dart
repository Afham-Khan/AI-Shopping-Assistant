import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/utils/extensions.dart';

/// Opens a banner / promo-notification target
/// (`{ type: category|department|search|assistant|product, value }`).
/// Unknown types fall back to Explore.
void openTarget(BuildContext context, {required String type, String? value, String? title}) {
  final v = value?.trim();
  switch (type) {
    case 'category' when v != null && v.isNotEmpty:
      context.push(Routes.productList(category: v, title: title ?? v.titleCase));
    case 'department' when v != null && v.isNotEmpty:
      context.push(Routes.productList(department: v, title: title ?? v.titleCase));
    case 'search' when v != null && v.isNotEmpty:
      context.push(Routes.productList(q: v, title: title ?? '"$v"'));
    case 'product' when v != null && v.isNotEmpty:
      context.push(Routes.product(v));
    case 'assistant':
      context.go(Routes.assistantWith(prompt: v));
    default:
      context.go(Routes.explore);
  }
}
