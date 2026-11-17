import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../config/app_config.dart';
import '../utils/extensions.dart';

/// Cached network image with a shimmer placeholder and a quiet fallback icon.
/// Relative URLs (`/uploads/...`) are resolved against the server origin.
///
/// ```dart
/// AppNetworkImage(product.thumbnail, width: 64, height: 64, borderRadius: AppRadii.inputAll)
/// ```
class AppNetworkImage extends ConsumerWidget {
  const AppNetworkImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.backgroundColor,
    this.semanticLabel,
    this.fallbackIcon = Icons.image_outlined,
    this.placeholder,
  });

  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  /// Tile color behind transparent images; defaults to the light "studio"
  /// `imageWell` (the catalog's cut-out photos include dark products, so the
  /// well stays light in both themes).
  final Color? backgroundColor;
  final String? semanticLabel;
  final IconData fallbackIcon;

  /// Shown while loading instead of the shimmer (e.g. a cached low-res thumbnail).
  final Widget? placeholder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final resolved = ref.watch(appConfigProvider).resolveImage(url);
    final background = backgroundColor ?? colors.imageWell;

    Widget fallback() => ColoredBox(
      color: background,
      child: Center(
        child: Icon(fallbackIcon, color: colors.onImageWell.withValues(alpha: 0.28), size: 26),
      ),
    );

    // decode at display size to save memory on long grids
    final dpr = MediaQuery.devicePixelRatioOf(context);
    int? cacheSize(double? logical) =>
        (logical == null || !logical.isFinite) ? null : (logical * dpr).round();

    Widget network(double? decodeWidth) => CachedNetworkImage(
      imageUrl: resolved!,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: cacheSize(decodeWidth),
      fadeInDuration: context.motion(const Duration(milliseconds: 200)),
      fadeOutDuration: Duration.zero,
      // the well itself is the placeholder: calm, no flashing tiles in long grids
      placeholder: (_, _) => placeholder ?? const SizedBox.expand(),
      errorWidget: (_, _, _) => fallback(),
    );

    Widget image;
    if (resolved == null) {
      image = fallback();
    } else if (width != null) {
      image = network(width);
    } else {
      // no explicit width (fills a tile): decode at the laid-out width
      image = LayoutBuilder(builder: (context, c) => network(c.hasBoundedWidth ? c.maxWidth : null));
    }

    image = ColoredBox(
      color: background,
      child: SizedBox(width: width, height: height, child: image),
    );

    if (borderRadius != null) image = ClipRRect(borderRadius: borderRadius!, child: image);

    return Semantics(
      image: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: image,
    );
  }
}
