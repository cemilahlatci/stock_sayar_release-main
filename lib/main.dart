// lib/main.dart
import 'dart:developer';
import 'package:flutter/material.dart';
import 'login_page.dart';

void main() {
  // ⚡ Fix 19: Global hata yakalayıcı
  FlutterError.onError = (FlutterErrorDetails details) {
    log('Flutter Error: ${details.exceptionAsString()}', name: 'GlobalError');
    FlutterError.presentError(details);
  };

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stok Sayım Sistemi',
      theme: ThemeData(
        // ⚡ Fix 18: ColorScheme kullanımı (primarySwatch deprecated)
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0EA14B)),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      home: const LoginPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
