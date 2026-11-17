import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/config/app_config.dart';
import '../../providers/ai_providers.dart';
import 'ai_rail_section.dart';

/// Personal recommendations rail (GET /ai/recommendations). Title and subtitle
/// come from the API; guests get popular picks. Hidden when empty.
class ForYouRail extends ConsumerWidget {
  const ForYouRail({super.key, this.padding});

  /// Horizontal gutter (defaults to the page gutter).
  final double? padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recommendationsProvider);
    final data = async.value;
    return AiRailSection(
      value: async.whenData((r) => r.products),
      title: data?.title ?? 'Picked for you',
      subtitle: data?.subtitle ?? 'Curated by ${AppConfig.assistantName}',
      source: 'for_you',
      padding: padding,
      onRetry: () => ref.invalidate(recommendationsProvider),
    );
  }
}
