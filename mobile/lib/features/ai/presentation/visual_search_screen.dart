import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../data/ai_repository.dart';
import '../data/models/ai_models.dart';
import 'widgets/ai_product_widgets.dart';
import 'widgets/ai_ui.dart';
import 'widgets/image_cropper.dart';

/// Snap & Find (POST /ai/visual-search): pick or take a photo, drag a box
/// around the item you mean ("select the item"), watch it get analyzed and
/// see the detected category and visually similar products. Also accepts a
/// text description. A 503 (vision model offline) is handled. When the photo
/// isn't something the store sells (`recognized: false`, e.g. class notes) a
/// friendly [VisualNoMatch] state replaces the results: no products are shown.
class VisualSearchScreen extends ConsumerStatefulWidget {
  const VisualSearchScreen({super.key});

  static const maxBytes = 5 * 1024 * 1024;

  @override
  ConsumerState<VisualSearchScreen> createState() => _VisualSearchScreenState();
}

class _VisualSearchScreenState extends ConsumerState<VisualSearchScreen> {
  final _picker = ImagePicker();
  final _describe = TextEditingController();

  /// What is sent to the search (the crop, or the whole photo).
  Uint8List? _bytes;
  String _filename = 'photo.jpg';
  String? _mime;
  String? _describedAs;

  // the photo as picked, kept so the selection can be adjusted
  Uint8List? _original;
  String _originalName = 'photo.jpg';
  String? _originalMime;
  ui.Image? _decoded;
  Rect _crop = kDefaultCrop;
  bool _cropping = false;

  bool _busy = false;
  ImageSource _lastSource = ImageSource.gallery;
  VisualSearchResult? _result;
  ApiException? _error;

  bool get _cameraSupported {
    try {
      return _picker.supportsImageSource(ImageSource.camera);
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _describe.dispose();
    _decoded?.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    XFile? file;
    try {
      file = await _picker.pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
    } catch (e) {
      if (mounted) {
        AppSnack.error(
          context,
          source == ImageSource.camera
              ? "Couldn't open the camera. Check the permission, or pick a photo instead."
              : "Couldn't open your photos. Check the permission and try again.",
        );
      }
      return;
    }
    if (file == null || !mounted) return;
    _lastSource = source;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (bytes.length > VisualSearchScreen.maxBytes) {
      AppSnack.error(context, 'That image is over 5 MB. Please choose a smaller one.');
      return;
    }
    final mime = file.mimeType ?? _mimeFromName(file.name);
    var name = file.name.isEmpty ? 'photo' : file.name;
    if (!name.contains('.')) name = '$name.${(mime ?? 'image/jpeg').split('/').last}';

    // decode for the "select the item" step; if that fails, search the whole photo
    ui.Image? decoded;
    try {
      decoded = await decodeImageBytes(bytes);
    } catch (_) {
      decoded = null;
    }
    if (!mounted) {
      decoded?.dispose();
      return;
    }
    _decoded?.dispose();
    setState(() {
      _original = bytes;
      _originalName = name;
      _originalMime = mime;
      _decoded = decoded;
      _crop = kDefaultCrop;
      _describedAs = null;
      _result = null;
      _error = null;
      _bytes = bytes;
      _filename = name;
      _mime = mime;
      _cropping = decoded != null;
    });
    if (decoded == null) await _searchImage();
  }

  /// Sends the selected area (or the whole photo) to the search.
  Future<void> _searchSelection({bool whole = false}) async {
    final original = _original;
    final decoded = _decoded;
    if (original == null) return;
    var bytes = original;
    var name = _originalName;
    var mime = _originalMime;
    var note = false;
    if (!whole && decoded != null && !isWholeImage(_crop)) {
      try {
        final cut = await cropToPng(decoded, _crop);
        if (cut != null && cut.isNotEmpty) {
          bytes = cut;
          name = 'selection.png';
          mime = 'image/png';
        } else {
          note = true;
        }
      } catch (_) {
        note = true;
      }
    }
    if (!mounted) return;
    if (bytes.length > VisualSearchScreen.maxBytes) {
      AppSnack.error(context, 'That image is over 5 MB. Please choose a smaller one.');
      return;
    }
    if (note) AppSnack.info(context, "Couldn't cut out that area, so Zel is searching the whole photo.");
    setState(() {
      _bytes = bytes;
      _filename = name;
      _mime = mime;
      _cropping = false;
    });
    await _searchImage();
  }

  void _adjustSelection() => setState(() {
    _cropping = true;
    _result = null;
    _error = null;
  });

  static String? _mimeFromName(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    return null;
  }

  Future<void> _searchImage() async {
    final bytes = _bytes;
    if (bytes == null) return;
    await _run(() => ref.read(aiRepositoryProvider).visualSearch(bytes, filename: _filename, mimeType: _mime));
  }

  Future<void> _searchText() async {
    final text = _describe.text.trim();
    if (text.isEmpty) return;
    context.unfocus();
    setState(() {
      _bytes = null;
      _original = null;
      _cropping = false;
      _describedAs = text;
    });
    await _run(() => ref.read(aiRepositoryProvider).describeSearch(text));
  }

  Future<void> _run(Future<VisualSearchResult> Function() call) async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final r = await call();
      if (mounted) setState(() => _result = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "Try another photo" from the no-match state: reopen the source used last.
  void _tryAnotherPhoto() =>
      _pick(_lastSource == ImageSource.camera && _cameraSupported ? ImageSource.camera : ImageSource.gallery);

  /// Popular-category chip: search it by description.
  void _searchSuggestion(String name) {
    _describe.text = name;
    _searchText();
  }

  void _reset() {
    _decoded?.dispose();
    setState(() {
      _bytes = null;
      _original = null;
      _decoded = null;
      _cropping = false;
      _crop = kDefaultCrop;
      _result = null;
      _error = null;
      _describedAs = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cropping = _cropping && _decoded != null;
    final hasQuery = _bytes != null || _describedAs != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Snap & Find'),
        actions: [
          if (hasQuery || cropping) TextButton(onPressed: _busy ? null : _reset, child: const Text('New search')),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverResponsiveCenter(
            maxWidth: 900,
            verticalPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            sliver: SliverToBoxAdapter(
              child: cropping ? _cropStage(context) : (hasQuery ? _queryHeader(context) : _start(context)),
            ),
          ),
          if (!cropping) ..._resultSlivers(context),
        ],
      ),
    );
  }

  /// "Select the item": drag the box over what to look for.
  Widget _cropStage(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AiHeader(title: 'Select the item', caption: 'Drag the box over the item you want to find.'),
        AppSpacing.gapMd,
        ImageCropper(image: _decoded!, rect: _crop, onChanged: (r) => setState(() => _crop = r)),
        AppSpacing.gapXs,
        Center(
          child: Text(
            'Move the box, or drag a corner to resize it.',
            style: t.bodySmall!.copyWith(color: colors.muted),
          ),
        ),
        AppSpacing.gapMd,
        AppButton(
          label: 'Search this area',
          icon: Icons.image_search_rounded,
          expand: true,
          onPressed: _searchSelection,
        ),
        AppSpacing.gapXs,
        Row(
          children: [
            Expanded(
              child: AppButton.secondary(
                label: 'Whole photo',
                onPressed: () => _searchSelection(whole: true),
              ),
            ),
            AppSpacing.gapXs,
            Expanded(
              child: AppButton.ghost(
                label: 'Reset box',
                onPressed: () => setState(() => _crop = kDefaultCrop),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _start(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AiHeader(title: 'Search with a photo', caption: 'Snap a product or pick a picture. The AI finds similar items in the catalog.'),
        AppSpacing.gapLg,
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: AppRadii.cardAll,
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              Icon(Icons.image_search_rounded, size: 40, color: colors.ai),
              AppSpacing.gapSm,
              Text('JPG, PNG or WebP up to 5 MB', style: t.bodySmall),
              AppSpacing.gapMd,
              Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (_cameraSupported)
                    AppButton(label: 'Take photo', icon: Icons.photo_camera_outlined, onPressed: () => _pick(ImageSource.camera)),
                  AppButton.secondary(label: 'Choose photo', icon: Icons.photo_library_outlined, onPressed: () => _pick(ImageSource.gallery)),
                ],
              ),
            ],
          ),
        ),
        AppSpacing.gapLg,
        _DescribeBox(controller: _describe, onSubmit: _searchText, busy: _busy),
      ],
    );
  }

  Widget _queryHeader(BuildContext context) {
    final bytes = _bytes;
    final preview = bytes == null
        ? AiCard(
            child: Row(
              children: [
                const AiMark(size: 18),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: Text('"$_describedAs"', style: context.textTheme.titleSmall)),
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ScanPreview(bytes: bytes, scanning: _busy),
              if (_decoded != null) ...[
                AppSpacing.gapXs,
                AppButton.secondary(
                  label: 'Adjust selection',
                  icon: Icons.crop_rounded,
                  size: AppButtonSize.small,
                  onPressed: _busy ? null : _adjustSelection,
                ),
              ],
            ],
          );
    return LayoutBuilder(
      builder: (context, c) {
        final side = c.maxWidth >= 640;
        final info = _DetectedInfo(busy: _busy, result: _result, error: _error, onRetry: bytes == null ? _searchText : _searchImage);
        if (!side) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [preview, AppSpacing.gapMd, info]);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: bytes == null ? 280 : 240, child: preview),
            AppSpacing.gapLg,
            Expanded(child: info),
          ],
        );
      },
    );
  }

  List<Widget> _resultSlivers(BuildContext context) {
    final r = _result;
    if (_busy) {
      return const [SliverResponsiveCenter(sliver: SliverProductGrid.loading(count: 6))];
    }
    if (_error != null) {
      final offline = _error!.statusCode == 503;
      return [
        SliverResponsiveCenter(
          maxWidth: 900,
          sliver: SliverToBoxAdapter(
            child: offline
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: _DescribeBox(controller: _describe, onSubmit: _searchText, busy: _busy, prominent: true),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ];
    }
    if (r == null) return const [];
    if (!r.recognized) {
      return [
        SliverResponsiveCenter(
          maxWidth: 900,
          verticalPadding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.xxl),
          sliver: SliverToBoxAdapter(
            child: VisualNoMatch(
              result: r,
              fromPhoto: _describedAs == null,
              cameraFirst: _lastSource == ImageSource.camera && _cameraSupported,
              onTryAnother: _busy ? null : _tryAnotherPhoto,
              onSuggestion: _busy ? null : _searchSuggestion,
              describe: _DescribeBox(controller: _describe, onSubmit: _searchText, busy: _busy, prominent: true),
            ),
          ),
        ),
      ];
    }
    if (r.products.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.image_not_supported_outlined,
            title: 'No similar products found',
            message: 'Try a clearer photo with the product centered, or describe it instead.',
            actionLabel: 'New search',
            onAction: _reset,
          ),
        ),
      ];
    }
    return [
      SliverResponsiveCenter(
        verticalPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
        sliver: SliverToBoxAdapter(
          child: Text(
            '${Formatters.plural(r.products.length, 'similar product')} · most similar first',
            style: context.textTheme.labelLarge!.copyWith(color: context.colors.muted),
          ),
        ),
      ),
      SliverResponsiveCenter(
        verticalPadding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        sliver: SliverAiProductGrid(products: r.products, source: 'visual_search'),
      ),
    ];
  }
}

class _ScanPreview extends StatefulWidget {
  const _ScanPreview({required this.bytes, required this.scanning});

  final Uint8List bytes;
  final bool scanning;

  @override
  State<_ScanPreview> createState() => _ScanPreviewState();
}

class _ScanPreviewState extends State<_ScanPreview> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_ScanPreview old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.scanning && !context.reduceMotion) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      image: true,
      label: widget.scanning ? 'Your photo, being analyzed' : 'Your photo',
      child: ClipRRect(
        borderRadius: AppRadii.cardAll,
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: colors.surfaceVariant),
              Image.memory(widget.bytes, fit: BoxFit.contain, gaplessPlayback: true),
              if (widget.scanning) ...[
                ColoredBox(color: colors.background.withValues(alpha: 0.25)),
                if (!context.reduceMotion)
                  AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) => Align(
                      alignment: Alignment(0, -1 + 2 * Curves.easeInOut.transform(_c.value)),
                      child: Container(height: 2, color: colors.ai),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DetectedInfo extends StatelessWidget {
  const _DetectedInfo({required this.busy, required this.result, required this.error, required this.onRetry});

  final bool busy;
  final VisualSearchResult? result;
  final ApiException? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    if (busy) {
      return const AiThinking(messages: ['Looking at your photo…', 'Recognizing the product…', 'Finding similar items…']);
    }
    final e = error;
    if (e != null) {
      final offline = e.statusCode == 503;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(offline ? Icons.visibility_off_outlined : Icons.error_outline_rounded, color: colors.warning),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(offline ? 'Visual search is resting right now' : "Couldn't analyze that", style: t.titleSmall),
              ),
            ],
          ),
          AppSpacing.gapXs,
          Text(
            offline ? 'The vision model is unavailable at the moment. Describe the item below and the AI will search by text.' : e.message,
            style: t.bodyMedium!.copyWith(color: colors.muted),
          ),
          AppSpacing.gapSm,
          AppButton.secondary(label: 'Try again', icon: Icons.refresh_rounded, size: AppButtonSize.small, onPressed: onRetry),
        ],
      );
    }
    final r = result;
    if (r == null) return const SizedBox.shrink();
    if (!r.recognized) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Detected', style: t.labelLarge!.copyWith(color: colors.muted)),
          AppSpacing.gapXs,
          _Pill(
            icon: Icons.do_not_disturb_alt_rounded,
            color: colors.warning,
            background: colors.surfaceVariant,
            label: r.label == null ? 'No product found' : 'Not a product',
          ),
          AppSpacing.gapSm,
          Text(
            r.label == null ? 'Nothing in the catalog matches this.' : 'This looks like ${r.label}.',
            style: t.bodyMedium,
          ),
          if (r.latencyMs != null) ...[
            AppSpacing.gapSm,
            Text('Analyzed in ${r.latencyMs} ms', style: t.bodySmall),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Detected', style: t.labelLarge!.copyWith(color: colors.muted)),
        AppSpacing.gapXs,
        if (r.category != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: colors.aiSoft, borderRadius: AppRadii.pillAll),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.category_outlined, size: 16, color: colors.ai),
                const SizedBox(width: 6),
                Flexible(child: Text(r.category!.titleCase, style: t.titleSmall)),
                if (r.confidence > 0) ...[
                  const SizedBox(width: 8),
                  Text(Formatters.percentFromRatio(r.confidence), style: t.labelLarge!.copyWith(color: colors.ai)),
                ],
              ],
            ),
          ),
          if (r.confidence > 0) ...[
            AppSpacing.gapSm,
            SizedBox(width: 220, child: AiConfidenceBar(value: r.confidence, semanticLabel: 'Detection confidence')),
            AppSpacing.gapXxs,
            Text(
              '${VisualSearchResult.confidenceWord(r.confidence)} · ${Formatters.percentFromRatio(r.confidence)} detection confidence',
              style: t.bodySmall!.copyWith(color: colors.muted),
            ),
          ],
        ] else
          Text('Matched by overall look and description', style: t.bodyMedium),
        if (r.latencyMs != null) ...[
          AppSpacing.gapSm,
          Text('Analyzed in ${r.latencyMs} ms', style: t.bodySmall),
        ],
      ],
    );
  }
}

class _DescribeBox extends StatelessWidget {
  const _DescribeBox({required this.controller, required this.onSubmit, required this.busy, this.prominent = false});

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final bool busy;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(prominent ? 'Describe it instead' : 'Or describe what you are looking for', style: context.textTheme.labelLarge),
        AppSpacing.gapXs,
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => onSubmit(),
                decoration: const InputDecoration(hintText: 'e.g. white leather sneakers with a gum sole'),
              ),
            ),
            AppSpacing.gapXs,
            AppButton(label: 'Find', loading: busy, onPressed: onSubmit),
          ],
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.color, required this.background});

  final IconData icon;
  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: background, borderRadius: AppRadii.pillAll),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(child: Text(label, style: context.textTheme.titleSmall)),
        ],
      ),
    );
  }
}

/// Shown instead of results when the photo (or description) isn't something
/// the store sells: what it looks like, why, a way to try again, the describe
/// box and popular categories. Never shows products.
class VisualNoMatch extends StatelessWidget {
  const VisualNoMatch({
    super.key,
    required this.result,
    required this.onTryAnother,
    required this.onSuggestion,
    this.describe,
    this.fromPhoto = true,
    this.cameraFirst = false,
  });

  final VisualSearchResult result;
  final VoidCallback? onTryAnother;
  final ValueChanged<String>? onSuggestion;

  /// The "Describe it instead" box.
  final Widget? describe;

  /// False when the query was a text description.
  final bool fromPhoto;

  /// Use the camera icon for "Try another photo".
  final bool cameraFirst;

  static const fallbackMessage = 'Try a clear photo of a product — shoes, a phone, a bag…';

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    final r = result;
    final label = r.label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: AppRadii.cardAll,
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: colors.aiSoft, shape: BoxShape.circle),
                    child: Icon(fromPhoto ? Icons.image_search_rounded : Icons.manage_search_rounded, color: colors.ai),
                  ),
                  AppSpacing.gapSm,
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        fromPhoto ? "That's not something we sell" : 'Nothing in the catalog looks like that',
                        style: t.titleMedium,
                      ),
                    ),
                  ),
                ],
              ),
              if (label != null) ...[
                AppSpacing.gapMd,
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Pill(
                      icon: Icons.visibility_outlined,
                      color: colors.ai,
                      background: colors.aiSoft,
                      label: 'Looks like ${label.toLowerCase()}',
                    ),
                    if (r.confidence > 0)
                      Text(
                        '${Formatters.percentFromRatio(r.confidence)} likely',
                        style: t.labelLarge!.copyWith(color: colors.muted),
                      ),
                  ],
                ),
              ],
              AppSpacing.gapSm,
              Text(r.message ?? fallbackMessage, style: t.bodyMedium!.copyWith(color: colors.muted)),
              AppSpacing.gapMd,
              AppButton(
                label: fromPhoto ? 'Try another photo' : 'Try a photo',
                icon: cameraFirst ? Icons.photo_camera_outlined : Icons.photo_library_outlined,
                onPressed: onTryAnother,
              ),
            ],
          ),
        ),
        if (describe != null) ...[AppSpacing.gapLg, describe!],
        if (r.suggestions.isNotEmpty) ...[
          AppSpacing.gapLg,
          Text('Popular categories', style: t.labelLarge),
          AppSpacing.gapXs,
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final name in r.suggestions)
                AiSuggestionChip(
                  label: name,
                  icon: Icons.category_outlined,
                  onTap: onSuggestion == null ? null : () => onSuggestion!(name),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
