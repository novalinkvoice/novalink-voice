import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'phone.dart';
import 'portal.dart';
import 'screens/about_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'theme.dart';

void main() {
  registerAppLicenses();
  runApp(const NovaLinkVoiceApp());
}

class NovaLinkVoiceApp extends StatelessWidget {
  const NovaLinkVoiceApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NovaLink Voice',
    debugShowCheckedModeBanner: false,
    theme: NL.theme(),
    home: const StartupGate(),
  );
}

/// Decides login vs app on launch. When the native side already has saved
/// creds, go straight in — critical when a push wakes the app for an incoming
/// call, so it lands on the call UI, not the login screen.
class StartupGate extends StatefulWidget {
  const StartupGate({super.key});
  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  @override
  void initState() { super.initState(); _route(); }

  Future<void> _route() async {
    await [Permission.microphone, Permission.notification].request();
    Widget next = const LoginScreen();
    try {
      final s = await PhoneState.I.status();
      if (s['loggedIn'] == true && await Portal.I.token != null) next = const HomeScreen();
    } catch (_) {/* fall back to login */}
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
        pageBuilder: (_, __, ___) => next, transitionDuration: const Duration(milliseconds: 250),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child)));
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: DecoratedBox(decoration: BoxDecoration(gradient: NL.heroGradient),
        child: Center(child: CircularProgressIndicator(color: NL.cyan))),
  );
}
