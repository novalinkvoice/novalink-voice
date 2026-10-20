import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';

/// AGPL-3.0 requires the source to be easy to find from the app itself, so
/// this screen links to the public repo and the tag for this exact build.
const sourceRepo = 'https://github.com/novalinkvoice/novalink-voice';

/// Add the Linphone SDK (native, so not picked up from pub packages) and the
/// app's own AGPL text to Flutter's license registry, which showLicensePage reads.
void registerAppLicenses() {
  LicenseRegistry.addLicense(() async* {
    final agpl = await rootBundle.loadString('LICENSE');
    yield LicenseEntryWithLineBreaks(['NovaLink Voice'],
        'Copyright (C) 2026 APEX Business Consultants LLC\n\n'
        'Licensed under the GNU Affero General Public License v3.0.\n'
        'Source code: $sourceRepo\n\n$agpl');
    yield LicenseEntryWithLineBreaks(['Linphone SDK (liblinphone)'],
        'Copyright (C) Belledonne Communications SARL\n'
        'https://www.linphone.org/\n'
        'https://gitlab.linphone.org/BC/public/linphone-sdk\n\n'
        'Licensed under the GNU Affero General Public License v3.0 '
        '(full text under "NovaLink Voice").');
  });
}

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});
  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  PackageInfo? _info;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) { if (mounted) setState(() => _info = i); });
  }

  String get _version => _info == null ? '' : '${_info!.version} (build ${_info!.buildNumber})';
  String get _tagUrl => _info == null ? sourceRepo : '$sourceRepo/tree/v${_info!.version}';

  Future<void> _open(String url) async {
    if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication) && mounted) {
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No browser found — link copied')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('About')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const SizedBox(height: 8),
      const Center(child: Text('NovaLink Voice', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
      const SizedBox(height: 4),
      Center(child: Text(_version.isEmpty ? '' : 'Version $_version', style: const TextStyle(color: NL.muted))),
      const SizedBox(height: 24),
      const Text(
        'NovaLink Voice is free software, licensed under the GNU Affero General Public '
        'License v3.0. You can get the complete source code for this app, including the '
        'exact version you have installed, from GitHub.',
        style: TextStyle(height: 1.4)),
      const SizedBox(height: 8),
      const Text('Calling is powered by the Linphone SDK from Belledonne Communications.',
          style: TextStyle(height: 1.4, color: NL.muted)),
      const SizedBox(height: 20),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.code, color: NL.purple),
        title: const Text('Source code'),
        subtitle: Text(_info == null ? sourceRepo : '$sourceRepo (v${_info!.version})'),
        onTap: () => _open(_tagUrl),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.description_outlined, color: NL.purple),
        title: const Text('Open-source licenses'),
        subtitle: const Text('NovaLink Voice, the Linphone SDK and every library the app uses'),
        onTap: () => showLicensePage(context: context, applicationName: 'NovaLink Voice',
            applicationVersion: _version, applicationLegalese: '© 2026 APEX Business Consultants LLC'),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.language, color: NL.purple),
        title: const Text('novalinkvoice.com'),
        onTap: () => _open('https://novalinkvoice.com'),
      ),
    ]),
  );
}
