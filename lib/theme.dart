import 'package:flutter/material.dart';

/// NovaLink brand palette (matches novalinkvoice.com and the portal).
class NL {
  static const purple = Color(0xFF7200BC);
  static const purpleDeep = Color(0xFF3D0F6E);
  static const magenta = Color(0xFFD900FF);
  static const cyan = Color(0xFF15E8FF);
  static const cyanDark = Color(0xFF00707C);
  static const ink = Color(0xFF1C1530);
  static const muted = Color(0xFF7A7592);
  static const line = Color(0xFFE3E2EE);
  static const bg = Color(0xFFF5F4FA);
  static const green = Color(0xFF1FAA59);
  static const red = Color(0xFFE5383B);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [purpleDeep, purple],
  );

  /// Call screen: all brand purple, deep at the top to bright at the bottom.
  static const callGradient = LinearGradient(
    begin: Alignment.topCenter, end: Alignment.bottomCenter,
    colors: [Color(0xFF2A0850), purpleDeep, purple],
    stops: [0.0, 0.45, 1.0],
  );

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(seedColor: purple, primary: purple, secondary: cyanDark,
        surface: Colors.white);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(backgroundColor: Colors.white, foregroundColor: ink,
          elevation: 0, scrolledUnderElevation: 1, centerTitle: false,
          titleTextStyle: TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w700)),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: purple.withValues(alpha: 0.12),
        iconTheme: WidgetStateProperty.resolveWith((s) =>
            IconThemeData(color: s.contains(WidgetState.selected) ? purple : muted)),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600,
            color: s.contains(WidgetState.selected) ? purple : muted)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: purple, foregroundColor: Colors.white),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: purple, width: 2)),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
          backgroundColor: purple, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
    );
  }
}

/// Round avatar with initials, colour picked from the name (Linphone-style).
class Avatar extends StatelessWidget {
  final String label;
  final double size;
  final Color? status;   // small presence dot (registration state on the account avatar)
  const Avatar(this.label, {super.key, this.size = 44, this.status});

  static const _palette = [NL.purple, NL.cyanDark, Color(0xFF5B2A86), Color(0xFF0B8793), Color(0xFF8E24AA)];

  String get _initials {
    final parts = label.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (RegExp(r'^[\d*#+]+$').hasMatch(parts.first)) return '#';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = _palette[label.hashCode.abs() % _palette.length];
    return SizedBox(
      width: size, height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        CircleAvatar(radius: size / 2, backgroundColor: c,
            child: Text(_initials, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.38))),
        if (status != null)
          Positioned(right: -1, bottom: -1, child: Container(
            width: size * 0.3, height: size * 0.3,
            decoration: BoxDecoration(color: status, shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2)))),
      ]),
    );
  }
}

String fmtDuration(int secs) {
  final h = secs ~/ 3600, m = (secs % 3600) ~/ 60, s = secs % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// "(903) 555-0100" for NANP numbers, otherwise as-is.
String fmtNumber(String n) {
  final d = n.replaceAll(RegExp(r'\D'), '');
  final ten = d.length == 11 && d.startsWith('1') ? d.substring(1) : d;
  if (ten.length == 10) return '(${ten.substring(0, 3)}) ${ten.substring(3, 6)}-${ten.substring(6)}';
  return n;
}
