import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// NovaLink Voice portal API (voice.novalinkvoice.com). The app signs in with
/// the user's portal email/password; the portal hands back the SIP line(s)
/// assigned to that user. The portal session token is kept in the Keystore.
class Portal {
  Portal._();
  static final Portal I = Portal._();
  static const base = 'https://voice.novalinkvoice.com/api';
  final _store = const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  Future<String?> get token => _store.read(key: 'portal_token');

  /// Throws [PortalError]. `mfaRequired` is set when the account needs a code.
  Future<void> signIn(String email, String password, {String? otp}) async {
    final r = await http.post(Uri.parse('$base/auth/login'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'username': email.trim(), 'password': password, if (otp != null && otp.isNotEmpty) 'otp': otp.trim()},
    ).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) {
      final msg = _detail(r);
      throw PortalError(msg, mfaRequired: msg.toLowerCase().contains('mfa'), status: r.statusCode);
    }
    await _store.write(key: 'portal_token', value: jsonDecode(r.body)['access_token'] as String);
    await _store.write(key: 'portal_email', value: email.trim());
  }

  Future<void> signOut() => _store.deleteAll();

  Future<String?> get email => _store.read(key: 'portal_email');

  Future<dynamic> _get(String path) async {
    final t = await token;
    if (t == null) throw PortalError('Signed out', status: 401);
    final r = await http.get(Uri.parse('$base$path'), headers: {'Authorization': 'Bearer $t'})
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw PortalError(_detail(r), status: r.statusCode);
    return jsonDecode(r.body);
  }

  Future<Map<String, dynamic>> profile() async => Map<String, dynamic>.from(await _get('/me/mobile') as Map);

  Future<List<Map<String, dynamic>>> directory() async =>
      (await _get('/me/directory') as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<List<Map<String, dynamic>>> voicemails() async =>
      (await _get('/me/voicemails') as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  /// Downloads a voicemail to a temp file and returns its path.
  Future<String> voicemailFile(String id) async {
    final t = await token;
    final r = await http.get(Uri.parse('$base/voicemails/$id/audio'), headers: {'Authorization': 'Bearer $t'})
        .timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw PortalError(_detail(r), status: r.statusCode);
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/vm-$id.wav');
    await f.writeAsBytes(r.bodyBytes);
    return f.path;
  }

  Future<void> markRead(String id) async {
    final t = await token;
    await http.post(Uri.parse('$base/voicemails/$id/read'), headers: {'Authorization': 'Bearer $t'});
  }

  Future<void> deleteVoicemail(String id) async {
    final t = await token;
    final r = await http.delete(Uri.parse('$base/voicemails/$id'), headers: {'Authorization': 'Bearer $t'});
    if (r.statusCode >= 300) throw PortalError(_detail(r), status: r.statusCode);
  }

  String _detail(http.Response r) {
    try {
      final d = jsonDecode(r.body)['detail'];
      if (d is String) return d;
      if (d is List && d.isNotEmpty) return (d.first['msg'] ?? 'Request failed').toString();
    } catch (_) {}
    return 'Request failed (${r.statusCode})';
  }
}

class PortalError implements Exception {
  final String message;
  final bool mfaRequired;
  final int status;
  PortalError(this.message, {this.mfaRequired = false, this.status = 0});
  @override
  String toString() => message;
}
