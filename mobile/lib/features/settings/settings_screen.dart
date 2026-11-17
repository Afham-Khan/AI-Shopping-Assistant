import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/utils/extensions.dart';
import '../../core/widgets/widgets.dart';

/// Appearance, server address (for emulator/LAN testing) and app info.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: const [
          ResponsiveCenter(
            maxWidth: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Section(title: 'Appearance', child: _ThemePicker()),
                _Section(
                  title: 'Server address',
                  subtitle: 'Where the app finds the Zelora API. Change it when testing on a device or another network.',
                  child: _ServerAddress(),
                ),
                _Section(title: 'About', child: _About()),
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
          Semantics(header: true, child: Text(title, style: t.titleMedium)),
          if (subtitle != null) ...[
            AppSpacing.gapXxs,
            Text(subtitle!, style: t.bodySmall),
          ],
          AppSpacing.gapMd,
          child,
        ],
      ),
    );
  }
}

class _ThemePicker extends ConsumerWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return SegmentedButton<ThemeMode>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined, size: 18), label: Text('System')),
        ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined, size: 18), label: Text('Light')),
        ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined, size: 18), label: Text('Dark')),
      ],
      selected: {mode},
      onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
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
          Row(
            children: [
              Icon(
                _check == _Check.ok ? Icons.check_circle_rounded : Icons.error_rounded,
                size: 18,
                color: _check == _Check.ok ? colors.success : colors.error,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  _checkMessage!,
                  style: context.textTheme.bodySmall!.copyWith(
                    color: _check == _Check.ok ? colors.success : colors.error,
                  ),
                ),
              ),
            ],
          ),
        ],
        AppSpacing.gapMd,
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            AppButton.secondary(
              label: 'Test connection',
              icon: Icons.wifi_tethering_rounded,
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

class _About extends StatelessWidget {
  const _About();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // a Material (not a DecoratedBox) so list tiles keep their ink
    return Material(
      color: colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.cardAll, side: BorderSide(color: colors.border)),
      child: Column(
        children: [
          const ListTile(
            leading: AppLogo(size: 32, showWordmark: false),
            title: Text(AppConfig.appName),
            subtitle: Text('AI shopping assistant'),
          ),
          const Divider(indent: AppSpacing.md, endIndent: AppSpacing.md),
          ListTile(
            title: const Text('Version'),
            trailing: Text(AppConfig.appVersion, style: context.textTheme.bodyMedium!.copyWith(color: colors.muted)),
          ),
          ListTile(
            title: const Text('Licenses'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showLicensePage(
              context: context,
              applicationName: AppConfig.appName,
              applicationVersion: AppConfig.appVersion,
            ),
          ),
        ],
      ),
    );
  }
}
