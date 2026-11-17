import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/models/product.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/widgets/widgets.dart';
import '../data/models/ai_models.dart';
import '../providers/ai_providers.dart';
import 'ai_actions.dart';
import 'widgets/ai_ui.dart';
import 'widgets/compare_table.dart';
import 'widgets/simple_markdown.dart';

/// AI comparison (POST /ai/compare): pinned product header, aligned spec rows
/// with the best value highlighted, verdict cards and a summary.
/// Phones scroll the table horizontally; products can be removed.
class CompareScreen extends ConsumerStatefulWidget {
  const CompareScreen({super.key, required this.productIds});

  final List<int> productIds;

  @override
  ConsumerState<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends ConsumerState<CompareScreen> {
  late List<int> _ids = _clean(widget.productIds);
  final _body = ScrollController();
  final _head = ScrollController();

  static List<int> _clean(List<int> ids) => ids.where((id) => id > 0).toSet().take(4).toList();

  @override
  void initState() {
    super.initState();
    _body.addListener(() {
      if (_head.hasClients && _head.offset != _body.offset) _head.jumpTo(_body.offset);
    });
  }

  @override
  void didUpdateWidget(CompareScreen old) {
    super.didUpdateWidget(old);
    if (old.productIds.join(',') != widget.productIds.join(',')) _ids = _clean(widget.productIds);
  }

  @override
  void dispose() {
    _body.dispose();
    _head.dispose();
    super.dispose();
  }

  void _remove(int id) => setState(() => _ids = [..._ids]..remove(id));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compare')),
      body: _ids.length < 2 ? _NotEnough(count: _ids.length) : _buildResult(context),
    );
  }

  Widget _buildResult(BuildContext context) {
    final key = compareKey(_ids);
    final async = ref.watch(compareProvider(key));
    return async.when(
      skipLoadingOnRefresh: true,
      loading: () => const _CompareSkeleton(),
      error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(compareProvider(key))),
      data: (r) => r.products.length < 2 ? _NotEnough(count: r.products.length) : _table(context, r),
    );
  }

  Widget _table(BuildContext context, CompareResult r) {
    final gutter = context.pagePadding;
    return LayoutBuilder(
      builder: (context, c) {
        final available = math.min(c.maxWidth, Breakpoints.maxContent) - gutter * 2;
        final n = r.products.length;
        final colW = compareColumnWidth(available, n, min: 148);
        final tableW = colW * n;
        final side = (c.maxWidth - available) / 2;
        void open(ProductSummary p) => openAiProduct(context, ref, p.id, source: 'compare');

        return CustomScrollView(
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _HeaderDelegate(
                height: compareHeaderHeight(context),
                child: Material(
                  color: context.colors.background,
                  child: DecoratedBox(
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.colors.border))),
                    child: SingleChildScrollView(
                      controller: _head,
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.symmetric(horizontal: side),
                      child: SizedBox(
                        width: tableW,
                        child: CompareHeaderRow(
                          products: r.products,
                          columnWidth: colW,
                          onOpen: open,
                          onRemove: (p) => _remove(p.id),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                controller: _body,
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: side),
                child: SizedBox(
                  width: tableW,
                  child: CompareSpecRows(rows: r.rows, count: n, columnWidth: colW),
                ),
              ),
            ),
            if (tableW > available)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text('Swipe sideways to see every product', textAlign: TextAlign.center, style: context.textTheme.bodySmall),
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, AppSpacing.xl, side, AppSpacing.xxl),
              sliver: SliverList.list(
                children: [
                  const AiHeader(title: 'Verdict', caption: 'How the AI would choose'),
                  AppSpacing.gapSm,
                  if (r.summary.isNotEmpty) ...[
                    SimpleMarkdown(r.summary),
                    AppSpacing.gapMd,
                  ],
                  VerdictCards(result: r, onOpen: open),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  _HeaderDelegate({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => SizedBox.expand(child: child);

  @override
  bool shouldRebuild(_HeaderDelegate old) => old.height != height || old.child != child;
}

class _NotEnough extends StatelessWidget {
  const _NotEnough({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.compare_arrows_rounded,
      title: count == 0 ? 'Nothing to compare yet' : 'Add one more product',
      message: count == 0
          ? 'Pick 2 to 4 products and the AI lines up their specs, highlights the best value and gives a verdict.'
          : 'Comparisons need at least 2 products. Open another product and choose Compare, or ask the assistant.',
      actionLabel: 'Browse products',
      onAction: () => context.go(Routes.explore),
    );
  }
}

class _CompareSkeleton extends StatelessWidget {
  const _CompareSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(context.pagePadding),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        const AiThinking(messages: ['Reading specs…', 'Aligning features…', 'Picking winners…'], lines: 0),
        AppSpacing.gapLg,
        const Row(
          children: [
            Expanded(child: Skeleton(height: 120, borderRadius: AppRadii.cardAll)),
            AppSpacing.gapSm,
            Expanded(child: Skeleton(height: 120, borderRadius: AppRadii.cardAll)),
          ],
        ),
        AppSpacing.gapLg,
        for (var i = 0; i < 6; i++) ...[const Skeleton(height: 44), AppSpacing.gapXs],
      ],
    );
  }
}
