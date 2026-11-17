import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/models/product_preview_cache.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/widgets.dart';

/// Swipeable product images with dots (phones) or a thumbnail strip (wide),
/// tap to open a full-screen pinch-zoom viewer. The first image carries the
/// product hero tag so it flies in from grids.
class ProductGallery extends StatefulWidget {
  const ProductGallery({
    super.key,
    required this.productId,
    required this.images,
    this.thumbnail,
    this.title = '',
    this.dimmed = false,
  });

  final int productId;
  final List<String> images;

  /// Low-res image shown while the first full image loads (and during the hero flight).
  final String? thumbnail;
  final String title;

  /// Out of stock: show images faded.
  final bool dimmed;

  @override
  State<ProductGallery> createState() => _ProductGalleryState();
}

class _ProductGalleryState extends State<ProductGallery> {
  final _controller = PageController();
  int _index = 0;

  List<String?> get _images => widget.images.isEmpty ? [widget.thumbnail] : widget.images;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int i) {
    setState(() => _index = i);
    _controller.animateToPage(i, duration: context.motion(AppDurations.normal), curve: AppCurves.standard);
  }

  void _openViewer() {
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: context.motion(AppDurations.normal),
        pageBuilder: (_, _, _) => _ImageViewer(images: _images, initial: _index, title: widget.title),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  Widget _image(int i) {
    final url = _images[i];
    final thumb = widget.thumbnail;
    Widget img = AppNetworkImage(
      url,
      fit: BoxFit.contain,
      backgroundColor: Colors.transparent,
      semanticLabel: '${widget.title}, image ${i + 1} of ${_images.length}',
      placeholder: i == 0 && thumb != null && thumb != url
          ? AppNetworkImage(thumb, fit: BoxFit.contain, backgroundColor: Colors.transparent)
          : null,
    );
    if (i == 0) img = Hero(tag: ProductPreviewCache.heroTag(widget.productId), child: img);
    return img;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final images = _images;
    final wide = context.isWide;

    final main = AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: AppRadii.sheetAll,
        child: ColoredBox(
          color: colors.surfaceVariant,
          child: Stack(
            children: [
              Positioned.fill(
                child: Focus(
                  onKeyEvent: (_, e) {
                    if (e is! KeyDownEvent) return KeyEventResult.ignored;
                    if (e.logicalKey == LogicalKeyboardKey.arrowRight && _index < images.length - 1) {
                      _go(_index + 1);
                      return KeyEventResult.handled;
                    }
                    if (e.logicalKey == LogicalKeyboardKey.arrowLeft && _index > 0) {
                      _go(_index - 1);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: GestureDetector(
                    onTap: _openViewer,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.zoomIn,
                      child: PageView.builder(
                        controller: _controller,
                        itemCount: images.length,
                        onPageChanged: (i) => setState(() => _index = i),
                        itemBuilder: (_, i) => Opacity(
                          opacity: widget.dimmed ? 0.5 : 1,
                          child: Padding(padding: const EdgeInsets.all(AppSpacing.xl), child: _image(i)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: AppSpacing.sm,
                bottom: AppSpacing.sm,
                child: IconButton.filledTonal(
                  tooltip: 'View full screen',
                  onPressed: _openViewer,
                  style: IconButton.styleFrom(backgroundColor: colors.surface, foregroundColor: colors.text),
                  icon: const Icon(Icons.zoom_out_map_rounded, size: 20),
                ),
              ),
              if (!wide && images.length > 1)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: AppSpacing.md,
                  child: _Dots(count: images.length, index: _index),
                ),
            ],
          ),
        ),
      ),
    );

    if (!wide || images.length < 2) return main;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        main,
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: images.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
            itemBuilder: (_, i) {
              final selected = i == _index;
              return Semantics(
                button: true,
                selected: selected,
                label: 'Image ${i + 1}',
                child: InkWell(
                  onTap: () => _go(i),
                  borderRadius: AppRadii.inputAll,
                  child: AnimatedContainer(
                    duration: context.motion(AppDurations.fast),
                    width: 72,
                    padding: const EdgeInsets.all(AppSpacing.xxs),
                    decoration: BoxDecoration(
                      color: colors.surfaceVariant,
                      borderRadius: AppRadii.inputAll,
                      border: Border.all(color: selected ? colors.text : colors.border, width: selected ? 1.5 : 1),
                    ),
                    child: AppNetworkImage(images[i], fit: BoxFit.contain, backgroundColor: Colors.transparent),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: context.motion(AppDurations.normal),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == index ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == index ? colors.text : colors.text.withValues(alpha: 0.25),
                borderRadius: AppRadii.pillAll,
              ),
            ),
        ],
      ),
    );
  }
}

/// Full-screen black viewer: swipe between images, pinch / double-tap to zoom.
class _ImageViewer extends StatefulWidget {
  const _ImageViewer({required this.images, required this.initial, required this.title});

  final List<String?> images;
  final int initial;
  final String title;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late final _controller = PageController(initialPage: widget.initial);
  late int _index = widget.initial;
  final _zoom = TransformationController();
  bool _zoomed = false;

  @override
  void dispose() {
    _controller.dispose();
    _zoom.dispose();
    super.dispose();
  }

  void _toggleZoom(TapDownDetails d) {
    if (_zoomed) {
      _zoom.value = Matrix4.identity();
    } else {
      final p = d.localPosition;
      _zoom.value = Matrix4.identity()
        ..translateByDouble(-p.dx, -p.dy, 0, 1)
        ..scaleByDouble(2.5, 2.5, 1, 1);
    }
    setState(() => _zoomed = !_zoomed);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    return Scaffold(
      backgroundColor: Colors.black,
      body: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop()},
        child: Focus(
          autofocus: true,
          child: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
                itemCount: widget.images.length,
                onPageChanged: (i) => setState(() {
                  _index = i;
                  _zoom.value = Matrix4.identity();
                  _zoomed = false;
                }),
                itemBuilder: (_, i) => GestureDetector(
                  onDoubleTapDown: _toggleZoom,
                  onDoubleTap: () {},
                  child: InteractiveViewer(
                    transformationController: i == _index ? _zoom : null,
                    minScale: 1,
                    maxScale: 5,
                    onInteractionEnd: (_) =>
                        setState(() => _zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: AppNetworkImage(
                          widget.images[i],
                          fit: BoxFit.contain,
                          backgroundColor: Colors.transparent,
                          semanticLabel: widget.title,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                      ),
                      const Spacer(),
                      if (widget.images.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.md),
                          child: Text(
                            '${_index + 1} / ${widget.images.length}',
                            style: t.labelLarge!.copyWith(color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
