import 'package:flutter/material.dart';
import '../address_book.dart';
import '../phone.dart';
import '../theme.dart';

const _keys = [
  ['1', ''], ['2', 'ABC'], ['3', 'DEF'],
  ['4', 'GHI'], ['5', 'JKL'], ['6', 'MNO'],
  ['7', 'PQRS'], ['8', 'TUV'], ['9', 'WXYZ'],
  ['*', ''], ['0', '+'], ['#', ''],
];

/// 12-key grid. Used for dialling (with a number display) and in-call DTMF.
class KeyGrid extends StatelessWidget {
  final void Function(String) onKey;
  final bool dark;
  const KeyGrid({super.key, required this.onKey, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : NL.ink;
    return GridView.count(
      crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 14, crossAxisSpacing: 26, childAspectRatio: 1.25,
      padding: const EdgeInsets.symmetric(horizontal: 36),
      children: [
        for (final k in _keys)
          Material(
            color: dark ? Colors.white.withValues(alpha: 0.12) : NL.purple.withValues(alpha: 0.07),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onKey(k[0]),
              onLongPress: k[0] == '0' ? () => onKey('+') : null,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(k[0], style: TextStyle(fontSize: 28, fontWeight: FontWeight.w500, color: fg)),
                if (k[1].isNotEmpty)
                  Text(k[1], style: TextStyle(fontSize: 10, letterSpacing: 1.5,
                      color: dark ? Colors.white60 : NL.muted)),
              ]),
            ),
          ),
      ],
    );
  }
}

/// Bottom-sheet dialer. Returns the number to call (or null).
class DialpadSheet extends StatefulWidget {
  final bool registered;
  const DialpadSheet({super.key, required this.registered});
  @override
  State<DialpadSheet> createState() => _DialpadSheetState();
}

class _DialpadSheetState extends State<DialpadSheet> {
  String _num = '';

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, decoration: BoxDecoration(color: NL.line, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 12, 12),
          child: Row(children: [
            const SizedBox(width: 48),
            Expanded(child: Text(_num.isEmpty ? 'Enter a number' : fmtNumber(_num),
                textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: _num.isEmpty ? 18 : 30, fontWeight: FontWeight.w500,
                    color: _num.isEmpty ? NL.muted : NL.ink))),
            SizedBox(width: 48, child: _num.isEmpty ? null : IconButton(
                icon: const Icon(Icons.backspace_outlined, color: NL.muted),
                onPressed: () => setState(() => _num = _num.substring(0, _num.length - 1)),
                onLongPress: () => setState(() => _num = ''))),
          ]),
        ),
        KeyGrid(onKey: (k) => setState(() => _num += k)),
        const SizedBox(height: 18),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(width: 72, child: IconButton(
          tooltip: 'Contacts', iconSize: 30,
          icon: const Icon(Icons.contacts_outlined, color: NL.purple),
          onPressed: () async {
            final n = await AddressBook.pickFromSystem(context);
            if (n != null && mounted) setState(() => _num = n);
          })),
        const SizedBox(width: 24),
        SizedBox(width: 72, height: 72, child: FloatingActionButton(
          heroTag: 'dial',
          backgroundColor: widget.registered || PhoneState.isEmergency(_num) ? NL.green : NL.muted,
          shape: const CircleBorder(),
          // 911 always dials (it goes to the phone's own dialer, no registration needed).
          onPressed: _num.isEmpty || !(widget.registered || PhoneState.isEmergency(_num))
              ? null : () => Navigator.pop(context, _num),
          child: const Icon(Icons.call, size: 32))),
        const SizedBox(width: 96),
        ]),
        if (!widget.registered) const Padding(padding: EdgeInsets.only(top: 10),
            child: Text('Connecting to NovaLink Voice…', style: TextStyle(color: NL.muted))),
      ]),
    ));
  }
}
