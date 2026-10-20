import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novalink_voice/screens/about_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('license registry carries the app (AGPL text) and the Linphone SDK', () async {
    registerAppLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    String body(String pkg) => entries.firstWhere((e) => e.packages.contains(pkg))
        .paragraphs.map((p) => p.text).join('\n');
    expect(body('NovaLink Voice'), contains('GNU AFFERO GENERAL PUBLIC LICENSE'));
    expect(body('NovaLink Voice'), contains(sourceRepo));
    expect(body('Linphone SDK (liblinphone)'), contains('Belledonne Communications'));
  });

  testWidgets('About shows the version and links the source for that exact tag', (t) async {
    PackageInfo.setMockInitialValues(appName: 'NovaLink Voice', packageName: 'x', version: '1.0.0',
        buildNumber: '1', buildSignature: '');
    await t.pumpWidget(const MaterialApp(home: AboutScreen()));
    await t.pumpAndSettle();
    expect(find.text('Version 1.0.0 (build 1)'), findsOneWidget);
    expect(find.text('$sourceRepo (v1.0.0)'), findsOneWidget);
    expect(find.text('Open-source licenses'), findsOneWidget);
  });
}
