import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'theme.dart';

/// The phone's own address book (read-only).
class AddressBook {
  AddressBook._();
  static List<Contact>? _cache;

  /// Contacts that have at least one phone number. Null if permission denied.
  static Future<List<Contact>?> load({bool refresh = false}) async {
    if (!await FlutterContacts.requestPermission(readonly: true)) return null;
    if (_cache != null && !refresh) return _cache;
    final all = await FlutterContacts.getContacts(withProperties: true, withPhoto: false);
    _cache = all.where((c) => c.phones.isNotEmpty).toList()
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return _cache;
  }

  /// "+1 (903) 555-0100" -> "19035550100"; keeps short codes/extensions as typed.
  static String dialable(String raw) {
    final d = raw.replaceAll(RegExp(r'[^\d*#]'), '');
    return d;
  }

  /// Ask which number to use when a contact has several. Returns a dialable number.
  static Future<String?> pickNumber(BuildContext context, Contact c) async {
    if (c.phones.length == 1) return dialable(c.phones.first.number);
    return showModalBottomSheet<String>(context: context, builder: (ctx) => SafeArea(child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: Avatar(c.displayName), title: Text(c.displayName,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18))),
        const Divider(height: 1),
        for (final p in c.phones) ListTile(
          leading: const Icon(Icons.call, color: NL.purple),
          title: Text(fmtNumber(dialable(p.number))),
          subtitle: Text(_label(p)),
          onTap: () => Navigator.pop(ctx, dialable(p.number))),
        const SizedBox(height: 8),
      ])));
  }

  /// System contact picker (used from the dialpad).
  static Future<String?> pickFromSystem(BuildContext context) async {
    if (!await FlutterContacts.requestPermission(readonly: true)) return null;
    final picked = await FlutterContacts.openExternalPick();
    if (picked == null) return null;
    final full = await FlutterContacts.getContact(picked.id, withProperties: true) ?? picked;
    if (full.phones.isEmpty || !context.mounted) return null;
    return pickNumber(context, full);
  }

  /// Name for a number, if it's in the address book (for call history/caller ID).
  static String? nameFor(String number) {
    final want = _last10(number);
    if (want.length < 7 || _cache == null) return null;
    for (final c in _cache!) {
      for (final p in c.phones) { if (_last10(p.number) == want) return c.displayName; }
    }
    return null;
  }

  static String _last10(String n) {
    final d = n.replaceAll(RegExp(r'\D'), '');
    return d.length > 10 ? d.substring(d.length - 10) : d;
  }

  static String _label(Phone p) {
    final l = p.label == PhoneLabel.custom ? p.customLabel : p.label.name;
    return l.isEmpty ? 'Phone' : '${l[0].toUpperCase()}${l.substring(1)}';
  }
}
