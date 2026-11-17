import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';

/// Smallest selection, as a fraction of the photo's width / height.
const double kMinCropFraction = 0.1;

/// Longest side of an exported crop. The vision model looks at a small
/// version anyway, and it keeps the upload far under the 5 MB limit.
const int kCropMaxSide = 1024;

/// A centred box covering 80 % of the photo: the item is usually in the middle.
const Rect kDefaultCrop = Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);

const Rect kWholeImage = Rect.fromLTRB(0, 0, 1, 1);

/// Decodes encoded image bytes (jpg / png / webp). The caller disposes the image.
Future<ui.Image> decodeImageBytes(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
  }
}

/// A 0..1 selection → whole pixels inside a [width] x [height] image.
Rect cropPixelRect(Rect normalized, int width, int height) {
  final l = (normalized.left.clamp(0.0, 1.0) * width).floorToDouble();
  final t = (normalized.top.clamp(0.0, 1.0) * height).floorToDouble();
  final r = (normalized.right.clamp(0.0, 1.0) * width).ceilToDouble().clamp(l + 1, width.toDouble());
  final b = (normalized.bottom.clamp(0.0, 1.0) * height).ceilToDouble().clamp(t + 1, height.toDouble());
  return Rect.fromLTRB(l, t, r, b);
}

/// Output size for a pixel crop: the same shape, longest side at most [maxSide].
Size cropOutputSize(Rect pixels, {int maxSide = kCropMaxSide}) {
  final w = pixels.width;
  final h = pixels.height;
  final longest = math.max(w, h);
  if (longest <= maxSide) return Size(w, h);
  final scale = maxSide / longest;
  return Size(math.max(1, (w * scale).roundToDouble()), math.max(1, (h * scale).roundToDouble()));
}

/// Whether a selection is (nearly) the whole photo, so no crop is needed.
bool isWholeImage(Rect normalized) =>
    normalized.left <= 0.02 && normalized.top <= 0.02 && normalized.right >= 0.98 && normalized.bottom >= 0.98;

/// Cuts the selected region out of [image] and encodes it as PNG bytes
/// (`null` if encoding fails). Uses only `dart:ui`, so it works on web too.
Future<Uint8List?> cropToPng(ui.Image image, Rect normalized, {int maxSide = kCropMaxSide}) async {
  final src = cropPixelRect(normalized, image.width, image.height);
  final out = cropOutputSize(src, maxSide: maxSide);
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
    image,
    src,
    Rect.fromLTWH(0, 0, out.width, out.height),
    Paint()..filterQuality = FilterQuality.medium,
  );
  final picture = recorder.endRecording();
  ui.Image? cropped;
  try {
    cropped = await picture.toImage(out.width.round(), out.height.round());
    final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    cropped?.dispose();
    picture.dispose();
  }
}

enum _Drag { none, move, create, topLeft, topRight, bottomLeft, bottomRight }

/// "Select the item": the photo with a draggable box. Drag inside to move it,
/// drag a corner to resize, or drag on the photo to draw a new box. The
/// parent owns [rect] (0..1 of the photo) and the decoded [image].
class ImageCropper extends StatefulWidget {
  const ImageCropper({super.key, required this.image, required this.rect, required this.onChanged, this.maxHeight = 420});

  final ui.Image image;
  final Rect rect;
  final ValueChanged<Rect> onChanged;
  final double maxHeight;

  @override
  State<ImageCropper> createState() => _ImageCropperState();
}


class _ImageCropperState extends State<ImageCropper> {
  static const _handleReach = 30.0;

  _Drag _mode = _Drag.none;
  int? _pointer;

  /// Where the finger went down (px) and the box at that moment: every drag
  /// is measured from these, so the box follows the finger exactly.
  Offset _downAt = Offset.zero;
  Rect _startRect = kDefaultCrop;

  Size _display(double maxWidth) {
    final ratio = widget.image.width / widget.image.height;
    final w = maxWidth;
    final h = w / ratio;
    return h <= widget.maxHeight ? Size(w, h) : Size(widget.maxHeight * ratio, widget.maxHeight);
  }

  Offset _norm(Offset local, Size size) =>
      Offset((local.dx / size.width).clamp(0.0, 1.0), (local.dy / size.height).clamp(0.0, 1.0));

  void _emit(Rect next) {
    if (next.width < kMinCropFraction || next.height < kMinCropFraction) return;
    widget.onChanged(next);
  }

  void _down(PointerDownEvent e, Size size) {
    if (_pointer != null) return; // one finger at a time
    _pointer = e.pointer;
    _downAt = e.localPosition;
    _startRect = widget.rect;
    final box = Rect.fromLTRB(
      _startRect.left * size.width,
      _startRect.top * size.height,
      _startRect.right * size.width,
      _startRect.bottom * size.height,
    );
    bool near(Offset corner) => (e.localPosition - corner).distance <= _handleReach;
    if (near(box.topLeft)) {
      _mode = _Drag.topLeft;
    } else if (near(box.topRight)) {
      _mode = _Drag.topRight;
    } else if (near(box.bottomLeft)) {
      _mode = _Drag.bottomLeft;
    } else if (near(box.bottomRight)) {
      _mode = _Drag.bottomRight;
    } else if (box.contains(e.localPosition)) {
      _mode = _Drag.move;
    } else {
      _mode = _Drag.create;
    }
  }

  void _move(PointerMoveEvent e, Size size) {
    if (e.pointer != _pointer) return;
    final r = _startRect;
    final p = _norm(e.localPosition, size);
    switch (_mode) {
      case _Drag.none:
        break;
      case _Drag.move:
        final d = e.localPosition - _downAt;
        final left = (r.left + d.dx / size.width).clamp(0.0, 1 - r.width);
        final top = (r.top + d.dy / size.height).clamp(0.0, 1 - r.height);
        widget.onChanged(Rect.fromLTWH(left, top, r.width, r.height));
      case _Drag.create:
        _emit(Rect.fromPoints(_norm(_downAt, size), p));
      case _Drag.topLeft:
        _emit(Rect.fromPoints(p, r.bottomRight));
      case _Drag.topRight:
        _emit(Rect.fromPoints(Offset(r.left, p.dy), Offset(p.dx, r.bottom)));
      case _Drag.bottomLeft:
        _emit(Rect.fromPoints(Offset(p.dx, r.top), Offset(r.right, p.dy)));
      case _Drag.bottomRight:
        _emit(Rect.fromPoints(r.topLeft, p));
    }
  }

  void _end(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _mode = _Drag.none;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, c) {
        final size = _display(c.maxWidth);
        return Center(
          child: Semantics(
            label:
                'Selection box over your photo. Drag it to move, or drag a corner to resize. '
                'Use the buttons below to search the whole photo.',
            child: ClipRRect(
              borderRadius: AppRadii.inputAll,
              child: SizedBox(
                width: size.width,
                height: size.height,
                // claims the gesture on touch-down so dragging the box never scrolls the page
                child: RawGestureDetector(
                  behavior: HitTestBehavior.opaque,
                  gestures: {
                    EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                      EagerGestureRecognizer.new,
                      (_) {},
                    ),
                  },
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (e) => _down(e, size),
                    onPointerMove: (e) => _move(e, size),
                    onPointerUp: _end,
                    onPointerCancel: _end,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: colors.surfaceVariant),
                        RawImage(image: widget.image, width: size.width, height: size.height, fit: BoxFit.fill),
                        CustomPaint(
                          painter: _CropPainter(
                            rect: widget.rect,
                            scrim: colors.onImageWell.withValues(alpha: 0.5),
                            edge: colors.primary,
                            handle: colors.surface,
                            grid: colors.surface.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter({required this.rect, required this.scrim, required this.edge, required this.handle, required this.grid});

  final Rect rect;
  final Color scrim;
  final Color edge;
  final Color handle;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Rect.fromLTRB(rect.left * size.width, rect.top * size.height, rect.right * size.width, rect.bottom * size.height);

    // dim everything outside the box
    final outside = Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRect(box));
    canvas.drawPath(outside, Paint()..color = scrim);

    // rule-of-thirds guides
    final guide = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 1; i <= 2; i++) {
      canvas.drawLine(Offset(box.left + box.width * i / 3, box.top), Offset(box.left + box.width * i / 3, box.bottom), guide);
      canvas.drawLine(Offset(box.left, box.top + box.height * i / 3), Offset(box.right, box.top + box.height * i / 3), guide);
    }

    canvas.drawRect(
      box,
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    for (final corner in [box.topLeft, box.topRight, box.bottomLeft, box.bottomRight]) {
      canvas.drawCircle(corner, 9, Paint()..color = handle);
      canvas.drawCircle(
        corner,
        9,
        Paint()
          ..color = edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.rect != rect || old.scrim != scrim || old.edge != edge || old.handle != handle || old.grid != grid;
}
