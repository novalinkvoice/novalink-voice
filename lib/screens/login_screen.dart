import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../phone.dart';
import '../portal.dart';
import '../theme.dart';
import 'home_screen.dart';

/// Sign in with the NovaLink Voice portal email + password (+ MFA code if on).
/// The portal returns the line(s) assigned to this user; the app registers the
/// first one (or the one the user picks).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _otp = TextEditingController();
  bool _needOtp = false, _busy = false, _hide = true;
  String _err = '';

  Future<void> _signIn() async {
    setState(() { _busy = true; _err = ''; });
    try {
      await Portal.I.signIn(_email.text, _pass.text, otp: _needOtp ? _otp.text : null);
      final prof = await Portal.I.profile();
      final lines = (prof['lines'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (lines.isEmpty) {
        await Portal.I.signOut();
        throw PortalError("Your account doesn't have a phone line yet. Ask your administrator to "
            "assign you an extension (Phone Lines / Extensions → Assigned to).");
      }
      final line = lines.length == 1 ? lines.first : await _pickLine(lines);
      if (line == null) { setState(() => _busy = false); return; }
      await PhoneState.I.login(
        domain: line['sip_domain'] as String, username: line['sip_username'] as String,
        password: line['sip_password'] as String, proxy: line['proxy'] as String,
        displayName: (prof['full_name'] as String?) ?? (line['display_name'] as String?));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } on PortalError catch (e) {
      setState(() { _err = e.mfaRequired && !_needOtp ? 'Enter the 6-digit code from your authenticator app.' : e.message;
        if (e.mfaRequired) _needOtp = true; _busy = false; });
    } catch (e) {
      setState(() { _err = 'Could not reach NovaLink Voice. Check your connection and try again.'; _busy = false; });
    }
  }

  Future<Map<String, dynamic>?> _pickLine(List<Map<String, dynamic>> lines) => showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Padding(padding: EdgeInsets.all(16), child: Text('Which line is this phone for?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
      for (final l in lines) ListTile(
        leading: Avatar(l['tenant_name'] as String, size: 40),
        title: Text('${l['display_name'] ?? 'Extension'} · ${l['extension']}'),
        subtitle: Text(l['tenant_name'] as String),
        onTap: () => Navigator.pop(ctx, l)),
      const SizedBox(height: 8),
    ])),
  );

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: NL.heroGradient),
        child: SafeArea(child: Center(child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const _Wordmark(),
            const SizedBox(height: 6),
            const Text('Business phones, in your pocket.', style: TextStyle(color: NL.cyan, fontSize: 15)),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 8))]),
              child: AutofillGroup(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Sign in', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: NL.ink)),
                const SizedBox(height: 4),
                const Text('Use your NovaLink Voice portal email and password.',
                    style: TextStyle(color: NL.muted)),
                const SizedBox(height: 18),
                TextField(controller: _email, keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email], textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline))),
                const SizedBox(height: 12),
                TextField(controller: _pass, obscureText: _hide, autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _needOtp ? null : _signIn(),
                    decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                            onPressed: () => setState(() => _hide = !_hide)))),
                if (_needOtp) ...[
                  const SizedBox(height: 12),
                  TextField(controller: _otp, keyboardType: TextInputType.number, autofocus: true,
                      autofillHints: const [AutofillHints.oneTimeCode], onSubmitted: (_) => _signIn(),
                      decoration: const InputDecoration(labelText: 'Authentication code', prefixIcon: Icon(Icons.shield_outlined))),
                ],
                if (_err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12),
                    child: Text(_err, style: const TextStyle(color: NL.red))),
                const SizedBox(height: 18),
                FilledButton(onPressed: _busy ? null : _signIn,
                    child: _busy ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Text('Sign in')),
              ])),
            ),
            const SizedBox(height: 18),
            const Text("New to NovaLink Voice? Sign up at novalinkvoice.com",
                style: TextStyle(color: Colors.white70)),
          ]),
        ))),
      ),
    ));
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();
  @override
  Widget build(BuildContext context) => RichText(text: const TextSpan(
    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 1),
    children: [
      TextSpan(text: 'NOVA', style: TextStyle(color: Colors.white)),
      TextSpan(text: 'LINK', style: TextStyle(color: NL.cyan)),
      TextSpan(text: ' Voice', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w400, letterSpacing: 0)),
    ],
  ));
}
