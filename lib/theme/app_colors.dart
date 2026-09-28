import 'package:flutter/material.dart';

/// ReadAlarm palette, sampled from the approved mockups.
class AppColors {
  AppColors._();

  // Brand
  static const Color navy = Color(0xFF1C2A55); // headers, primary text
  static const Color orange = Color(0xFFEF7A3B); // CTAs, active states
  static const Color orangeDark = Color(0xFFD9652A); // pressed / text on peach
  static const Color peach = Color(0xFFFDE8DA); // highlight cards, slider track
  static const Color peachBorder = Color(0xFFF7D2BC);

  // Surfaces
  static const Color cream = Color(0xFFFBF7F3); // scaffold background
  static const Color surface = Color(0xFFFFFFFF); // cards
  static const Color border = Color(0xFFEDE4DC);

  // Text
  static const Color textPrimary = Color(0xFF1A2342);
  static const Color textSecondary = Color(0xFF5B6275);
  static const Color textMuted = Color(0xFFA7ABB7);

  // Controls
  static const Color switchOff = Color(0xFFDADCE0);
  static const Color shadow = Color(0x14331A00); // warm, soft
}
