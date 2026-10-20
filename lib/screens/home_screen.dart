import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../address_book.dart';
import '../phone.dart';
import '../portal.dart';
import '../theme.dart';
import 'call_screen.dart';
import 'dialpad.dart';
import 'login_screen.dart';

/// Main shell, Linphone layout: account avatar + status up top, Calls /
/// Contacts / Voicemail tabs below, dialpad button bottom-right. Any live call
/// takes over the screen.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final p = PhoneState.I;
  int _tab = 0;
  bool _callShown = false;
  Map<String, dynamic> _me = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    p.addListener(_changed);
    p.status().then((s) { if (mounted) setState(() => _me = s); });
    WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
  }

  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); p.removeListener(_changed); super.dispose(); }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) { if (s == AppLifecycleState.resumed) p.refresh(); }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    final c = p.call;
    if (c != null && !c.ended && !_callShown) {
      _callShown = true;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CallScreen(), fullscreenDialog: true))
          .then((_) => _callShown = false);
    }
  }

  Future<void> _dial([String? number]) async {
    final n = number ?? await showModalBottomSheet<String>(context: context, isScrollControlled: true,
        showDragHandle: false, builder: (_) => DialpadSheet(registered: p.registered));
    if (n == null || n.isEmpty) return;
    final how = await p.dial(n);
    if (how == 'emergency_native' && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        duration: Duration(seconds: 8),
        content: Text('Emergency calls use your phone\'s own dialer so 911 receives your '
            'location. Tap the green call button there.')));
    }
  }

  Color get _statusColor => p.registered ? NL.green : p.registering ? Colors.amber : NL.red;
  String get _statusText => p.registered ? 'Ready for calls' : p.registering ? 'Connecting…'
      : p.registration == 'Failed' ? 'Not connected — tap to retry' : 'Offline';

  void _account() => showModalBottomSheet(context: context, builder: (ctx) => SafeArea(child: Padding(
    padding: const EdgeInsets.all(20),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Avatar(_name, size: 56, status: _statusColor),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          Text('Extension ${_me['user'] ?? ''}', style: const TextStyle(color: NL.muted)),
          Text(_statusText, style: TextStyle(color: _statusColor, fontWeight: FontWeight.w600)),
        ])),
      ]),
      const SizedBox(height: 20),
      OutlinedButton.icon(icon: const Icon(Icons.refresh), label: const Text('Reconnect'),
          onPressed: () { p.refresh(); Navigator.pop(ctx); }),
      const SizedBox(height: 8),
      OutlinedButton.icon(icon: const Icon(Icons.logout, color: NL.red),
          label: const Text('Sign out', style: TextStyle(color: NL.red)),
          onPressed: () async {
            await p.logout(); await Portal.I.signOut();
            if (!ctx.mounted) return;
            Navigator.of(ctx).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
          }),
    ]),
  )));

  String get _name {
    final n = (_me['name'] as String?) ?? '';
    return n.isNotEmpty ? n : 'Extension ${_me['user'] ?? ''}';
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      CallsTab(onDial: _dial),
      ContactsTab(onDial: _dial),
      VoicemailTab(onDial: _dial),
    ];
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: InkWell(
          onTap: _account,
          borderRadius: BorderRadius.circular(30),
          child: Row(children: [
            Avatar(_name, size: 40, status: _statusColor),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
              Text(_statusText, style: TextStyle(fontSize: 12, color: _statusColor, fontWeight: FontWeight.w600)),
            ])),
          ]),
        ),
        actions: [if (_tab == 0) PopupMenuButton<String>(
          onSelected: (v) { if (v == 'clear') p.clearCallLogs(); },
          itemBuilder: (_) => const [PopupMenuItem(value: 'clear', child: Text('Clear call history'))])],
      ),
      body: IndexedStack(index: _tab, children: tabs),
      floatingActionButton: FloatingActionButton.large(
        heroTag: 'pad', onPressed: () => _dial(), shape: const CircleBorder(),
        child: const Icon(Icons.dialpad, size: 34)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.history), label: 'Calls'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Contacts'),
          NavigationDestination(icon: Icon(Icons.voicemail), label: 'Voicemail'),
        ],
      ),
    );
  }
}

String _ago(int epochSecs) {
  final t = DateTime.fromMillisecondsSinceEpoch(epochSecs * 1000);
  final now = DateTime.now();
  if (now.difference(t).inDays == 0 && t.day == now.day) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  }
  if (now.difference(t).inDays < 7) return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][t.weekday - 1];
  return '${t.month}/${t.day}';
}

Widget _empty(IconData icon, String title, String sub) => Center(child: Padding(
  padding: const EdgeInsets.all(32),
  child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 56, color: NL.purple.withValues(alpha: 0.35)),
    const SizedBox(height: 12),
    Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
    const SizedBox(height: 4),
    Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: NL.muted)),
  ]),
));

// ---------------- Calls ----------------

class CallsTab extends StatefulWidget {
  final Future<void> Function([String?]) onDial;
  const CallsTab({super.key, required this.onDial});
  @override
  State<CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends State<CallsTab> {
  List<Map<String, dynamic>> _logs = [];
  int _ver = -1;

  @override
  void initState() { super.initState(); PhoneState.I.addListener(_maybeReload); _load(); }
  @override
  void dispose() { PhoneState.I.removeListener(_maybeReload); super.dispose(); }

  void _maybeReload() { if (PhoneState.I.historyVersion != _ver) _load(); }
  Future<void> _load() async {
    _ver = PhoneState.I.historyVersion;
    final l = await PhoneState.I.callLogs();
    if (mounted) setState(() => _logs = l);
  }

  @override
  Widget build(BuildContext context) {
    if (_logs.isEmpty) return _empty(Icons.history, 'No calls yet', 'Calls you make and receive show up here.');
    return RefreshIndicator(onRefresh: _load, child: ListView.separated(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: _logs.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
      itemBuilder: (_, i) {
        final l = _logs[i];
        final remote = l['remote'] as String;
        final sipName = (l['name'] as String?) ?? '';
        final name = sipName.isNotEmpty ? sipName : (AddressBook.nameFor(remote) ?? '');
        final missed = l['incoming'] == true && l['status'] != 'Success';
        final icon = l['incoming'] == true ? (missed ? Icons.call_missed : Icons.call_received) : Icons.call_made;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          leading: Avatar(name.isNotEmpty ? name : remote),
          title: Text(name.isNotEmpty ? name : fmtNumber(remote),
              style: TextStyle(fontWeight: FontWeight.w600, color: missed ? NL.red : NL.ink)),
          subtitle: Row(children: [
            Icon(icon, size: 15, color: missed ? NL.red : NL.cyanDark),
            const SizedBox(width: 4),
            Text(name.isNotEmpty ? fmtNumber(remote) : (missed ? 'Missed' : l['incoming'] == true ? 'Incoming' : 'Outgoing'),
                style: const TextStyle(color: NL.muted)),
          ]),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_ago((l['start'] as num).toInt()), style: const TextStyle(color: NL.muted, fontSize: 12)),
            IconButton(icon: const Icon(Icons.call, color: NL.purple), onPressed: () => widget.onDial(remote)),
          ]),
          onTap: () => widget.onDial(remote),
        );
      },
    ));
  }
}

// ---------------- Contacts: company directory + phone address book ----------------

class ContactsTab extends StatefulWidget {
  final Future<void> Function([String?]) onDial;
  const ContactsTab({super.key, required this.onDial});
  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> {
  List<Map<String, dynamic>>? _dir;
  List<Contact>? _phone;
  bool _phoneDenied = false, _phoneLoading = false;
  String _q = '', _err = '';
  int _src = 1;   // 0 = company, 1 = phone (most people want their own contacts)

  @override
  void initState() { super.initState(); _loadDir(); _loadPhone(); }

  Future<void> _loadDir() async {
    try { final d = await Portal.I.directory(); if (mounted) setState(() { _dir = d; _err = ''; }); }
    catch (e) { if (mounted) setState(() { _dir ??= []; _err = e.toString(); }); }
  }

  Future<void> _loadPhone({bool refresh = false}) async {
    setState(() => _phoneLoading = true);
    final c = await AddressBook.load(refresh: refresh);
    if (mounted) setState(() { _phone = c ?? []; _phoneDenied = c == null; _phoneLoading = false; });
  }

  bool _match(String name, String number) {
    if (_q.isEmpty || name.toLowerCase().contains(_q)) return true;
    final qd = _q.replaceAll(RegExp(r'\D'), '');
    return qd.isNotEmpty && number.replaceAll(RegExp(r'\D'), '').contains(qd);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: TextField(
        decoration: const InputDecoration(hintText: 'Search name or number', prefixIcon: Icon(Icons.search), isDense: true),
        onChanged: (v) => setState(() => _q = v.trim().toLowerCase()))),
      Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 4), child: SizedBox(width: double.infinity,
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(selectedBackgroundColor: NL.purple, selectedForegroundColor: Colors.white),
          segments: const [
            ButtonSegment(value: 1, icon: Icon(Icons.contact_phone_outlined), label: Text('My contacts')),
            ButtonSegment(value: 0, icon: Icon(Icons.business), label: Text('Company')),
          ],
          selected: {_src},
          onSelectionChanged: (v) => setState(() => _src = v.first)))),
      Expanded(child: _src == 0 ? _company() : _phoneList()),
    ]);
  }

  Widget _company() {
    if (_dir == null) return const Center(child: CircularProgressIndicator());
    final list = _dir!.where((e) => _match(e['name'] as String, e['extension'] as String)).toList();
    if (list.isEmpty) {
      return _empty(Icons.business, _err.isNotEmpty ? "Couldn't load your company" : 'No one here yet',
          _err.isNotEmpty ? 'Pull down to try again.' : 'People in your company appear here.');
    }
    return RefreshIndicator(onRefresh: _loadDir, child: ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final e = list[i];
        return ListTile(
          leading: Avatar(e['name'] as String),
          title: Text(e['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('Ext ${e['extension']}', style: const TextStyle(color: NL.muted)),
          trailing: IconButton(icon: const Icon(Icons.call, color: NL.purple),
              onPressed: () => widget.onDial(e['extension'] as String)),
          onTap: () => widget.onDial(e['extension'] as String),
        );
      }));
  }

  Widget _phoneList() {
    if (_phoneDenied) {
      return Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.contact_phone_outlined, size: 56, color: NL.purple.withValues(alpha: 0.35)),
        const SizedBox(height: 12),
        const Text('Call your contacts', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text("Allow access to your phone's contacts to call them from NovaLink Voice. "
            "They stay on your phone.", textAlign: TextAlign.center, style: TextStyle(color: NL.muted)),
        const SizedBox(height: 16),
        FilledButton(onPressed: () => _loadPhone(refresh: true), child: const Text('Allow contacts')),
      ])));
    }
    if (_phone == null || _phoneLoading && _phone!.isEmpty) return const Center(child: CircularProgressIndicator());
    final list = _phone!.where((c) => _match(c.displayName, c.phones.map((p) => p.number).join(' '))).toList();
    if (list.isEmpty) return _empty(Icons.contact_phone_outlined, 'No matches', 'Try a different name or number.');
    return RefreshIndicator(onRefresh: () => _loadPhone(refresh: true), child: ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final c = list[i];
        final first = c.phones.first.number;
        return ListTile(
          leading: Avatar(c.displayName),
          title: Text(c.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(c.phones.length > 1 ? '${fmtNumber(AddressBook.dialable(first))} · +${c.phones.length - 1} more'
              : fmtNumber(AddressBook.dialable(first)), style: const TextStyle(color: NL.muted)),
          trailing: IconButton(icon: const Icon(Icons.call, color: NL.purple), onPressed: () => _call(c)),
          onTap: () => _call(c),
        );
      }));
  }

  Future<void> _call(Contact c) async {
    final n = await AddressBook.pickNumber(context, c);
    if (n != null && n.isNotEmpty) await widget.onDial(n);
  }
}

// ---------------- Voicemail ----------------

class VoicemailTab extends StatefulWidget {
  final Future<void> Function([String?]) onDial;
  const VoicemailTab({super.key, required this.onDial});
  @override
  State<VoicemailTab> createState() => _VoicemailTabState();
}

class _VoicemailTabState extends State<VoicemailTab> {
  List<Map<String, dynamic>>? _vms;
  final _player = AudioPlayer();
  String? _playing;
  String _err = '';

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) { if (mounted) setState(() => _playing = null); });
    _load();
  }
  @override
  void dispose() { _player.dispose(); super.dispose(); }

  Future<void> _load() async {
    try { final v = await Portal.I.voicemails(); if (mounted) setState(() { _vms = v; _err = ''; }); }
    catch (e) { if (mounted) setState(() { _vms ??= []; _err = e.toString(); }); }
  }

  Future<void> _play(Map<String, dynamic> vm) async {
    final id = vm['id'] as String;
    if (_playing == id) { await _player.stop(); setState(() => _playing = null); return; }
    setState(() => _playing = id);
    try {
      final path = await Portal.I.voicemailFile(id);
      await _player.play(DeviceFileSource(path));
      if (vm['read'] != true) { Portal.I.markRead(id); vm['read'] = true; }
    } catch (e) {
      if (!mounted) return;
      setState(() => _playing = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't play voicemail: $e")));
    }
  }

  Future<void> _delete(Map<String, dynamic> vm) async {
    try { await Portal.I.deleteVoicemail(vm['id'] as String); setState(() => _vms!.remove(vm)); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e'))); }
  }

  @override
  Widget build(BuildContext context) {
    if (_vms == null) return const Center(child: CircularProgressIndicator());
    if (_vms!.isEmpty) {
      return RefreshIndicator(onRefresh: _load, child: ListView(children: [
        SizedBox(height: 420, child: _empty(Icons.voicemail, _err.isNotEmpty ? "Couldn't load voicemail" : 'No voicemail',
            _err.isNotEmpty ? 'Pull down to try again.' : 'Messages people leave you appear here.')),
      ]));
    }
    return RefreshIndicator(onRefresh: _load, child: ListView.separated(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: _vms!.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
      itemBuilder: (_, i) {
        final vm = _vms![i];
        final num = (vm['caller_id_number'] as String?) ?? '';
        final name = (vm['caller_id_name'] as String?) ?? '';
        final unread = vm['read'] != true;
        final t = vm['created_epoch'] as int?;
        return Dismissible(
          key: ValueKey(vm['id']),
          direction: DismissDirection.endToStart,
          background: Container(color: NL.red, alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24), child: const Icon(Icons.delete, color: Colors.white)),
          onDismissed: (_) => _delete(vm),
          child: ListTile(
            leading: Avatar(name.isNotEmpty ? name : num),
            title: Text(name.isNotEmpty && name != num ? name : fmtNumber(num),
                style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w500)),
            subtitle: Text([
              if (t != null) _ago(t),
              if (vm['length_seconds'] != null) fmtDuration(vm['length_seconds'] as int),
              if ((vm['transcription'] as String?)?.isNotEmpty == true) '“${vm['transcription']}”',
            ].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: NL.muted)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: Icon(_playing == vm['id'] ? Icons.stop_circle : Icons.play_circle_fill,
                  color: NL.purple, size: 32), onPressed: () => _play(vm)),
              if (num.isNotEmpty) IconButton(icon: const Icon(Icons.call, color: NL.cyanDark),
                  onPressed: () => widget.onDial(num)),
            ]),
          ),
        );
      },
    ));
  }
}
