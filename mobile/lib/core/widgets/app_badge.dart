import 'package:material_ui/material_ui.dart';

/// Count badge over an icon. Hidden at 0, shows "99+" above 99.
///
/// ```dart
/// AppBadge(count: cartCount, child: Icon(Icons.shopping_bag_outlined))
/// AppBadge.dot(show: hasUnread, child: Icon(Icons.notifications_none))
/// ```
class AppBadge extends StatelessWidget {
  const AppBadge({super.key, required this.count, required this.child, this.max = 99})
    : dot = false;

  const AppBadge.dot({super.key, required bool show, required this.child})
    : count = show ? 1 : 0,
      max = 99,
      dot = true;

  final int count;
  final Widget child;
  final int max;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final visible = count > 0;
    if (dot) {
      return Badge(isLabelVisible: visible, smallSize: 8, child: child);
    }
    return Semantics(
      value: visible ? '$count' : null,
      child: Badge(
        isLabelVisible: visible,
        label: Text(count > max ? '$max+' : '$count'),
        offset: const Offset(6, -4),
        child: child,
      ),
    );
  }
}
