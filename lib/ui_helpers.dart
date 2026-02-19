// lib/ui_helpers.dart - Ortak UI yardımcıları ve tema sabitleri

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────
// UYGULAMA RENK SABİTLERİ
// ─────────────────────────────────────────────
class AppColors {
  AppColors._();

  // Arka planlar
  static const Color scaffoldBackground = Color(0xFF212121);   // Colors.grey[900]
  static const Color cardBackground = Color(0xFF424242);       // Colors.grey[800]
  static const Color listItemBackground = Color(0xFF616161);   // Colors.grey[700]
  static const Color appBarBackground = Colors.black;

  // Metin renkleri
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xB3FFFFFF);        // Colors.white70
  static const Color textHint = Color(0xFF9E9E9E);             // Colors.grey
  static const Color textSubtle = Color(0xFF757575);           // Colors.grey[600]
  static const Color textMuted = Color(0xFFBDBDBD);            // Colors.grey[400]
  static const Color textDimmed = Color(0xFF9E9E9E);           // Colors.grey[500]

  // Durum renkleri
  static const Color success = Colors.green;
  static const Color error = Colors.red;
  static const Color warning = Colors.orange;
  static const Color info = Colors.blue;

  // Özel renkler
  static Color get shelfAccent => Colors.orange[400]!;
}

// ─────────────────────────────────────────────
// SNACKBAR MİXİN
// ─────────────────────────────────────────────
mixin SnackBarMixin<T extends StatefulWidget> on State<T> {
  void showAppSnackBar(String message, {bool isError = false, Duration? duration}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        duration: duration ?? const Duration(seconds: 2),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// TARİH/ZAMAN YARDIMCILARI
// ─────────────────────────────────────────────
class DateTimeHelper {
  DateTimeHelper._();

  /// ISO 8601 formatında zaman damgası: "2025-01-15T14:30:00.000"
  static String nowIso8601() => DateTime.now().toIso8601String();

  /// Dosya adı uyumlu zaman damgası: "20250115143000"
  static String nowFileTimestamp() {
    final now = DateTime.now();
    return '${now.year}'
        '${_pad(now.month)}'
        '${_pad(now.day)}'
        '${_pad(now.hour)}'
        '${_pad(now.minute)}'
        '${_pad(now.second)}';
  }

  /// Kısa dosya adı zaman damgası: "202501151430" (saniyesiz)
  static String nowShortTimestamp() {
    final now = DateTime.now();
    return '${now.year}'
        '${_pad(now.month)}'
        '${_pad(now.day)}'
        '${_pad(now.hour)}'
        '${_pad(now.minute)}';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
