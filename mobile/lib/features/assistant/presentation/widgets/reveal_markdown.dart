import 'package:material_ui/material_ui.dart';

import '../../../../core/utils/extensions.dart';
import '../../../ai/presentation/widgets/simple_markdown.dart';

/// Streaming-like reveal: the reply appears word by word, then [onDone]
/// fires (used to slide in product cards). Instant under reduced motion
/// or when [animate] is false.
class RevealMarkdown extends StatefulWidget {
  const RevealMarkdown({super.key, required this.text, this.animate = true, this.onDone, this.style});

  final String text;
  final bool animate;
  final VoidCallback? onDone;
  final TextStyle? style;

  /// ~70 chars/s feels like fast typing; capped so long replies don't drag.
  static Duration durationFor(String text) =>
      Duration(milliseconds: (text.length * 14).clamp(350, 2400));

  /// The prefix of [text] visible at progress [t] (0..1), cut at a word end.
  static String visiblePrefix(String text, double t) {
    if (t >= 1) return text;
    if (t <= 0) return '';
    var end = (text.length * t).round().clamp(0, text.length);
    while (end < text.length && !RegExp(r'\s').hasMatch(text[end])) {
      end++;
    }
    return text.substring(0, end);
  }

  @override
  State<RevealMarkdown> createState() => _RevealMarkdownState();
}

class _RevealMarkdownState extends State<RevealMarkdown> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.animate || context.reduceMotion || widget.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone?.call());
      return;
    }
    _c = AnimationController(vsync: this, duration: RevealMarkdown.durationFor(widget.text))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone?.call();
      })
      ..forward();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return SimpleMarkdown(widget.text, style: widget.style);
    return Semantics(
      // screen readers get the whole reply at once
      label: widget.text,
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: c,
        builder: (context, _) => SimpleMarkdown(
          RevealMarkdown.visiblePrefix(widget.text, Curves.easeOut.transform(c.value)),
          style: widget.style,
        ),
      ),
    );
  }
}
