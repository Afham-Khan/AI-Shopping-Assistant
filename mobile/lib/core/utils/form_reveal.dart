import 'package:material_ui/material_ui.dart';

/// Form helpers shared by every form screen.
abstract final class FormReveal {
  /// Banner text shown when a submit finds invalid fields.
  static const fixFields = 'Please fix the highlighted fields.';

  /// Validates [form] and, when invalid, scrolls the first field with an
  /// error into view. Returns true when valid.
  ///
  /// ```dart
  /// if (!FormReveal.validate(_formKey)) {
  ///   setState(() => _banner = FormReveal.fixFields);
  ///   return;
  /// }
  /// ```
  static bool validate(GlobalKey<FormState> form) {
    final state = form.currentState;
    if (state == null) return false;
    if (state.validate()) return true;
    final root = form.currentContext;
    if (root == null) return false;
    BuildContext? first;
    void visit(Element e) {
      if (first != null) return;
      if (e is StatefulElement && e.state is FormFieldState && (e.state as FormFieldState).hasError) {
        first = e;
        return;
      }
      e.visitChildElements(visit);
    }

    root.visitChildElements(visit);
    final target = first;
    if (target != null && target.mounted) {
      Scrollable.ensureVisible(
        target,
        alignment: 0.2,
        duration: MediaQuery.maybeDisableAnimationsOf(target) ?? false
            ? Duration.zero
            : const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
    return false;
  }
}
