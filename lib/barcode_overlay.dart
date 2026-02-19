// lib/barcode_overlay.dart - TAM OTOMATİK ADAPTİF SİSTEM (FİNAL)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'barcode_painter.dart' as custom_painter;
import 'scanned_item_model.dart';

class BarcodeOverlay extends StatefulWidget {
  const BarcodeOverlay({
    required this.boxFit,
    required this.controller,
    required this.currentShelfItems,
    super.key,
  });

  final BoxFit boxFit;
  final MobileScannerController controller;
  final List<ScannedItem> currentShelfItems;

  @override
  State<BarcodeOverlay> createState() => _BarcodeOverlayState();
}

class _BarcodeOverlayState extends State<BarcodeOverlay> {
  // 🧠 AKILLI HAFIZA SİSTEMİ
  final Map<String, DateTime> _barcodeHistory = {};
  final Map<String, List<Offset>> _barcodeCornersHistory = {};
  final Map<String, Size> _barcodeSizeHistory = {};
  Timer? _adaptiveTimer;

  // 🎯 ADAPTİF AYARLAR
  Duration _currentDisplayDuration = const Duration(milliseconds: 800);
  int _currentMaxBarcodes = 50;
  double _currentStrokeWidth = 2.5;

  // 📊 PERFORMANS METRİKLERİ
  int _totalBarcodesDetected = 0;
  DateTime _lastMetricsReset = DateTime.now();

  DeviceOrientation _currentOrientation = DeviceOrientation.portraitUp;
  List<Barcode> _currentFrameBarcodes = [];

  @override
  void initState() {
    super.initState();
    _startAdaptiveSystem();
    _detectOrientation();
  }

  void _detectOrientation() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final size = view.physicalSize;
    _currentOrientation = size.width > size.height
        ? DeviceOrientation.landscapeLeft
        : DeviceOrientation.portraitUp;
  }

  void _startAdaptiveSystem() {
    _adaptiveTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _cleanupOldBarcodes();
      _adaptToEnvironment();
      if (mounted) setState(() {});
    });
  }

  void _adaptToEnvironment() {
    final now = DateTime.now();
    final timeSinceReset = now.difference(_lastMetricsReset);

    // 🧠 HER 2 SANİYEDE BİR AYARLARI GÜNCELLE
    if (timeSinceReset > const Duration(seconds: 2)) {
      final barcodesPerSecond = _totalBarcodesDetected / timeSinceReset.inSeconds;

      // 🎯 BARKOD YOĞUNLUĞUNA GÖRE AYARLA
      if (barcodesPerSecond > 15) {
        // 🚀 YOĞUN ORTAM - PERFORMANS MODU
        _currentDisplayDuration = const Duration(milliseconds: 400);
        _currentMaxBarcodes = 15;
        _currentStrokeWidth = 2.0;
      } else if (barcodesPerSecond > 8) {
        // ⚡ ORTA YOĞUNLUK - DENGE MODU
        _currentDisplayDuration = const Duration(milliseconds: 600);
        _currentMaxBarcodes = 20;
        _currentStrokeWidth = 2.5;
      } else {
        // 🐢 DÜŞÜK YOĞUNLUK - DETAY MODU
        _currentDisplayDuration = const Duration(milliseconds: 1000);
        _currentMaxBarcodes = 25;
        _currentStrokeWidth = 3.0;
      }

      // 🧠 METRİKLERİ SIFIRLA
      _totalBarcodesDetected = 0;
      _lastMetricsReset = now;
    }
  }

  void _cleanupOldBarcodes() {
    final now = DateTime.now();

    // 🧠 AKILLI HAFIZA SÜRESİ - ORTAMA GÖRE DEĞİŞİR
    final memoryDuration = _currentDisplayDuration * 4;

    _barcodeHistory.removeWhere((key, timestamp) {
      return now.difference(timestamp) > memoryDuration;
    });

    _barcodeCornersHistory.removeWhere((key, corners) => !_barcodeHistory.containsKey(key));
    _barcodeSizeHistory.removeWhere((key, size) => !_barcodeHistory.containsKey(key));
  }

  void _updateBarcodeHistory(Barcode barcode) {
    final rawValue = barcode.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    _barcodeHistory[rawValue] = DateTime.now();
    _barcodeCornersHistory[rawValue] = barcode.corners;
    _barcodeSizeHistory[rawValue] = barcode.size;

    // 🧠 PERFORMANS METRİKLERİNİ GÜNCELLE
    _totalBarcodesDetected++;

    // 🎯 AKILLI LİMİT YÖNETİMİ
    if (_barcodeHistory.length > _currentMaxBarcodes) {
      final oldestEntries = _barcodeHistory.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      final itemsToRemove = (_barcodeHistory.length - _currentMaxBarcodes).clamp(1, 10);

      for (int i = 0; i < itemsToRemove; i++) {
        final keyToRemove = oldestEntries[i].key;
        _barcodeHistory.remove(keyToRemove);
        _barcodeCornersHistory.remove(keyToRemove);
        _barcodeSizeHistory.remove(keyToRemove);
      }
    }
  }

  List<Barcode> _getAllVisibleBarcodes() {
    final allBarcodes = <Barcode>[];
    final now = DateTime.now();

    // 🎯 MEVCUT FRAME'DEKİ BARKODLAR
    allBarcodes.addAll(_currentFrameBarcodes);

    // 🧠 HAFIZADAKİ BARKODLARI DA EKLE (Adaptif süreye göre)
    for (final entry in _barcodeHistory.entries) {
      final barcodeValue = entry.key;
      final timestamp = entry.value;

      if (now.difference(timestamp) <= _currentDisplayDuration &&
          !_currentFrameBarcodes.any((b) => b.rawValue == barcodeValue)) {

        final corners = _barcodeCornersHistory[barcodeValue];
        final size = _barcodeSizeHistory[barcodeValue];

        if (corners != null && corners.isNotEmpty && size != null) {
          final persistentBarcode = Barcode(
            rawValue: barcodeValue,
            format: BarcodeFormat.qrCode,
            corners: corners,
            size: size,
          );
          allBarcodes.add(persistentBarcode);
        }
      }
    }

    return allBarcodes;
  }

  @override
  void dispose() {
    _adaptiveTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.controller,
      builder: (context, value, child) {
        if (!value.isInitialized || !value.isRunning || value.error != null) {
          return const SizedBox();
        }

        return StreamBuilder<BarcodeCapture>(
          stream: widget.controller.barcodes,
          builder: (context, snapshot) {
            final BarcodeCapture? barcodeCapture = snapshot.data;

            if (barcodeCapture == null || barcodeCapture.size.isEmpty) {
              _currentFrameBarcodes = [];
              return const SizedBox();
            }

            // 🎯 GEÇERLİ BARKODLARI AL (frame-içi deduplikasyon dahil)
            final seen = <String>{};
            _currentFrameBarcodes = barcodeCapture.barcodes.where((barcode) {
              return barcode.rawValue != null &&
                     barcode.rawValue!.isNotEmpty &&
                     !barcode.size.isEmpty &&
                     barcode.corners.isNotEmpty &&
                     seen.add(barcode.rawValue!);
            }).toList();

            // 🧠 HAFIZAYI GÜNCELLE
            for (final barcode in _currentFrameBarcodes) {
              _updateBarcodeHistory(barcode);
            }

            // Cihaz yönünü güncelle
            _updateOrientation();

            // 🎯 TÜM GÖRÜNÜR BARKODLARI AL
            final allVisibleBarcodes = _getAllVisibleBarcodes();

            // 🧠 ADAPTİF LİMİT UYGULA
            final displayedBarcodes = allVisibleBarcodes.length > _currentMaxBarcodes
                ? allVisibleBarcodes.sublist(0, _currentMaxBarcodes)
                : allVisibleBarcodes;

            final overlays = <Widget>[
              for (final Barcode barcode in displayedBarcodes)
                CustomPaint(
                  painter: custom_painter.BarcodePainter(
                    barcodeCorners: barcode.corners,
                    barcodeSize: barcode.size,
                    boxFit: widget.boxFit,
                    cameraPreviewSize: barcodeCapture.size,
                    color: _getBarcodeColor(barcode.rawValue ?? ''),
                    style: PaintingStyle.stroke,
                    deviceOrientation: _currentOrientation,
                    strokeWidth: _currentStrokeWidth,
                  ),
                ),
            ];

            return Stack(fit: StackFit.expand, children: overlays);
          },
        );
      },
    );
  }

  void _updateOrientation() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final size = view.physicalSize;
    final newOrientation = size.width > size.height
        ? DeviceOrientation.landscapeLeft
        : DeviceOrientation.portraitUp;

    if (newOrientation != _currentOrientation) {
      setState(() {
        _currentOrientation = newOrientation;
      });
    }
  }

  Color _getBarcodeColor(String barcodeValue) {
    if (barcodeValue.isEmpty) return Colors.green;

    final isSuccessfullyScanned = widget.currentShelfItems.any(
      (ScannedItem item) => item.barcode == barcodeValue && item.isQR && item.success
    );

    if (isSuccessfullyScanned) {
      return Colors.red; // 🔴 OKUNMUŞ
    }
    else {
      return Colors.green; // 🟢 YENİ VEYA OKUNUYOR
    }
  }
}
