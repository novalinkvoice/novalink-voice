import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _method = MethodChannel('novalink/linphone');
const _events = EventChannel('novalink/linphone/events');

/// Snapshot of the active call, from the native Linphone core.
class CallInfo {
  final String state, remote, name, message;
  final bool incoming, muted, speaker, paused;
  final int duration;
  const CallInfo({required this.state, required this.remote, required this.name, required this.message,
      required this.incoming, required this.muted, required this.speaker, required this.paused,
      required this.duration});

  bool get ended => const ['End', 'Released', 'Error'].contains(state);
  bool get ringing => incoming && (state == 'IncomingReceived' || state == 'IncomingEarlyMedia');
  bool get connected => const ['Connected', 'StreamsRunning', 'Paused', 'Pausing', 'Resuming',
      'PausedByRemote', 'Updating', 'UpdatedByRemote'].contains(state);
  String get label => name.isNotEmpty ? name : remote;
}

/// App-wide phone state. One instance, listened to by every screen.
class PhoneState extends ChangeNotifier {
  PhoneState._() {
    _events.receiveBroadcastStream().listen(_onEvent);
  }
  static final PhoneState I = PhoneState._();

  String registration = 'None';
  String registrationMessage = '';
  CallInfo? call;
  /// Bumped whenever a call ends so the Calls tab reloads history.
  int historyVersion = 0;

  bool get registered => registration == 'Ok';
  bool get registering => registration == 'Progress' || registration == 'Refreshing';

  void _onEvent(dynamic e) {
    final m = Map<String, dynamic>.from(e as Map);
    if (m['type'] == 'registration') {
      registration = m['state'] as String? ?? 'None';
      registrationMessage = m['message'] as String? ?? '';
    } else if (m['type'] == 'call') {
      final c = CallInfo(
        state: m['state'] as String? ?? '', remote: m['remote'] as String? ?? '',
        name: m['name'] as String? ?? '', message: m['message'] as String? ?? '',
        incoming: m['incoming'] == true, muted: m['muted'] == true,
        speaker: m['speaker'] == true, paused: m['paused'] == true,
        duration: (m['duration'] as num?)?.toInt() ?? 0);
      if (c.ended) {
        historyVersion++;
        // Keep the ended call briefly so the call screen can show "Call ended".
        call = c;
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (call?.ended == true) { call = null; notifyListeners(); }
        });
      } else {
        call = c;
      }
    }
    notifyListeners();
  }

  // ---- commands ----
  Future<Map<String, dynamic>> status() async =>
      Map<String, dynamic>.from(await _method.invokeMethod('status') as Map);
  Future<void> login({required String domain, required String username, required String password,
      required String proxy, String? displayName}) =>
      _method.invokeMethod('login', {'domain': domain, 'username': username, 'password': password,
          'proxy': proxy, 'displayName': displayName});
  Future<void> logout() => _method.invokeMethod('logout');
  /// Returns 'emergency_native' when 911 was handed to the phone's own dialer.
  Future<String> dial(String target) async =>
      (await _method.invokeMethod('call', {'target': target}) as String?) ?? 'voip';

  /// 911 / 112 / 9911 — dialable even when not registered (goes to the phone's dialer).
  static bool isEmergency(String n) =>
      !n.trim().startsWith('sip:') && const {'911', '112', '9911'}.contains(n.replaceAll(RegExp(r'\D'), ''));
  Future<void> answer() => _method.invokeMethod('answer');
  Future<void> decline() => _method.invokeMethod('decline');
  Future<void> hangup() => _method.invokeMethod('hangup');
  Future<void> mute(bool on) => _method.invokeMethod('mute', {'on': on});
  Future<void> speaker(bool on) => _method.invokeMethod('speaker', {'on': on});
  Future<void> hold(bool on) => _method.invokeMethod('hold', {'on': on});
  Future<void> dtmf(String d) => _method.invokeMethod('dtmf', {'digit': d});
  Future<void> transfer(String target) => _method.invokeMethod('transfer', {'target': target});
  Future<void> refresh() => _method.invokeMethod('refresh');
  Future<void> clearCallLogs() async { await _method.invokeMethod('clearCallLogs'); historyVersion++; notifyListeners(); }
  Future<List<Map<String, dynamic>>> callLogs() async {
    final l = await _method.invokeMethod('callLogs') as List;
    return l.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
