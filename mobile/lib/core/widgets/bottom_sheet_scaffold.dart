import 'package:material_ui/material_ui.dart';

import '../theme/app_spacing.dart';
import '../utils/extensions.dart';

/// Opens a modal sheet with the app's defaults (scroll-controlled, safe
/// area, max width on tablets/desktop). Pair with [BottomSheetScaffold].
///
/// ```dart
/// final sort = await showAppBottomSheet<String>(
///   context,
///   builder: (_) => BottomSheetScaffold(title: 'Sort by', child: SortOptions()),
/// );
/// ```
Future<T?> showAppBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool useRootNavigator = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    useRootNavigator: useRootNavigator,
    showDragHandle: false,
    sheetAnimationStyle: context.reduceMotion ? AnimationStyle.noAnimation : null,
  );
}

/// Standard sheet layout: drag handle, title row with close button,
/// scrollable body and an optional sticky footer (e.g. "Apply" button).
class BottomSheetScaffold extends StatelessWidget {
  const BottomSheetScaffold({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.footer,
    this.padding = const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
    this.maxHeightFactor = 0.9,
    this.showClose = true,
  });

  final Widget child;
  final String? title;

  /// Extra action in the header (e.g. a "Reset" text button).
  final Widget? trailing;

  /// Pinned below the scrollable body.
  final Widget? footer;
  final EdgeInsetsGeometry padding;

  /// Max sheet height as a fraction of the screen.
  final double maxHeightFactor;
  final bool showClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final media = MediaQuery.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * maxHeightFactor),
      child: Padding(
        // lift the sheet above the keyboard
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.xs),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: colors.borderStrong, borderRadius: AppRadii.pillAll),
              ),
            ),
            if (title != null || showClose)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: title == null
                          ? const SizedBox.shrink()
                          : Semantics(header: true, child: Text(title!, style: context.textTheme.headlineSmall)),
                    ),
                    ?trailing,
                    if (showClose)
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Close',
                      ),
                  ],
                ),
              )
            else
              const SizedBox(height: AppSpacing.md),
            Flexible(
              child: SingleChildScrollView(padding: padding, child: child),
            ),
            if (footer != null)
              DecoratedBox(
                decoration: BoxDecoration(border: Border(top: BorderSide(color: colors.border))),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
                    child: footer,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
