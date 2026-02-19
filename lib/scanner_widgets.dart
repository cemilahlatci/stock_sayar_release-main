// lib/scanner_widgets.dart - OPTİMİZE EDİLMİŞ VERSİYON
// ⚡ 1D MOD: NO DUPLICATE CONTROL | 🚀 QR MOD: FULL DUPLICATE CONTROL
import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'scanned_item_model.dart';
import 'ilac_manager.dart';
import 'barcode_overlay.dart' as custom_overlay;
import 'gs1_parser.dart';
import 'database_helper.dart';
import 'ui_helpers.dart';

enum ScannerMode {
  otcBarkod,    // Sadece 1D barkod - HIZLI MOD
  ilacQr,       // Tüm QR/Data Matrix - Dynamsoft style real-time
}

enum ScannerPriority {
  maxPerformance,
  balanced,
  batterySaver
}

class ScannerConstants {
  // QR Modu Duplicate Prevention
  static const maxRapidScans = 3;
  static const Duration rapidTimeWindow = Duration(seconds: 2);
  static const Duration ilacUyariGecmisSuresi = Duration(seconds: 3);
  static const Duration expiredWarningCooldown = Duration(minutes: 10);
  
  // Performance Settings
  static const int maxBarcodesToProcess = 20;
  // Timers
  static const Duration duplicateCleanupInterval = Duration(seconds: 30);
  static const Duration rapidDuplicateCleanupInterval = Duration(seconds: 10);
  static const Duration adaptiveCleanupInterval = Duration(seconds: 10);
  static const Duration expiredWarningAutoClose = Duration(seconds: 10);

  // Scanner Settings
  static const Duration scannerRestartDelay = Duration(milliseconds: 300);
  static const Duration cameraRecoveryDelay = Duration(milliseconds: 500);
  static const Duration min1DBarcodeInterval = Duration(milliseconds: 50);
}

class UnifiedScannerWidget extends StatefulWidget {
  final Function(String barcode, bool isQR, int quantity, {
    String? urunAdi,
    String? urunTipi,
    String? sonKullanmaTarihi,
    String? partiNo
  }) onBarcodeDetected;
  final List<ScannedItem> currentShelfItems;
  final String currentShelfCode;
  final Function(String)? onShelfCodeDetected;
  final bool waitingForShelfCode;
  final bool miadUyarisiAktif;

  const UnifiedScannerWidget({
    super.key,
    required this.onBarcodeDetected,
    required this.currentShelfItems,
    required this.currentShelfCode,
    this.onShelfCodeDetected,
    this.waitingForShelfCode = false,
    this.miadUyarisiAktif = true,
  });
  
  @override
  State<UnifiedScannerWidget> createState() => _UnifiedScannerWidgetState();
}

class _UnifiedScannerWidgetState extends State<UnifiedScannerWidget>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin, SnackBarMixin {
  
  @override
  bool get wantKeepAlive => true;
  
  MobileScannerController? controller;
  StreamSubscription<BarcodeCapture>? _barcodeSubscription;
  
  bool isTorchOn = false;
  bool _isControllerInitializing = false;
  bool _isDisposed = false;
  bool _timersStarted = false;
  
  ScannerMode _currentScannerMode = ScannerMode.otcBarkod;
  
  ScannerPriority _currentPriority = ScannerPriority.maxPerformance;
  final Battery _battery = Battery();
  Timer? _batteryPriorityTimer;
  
  late SharedPreferences _prefs;
  bool _prefsLoaded = false;
  
  // ⚡ OPTİMİZE DUPLICATE CACHE - SADECE EKSTRA GÜVENLİK İÇİN
  // Mobile Scanner 7.2.0'ın native noDuplicates özelliği ile birlikte çalışır
  final Map<String, DateTime> _lastScannedBarcodes = {};
  Timer? _duplicateCleanupTimer;

  final Map<String, List<DateTime>> _rapidDuplicateCache = {};
  Timer? _rapidDuplicateCleanupTimer;

  bool _showQuantityDialog = false;
  String? _pending1DBarcode;
  final TextEditingController _quantityController = TextEditingController();

  bool _showWarningDialog = false;
  String _warningTitle = '';
  String _warningMessage = '';
  String? _pendingShelfChangeCode;
  VoidCallback? _warningAction;
  IlacModel? _detectedIlac;

  bool invertImage = false;

  bool _isCsvLoading = false;
  bool _csvLoaded = false;

  final Map<String, DateTime> _ilacUyariGecmisi = {};

  int _frameCounter = 0;
  int _frameSkip = 2;

  // ⚡ 1D MOD DEĞİŞKENLERİ - DUPLICATE KONTROLSÜZ
  DateTime? _last1DBarcodeTime;

  // 🚨 MİAD UYARI DEĞİŞKENLERİ
  bool _showExpiredWarning = false;
  String? _expiredProductName;
  String? _expiredBarcode;
  String? _expiredExpirationDate;
  int _expiredDaysExpired = 0;
  Timer? _expiredWarningTimer;
  Timer? _ilacUyariTemizlemeTimer;

  // MİAD UYARI GEÇMİŞİ
  final Map<String, DateTime> _expiredWarningHistory = {};

  // ⚡ OPTİMİZASYON DEĞİŞKENLERİ
  final Set<String> _tempUniqueBarcodes = HashSet();

  // 📊 RAF MEVCUT ADET DEĞİŞKENİ
  int _currentShelfQuantity = 0;

  bool get _effectiveInvertImage {
    return _currentScannerMode == ScannerMode.ilacQr ? invertImage : false;
  }

  static const String _prefsScannerMode = 'scanner_mode';

  // ⚡ STATIC REGEX - Hot path'te her cagride yeniden olusturulmaz
  static final _rafKoduPattern = RegExp(r'^SG[A-Z][0-9]{2}C$');
  static final _urlPattern = RegExp(
    r'^(https?:\/\/|www\.)[a-zA-Z0-9-]+\.[a-zA-Z]{2,}(?:\/[^\s]*)?$',
    caseSensitive: false,
  );
  static final _domainPattern = RegExp(
    r'\.(com|net|org|tr|io|gov|edu|info|biz|app|dev|shop|store)($|\/)',
    caseSensitive: false,
  );

  // ⚡ SADECE QR MOD İÇİN DUPLICATE SÜRELERİ
  Duration _getStrictDuplicatePreventionDuration() {
    switch (_currentPriority) {
      case ScannerPriority.maxPerformance:
        return const Duration(milliseconds: 800);
      case ScannerPriority.balanced:
        return const Duration(milliseconds: 1500);
      case ScannerPriority.batterySaver:
        return const Duration(milliseconds: 2500);
    }
  }

  // ✅ SADECE QR MOD İÇİN RAPID DUPLICATE
  bool _isRapidDuplicate(String barcode, DateTime now) {
    if (!_rapidDuplicateCache.containsKey(barcode)) {
      _rapidDuplicateCache[barcode] = [];
    }
    
    final scans = _rapidDuplicateCache[barcode]!;
    scans.removeWhere((timestamp) => now.difference(timestamp) > ScannerConstants.rapidTimeWindow);
    
    return scans.length >= ScannerConstants.maxRapidScans;
  }

  void _updateRapidDuplicateCache(String barcode, DateTime now) {
    if (!_rapidDuplicateCache.containsKey(barcode)) {
      _rapidDuplicateCache[barcode] = [];
    }
    
    final scans = _rapidDuplicateCache[barcode]!;
    scans.add(now);
    scans.removeWhere((timestamp) => now.difference(timestamp) > ScannerConstants.rapidTimeWindow);
  }

  void _startBatteryPriorityMonitoring() {
    // İlk okuma
    _updatePriorityFromBattery();
    // 2 dakikada bir batarya kontrol et
    _batteryPriorityTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _updatePriorityFromBattery(),
    );
  }

  Future<void> _updatePriorityFromBattery() async {
    try {
      final level = await _battery.batteryLevel;
      if (!mounted || _isDisposed) return;

      ScannerPriority newPriority;
      
      if (level >= 50) {
        newPriority = ScannerPriority.maxPerformance;
      } else if (level >= 30) {
        newPriority = ScannerPriority.maxPerformance;
      } else if (level >= 15) {
        newPriority = ScannerPriority.balanced;
      } else {
        newPriority = ScannerPriority.batterySaver;
      }

      if (newPriority != _currentPriority) {
        setState(() {
          _currentPriority = newPriority;
        });
        _applyPrioritySettings();
        
        // Eğer QR modundaysak ve batarya durumu değiştiyse controller'ı recreate et
        if (_currentScannerMode == ScannerMode.ilacQr) {
          await _recreateController();
        }
      }
    } catch (_) {
      // Batarya okunamadı - mevcut priority ile devam
    }
  }

  void _applyPrioritySettings() {
    switch (_currentPriority) {
      case ScannerPriority.maxPerformance:
        _configureMaxPerformance();
        break;
      case ScannerPriority.balanced:
        _configureBalanced();
        break;
      case ScannerPriority.batterySaver:
        _configureBatterySaver();
        break;
    }
  }

  void _configureMaxPerformance() {
    _frameSkip = 1;
  }

  void _configureBalanced() {
    _frameSkip = 2;
  }

  void _configureBatterySaver() {
    _frameSkip = 4;
    if (isTorchOn) _safeToggleTorch(false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // HEMEN PORTRAIT KİLİDİ UYGULA
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    
    _initializePreferences().then((_) {
      _initializeController();

      _initializeIlacDatabase();

      if (!_timersStarted) {
        _timersStarted = true;
        _startIlacUyariTemizlemeTimer();
        _startDuplicateCleanupTimer();
        _startRapidDuplicateCleanupTimer();
        _startBatteryPriorityMonitoring();
      }
    });
  }

  Future<void> _initializePreferences() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadManualSettings();
      _prefsLoaded = true;
    } catch (e) {
      _setDefaultSettings();
    }
  }

  Future<void> _loadManualSettings() async {
    try {
      final savedMode = _prefs.getString(_prefsScannerMode);
      if (savedMode != null) {
        _currentScannerMode = ScannerMode.values.firstWhere(
          (e) => e.name == savedMode,
          orElse: () => ScannerMode.otcBarkod,
        );
      }


    } catch (e) {
      _setDefaultSettings();
    }
  }

  void _setDefaultSettings() {
    _currentScannerMode = ScannerMode.otcBarkod;
    _currentPriority = ScannerPriority.maxPerformance;
  }

  Future<void> _saveManualSettings() async {
    if (!_prefsLoaded) return;
    
    try {
      await _prefs.setString(_prefsScannerMode, _currentScannerMode.name);

    } catch (_) {
      // Ayar kaydetme başarısız - kritik değil
    }
  }

  void _startDuplicateCleanupTimer() {
    _duplicateCleanupTimer = Timer.periodic(
      ScannerConstants.duplicateCleanupInterval,
      (timer) {
      if (!mounted || _isDisposed) {
        timer.cancel();
        return;
      }
      _cleanupOldBarcodeEntries();
    });
  }

  void _cleanupOldBarcodeEntries() {
    final now = DateTime.now();
    const threshold = Duration(minutes: 2);
    
    _lastScannedBarcodes.removeWhere((barcode, timestamp) {
      return now.difference(timestamp) > threshold;
    });
  }

  void _startRapidDuplicateCleanupTimer() {
    _rapidDuplicateCleanupTimer = Timer.periodic(
      ScannerConstants.rapidDuplicateCleanupInterval,
      (timer) {
      if (!mounted || _isDisposed) {
        timer.cancel();
        return;
      }
      _cleanupOldRapidDuplicates();
    });
  }

  void _cleanupOldRapidDuplicates() {
    final now = DateTime.now();
    _rapidDuplicateCache.removeWhere((barcode, timestamps) {
      timestamps.removeWhere((timestamp) => now.difference(timestamp) > ScannerConstants.rapidTimeWindow);
      return timestamps.isEmpty;
    });
  }

  void _startIlacUyariTemizlemeTimer() {
    _ilacUyariTemizlemeTimer = Timer.periodic(
      ScannerConstants.adaptiveCleanupInterval,
      (timer) {
      if (!mounted || _isDisposed) {
        timer.cancel();
        return;
      }
      _temizleEskiIlacUyarilari();
    });
  }

  void _temizleEskiIlacUyarilari() {
    final now = DateTime.now();
    _ilacUyariGecmisi.removeWhere((barkod, zaman) {
      return now.difference(zaman) > ScannerConstants.ilacUyariGecmisSuresi;
    });
  }

  Future<void> _initializeIlacDatabase() async {
    if (_csvLoaded || _isCsvLoading) return;

    setState(() { _isCsvLoading = true; });

    try {
      final ilacManager = IlacManager();
      if (ilacManager.toplamUrunSayisi == 0) {
        await ilacManager.initialize();
      }
      setState(() {
        _csvLoaded = true;
        _isCsvLoading = false;
      });
    } catch (e) {
      setState(() { _isCsvLoading = false; });
    }
  }

  List<BarcodeFormat> _getFormatsForCurrentMode() {
    // Raf kodu beklenirken hem QR hem barkod destekle
    if (widget.waitingForShelfCode) {
      return const [
        BarcodeFormat.qrCode,
        BarcodeFormat.dataMatrix,
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
      ];
    }
    switch (_currentScannerMode) {
      case ScannerMode.otcBarkod:
        return const [
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.code128,
          BarcodeFormat.code39,
          BarcodeFormat.upcA,
          BarcodeFormat.upcE,
        ];
      case ScannerMode.ilacQr:
        return const [
          BarcodeFormat.qrCode,
          BarcodeFormat.dataMatrix,
        ];
    }
  }

  MobileScannerController _createDynamsoftStyleController() {
    final formats = _getFormatsForCurrentMode();
    final isQrMode = _currentScannerMode == ScannerMode.ilacQr;

    // Mobile Scanner 7.2.0 Optimizasyonu:
    // - QR modunda: noDuplicates (native duplicate kontrol)
    // - 1D modunda: normal (hızlı tarama)
    // - Max performance modunda: unrestricted (sadece özel durumlarda)
    DetectionSpeed detectionSpeed;
    
    if (isQrMode) {
      // QR modunda native duplicate kontrol kullan
      detectionSpeed = DetectionSpeed.noDuplicates;
    } else {
      // 1D modunda normal hız, duplicate kontrol gerekmez
      detectionSpeed = DetectionSpeed.unrestricted;
    }
    
    // Özel durum: Max performance ve batarya yüksekse unrestricted
    if (_currentPriority == ScannerPriority.maxPerformance && isQrMode) {
      // Sadece batarya %50'den fazlaysa unrestricted kullan
      // (Bu kontrol _updatePriorityFromBattery'de yapılacak)
      detectionSpeed = DetectionSpeed.unrestricted;
    }

    return MobileScannerController(
      formats: formats,
      autoStart: false,
      torchEnabled: isTorchOn,
      invertImage: _effectiveInvertImage,
      autoZoom: false,
      detectionSpeed: detectionSpeed,
      detectionTimeoutMs: isQrMode ? 0 : 1000,
      returnImage: false,
      facing: CameraFacing.back,
    );
  }

  void _initializeController() {
    _applyPrioritySettings();
    
    controller = _createDynamsoftStyleController();
    _barcodeSubscription = controller!.barcodes.listen(_handleBarcode);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed) _safeStartScanner();
    });
  }

  Future<void> _recreateController() async {
    if (_isControllerInitializing || _isDisposed) return;
    
    setState(() { _isControllerInitializing = true; });
    
    try {
      if (isTorchOn) {
        await _safeToggleTorch(false);
      }
      
      await _safeStopScanner();
      _barcodeSubscription?.cancel();
      _barcodeSubscription = null;
      
      await controller?.dispose();
      controller = null;

      await Future.delayed(const Duration(milliseconds: 500));
      
      _initializeController();

    } catch (e) {
      if (mounted && !_isDisposed) {
        showAppSnackBar('Scanner yeniden başlatılamadı');
      }
    } finally {
      if (mounted && !_isDisposed) {
        setState(() { _isControllerInitializing = false; });
      }
    }
  }

  // ⚡ OPTİMİZE BARKOD İŞLEME FONKSİYONU
  void _handleBarcode(BarcodeCapture capture) {
    // ✅ 1. ERKEN ÇIKIŞ KONTROLLERİ
    if (_shouldSkipBarcodeProcessing()) {
      return;
    }
    
    // ✅ 2. FRAME SKIP KONTROLÜ
    if (!_shouldProcessThisFrame()) {
      return;
    }
    
    // ✅ 3. RAF KODU BEKLEME MODU
    if (widget.waitingForShelfCode) {
      _handleShelfCodeDetectionOptimized(capture);
      return;
    }
    
    // ✅ 5. MODA GÖRE İŞLEM
    switch (_currentScannerMode) {
      case ScannerMode.otcBarkod:
        _handle1DModeSuperFast(capture); // ⚡ NO DUPLICATE CONTROL
        break;
      case ScannerMode.ilacQr:
        _handleDynamsoftStyleMultiBarcodeOptimized(capture); // ✅ FULL DUPLICATE CONTROL
        break;
    }
  }

  // ✅ YARDIMCI METODLAR
  bool _shouldSkipBarcodeProcessing() {
    return _isDisposed ||
           _showQuantityDialog ||
           _showWarningDialog;
  }

  bool _shouldProcessThisFrame() {
    if (_currentPriority == ScannerPriority.maxPerformance) return true;
    _frameCounter = (_frameCounter + 1) % 1000;
    return _frameCounter % _frameSkip == 0;
  }

  // ⚡ RAF KODU TESPİTİ
  void _handleShelfCodeDetectionOptimized(BarcodeCapture capture) {
    final maxCheck = capture.barcodes.length > 3 ? 3 : capture.barcodes.length;
    for (int i = 0; i < maxCheck; i++) {
      final barcode = capture.barcodes[i];
      final rawValue = barcode.rawValue;

      if (rawValue != null && rawValue.isNotEmpty && _isRafKodu(rawValue)) {
        _processDetectedShelfCode(rawValue);
        return;
      }
    }
  }

  // ⚡ SÜPER HIZLI 1D MOD - DUPLICATE KONTROLSÜZ VE ASENKRON
  void _handle1DModeSuperFast(BarcodeCapture capture) {
    // HIZ SINIRI: Saniyede max 20 barkod
    final now = DateTime.now();
    if (_last1DBarcodeTime != null && 
        now.difference(_last1DBarcodeTime!) < ScannerConstants.min1DBarcodeInterval) {
      return;
    }
    _last1DBarcodeTime = now;
    
    if (capture.barcodes.isNotEmpty) {
      final barcode = capture.barcodes.first;
      final rawValue = barcode.rawValue;
      
      if (rawValue != null && rawValue.isNotEmpty) {
        // 🎯 RAF KODU KONTROLÜ
        if (_isRafKodu(rawValue)) {
          _handleShelfCode(rawValue);
          return;
        }
        
        // 🚫 QR/DataMatrix ENGELLE (1D modunda)
        if (barcode.format == BarcodeFormat.qrCode || 
            barcode.format == BarcodeFormat.dataMatrix) {
          return;
        }
        
        // ⚡ ASENKRON İŞLEME - BLOKE ETMEDEN
        Future.microtask(() async {
          if (!_isDisposed) {
            await _processOtcBarkod(rawValue, barcode);
          }
        });
      }
    }
  }

  // 🚀 QR MOD - TAM DUPLICATE KONTROLLÜ
  void _handleDynamsoftStyleMultiBarcodeOptimized(BarcodeCapture capture) {

    final DateTime now = DateTime.now();
    _tempUniqueBarcodes.clear();
    
    // ✅ MAX LİMİT KONTROLÜ
    final int barcodeCount = capture.barcodes.length;
    final int limit = barcodeCount > ScannerConstants.maxBarcodesToProcess 
        ? ScannerConstants.maxBarcodesToProcess 
        : barcodeCount;
    
    for (int i = 0; i < limit; i++) {
      final barcode = capture.barcodes[i];
      final rawValue = barcode.rawValue;
      
      if (rawValue == null || rawValue.isEmpty) continue;
      
      // ⚡ HIZLI UNIQUE KONTROL
      if (_tempUniqueBarcodes.contains(rawValue)) continue;
      _tempUniqueBarcodes.add(rawValue);

      // ⚡ DUPLICATE KONTROL (SADECE QR MOD İÇİN)
      if (_isQuickDuplicate(rawValue, now)) continue;

      // ✅ RAF KODU KONTROLÜ
      if (_isRafKodu(rawValue)) {
        _handleShelfCode(rawValue);
        continue;
      }

      // ✅ WEB SİTESİ ENGEL
      if (_isWebsiteUrl(rawValue.toLowerCase())) continue;

      // ⚡ ASENKRON İŞLEME
      final barcodeRef = barcode;
      Future.microtask(() {
        if (!_isDisposed) {
          final rawVal = barcodeRef.rawValue;
          if (rawVal != null && rawVal.isNotEmpty) {
            _processIlacQr(rawVal, barcodeRef);
          }
        }
      });
    }
  }

  // ⚡ SADECE QR MOD İÇİN DUPLICATE KONTROL
  bool _isQuickDuplicate(String barcode, DateTime now) {
    if (_lastScannedBarcodes.containsKey(barcode)) {
      final lastTime = _lastScannedBarcodes[barcode]!;
      final preventionDuration = _getStrictDuplicatePreventionDuration();
      
      if (now.difference(lastTime) < preventionDuration) {
        return true;
      }
    }
    
    if (_isRapidDuplicate(barcode, now)) {
      return true;
    }
    
    _lastScannedBarcodes[barcode] = now;
    _updateRapidDuplicateCache(barcode, now);

    return false;
  }

  // 🔄 RAF KODU İŞLEME
  void _processDetectedShelfCode(String rafKodu) {
    if (widget.onShelfCodeDetected != null) {
      widget.onShelfCodeDetected!(rafKodu);
    }
    
    showAppSnackBar('Raf kodu tespit edildi: $rafKodu');
    
    _recreateControllerAfterShelfCode();
  }

  Future<void> _recreateControllerAfterShelfCode() async {
    if (mounted && !_isDisposed) {
      try {
        if (_currentScannerMode == ScannerMode.ilacQr) {
          setState(() {
            _currentScannerMode = ScannerMode.otcBarkod;
            invertImage = false;
          });
          await _saveManualSettings();
        }
        await _recreateController();
      } catch (e) {
        _recoverFromCameraError();
      }
    }
  }

  void _handleShelfCode(String rafKodu) {
    if (rafKodu != widget.currentShelfCode) {
      _showRafDegisimUyarisi(rafKodu);
    }
  }

  Future<void> _processOtcBarkod(String rawValue, Barcode barcode) async {
    final ilac = await IlacManager().ilacAra(rawValue);
    
    if (ilac != null && ilac.tip == 'ilac') {
      _showBilgilendirmeVeQrGecisUyarisi(ilac);
      return;
    }
    
    _showUpdateDialog(rawValue, ilac);
  }

  void _showBilgilendirmeVeQrGecisUyarisi(IlacModel ilac) {
    final now = DateTime.now();
    final sonUyariZamani = _ilacUyariGecmisi[ilac.barkod];
    
    if (sonUyariZamani != null && 
        now.difference(sonUyariZamani) < ScannerConstants.ilacUyariGecmisSuresi) {
      return;
    }
    
    _ilacUyariGecmisi[ilac.barkod] = now;
    
    setState(() {
      _showWarningDialog = true;
      _warningTitle = 'İLAÇ BARKODU TESPİT EDİLDİ';
      _warningMessage = '${ilac.ilacAdi}\n\nBu bir ilaç barkodudur. Otomatik olarak karekod moduna geçiliyor...';
      _detectedIlac = ilac;
      _warningAction = null;
    });
    
    // GEREKSİZ: _safeStopScanner(); - _showWarningDialog flag'i zaten taramayı engelliyor
    
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && !_isDisposed && _showWarningDialog) {
        _qrModunaGec();
      }
    });
  }

  void _qrModunaGec() {
    if (_showQuantityDialog) {
      setState(() {
        _showQuantityDialog = false;
        _pending1DBarcode = null;
        _detectedIlac = null;
      });
      _quantityController.clear();
    }
    
    if (_showWarningDialog) {
      setState(() {
        _showWarningDialog = false;
        _warningAction = null;
        _detectedIlac = null;
      });
    }
    
    _changeToQrMode();
  }

  Future<void> _changeToQrMode() async {
    setState(() {
      _currentScannerMode = ScannerMode.ilacQr;
      invertImage = false;
    });
    
    await _saveManualSettings();
    await _recreateController();
    
    if (mounted && !_isDisposed) {
      showAppSnackBar('🚀 İlaç QR Moduna Geçildi');
    }
  }

  Future<void> _processIlacQr(String rawValue, Barcode barcode) async {
    // Parsing asamasi - hata olursa ham degerlerle devam et
    String? urunAdi;
    String urunTipi = 'unknown';
    String? sonKullanmaTarihi;
    String? partiNo;
    String aramaBarkodu = rawValue;

    try {
      final parsedData = GS1Parser.parseBarkod(rawValue);
      if (parsedData.gtin != null) aramaBarkodu = parsedData.gtin!;
      sonKullanmaTarihi = parsedData.sonKullanmaTarihi;
      partiNo = parsedData.partiNo;

      final ilac = await IlacManager().ilacAra(aramaBarkodu);
      if (ilac != null) {
        urunAdi = ilac.ilacAdi;
        urunTipi = ilac.tip;
      } else {
        urunAdi = 'Barkod: ${aramaBarkodu.length > 12 ? '${aramaBarkodu.substring(0, 12)}...' : aramaBarkodu}';
      }
    } catch (_) {
      // Parsing hatasi - ham degerlerle devam et
    }

    // Miad kontrolu
    if (sonKullanmaTarihi != null && sonKullanmaTarihi.isNotEmpty) {
      _checkExpirationDate(aramaBarkodu, sonKullanmaTarihi, urunAdi);
    }

    // Tek seferlik database kaydi
    final success = await _saveToDatabase(
      rawValue, true, 1,
      urunAdi: urunAdi,
      urunTipi: urunTipi,
      sonKullanmaTarihi: sonKullanmaTarihi,
      partiNo: partiNo,
    );

    if (success) {
      widget.onBarcodeDetected(
        rawValue, true, 1,
        urunAdi: urunAdi,
        urunTipi: urunTipi,
        sonKullanmaTarihi: sonKullanmaTarihi,
        partiNo: partiNo,
      );
    }
  }

  // 🚨 MİAD KONTROL FONKSİYONU
  void _checkExpirationDate(String barcode, String expirationDate, String? productName) {
    if (!widget.miadUyarisiAktif) return;

    try {
      final now = DateTime.now();
      final lastWarning = _expiredWarningHistory[barcode];
      if (lastWarning != null && now.difference(lastWarning) < ScannerConstants.expiredWarningCooldown) {
        return;
      }

      if (GS1Parser.isSKTExpired(expirationDate)) {
        final daysExpired = GS1Parser.getDaysUntilExpiry(expirationDate) ?? 0;

        _showExpiredProductWarning(
          barcode: barcode,
          productName: productName,
          expirationDate: expirationDate,
          daysExpired: daysExpired.abs()
        );
      }
    } catch (_) {
      // Miad kontrol hatası - taramayı engelleme
    }
  }

  // 🚨 MİADI DOLMUŞ ÜRÜN UYARISI
  void _showExpiredProductWarning({
    required String barcode,
    required String? productName,
    required String expirationDate,
    required int daysExpired
  }) {
    _expiredWarningHistory[barcode] = DateTime.now();
    
    setState(() {
      _showExpiredWarning = true;
      _expiredBarcode = barcode;
      _expiredProductName = productName;
      _expiredExpirationDate = expirationDate;
      _expiredDaysExpired = daysExpired;
    });

    _playWarningBeep();

    _expiredWarningTimer?.cancel();
    _expiredWarningTimer = Timer(ScannerConstants.expiredWarningAutoClose, () {
      if (mounted && !_isDisposed && _showExpiredWarning) {
        setState(() {
          _showExpiredWarning = false;
        });
      }
    });
  }

  // 🔊 UYARI BİP SESİ (Android ToneGenerator)
  static const _toneChannel = MethodChannel('com.stock_sayar/tone');

  void _playWarningBeep() {
    _toneChannel.invokeMethod('playWarningTone').catchError((_) {});
  }

  Future<bool> _saveToDatabase(
    String barcode, 
    bool isQR, 
    int quantity, {
    String? urunAdi,
    String? urunTipi,
    String? sonKullanmaTarihi,
    String? partiNo
  }) async {
    try {
      if (quantity == 0) {
        final deleted = await DatabaseHelper().deleteScannedItemByBarcode(
          barcode,
          shelfCode: widget.currentShelfCode,
          sayimKodu: 'AKTIF_SAYIM'
        );
        return deleted > 0;
      }
      
      final newItem = ScannedItem(
        barcode: barcode,
        isQR: isQR,
        quantity: quantity,
        success: true,
        shelfCode: widget.currentShelfCode,
        isSentToServer: false,
        isUpdated: false,
        productName: urunAdi,
        productType: urunTipi,
        expirationDate: sonKullanmaTarihi,
        batchNumber: partiNo,
      );
      
      final result = await DatabaseHelper().insertScannedItem(
        newItem, 
        shelfCode: widget.currentShelfCode,
        sayimKodu: 'AKTIF_SAYIM'
      );

      return result > 0;
    } catch (e) {
      showAppSnackBar('Veritabanı hatası: $e');
      return false;
    }
  }

  bool _isRafKodu(String barkod) => _rafKoduPattern.hasMatch(barkod);

  void _showRafDegisimUyarisi(String yeniRafKodu) {
    final now = DateTime.now();
    final sonUyariZamani = _ilacUyariGecmisi[yeniRafKodu];
    
    if (sonUyariZamani != null && 
        now.difference(sonUyariZamani) < ScannerConstants.ilacUyariGecmisSuresi) {
      return;
    }
    
    _ilacUyariGecmisi[yeniRafKodu] = now;
    
    setState(() {
      _showWarningDialog = true;
      _warningTitle = 'RAF DEĞİŞİMİ TESPİT EDİLDİ!';
      _warningMessage = 'Mevcut Raf: ${widget.currentShelfCode}\nYeni Raf: $yeniRafKodu\n\nBu rafa geçiş yapılsın mı?';
      _pendingShelfChangeCode = yeniRafKodu;
      _warningAction = _onRafDegisimOnayi;
    });
    
    // GEREKSİZ: _safeStopScanner(); - _showWarningDialog flag'i zaten taramayı engelliyor
  }

  void _onRafDegisimOnayi() {
    if (_pendingShelfChangeCode != null) {
      if (widget.onShelfCodeDetected != null) {
        widget.onShelfCodeDetected!(_pendingShelfChangeCode!);
      }
      
      setState(() {
        _showWarningDialog = false;
        _pendingShelfChangeCode = null;
        _warningAction = null;
      });
      _safeStartScanner();
    }
  }

  bool _isWebsiteUrl(String lowerValue) {
    return _urlPattern.hasMatch(lowerValue) || _domainPattern.hasMatch(lowerValue);
  }

  void _showUpdateDialog(String barcode, IlacModel? ilac) {
    _quantityController.text = '';

    setState(() {
      _showQuantityDialog = true;
      _pending1DBarcode = barcode;
      _detectedIlac = ilac;
      _currentShelfQuantity = 0; // Reset
    });

    // 📊 MEVCUT RAF ADEDİNİ SORGULA
    _fetchCurrentShelfQuantity(barcode);
  }

  // 📊 MEVCUT RAF ADEDİ SORGULAMA FONKSİYONU
  Future<void> _fetchCurrentShelfQuantity(String barcode) async {
    try {
      final existingItem = await DatabaseHelper().getScannedItemByBarcode(
        barcode,
        shelfCode: widget.currentShelfCode,
        sayimKodu: 'AKTIF_SAYIM'
      );
      
      if (mounted && !_isDisposed) {
        setState(() {
          _currentShelfQuantity = existingItem?.quantity ?? 0;
        });
      }
    } catch (e) {
      if (mounted && !_isDisposed) {
        setState(() {
          _currentShelfQuantity = 0;
        });
      }
    }
  }

  Future<void> _updateQuantity(bool isAdd) async {
    if (_pending1DBarcode == null) return;
    
    final changeAmount = int.tryParse(_quantityController.text) ?? 0;
    if (changeAmount <= 0) {
      showAppSnackBar('⚠️ Lütfen geçerli bir miktar girin!');
      return;
    }
    
    // ⚡ _fetchCurrentShelfQuantity zaten sorgulamis, cache'den kullan
    final existingQuantity = _currentShelfQuantity;

    int newQuantity;
    if (isAdd) {
      newQuantity = existingQuantity + changeAmount;
    } else {
      newQuantity = existingQuantity - changeAmount;
      
      if (newQuantity < 0) {
        showAppSnackBar('⚠️ Stok negatif olamaz! Mevcut: $existingQuantity');
        return;
      }
    }
    
    String? urunAdi;
    String? urunTipi;
    
    IlacModel? ilac = _detectedIlac ?? await IlacManager().ilacAra(_pending1DBarcode!);
    
    if (ilac != null) {
      urunAdi = ilac.ilacAdi;
      urunTipi = ilac.tip;
    } else {
      urunAdi = 'Barkod: ${_pending1DBarcode!.length > 12 ? '${_pending1DBarcode!.substring(0, 12)}...' : _pending1DBarcode}';
      urunTipi = 'unknown';
    }
    
    if (newQuantity == 0) {
      try {
        final db = DatabaseHelper();
        final deletedCount = await db.deleteScannedItemByBarcode(
          _pending1DBarcode!,
          shelfCode: widget.currentShelfCode,
          sayimKodu: 'AKTIF_SAYIM'
        );


        if (deletedCount > 0) {
          widget.onBarcodeDetected(
            _pending1DBarcode!, 
            false, 
            0,
            urunAdi: urunAdi,
            urunTipi: urunTipi,
            sonKullanmaTarihi: null,
            partiNo: null
          );
          
          showAppSnackBar('🗑️ $urunAdi listeden silindi (stok: 0)');
        } else {
          showAppSnackBar('ℹ️ Ürün zaten listede yok');
        }

      } catch (e) {
        showAppSnackBar('❌ Ürün silinemedi');
      }
      
      setState(() {
        _showQuantityDialog = false;
        _pending1DBarcode = null;
        _detectedIlac = null;
      });
      
      _quantityController.clear();
      _safeStartScanner();
      return;
    }
    
    final success = await _saveToDatabase(
      _pending1DBarcode!, 
      false, 
      newQuantity,
      urunAdi: urunAdi,
      urunTipi: urunTipi
    );
    
    if (success) {
      widget.onBarcodeDetected(
        _pending1DBarcode!, 
        false, 
        newQuantity,
        urunAdi: urunAdi,
        urunTipi: urunTipi,
        sonKullanmaTarihi: null,
        partiNo: null
      );
      
      final operation = isAdd ? 'eklendi' : 'çıkarıldı';
      showAppSnackBar('$urunAdi: $operation ($changeAmount adet)');
    }
    
    setState(() {
      _showQuantityDialog = false;
      _pending1DBarcode = null;
      _detectedIlac = null;
    });
    
    _quantityController.clear();
    _safeStartScanner();
  }

  void _cancelQuantity() {
    setState(() {
      _showQuantityDialog = false;
      _pending1DBarcode = null;
      _detectedIlac = null;
    });
    _quantityController.clear();
    _safeStartScanner();
  }

  Future<void> _toggleScannerMode() async {
    if (isTorchOn) {
      await _safeToggleTorch(false);
    }

    final newMode = _currentScannerMode == ScannerMode.otcBarkod 
        ? ScannerMode.ilacQr 
        : ScannerMode.otcBarkod;
    
    setState(() {
      _currentScannerMode = newMode;
      invertImage = false;
    });

    await _saveManualSettings();
    
    // ⚡ OPTİMİZASYON: Formatlar her zaman farklı olduğu için recreate et
    // 1D mod: sadece barkod formatları
    // QR mod: sadece QR/DataMatrix formatları
    // Bu nedenle her mod değişikliğinde recreate gerekli
    await _recreateController();

    if (mounted && !_isDisposed) {
      showAppSnackBar(newMode == ScannerMode.otcBarkod
          ? '⚡ HIZLI 1D Modu'
          : '🚀 İlaç QR Modu');
    }
  }

  Future<void> _safeToggleTorch(bool turnOn) async {
    try {
      if (controller != null && controller!.value.isInitialized) {
        final currentTorchState = controller!.value.torchState;
        
        if (turnOn && currentTorchState != TorchState.on) {
          await controller!.toggleTorch();
          setState(() { isTorchOn = true; });
        } else if (!turnOn && currentTorchState != TorchState.off) {
          await controller!.toggleTorch();
          setState(() { isTorchOn = false; });
        }
      }
    } catch (e) {
      setState(() { isTorchOn = false; });
    }
  }

  Future<void> _toggleTorch() async {
    try {
      if (controller == null || !controller!.value.isInitialized) {
        return;
      }
      
      await _safeToggleTorch(!isTorchOn);
    } catch (e) {
      setState(() { isTorchOn = false; });
    }
  }

  Future<void> _safeStopScanner() async {
    if (_isDisposed || controller == null) return;

    try {
      await controller!.stop();
    } catch (_) {
      // Scanner durdurma hatası - güvenli şekilde yoksay
    }
  }

  Future<void> _safeStartScanner() async {
    if (_isDisposed || !mounted || controller == null) return;
    try {
      await controller!.start();
    } catch (_) {
      // Scanner başlatma hatası - güvenli şekilde yoksay
    }
  }

  Future<void> _recoverFromCameraError() async {
    try {
      await _safeStopScanner();
      _barcodeSubscription?.cancel();
      _barcodeSubscription = null;

      // Eski controller'i dispose et (kaynak sizintisi onleme)
      try {
        await controller?.dispose();
      } catch (_) {}
      controller = null;

      if (mounted && !_isDisposed) {
        setState(() {
          isTorchOn = false;
          _isControllerInitializing = false;
        });
      }

      await Future.delayed(ScannerConstants.cameraRecoveryDelay);

      if (mounted && !_isDisposed) {
        _initializeController();
        showAppSnackBar('Kamera yeniden başlatıldı');
      }

    } catch (e) {
      if (mounted && !_isDisposed) {
        showAppSnackBar('Kamera hatası: Uygulamayı yeniden başlatın');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (controller == null) return;

    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        return;
      case AppLifecycleState.resumed:
        if (!_isDisposed && mounted) {
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
          ]);
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (_isDisposed || !mounted) return;
            if (isTorchOn) {
              await _safeToggleTorch(false);
            }
            _barcodeSubscription?.cancel();
            if (controller != null) {
              _barcodeSubscription = controller!.barcodes.listen(_handleBarcode);
            }
            await _safeStartScanner();
          });
        }
        break;
      case AppLifecycleState.inactive:
        if (!_isDisposed) {
          _barcodeSubscription?.cancel();
          _barcodeSubscription = null;
          if (isTorchOn) {
            _safeToggleTorch(false);
          }
          _safeStopScanner();
        }
        break;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    
    if (_prefsLoaded) {
      _saveManualSettings();
    }
    
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    
    // Tüm timer'ları temizle
    final timers = [
      _duplicateCleanupTimer,
      _rapidDuplicateCleanupTimer, _batteryPriorityTimer,
      _expiredWarningTimer, _ilacUyariTemizlemeTimer
    ];
    
    for (var timer in timers) {
      timer?.cancel();
    }
    
    // Tüm subscription'ları temizle
    _barcodeSubscription?.cancel();

    _quantityController.dispose();
    
    try {
      if (isTorchOn && controller != null && controller!.value.isInitialized) {
        controller!.toggleTorch(); // setState olmadan, fire-and-forget
      }
      controller?.dispose();
      controller = null;
    } catch (_) {
      // Controller dispose hatası - zaten temizleniyor
    }

    WidgetsBinding.instance.removeObserver(this);
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    if (widget.waitingForShelfCode) {
      return _buildWaitingForShelfCodeScreen();
    }
    
    return Stack(
      children: [
        _buildScannerWidget(),
        if (_showQuantityDialog) _buildQuantityDialog(),
        if (_showWarningDialog) _buildWarningDialog(),
        if (_showExpiredWarning) _buildExpiredWarningDialog(),
        _buildInfoPanel(),
      ],
    );
  }

  // MİADI DOLMUŞ ÜRÜN UYARI BANNER'I
  Widget _buildExpiredWarningDialog() {
    return Positioned(
      bottom: 70,
      left: 8,
      right: 8,
      child: GestureDetector(
        onTap: () {
          setState(() { _showExpiredWarning = false; });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF7F0000),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red, width: 2),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber, color: Colors.yellow, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _expiredProductName ?? _expiredBarcode ?? 'Bilinmeyen',
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'SKT: ${GS1Parser.formatSKTForDisplay(_expiredExpirationDate) ?? ""} - $_expiredDaysExpired gün önce dolmuş!',
                      style: const TextStyle(color: Colors.yellow, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.close, color: Colors.white54, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  // RAF KODU BEKLEME EKRANI
  Widget _buildWaitingForShelfCodeScreen() {
    return Stack(
      children: [
        // ARKAPLAN - NORMAL SCANNER GİBİ
        if (controller != null && !_isControllerInitializing)
          MobileScanner(
            controller: controller!,
            fit: BoxFit.cover,
          ),
        
        // KARANLIK OVERLAY
        Container(
          color: Colors.black.withAlpha(120),
        ),
        
        // İÇERİK
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // BÜYÜK RAF İKONU
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(80),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.orange, width: 3),
              ),
              child: const Icon(
                Icons.shelves,
                color: Colors.orange,
                size: 60,
              ),
            ),
            
            const SizedBox(height: 32),
            
            // ANA MESAJ
            const Text(
              'RAF KODU BEKLENİYOR',
              style: TextStyle(
                color: Colors.orange,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 16),
            
            // AÇIKLAMA MESAJI
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Yeni sayım için lütfen raf barkodunu taratın\n\n'
                'Raf kodları "SG" ile başlar (Örnek: SGA01C)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            
            const SizedBox(height: 32),
            
            // TARAMA İPUCU
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(50),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange),
              ),
              child: Column(
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info, color: Colors.orange, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Tarama İpucu',
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _currentScannerMode == ScannerMode.otcBarkod 
                        ? '⚡ Hızlı 1D modunda raf kodunu tarayabilirsiniz'
                        : '🚀 İlaç QR modunda raf kodunu tarayabilirsiniz',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '💡 Karanlık ortamlarda sağ üstteki flaş butonunu kullanın',
                    style: TextStyle(
                      color: Colors.yellow,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // MOD DEĞİŞTİRME BUTONU
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              child: ElevatedButton.icon(
                onPressed: _toggleScannerMode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.withAlpha(200),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: Icon(
                  _currentScannerMode == ScannerMode.otcBarkod 
                      ? Icons.qr_code 
                      : Icons.barcode_reader,
                ),
                label: Text(
                  _currentScannerMode == ScannerMode.otcBarkod 
                      ? 'QR Moduna Geç' 
                      : '1D Moduna Geç',
                ),
              ),
            ),
            
            const Spacer(),
            
            // ALT BİLGİ
            Container(
              padding: const EdgeInsets.all(16),
              child: const Column(
                children: [
                  Text(
                    'Raf kodu tarandığında otomatik olarak sayıma başlanacaktır',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8),
                  Text(
                    '🔦 Flaş: Sağ üst köşede',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // TORCH BUTONU - SAĞ ÜST KÖŞEDE
        Positioned(
          top: 16,
          right: 16,
          child: _buildControlButton(
            icon: Icons.flash_on,
            isActive: isTorchOn,
            onTap: _toggleTorch,
          ),
        ),

        // INFO PANEL - SOL ÜST KÖŞEDE
        _buildInfoPanel(),
      ],
    );
  }

  Widget _buildScannerWidget() {
    if (controller == null || _isControllerInitializing) {
      return Container(
        color: Colors.black,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              _isControllerInitializing ? 'Kamera hazırlanıyor...' : 'Scanner yükleniyor...',
              style: const TextStyle(color: Colors.white),
            ),
            // ⚡ OPTİMİZASYON: Sadece gerçek kamera hatası durumunda kurtarma modu göster
            // Normal mod geçişlerinde kurtarma modu butonu gereksiz
          ],
        ),
      );
    }

    return Stack(
      children: [
        // SADECE PORTRAIT MOD
        MobileScanner(
          controller: controller!,
          fit: BoxFit.cover,
        ),
        
        // OVERLAY - SADECE QR MODUNDA GÖSTER
        if (_currentScannerMode == ScannerMode.ilacQr && controller != null)
          custom_overlay.BarcodeOverlay(
            boxFit: BoxFit.cover,
            controller: controller!,
            currentShelfItems: widget.currentShelfItems,
          ),
        
        // ⚡ 1D MODUNDA CROSSHAIR YOK - SADECE KONTROL BUTONLARI
        Positioned(
          top: 16,
          right: 16,
          child: Column(
            children: [
              _buildControlButton(
                icon: Icons.flash_on,
                isActive: isTorchOn,
                onTap: _toggleTorch,
              ),
              const SizedBox(height: 8),
              _buildControlButton(
                icon: _currentScannerMode == ScannerMode.otcBarkod 
                    ? Icons.qr_code 
                    : Icons.barcode_reader,
                isActive: false,
                onTap: _toggleScannerMode,
              ),
              const SizedBox(height: 8),
              if (_currentScannerMode == ScannerMode.ilacQr)
                _buildInvertButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(130),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: isActive ? Colors.amber : Colors.white,
            width: 2,
          ),
        ),
        child: Icon(
          icon,
          color: isActive ? Colors.amber : Colors.white,
          size: 24,
        ),
      ),
    );
  }

  Widget _buildInvertButton() {
    return Tooltip(
      message: 'Siyah Karekod',
      child: GestureDetector(
        onTap: _toggleInvertManual,
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: invertImage ? Colors.black : Colors.black.withAlpha(130),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(
              color: invertImage ? Colors.amber : Colors.white,
              width: 2,
            ),
          ),
          child: Icon(
            Icons.qr_code_2,
            color: invertImage ? Colors.amber : Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }

  Future<void> _toggleInvertManual() async {
    // ⚡ PERFORMANS OPTİMİZASYONU: Invert image sadece QR modunda ve gerekliyse aç
    // Invert image CPU yoğun bir işlemdir, sadece siyah arka planlı QR kodlar için kullan
    final newInvertState = !invertImage;
    
    // Eğer 1D modundaysa invert image'i açma (gereksiz CPU kullanımı)
    if (_currentScannerMode == ScannerMode.otcBarkod && newInvertState) {
      showAppSnackBar('⚠️ Invert image sadece QR modunda kullanılabilir');
      return;
    }
    
    setState(() { invertImage = newInvertState; });
    
    await _saveManualSettings();
    
    // ⚡ OPTİMİZASYON: Sadece invert image durumu değiştiyse controller'ı recreate et
    // Eski: Her zaman recreate ediyordu
    // Yeni: Sadece invert image değiştiyse recreate et
    if (_currentScannerMode == ScannerMode.ilacQr) {
      await _recreateController();
    }
    
    if (mounted && !_isDisposed) {
      showAppSnackBar(invertImage ? '⚫ Siyah Karekod Modu: AÇIK' : '⚪ Siyah Karekod Modu: KAPALI');
    }
  }

 Widget _buildQuantityDialog() {
    return Container(
      color: Colors.black.withAlpha(150),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(100),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_detectedIlac != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _detectedIlac!.tip == 'ilac' 
                        ? Colors.red[50] 
                        : Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _detectedIlac!.tip == 'ilac'
                          ? Colors.red[200]!
                          : Colors.blue[200]!,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _detectedIlac!.ilacAdi,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Barkod: ${_pending1DBarcode ?? ''}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              
              // 📊 MEVCUT RAF ADEDİ GÖSTERİMİ
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!, width: 1),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.inventory_2, color: Colors.blue, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Mevcut Raf Adedi: $_currentShelfQuantity adet',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                    ),
                  ],
                ),
              ),
              
              TextField(
                controller: _quantityController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  labelText: 'Miktar girin',
                  labelStyle: const TextStyle(fontSize: 13),
                  hintText: 'Sayı girin...',
                  hintStyle: const TextStyle(fontSize: 13),
                ),
                autofocus: true,
                style: const TextStyle(fontSize: 14),
              ),
              
              const SizedBox(height: 16),
              
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: ElevatedButton.icon(
                        onPressed: () => _updateQuantity(false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        icon: const Icon(Icons.remove, size: 18),
                        label: const Text(
                          'Çıkart',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(width: 10),
                  
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: ElevatedButton.icon(
                        onPressed: () => _updateQuantity(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text(
                          'Ekle',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 8),
              
              SizedBox(
                width: double.infinity,
                height: 36,
                child: ElevatedButton(
                  onPressed: _cancelQuantity,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[300]!,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: const Text(
                    'İptal',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWarningDialog() {
    final isRafDegisimi = _pendingShelfChangeCode != null;
    final isIlacUyarisi = _detectedIlac != null && _warningAction == null;
    
    return Container(
      color: Colors.black.withAlpha(170),
      child: Center(
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isRafDegisimi ? Icons.shelves : Icons.qr_code_scanner,
                color: isRafDegisimi ? Colors.orange : Colors.green,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                _warningTitle,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                _warningMessage,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              
              if (isIlacUyarisi) ...[
                const SizedBox(height: 20),
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text(
                  'Karekod moduna geçiliyor...',
                  style: TextStyle(fontSize: 14, color: Colors.green),
                ),
              ],
              
              if (isRafDegisimi) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _showWarningDialog = false;
                            _warningAction = null;
                            _pendingShelfChangeCode = null;
                            _detectedIlac = null;
                          });
                          // GEREKSİZ: _safeStartScanner(); - Flag false olunca tarama devam eder
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey,
                        ),
                        child: const Text('Hayır'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _warningAction,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                        child: const Text('Evet'),
                      ),
                    ),
                  ],
                ),
              ],
              
              if (!isRafDegisimi && !isIlacUyarisi) ...[
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _showWarningDialog = false;
                      _warningAction = null;
                      _pendingShelfChangeCode = null;
                      _detectedIlac = null;
                    });
                    // GEREKSİZ: _safeStartScanner(); - Flag false olunca tarama devam eder
                  },
                  child: const Text('Tamam'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // SABİT INFO PANEL - MINIMAL VE KOMPAKT
  Widget _buildInfoPanel() {
    // TEHLİKELİ: Her rebuild'de çalışan _safeStartScanner() kaldırıldı
    // Bu kontrol zaten _shouldSkipBarcodeProcessing()'de yapılıyor
    
    // RAF KODU BEKLENİYORSA INFO PANEL GÖSTERİLMESİN
    if (widget.waitingForShelfCode) {
      return const SizedBox.shrink();
    }

    // RAF TOPLAM VE MOD BAZLI MİKTARLARI TEK DÖNGÜDE HESAPLA
    int rafToplamMiktar = 0;
    int qrToplamMiktar = 0;
    int birDToplamMiktar = 0;

    for (var item in widget.currentShelfItems) {
      rafToplamMiktar += item.quantity;
      if (item.isQR) {
        qrToplamMiktar += item.quantity;
      } else {
        birDToplamMiktar += item.quantity;
      }
    }
    
    // 3. MEVCUT MODA GÖRE GÖSTERİLECEK TOPLAM
    final modToplam = _currentScannerMode == ScannerMode.ilacQr 
        ? qrToplamMiktar 
        : birDToplamMiktar;
    
    return Positioned(
      top: 16,
      left: 16,
      right: 100,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(180),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // SATIR 1: MOD ve MOD TOPLAMI + RAF KODU
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // MOD BİLGİSİ ve MOD TOPLAMI
                Row(
                  children: [
                    Icon(
                      _currentScannerMode == ScannerMode.otcBarkod
                          ? Icons.barcode_reader
                          : Icons.qr_code,
                      color: _currentScannerMode == ScannerMode.otcBarkod
                          ? Colors.cyan
                          : Colors.green,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // MOD ADI
                        Text(
                          _currentScannerMode == ScannerMode.otcBarkod
                              ? 'HIZLI 1D'
                              : 'İLAÇ QR',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // MOD TOPLAMI
                        Row(
                          children: [
                            const Icon(Icons.numbers, 
                                color: Colors.white70, size: 10),
                            const SizedBox(width: 2),
                            Text(
                              '$modToplam',
                              style: const TextStyle(
                                color: Colors.white70, 
                                fontSize: 10
                              ),
                            ),
                            const SizedBox(width: 4),
                            // MOD DETAY AÇIKLAMASI
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: _currentScannerMode == ScannerMode.otcBarkod
                                    ? Colors.cyan.withAlpha(30)
                                    : Colors.green.withAlpha(30),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                _currentScannerMode == ScannerMode.otcBarkod
                                    ? '1D'
                                    : 'QR',
                                style: TextStyle(
                                  color: _currentScannerMode == ScannerMode.otcBarkod
                                      ? Colors.cyan
                                      : Colors.green,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                
                // RAF KODU
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withAlpha(30),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.green,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shelves,
                          size: 12,
                          color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        widget.currentShelfCode,
                        style: const TextStyle(
                          color: Colors.green,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // SATIR 2: RAF TOPLAMI (TÜM BARKODLAR) + DİĞER MOD TOPLAMI + BATARYA
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // RAF TOPLAMI (TÜM BARKODLAR)
                Row(
                  children: [
                    Icon(Icons.inventory_2, 
                        color: Colors.amber[300], 
                        size: 14),
                    const SizedBox(width: 4),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // RAF TOPLAM ETİKETİ
                        Row(
                          children: [
                            Text(
                              'RAF TOPLAM',
                              style: TextStyle(
                                color: Colors.amber[300],
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 4),
                            // DİĞER MOD TOPLAMI (KÜÇÜK)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                              decoration: BoxDecoration(
                                color: _currentScannerMode == ScannerMode.otcBarkod
                                    ? Colors.green.withAlpha(20)
                                    : Colors.cyan.withAlpha(20),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: Text(
                                _currentScannerMode == ScannerMode.otcBarkod
                                    ? 'QR: $qrToplamMiktar'
                                    : '1D: $birDToplamMiktar',
                                style: TextStyle(
                                  color: _currentScannerMode == ScannerMode.otcBarkod
                                      ? Colors.green
                                      : Colors.cyan,
                                  fontSize: 7,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        // RAF TOPLAM MİKTARI
                        Text(
                          '$rafToplamMiktar adet',
                          style: const TextStyle(
                            color: Colors.white, 
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                
              ],
            ),
            
          ],
        ),
      ),
    );
  }
}