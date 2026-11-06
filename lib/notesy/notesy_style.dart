import 'package:flutter/material.dart';

/// Foluma's approved palette. Notesy uses luma as its study accent so the AI
/// surface feels part of the same product instead of a separate purple app.
const Color kNotesyInk = Color(0xFF111214);
const Color kNotesyLuma = Color(0xFFFFC53D);
const Color kNotesyFold = Color(0xFFFFE08A);

BoxDecoration notesyInkPanel(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(28),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? const [Color(0xFF1C1D21), Color(0xFF111214)]
          : const [Color(0xFF1B1C20), kNotesyInk],
    ),
    border: Border.all(color: kNotesyLuma.withValues(alpha: 0.22)),
    boxShadow: [
      BoxShadow(
        color: kNotesyLuma.withValues(alpha: isDark ? 0.08 : 0.14),
        blurRadius: 30,
        offset: const Offset(0, 14),
      ),
    ],
  );
}

Widget notesyMark({double size = 48, bool dark = false}) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: kNotesyLuma,
      borderRadius: BorderRadius.circular(size * 0.28),
    ),
    child: Icon(
      Icons.auto_awesome_rounded,
      size: size * 0.54,
      color: kNotesyInk,
    ),
  );
}
