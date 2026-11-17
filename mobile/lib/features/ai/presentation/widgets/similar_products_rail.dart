import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../providers/ai_providers.dart';
import 'ai_rail_section.dart';

/// "Similar products" rail (GET /ai/similar/:productId) — semantic similarity.
/// Hidden when there is nothing similar.
class SimilarProductsRail extends ConsumerWidget {
  const SimilarProductsRail({super.key, required this.productId, this.padding});

  final int productId;
  final double? padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AiRailSection(
      value: ref.watch(similarProductsProvider(productId)),
      title: 'Similar products',
      subtitle: 'Found by AI from specs, style and price',
      source: 'similar',
      padding: padding,
      onRetry: () => ref.invalidate(similarProductsProvider(productId)),
    );
  }
}
