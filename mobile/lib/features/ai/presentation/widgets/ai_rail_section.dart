import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/models/product.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/widgets.dart';
import 'ai_product_widgets.dart';
import 'ai_ui.dart';

/// Titled AI rail with loading / error / empty handling. Empty → hidden.
class AiRailSection extends StatelessWidget {
  const AiRailSection({
    super.key,
    required this.value,
    required this.title,
    this.subtitle,
    this.onRetry,
    this.source = 'ai',
    this.showWhy = true,
    this.padding,
  });

  final AsyncValue<List<ProductSummary>> value;
  final String title;
  final String? subtitle;
  final VoidCallback? onRetry;
  final String source;
  final bool showWhy;

  /// Horizontal gutter for the header and the rail (defaults to the page gutter).
  final double? padding;

  @override
  Widget build(BuildContext context) {
    final gutter = padding ?? context.pagePadding;
    final header = SectionHeader(
      title: title,
      subtitle: subtitle,
      leading: const AiMark(size: 20),
      padding: EdgeInsets.symmetric(horizontal: gutter),
    );
    Widget section(Widget body) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [header, AppSpacing.gapSm, body],
      ),
    );

    // keep showing previous data while refreshing
    final products = value.value;
    if (products != null) {
      if (products.isEmpty) return const SizedBox.shrink();
      return Semantics(
        container: true,
        label: '$title, AI recommendations',
        child: section(
          AiProductRail(
            products: products,
            source: source,
            showWhy: showWhy,
            padding: EdgeInsets.symmetric(horizontal: gutter),
          ),
        ),
      );
    }
    if (value.hasError) {
      return section(
        Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: AiInlineError(error: value.error!, onRetry: onRetry),
        ),
      );
    }
    return section(ProductRail.loading(padding: EdgeInsets.symmetric(horizontal: gutter)));
  }
}
