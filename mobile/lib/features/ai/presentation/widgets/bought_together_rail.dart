import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../providers/ai_providers.dart';
import 'ai_rail_section.dart';

/// "Frequently bought together" rail (GET /ai/bought-together/:productId).
/// Hidden when there are no co-purchases.
class BoughtTogetherRail extends ConsumerWidget {
  const BoughtTogetherRail({super.key, required this.productId, this.padding});

  final int productId;
  final double? padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AiRailSection(
      value: ref.watch(boughtTogetherProvider(productId)),
      title: 'Frequently bought together',
      subtitle: 'Shoppers who bought this also picked',
      source: 'bought_together',
      padding: padding,
      onRetry: () => ref.invalidate(boughtTogetherProvider(productId)),
    );
  }
}
