import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/utils/extensions.dart';
import '../../core/widgets/widgets.dart';

/// Appearance, server address (for emulator/LAN testing), keyboard
/// shortcuts and app info, as white grouped cards on the page wash.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // shortcuts only exist where there is a hardware keyboard
    final keyboard = kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          ResponsiveCenter(
            maxWidth: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Section(title: 'Appearance', child: _ThemePicker()),
                const _Section(
                  title: 'Server address',
                  subtitle: 'Where the app finds the Zelora API. Change it when testing on a device or another network.',
                  child: _ServerAddress(),
                ),
                if (keyboard) const _Section(title: 'Keyboard shortcuts', child: _Shortcuts()),
                const _Section(title: 'About', child: _About()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text(title, style: t.titleMedium!.copyWith(fontWeight: FontWeight.w800))),
          if (subtitle != null) ...[
            AppSpacing.gapXxs,
            Text(subtitle!, style: t.bodySmall!.copyWith(fontSize: 13)),
          ],
          AppSpacing.gapSm,
          child,
        ],
      ),
    );
  }
}

/// Three theme options, each a miniature of what it looks like.
class _ThemePicker extends ConsumerWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    void pick(ThemeMode m) => ref.read(themeModeProvider.notifier).set(m);

    return Row(
      children: [
        Expanded(
          child: _ThemeOption(
            label: 'Light',
            caption: 'Airy blue',
            palettes: const [AppPalette.light],
            selected: mode == ThemeMode.light,
            onTap: () => pick(ThemeMode.light),
          ),
        ),
        AppSpacing.gapSm,
        Expanded(
          child: _ThemeOption(
            label: 'Dark',
            caption: 'Deep navy',
            palettes: const [AppPalette.dark],
            selected: mode == ThemeMode.dark,
            onTap: () => pick(ThemeMode.dark),
          ),
        ),
        AppSpacing.gapSm,
        Expanded(
          child: _ThemeOption(
            label: 'System',
            caption: 'Follows device',
            palettes: const [AppPalette.light, AppPalette.dark],
            selected: mode == ThemeMode.system,
            onTap: () => pick(ThemeMode.system),
          ),
        ),
      ],
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.label,
    required this.caption,
    required this.palettes,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String caption;
  final List<AppPalette> palettes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label theme',
      excludeSemantics: true,
      child: AppCard(
        padding: EdgeInsets.zero,
        selected: selected,
        color: selected ? colors.primarySoft : null,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: AppRadii.inputAll,
                  child: SizedBox(
                    height: 64,
                    child: Row(children: [for (final p in palettes) Expanded(child: _MiniPreview(palette: p))]),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: t.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(
                            caption,
                            style: t.bodySmall!.copyWith(color: colors.faint, fontSize: 11.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    AnimatedOpacity(
                      opacity: selected ? 1 : 0,
                      duration: context.motion(AppDurations.fast),
                      child: Icon(Icons.check_circle_rounded, size: 18, color: colors.primary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A tiny abstract of the app in a palette: page, card, image well, text
/// lines and the accent button.
class _MiniPreview extends StatelessWidget {
  const _MiniPreview({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    Widget line(double w, Color c) => Container(
      width: w,
      height: 3,
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(color: c, borderRadius: AppRadii.pillAll),
    );
    return DecoratedBox(
      decoration: BoxDecoration(gradient: p.backgroundWash),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Container(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: const BorderRadius.all(Radius.circular(7)),
          ),
          padding: const EdgeInsets.all(5),
          // stacked so it holds up even when two palettes share one tile
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: p.imageWell, borderRadius: const BorderRadius.all(Radius.circular(3))),
                  child: const SizedBox.expand(),
                ),
              ),
              FractionallySizedBox(widthFactor: 0.7, child: line(double.infinity, p.text)),
              Row(
                children: [
                  Expanded(child: line(double.infinity, p.faint)),
                  const SizedBox(width: 6),
                  Container(
                    width: 14,
                    height: 6,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(color: p.primary, borderRadius: AppRadii.pillAll),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Check { idle, checking, ok, failed }

class _ServerAddress extends ConsumerStatefulWidget {
  const _ServerAddress();

  @override
  ConsumerState<_ServerAddress> createState() => _ServerAddressState();
}

class _ServerAddressState extends ConsumerState<_ServerAddress> {
  late final TextEditingController _url;
  _Check _check = _Check.idle;
  String? _checkMessage;
  String? _error;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: ref.read(serverUrlProvider));
    // check once on open, so the status is already there when you look
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _test();
    });
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  bool _validate() {
    final valid = AppConfig.isValidBaseUrl(_url.text);
    setState(() => _error = valid ? null : 'Enter an address like http://192.168.1.5:5000');
    return valid;
  }

  Future<void> _test() async {
    if (!_validate()) return;
    context.unfocus();
    setState(() {
      _check = _Check.checking;
      _checkMessage = null;
    });
    try {
      final latency = await ApiClient.checkHealth(_url.text);
      if (!mounted) return;
      setState(() {
        _check = _Check.ok;
        _checkMessage = 'Connected · ${latency.inMilliseconds} ms';
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _check = _Check.failed;
        _checkMessage = e.message;
      });
    }
  }

  Future<void> _save() async {
    if (!_validate()) return;
    context.unfocus();
    await ref.read(serverUrlProvider.notifier).set(_url.text);
    if (!mounted) return;
    _url.text = ref.read(serverUrlProvider);
    AppSnack.success(context, 'Server address saved');
  }

  Future<void> _reset() async {
    await ref.read(serverUrlProvider.notifier).reset();
    if (!mounted) return;
    setState(() {
      _url.text = ref.read(serverUrlProvider);
      _check = _Check.idle;
      _checkMessage = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final current = ref.watch(serverUrlProvider);
    final locked = AppConfig.isEnvOverridden;
    final changed = AppConfig.normalize(_url.text) != current;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: _url,
          hint: AppConfig.platformDefault,
          prefixIcon: Icons.dns_outlined,
          keyboardType: TextInputType.url,
          errorText: _error,
          enabled: !locked,
          helperText: locked
              ? 'Set at build time with --dart-define=API_BASE_URL.'
              : 'API: ${AppConfig.normalize(_url.text)}${AppConfig.apiPrefix}',
          onChanged: (_) => setState(() {
            _error = null;
            _check = _Check.idle;
          }),
          onSubmitted: (_) => _test(),
        ),
        if (_checkMessage != null) ...[
          AppSpacing.gapSm,
          Align(
            alignment: Alignment.centerLeft,
            child: StatusLine(
              _checkMessage!,
              key: ValueKey(_checkMessage),
              color: _check == _Check.ok ? colors.success : colors.error,
              textColor: _check == _Check.ok ? colors.muted : colors.error,
            ),
          ),
        ],
        AppSpacing.gapMd,
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            AppButton.secondary(
              label: 'Test connection',
              icon: Icons.bolt_rounded,
              size: AppButtonSize.small,
              loading: _check == _Check.checking,
              onPressed: _test,
            ),
            if (!locked)
              AppButton(
                label: 'Save',
                size: AppButtonSize.small,
                onPressed: changed ? _save : null,
              ),
            if (!locked)
              AppButton.ghost(
                label: 'Reset to default',
                size: AppButtonSize.small,
                onPressed: _reset,
              ),
          ],
        ),
      ],
    );
  }
}

/// The shortcuts that really work, with the keys drawn as keys.
class _Shortcuts extends StatelessWidget {
  const _Shortcuts();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final apple = defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;
    final rows = <(String, List<String>)>[
      ('Search from anywhere', [apple ? '\u2318' : 'Ctrl', 'K']),
      ('Search (when not typing)', ['/']),
      ('Switch tabs', ['Alt', '1\u20135']),
      ('Submit a form', ['Enter']),
    ];
    return _Card(
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(color: colors.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 11),
              child: Row(
                children: [
                  Expanded(child: Text(rows[i].$1, style: context.textTheme.bodyMedium)),
                  for (final key in rows[i].$2) ...[const SizedBox(width: 4), KbdChip(key)],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // AppCard is a Material inside, so list tiles keep their ink
    return AppCard(padding: EdgeInsets.zero, child: child);
  }
}

class _About extends ConsumerWidget {
  const _About();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final t = context.textTheme;
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();
    final mode = kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug');
    final theme = ref.watch(themeModeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    const AppLogo(size: 40, showWordmark: false),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ZeloraWordmark(size: 20, color: colors.text),
                          const SizedBox(height: 4),
                          Text('Your AI shopping assistant', style: t.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: colors.border),
              const KeyValueRow(label: 'Version', value: AppConfig.appVersion, copyable: true),
              Divider(color: colors.border, indent: AppSpacing.md),
              KeyValueRow(label: 'Build', value: '$platform \u00b7 $mode'),
              Divider(color: colors.border, indent: AppSpacing.md),
              KeyValueRow(label: 'Theme', value: theme.name),
              Divider(color: colors.border, indent: AppSpacing.md),
              KeyValueRow(label: 'API', value: Uri.tryParse(ref.watch(serverUrlProvider))?.authority ?? '\u2014', copyable: true),
              Divider(color: colors.border),
              ListTile(
                title: const Text('Open-source licenses'),
                trailing: Icon(Icons.arrow_forward_rounded, size: 18, color: colors.faint),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: AppConfig.appName,
                  applicationVersion: AppConfig.appVersion,
                ),
              ),
            ],
          ),
        ),
        AppSpacing.gapLg,
        Center(
          child: Text(
            '${AppConfig.assistantName} is code. The prices are real.',
            style: t.bodySmall!.copyWith(color: colors.faint),
          ),
        ),
      ],
    );
  }
}
