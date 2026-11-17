import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/app_spacing.dart';
import '../utils/extensions.dart';

/// Centers content and caps its width (default 1200) on large screens,
/// with the standard page gutter.
///
/// ```dart
/// body: ResponsiveCenter(child: ...)
/// body: ResponsiveCenter(maxWidth: Breakpoints.maxForm, child: LoginForm())
/// ```
class ResponsiveCenter extends StatelessWidget {
  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = Breakpoints.maxContent,
    this.padding,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;

  /// Defaults to horizontal page gutter; pass EdgeInsets.zero for none.
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding ?? EdgeInsets.symmetric(horizontal: context.pagePadding),
          child: child,
        ),
      ),
    );
  }
}

/// Sliver version for CustomScrollView pages: pads [sliver] so its content
/// is at most [maxWidth] wide and centered.
///
/// ```dart
/// CustomScrollView(slivers: [
///   SliverResponsiveCenter(sliver: SliverProductGrid(products: items)),
/// ])
/// ```
class SliverResponsiveCenter extends StatelessWidget {
  const SliverResponsiveCenter({
    super.key,
    required this.sliver,
    this.maxWidth = Breakpoints.maxContent,
    this.verticalPadding = EdgeInsets.zero,
    this.gutter = true,
  });

  final Widget sliver;
  final double maxWidth;
  final EdgeInsets verticalPadding;

  /// Include the standard horizontal page gutter.
  final bool gutter;

  /// Horizontal padding that centers [maxWidth] content in [available].
  static double sidePadding(BuildContext context, double available, {double maxWidth = Breakpoints.maxContent, bool gutter = true}) {
    final g = gutter ? context.pagePadding : 0.0;
    return math.max(g, (available - maxWidth) / 2 + g);
  }

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final side = sidePadding(context, constraints.crossAxisExtent, maxWidth: maxWidth, gutter: gutter);
        return SliverPadding(
          padding: EdgeInsets.fromLTRB(side, verticalPadding.top, side, verticalPadding.bottom),
          sliver: sliver,
        );
      },
    );
  }
}
