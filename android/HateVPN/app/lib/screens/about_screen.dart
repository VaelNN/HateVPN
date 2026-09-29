import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/donate_methods.dart';
import '../services/install_source.dart';
import '../services/project_links.dart';
import '../services/relative_time.dart';
import '../services/update_checker.dart';
import '../services/url_launcher.dart' as ul;
import '../services/version_info.dart';
import '../vpn/box_vpn_client.dart';
import '../services/l10n/locale_controller.dart';
import '../widgets/safe_bottom.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, this.openDonate = false});




  final bool openDonate;




  static const _repoUrl = ProjectLinks.repo;
  static const _singboxUpstreamUrl = ProjectLinks.singboxUpstream;
  static const _singboxLauncherUrl = ProjectLinks.launcher;











  static const guideUrlEn = ProjectLinks.guideEn;
  static const guideUrlRu = ProjectLinks.guideRu;



  @visibleForTesting
  static String guideUrlFor(String tag) => ProjectLinks.guideFor(tag);



  static String get _guideUrl =>
      guideUrlFor(LocaleController.I.effectiveTag);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (openDonate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) _showDonateDialog(context);
      });
    }
    return Scaffold(
      appBar: AppBar(title: Text(getLocalText.s("About"))),
      body: ListView(
        padding: const EdgeInsets.all(16).withSafeBottom(context),
        children: [
          Center(
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/icons/hatevpn.png',
                    width: 72,
                    height: 72,
                  ),
                ),
                const SizedBox(height: 8),
                Text(

                  'HateVPN',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(

                  'v${VersionInfo.I.version}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 2),


                Text(
                  getLocalText.s(
                      "Installed from %s", InstallSourceResolver.current.label),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Частная сборка by DarkSide. Основана на открытом проекте L×Box (GPL-3.0). Исходный код поставляется вместе с APK.'),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(getLocalText.s("User guide")),
                  subtitle: Text(getLocalText.s(
                      "How it works: directions, rules, DNS, detour, recipes")),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => ul.UrlLauncher.open(_guideUrl),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.code),
                  title: Text(getLocalText.s("Source Code")),
                  subtitle: const Text(_repoUrl),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => ul.UrlLauncher.open(_repoUrl),
                ),
                const Divider(height: 1),





                FutureBuilder<String>(
                  future: BoxVpnClient.I.getCoreVersion(),
                  builder: (ctx, snap) {
                    final v = (snap.data ?? '').trim();
                    final subtitle = switch (snap.connectionState) {
                      ConnectionState.waiting => 'Loading…',
                      _ when v.isEmpty => 'sing-box (version unknown)',
                      _ => 'sing-box $v · via libbox',
                    };
                    return ListTile(
                      leading: const Icon(Icons.architecture),
                      title: Text(getLocalText.s("VPN core")),
                      subtitle: Text(subtitle),
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      onTap: () => ul.UrlLauncher.open(_singboxUpstreamUrl),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            getLocalText.s("Credits"),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),

                  title: const Text('singbox-launcher'),
                  subtitle: Text(getLocalText.s("Config wizard and parser reference")),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => ul.UrlLauncher.open(_singboxLauncherUrl),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _showDonateDialog(context),
            icon: const Icon(Icons.favorite),
            label: Text(getLocalText.s("Support the project")),
          ),
          const SizedBox(height: 16),
          Text(
            getLocalText.s("Tech Stack"),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: const [

              Chip(label: Text('Flutter')),

              Chip(label: Text('Dart')),

              Chip(label: Text('sing-box')),

              Chip(label: Text('libbox')),

              Chip(label: Text('CommandClient')),

              Chip(label: Text('Material 3')),
            ],
          ),
        ],
      ),
    );
  }





  void _showDonateDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(getLocalText.s("Support L×Box")),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<List<DonateMethod>>(
            future: DonateMethods.I.load(),
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final methods = snap.data ?? const <DonateMethod>[];
              return ListView(
                shrinkWrap: true,
                children: [
                  for (final m in methods) ...[
                    _DonateTile(method: m, onCopy: _copyToClipboard),
                    const Divider(height: 20),
                  ],
                  TextButton.icon(
                    onPressed: () => ul.UrlLauncher.open(
                        ProjectLinks.donatePageFor(
                            LocaleController.I.effectiveTag)),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text(getLocalText.s("All ways to support")),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(getLocalText.s("Close"))),
        ],
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(getLocalText.s("Copied: %s", text))),
    );
  }
}




class _DonateTile extends StatelessWidget {
  const _DonateTile({required this.method, required this.onCopy});

  final DonateMethod method;
  final void Function(BuildContext, String) onCopy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final note = method.note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        Text(method.title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        if (note != null && note.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(note,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
        if (method.isCrypto) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => onCopy(context, method.address!),

            child: Text(method.address!,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
          ),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => onCopy(context, method.address!),
                icon: const Icon(Icons.copy, size: 14),
                label: Text(getLocalText.s("Copy"),
                    style: const TextStyle(fontSize: 12)),
              ),
              TextButton.icon(
                onPressed: () => ul.UrlLauncher.open(method.url),
                icon: const Icon(Icons.account_balance_wallet_outlined, size: 14),
                label: Text(getLocalText.s("Pay"),
                    style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ] else ...[
          const SizedBox(height: 4),
          FilledButton.tonal(
            onPressed: () => ul.UrlLauncher.open(method.url),
            child: Text(getLocalText.s("Open")),
          ),
        ],
      ],
    );
  }
}






class _SourcesCard extends StatelessWidget {
  const _SourcesCard();

  static IconData _icon(InstallSource source) => switch (source) {
        InstallSource.github => Icons.download_outlined,
        InstallSource.play => Icons.shop_outlined,
        InstallSource.fdroid => Icons.storefront_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final current = InstallSourceResolver.current;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              getLocalText.s("Where to get L×Box"),
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          for (final source in InstallSource.values) ...[
            ListTile(
              leading: Icon(_icon(source)),
              title: Text(source.label),
              subtitle: source == current
                  ? Text(getLocalText.s("Installed from here"))
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (source == current)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(Icons.check, size: 18, color: cs.primary),
                    ),
                  const Icon(Icons.open_in_new, size: 18),
                ],
              ),
              onTap: () => ul.UrlLauncher.open(
                source.pageUrl,
                fallbackUrl: source.updateUrlFallback,
              ),
            ),
            if (source != InstallSource.values.last) const Divider(height: 1),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              getLocalText.s(
                  "Each source signs the app with its own key, so builds from different sources do not install over each other. To switch: back up your settings, uninstall L×Box, install it from the new source and restore the backup."),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}



class _UpdateBlock extends StatefulWidget {
  const _UpdateBlock();

  @override
  State<_UpdateBlock> createState() => _UpdateBlockState();
}

class _UpdateBlockState extends State<_UpdateBlock> {
  bool _checking = false;
  String? _statusLine;

  Future<void> _checkNow() async {
    setState(() {
      _checking = true;
      _statusLine = null;
    });
    final result = await UpdateChecker.I.forceCheck(
      localVersion: VersionInfo.I.version,
    );
    if (!mounted) return;
    setState(() {
      _checking = false;
      switch (result.kind) {
        case UpdateCheckKind.newer:
          _statusLine = null;
        case UpdateCheckKind.upToDate:
          _statusLine = "You're up to date";
        case UpdateCheckKind.failed:
          _statusLine = 'Check failed: ${result.message ?? 'unknown error'}';
        case UpdateCheckKind.skipped:
          _statusLine = 'Check skipped: ${result.message ?? ''}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: ValueListenableBuilder<UpdateInfo?>(
        valueListenable: UpdateChecker.I.latest,
        builder: (context, info, _) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      info != null ? Icons.system_update_alt : Icons.check_circle_outline,
                      size: 18,
                      color: info != null ? cs.primary : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        info != null
                            ? getLocalText.s("%s available", info.tag)
                            : getLocalText.s("No updates pending"),
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    if (_checking)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      TextButton(
                        onPressed: _checkNow,
                        child: Text(getLocalText.s("Check now")),
                      ),
                  ],
                ),
                if (info != null) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 26),
                    child: Text(
                      info.publishedAt != null
                          ? getLocalText.s("Released %s",
                              relativeTime(DateTime.now(), info.publishedAt!))
                          : getLocalText.s("(cached info)"),
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Builder(builder: (context) {


                      final source = InstallSourceResolver.current;
                      return TextButton.icon(
                        onPressed: () => ul.UrlLauncher.open(
                          source.updateUrl(info.tag),
                          fallbackUrl: source.updateUrlFallback,
                        ),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: Text(source == InstallSource.github
                            ? getLocalText.s("View release")
                            : getLocalText.s("Open in %s", source.label)),
                      );
                    }),
                  ),
                ],
                if (_statusLine != null) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 26),
                    child: Text(
                      _statusLine!,
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
