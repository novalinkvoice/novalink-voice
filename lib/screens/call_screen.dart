import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../address_book.dart';
import '../phone.dart';
import '../theme.dart';
import 'dialpad.dart';

/// Full-screen call UI (incoming, outgoing and active), Linphone-style layout.
/// Pops itself when the call is gone.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key});
  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final p = PhoneState.I;
  Timer? _tick;
  int _secs = 0;
  bool _keypad = false;
  String _dtmf = '';
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    p.addListener(_changed);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (p.call?.connected == true && mounted) setState(() => _secs++);
    });
    _secs = p.call?.duration ?? 0;
  }

  void _changed() {
    final c = p.call;
    if (c == null && !_popped && mounted) { _popped = true; Navigator.of(context).maybePop(); return; }
    if (c != null && c.duration > _secs) _secs = c.duration;
    if (mounted) setState(() {});
  }

  @override
  void dispose() { p.removeListener(_changed); _tick?.cancel(); super.dispose(); }

  String _status(CallInfo c) {
    if (c.ended) return c.message.isNotEmpty && c.state == 'Error' ? c.message : 'Call ended';
    if (c.ringing) return 'Incoming call';
    if (c.paused) return 'On hold · ${fmtDuration(_secs)}';
    if (c.connected) return fmtDuration(_secs);
    if (c.state == 'OutgoingRinging') return 'Ringing…';
    return 'Calling…';
  }

  Future<void> _transfer() async {
    final ctl = TextEditingController();
    final to = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Transfer call'),
      content: TextField(controller: ctl, autofocus: true, keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Extension or number')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Transfer')),
      ],
    ));
    if (to != null && to.isNotEmpty) p.transfer(to);
  }

  @override
  Widget build(BuildContext context) {
    final c = p.call;
    if (c == null) return const Scaffold(backgroundColor: NL.purpleDeep);
    final name = c.name.isNotEmpty ? c.name : (AddressBook.nameFor(c.remote) ?? '');
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent,
          systemNavigationBarColor: NL.purple),
      child: PopScope(
      canPop: c.ended,   // back button doesn't drop a live call
      child: Scaffold(
        backgroundColor: NL.purpleDeep,
        body: Container(
          width: double.infinity, height: double.infinity,
          decoration: const BoxDecoration(gradient: NL.callGradient),
          child: SafeArea(child: Column(children: [
            const SizedBox(height: 28),
            Text(_status(c), style: TextStyle(color: c.ringing ? NL.cyan : Colors.white70, fontSize: 16,
                fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            const SizedBox(height: 28),
            if (!_keypad) ...[
              Avatar(name.isNotEmpty ? name : c.remote, size: 128),
              const SizedBox(height: 20),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Text(
                  name.isNotEmpty ? name : fmtNumber(c.remote), textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700))),
              if (name.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6),
                  child: Text(fmtNumber(c.remote), style: const TextStyle(color: Colors.white60, fontSize: 16))),
              const Spacer(),
            ] else ...[
              Text(_dtmf.isEmpty ? ' ' : _dtmf, style: const TextStyle(color: Colors.white, fontSize: 30, letterSpacing: 2)),
              const SizedBox(height: 16),
              KeyGrid(dark: true, onKey: (k) { setState(() => _dtmf += k); p.dtmf(k); }),
              const Spacer(),
            ],
            if (c.ringing) _incomingActions() else _activeActions(c),
            const SizedBox(height: 36),
          ])),
        ),
      ),
    ));
  }

  Widget _incomingActions() => Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
    _bigButton(Icons.call_end, NL.red, 'Decline', p.decline),
    _bigButton(Icons.call, NL.green, 'Answer', p.answer),
  ]);

  Widget _activeActions(CallInfo c) => Column(children: [
    if (c.connected) Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _toggle(c.muted ? Icons.mic_off : Icons.mic, 'Mute', c.muted, () => p.mute(!c.muted)),
        _toggle(Icons.volume_up, 'Speaker', c.speaker, () => p.speaker(!c.speaker)),
        _toggle(Icons.dialpad, 'Keypad', _keypad, () => setState(() => _keypad = !_keypad)),
        _toggle(c.paused ? Icons.play_arrow : Icons.pause, c.paused ? 'Resume' : 'Hold', c.paused, () => p.hold(!c.paused)),
        _toggle(Icons.phone_forwarded, 'Transfer', false, _transfer),
      ]),
    ),
    const SizedBox(height: 28),
    _bigButton(Icons.call_end, NL.red, c.ended ? 'Ended' : 'End call', c.ended ? null : p.hangup),
  ]);

  Widget _toggle(IconData icon, String label, bool on, VoidCallback onTap) => Column(children: [
    Material(
      color: on ? Colors.white : Colors.white.withValues(alpha: 0.14), shape: const CircleBorder(),
      child: InkWell(customBorder: const CircleBorder(), onTap: onTap,
          child: SizedBox(width: 56, height: 56, child: Icon(icon, color: on ? NL.purple : Colors.white))),
    ),
    const SizedBox(height: 6),
    Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
  ]);

  Widget _bigButton(IconData icon, Color color, String label, VoidCallback? onTap) => Column(children: [
    SizedBox(width: 76, height: 76, child: FloatingActionButton(
      heroTag: label, backgroundColor: color, shape: const CircleBorder(), elevation: 0,
      onPressed: onTap, child: Icon(icon, size: 34, color: Colors.white))),
    const SizedBox(height: 8),
    Text(label, style: const TextStyle(color: Colors.white70)),
  ]);
}
