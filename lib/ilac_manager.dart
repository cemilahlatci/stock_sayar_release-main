// lib/ilac_manager.dart - QR ORJİNAL DÜZELTMELİ TAM KOD
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';
import 'scanned_item_model.dart';
import 'gs1_parser.dart';
import 'ui_helpers.dart';

class IlacModel {
  final String ilacAdi;
  final String barkod;
  final String tip;

  IlacModel({
    required this.ilacAdi,
    required this.barkod,
    this.tip = 'ilac',
  });

  factory IlacModel.fromCSV(List<dynamic> row) {
    String ilacAdi = '';
    String barkod = '';
    
    if (row.length >= 2) {
      barkod = row[0]?.toString().trim() ?? '';
      ilacAdi = row[1]?.toString().trim() ?? '';
    } else if (row.isNotEmpty) {
      barkod = row[0]?.toString().trim() ?? '';
    }
    
    barkod = barkod.replaceAll(RegExp(r'[^0-9]'), '');
    
    if (ilacAdi.isEmpty) {
      ilacAdi = 'Barkod: ${barkod.length > 12 ? '${barkod.substring(0, 12)}...' : barkod}';
    }
    
    return IlacModel(
      ilacAdi: ilacAdi,
      barkod: barkod,
      tip: 'ilac',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ilacAdi': ilacAdi,
      'barkod': barkod,
      'tip': tip,
    };
  }

  @override
  String toString() {
    return '$ilacAdi - $barkod ($tip)';
  }

}

class IlacManager {
  static final IlacManager _instance = IlacManager._internal();
  factory IlacManager() => _instance;
  
  IlacManager._internal() {
    _log('🚀 İlaç Yöneticisi başlatıldı');
    _loadFromCache();
  }

  Map<String, IlacModel> _ilacListesi = {};
  Map<String, IlacModel> _otcListesi = {};

  static const String _ilacCacheKey = 'ilac_listesi_cache';
  static const String _otcCacheKey = 'otc_listesi_cache';
  static const String _lastUpdateKey = 'ilac_listesi_last_update';
  static const Duration _cacheTTL = Duration(hours: 24);

  final DatabaseHelper _dbHelper = DatabaseHelper();

  static const String _ilacListesiUrl = 'https://stokdurum.com/analiz/uploads/ilacliste.csv';
  static const String _otcListesiUrl = 'https://stokdurum.com/analiz/uploads/otcliste.csv';

  bool _isInitialized = false;
  Completer<void>? _initCompleter;

  Future<void> initialize() async {
    if (_isInitialized) {
      // TTL kontrolü - süresi dolmuşsa arka planda güncelle
      _checkAndRefreshIfNeeded();
      return;
    }
    // Zaten başlatılıyorsa, mevcut Future'ı bekle (race condition önlenir)
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<void>();
    try {
      _log('🔄 İlaç Yöneticisi başlatılıyor...');

      await _loadFromCache();
      await _fetchAndUpdateLists();

      _isInitialized = true;
      _initCompleter!.complete();
      _log('✅ İlaç Yöneticisi başarıyla başlatıldı');

    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null;
      _log('❌ İlaç Yöneticisi başlatma hatası: $e');
    }
  }

  void _checkAndRefreshIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastUpdate = prefs.getString(_lastUpdateKey);
      if (lastUpdate != null) {
        final lastDate = DateTime.tryParse(lastUpdate);
        if (lastDate != null && DateTime.now().difference(lastDate) > _cacheTTL) {
          _log('🔄 Cache TTL dolmuş, arka planda güncelleniyor...');
          _fetchAndUpdateLists().catchError((e) {
            _log('❌ Arka plan güncelleme hatası: $e');
          });
        }
      }
    } catch (_) {}
  }

  String _normalizeGTIN(String barkod) {
    final temizBarkod = barkod.replaceAll(RegExp(r'[^0-9]'), '');
    
    if (temizBarkod.length == 14 && temizBarkod.startsWith('0')) {
      return temizBarkod.substring(1);
    }
    if (temizBarkod.length == 12) {
      return temizBarkod.padLeft(13, '0');
    }
    if (temizBarkod.length == 8) {
      return temizBarkod.padLeft(13, '0');
    }
    
    return temizBarkod;
  }

  Future<IlacModel?> ilacAra(String barkod) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    final normalizedBarkod = _normalizeGTIN(barkod);
    
    _log('🔍 Barkod aranıyor: $barkod -> Normalize: $normalizedBarkod');
    
    if (normalizedBarkod.isEmpty) {
      _log('⚠️ Geçersiz barkod: $barkod');
      return null;
    }
    
    try {
      if (_ilacListesi.containsKey(normalizedBarkod)) {
        final ilac = _ilacListesi[normalizedBarkod]!;
        _log('💊 İlaç bulundu: ${ilac.ilacAdi}');
        return ilac;
      }
      
      if (_otcListesi.containsKey(normalizedBarkod)) {
        final otc = _otcListesi[normalizedBarkod]!;
        _log('💊 OTC ürün bulundu: ${otc.ilacAdi}');
        return otc;
      }
      
      _log('❌ Barkod bulunamadı: $normalizedBarkod');
      return null;
      
    } catch (e) {
      _log('❌ İlaç arama hatası: $e');
      return null;
    }
  }

  Future<String> barkodTipiniBelirle(String barkod) async {
    final normalizedBarkod = _normalizeGTIN(barkod);
    
    if (_ilacListesi.containsKey(normalizedBarkod)) {
      return 'ilac';
    } else if (_otcListesi.containsKey(normalizedBarkod)) {
      return 'otc';
    } else {
      return 'unknown';
    }
  }

  Future<void> listeleriGuncelle() async {
    try {
      _log('🔄 İlaç listeleri güncelleniyor...');
      await _fetchAndUpdateLists();
      _log('✅ İlaç listeleri güncellendi');
    } catch (e) {
      _log('❌ Liste güncelleme hatası: $e');
      rethrow;
    }
  }

  Future<List<IlacModel>> _parseCsvFromResponse(http.Response response) async {
    try {
      String csvData;
      try {
        csvData = utf8.decode(response.bodyBytes);
      } catch (e) {
        csvData = latin1.decode(response.bodyBytes);
      }
      
      if (csvData.startsWith('\uFEFF')) {
        csvData = csvData.substring(1);
      }
      
      csvData = csvData.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      
      List<List<dynamic>> parsedLines;
      try {
        parsedLines = const CsvToListConverter(
          fieldDelimiter: ';',
          textDelimiter: '"',
          eol: '\n',
          shouldParseNumbers: false,
        ).convert(csvData);
      } catch (e) {
        try {
          parsedLines = const CsvToListConverter(
            fieldDelimiter: ',',
            textDelimiter: '"',
            eol: '\n',
            shouldParseNumbers: false,
          ).convert(csvData);
        } catch (e2) {
          parsedLines = _manualCsvParse(csvData);
        }
      }
      
      return _processParsedLines(parsedLines);
      
    } catch (e) {
      _log('❌ CSV parse hatası: $e');
      throw Exception('CSV parse hatası: $e');
    }
  }

  static List<List<dynamic>> _manualCsvParse(String csvData) {
    final List<List<dynamic>> parsedLines = [];
    final lines = csvData.split('\n');
    
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      
      try {
        var parts = line.split(';');
        if (parts.length < 2) {
          parts = line.split(',');
        }
        
        if (parts.isNotEmpty) {
          final cleanedParts = parts.map((part) => part.trim()).toList();
          parsedLines.add(cleanedParts);
        }
      } catch (e) {
        _log('❌ Satır parse hatası: $line - $e');
      }
    }
    
    return parsedLines;
  }

  static List<IlacModel> _processParsedLines(List<List<dynamic>> parsedLines) {
    final List<IlacModel> urunListesi = [];

    int startIndex = 0;
    if (parsedLines.isNotEmpty && parsedLines.first.isNotEmpty) {
      final firstCell = parsedLines.first[0].toString().toLowerCase();
      if (firstCell.contains('ilac') || firstCell.contains('urun') || firstCell.contains('adi') || 
          firstCell.contains('barkod') || firstCell.contains('product') || firstCell.contains('name')) {
        startIndex = 1;
        _log('ℹ️ Header satırı atlandı');
      }
    }

    int successCount = 0;
    int errorCount = 0;

    for (int i = startIndex; i < parsedLines.length; i++) {
      try {
        final row = parsedLines[i];
        if (row.isEmpty) continue;
        
        final ilac = IlacModel.fromCSV(row);
        
        if (ilac.barkod.isEmpty || ilac.barkod.length < 8) {
          errorCount++;
          continue;
        }
        
        urunListesi.add(ilac);
        successCount++;
        
      } catch (e) {
        errorCount++;
        _log('❌ Satır $i parse hatası: $e');
      }
    }

    _log('📊 CSV parse sonucu: $successCount başarılı, $errorCount hatalı');
    return urunListesi;
  }

  Future<http.Response> _httpGetWithRetry(String url, {int maxRetries = 3}) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        return await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      } catch (e) {
        if (attempt == maxRetries) rethrow;
        _log('⚠️ HTTP deneme $attempt/$maxRetries başarısız, tekrar deneniyor...');
        await Future.delayed(Duration(seconds: attempt * 2)); // Exponential backoff
      }
    }
    throw Exception('HTTP isteği başarısız: $url');
  }

  Future<void> _fetchAndUpdateLists() async {
    try {
      _log('🌐 İnternetten listeler çekiliyor...');

      final ilacCevap = await _httpGetWithRetry(_ilacListesiUrl);
      final otcCevap = await _httpGetWithRetry(_otcListesiUrl);
      
      if (ilacCevap.statusCode == 200 && otcCevap.statusCode == 200) {
        final ilacList = await _parseCsvFromResponse(ilacCevap);
        final otcList = await _parseCsvFromResponse(otcCevap);
        
        // ⚡ Atomik swap - arama sırasında boş durum oluşmaz
        final newIlacMap = <String, IlacModel>{};
        for (final ilac in ilacList) {
          newIlacMap[ilac.barkod] = ilac;
        }

        final newOtcMap = <String, IlacModel>{};
        for (final otc in otcList) {
          newOtcMap[otc.barkod] = IlacModel(
            ilacAdi: otc.ilacAdi,
            barkod: otc.barkod,
            tip: 'otc',
          );
        }

        _ilacListesi = newIlacMap;
        _otcListesi = newOtcMap;
        
        await _saveToCache();
        
        _log('✅ Listeler güncellendi: ${_ilacListesi.length} ilaç, ${_otcListesi.length} OTC');
        
      } else {
        throw Exception('HTTP hatası: İlaç=${ilacCevap.statusCode}, OTC=${otcCevap.statusCode}');
      }
      
    } catch (e) {
      _log('❌ Liste çekme hatası: $e');
      
      if (_ilacListesi.isEmpty || _otcListesi.isEmpty) {
        await _loadFromCache();
      }
      
      rethrow;
    }
  }

Future<void> barkoduIsle(
  String barkod, {
  required int miktar,
  required bool isQR,
  required bool basarili,
  String? rafKodu,
  String? expirationDate,
}) async {
  try {
    _log('🔄 Barkod işleniyor: $barkod (${isQR ? "QR" : "1D"})');
    
    String? gtin;
    String? qrExpirationDate;
    String? qrPartiNo;
    
    if (isQR) {
      final parsed = GS1Parser.parseBarkod(barkod);
      gtin = parsed.gtin;
      qrExpirationDate = parsed.sonKullanmaTarihi;
      qrPartiNo = parsed.partiNo;
      
      _log('📦 QR Parsed: GTIN=$gtin, SKT=$qrExpirationDate, Parti=$qrPartiNo');
    }
    
    // SADECE ARAMA İÇİN GTIN KULLAN, KAYIT İÇİN ORJİNAL BARKOD
    final String aramaBarkodu = isQR ? (gtin ?? barkod) : barkod;
    final ilac = await ilacAra(aramaBarkodu);
    
    String urunTipi = 'unknown';
    String? urunAdi;
    
    if (ilac != null) {
      urunTipi = ilac.tip;
      urunAdi = ilac.ilacAdi;
      _log('💊 Ürün bulundu: $urunTipi - $urunAdi');
    } else {
      _log('⚠️ Ürün bulunamadı: $aramaBarkodu');
      urunAdi = 'Barkod: ${barkod.length > 12 ? '${barkod.substring(0, 12)}...' : barkod}';
    }
    
    final finalExpirationDate = isQR ? qrExpirationDate : expirationDate;
    final finalBatchNumber = isQR ? qrPartiNo : null;
    
    // QR KODLARI ORJİNAL HALLERİYLE KAYDEDİLSİN
    final scannedItem = ScannedItem(
      barcode: barkod, // ✅ ORJİNAL BARKOD (QR da dahil)
      quantity: miktar,
      isQR: isQR,
      success: basarili,
      timestamp: DateTime.now(),
      productType: urunTipi,
      shelfCode: rafKodu,
      productName: urunAdi,
      expirationDate: finalExpirationDate,
      batchNumber: finalBatchNumber,
    );
    
    await _dbHelper.insertTarananUrun({
      'sayim_kodu': 'SAYIM_${DateTime.now().millisecondsSinceEpoch}',
      'barkod': scannedItem.barcode, // ✅ ORJİNAL BARKOD
      'is_qr': scannedItem.isQR ? 1 : 0,
      'adet': scannedItem.quantity,
      'raf_kodu': scannedItem.shelfCode ?? 'SGAA01C',
      'tarama_tarihi': scannedItem.timestamp.toIso8601String(),
      'durum': scannedItem.success ? 1 : 0,
      'sunucuya_gonderildi': 0,
      'product_type': scannedItem.productType ?? 'unknown',
      'product_name': scannedItem.productName,
      'expiration_date': scannedItem.expirationDate,
      'batch_number': scannedItem.batchNumber,
    });
    
    _log('✅ Barkod kaydedildi: ORJİNAL: $barkod - Ürün: $urunAdi - Tip: $urunTipi - SKT: $finalExpirationDate');
    
  } catch (e) {
    _log('❌ Barkod işleme hatası: $e');
    rethrow;
  }
}

  Future<void> urunTipiniGuncelle(String barkod, String yeniTip) async {
    try {
      if (yeniTip != 'ilac' && yeniTip != 'otc' && yeniTip != 'unknown') {
        _log('⚠️ Geçersiz ürün tipi: $yeniTip');
        return;
      }
      
      await _dbHelper.updateProductType(barkod, yeniTip);
      _log('✅ Ürün tipi güncellendi: $barkod -> $yeniTip');
      
    } catch (e) {
      _log('❌ Ürün tipi güncelleme hatası: $e');
    }
  }

  Future<void> tumUrunTipleriniGuncelle() async {
    try {
      _log('🔄 Tüm ürün tipleri güncelleniyor...');
      
      final tumOgeler = await _dbHelper.getTarananUrunler('');
      int guncellenen = 0;
      
      for (final ogeMap in tumOgeler) {
        final oge = ScannedItem.fromMap(ogeMap);
        final yeniTip = await barkodTipiniBelirle(oge.barcode);
        
        await urunTipiniGuncelle(oge.barcode, yeniTip);
        guncellenen++;
      }
      
      _log('✅ $guncellenen öğenin ürün tipi güncellendi');
      
    } catch (e) {
      _log('❌ Ürün tipi toplu güncelleme hatası: $e');
    }
  }

  Future<Map<String, dynamic>> istatistikleriGetir({String? rafKodu}) async {
    try {
      _log('📊 İstatistikler hesaplanıyor...');
      
      final urunler = await _dbHelper.getTarananUrunler('');
      final scannedItems = urunler.map((map) => ScannedItem.fromMap(map)).toList();
      
      final filteredItems = rafKodu != null 
          ? scannedItems.where((item) => item.shelfCode == rafKodu).toList()
          : scannedItems;
      
      final toplamTaranan = filteredItems.length;
      final toplamMiktar = filteredItems.fold(0, (sum, item) => sum + (item.isQR ? 1 : item.quantity));
      final benzersizUrun = filteredItems.map((item) => item.barcode).toSet().length;
      final ilacSayisi = filteredItems.where((item) => item.productType == 'ilac').length;
      final otcSayisi = filteredItems.where((item) => item.productType == 'otc').length;
      final bilinmeyenSayisi = filteredItems.where((item) => item.productType == 'unknown' || item.productType == null).length;
      final qrKodSayisi = filteredItems.where((item) => item.isQR).length;
      final barkodSayisi = filteredItems.where((item) => !item.isQR).length;
      
      final ilacMiktari = filteredItems
          .where((item) => item.productType == 'ilac')
          .fold(0, (sum, item) => sum + (item.isQR ? 1 : item.quantity));
          
      final otcMiktari = filteredItems
          .where((item) => item.productType == 'otc')
          .fold(0, (sum, item) => sum + (item.isQR ? 1 : item.quantity));
          
      final bilinmeyenMiktari = filteredItems
          .where((item) => item.productType == 'unknown' || item.productType == null)
          .fold(0, (sum, item) => sum + (item.isQR ? 1 : item.quantity));
      
      return {
        'toplam_taranan': toplamTaranan,
        'toplam_miktar': toplamMiktar,
        'benzersiz_urun': benzersizUrun,
        'ilac_sayisi': ilacSayisi,
        'ilac_miktari': ilacMiktari,
        'otc_sayisi': otcSayisi,
        'otc_miktari': otcMiktari,
        'bilinmeyen_sayisi': bilinmeyenSayisi,
        'bilinmeyen_miktari': bilinmeyenMiktari,
        'qr_kod_sayisi': qrKodSayisi,
        'barkod_sayisi': barkodSayisi,
      };
      
    } catch (e) {
      _log('❌ İstatistik hesaplama hatası: $e');
      return {
        'toplam_taranan': 0,
        'toplam_miktar': 0,
        'benzersiz_urun': 0,
        'ilac_sayisi': 0,
        'ilac_miktari': 0,
        'otc_sayisi': 0,
        'otc_miktari': 0,
        'bilinmeyen_sayisi': 0,
        'bilinmeyen_miktari': 0,
        'qr_kod_sayisi': 0,
        'barkod_sayisi': 0,
      };
    }
  }

  Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final ilacList = _ilacListesi.values.map((ilac) => ilac.toJson()).toList();
      await prefs.setString(_ilacCacheKey, jsonEncode(ilacList));
      
      final otcList = _otcListesi.values.map((otc) => otc.toJson()).toList();
      await prefs.setString(_otcCacheKey, jsonEncode(otcList));
      
      await prefs.setString(_lastUpdateKey, DateTimeHelper.nowIso8601());
      
      _log('💾 Listeler cache\'e kaydedildi');
      
    } catch (e) {
      _log('❌ Cache kaydetme hatası: $e');
    }
  }

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final ilacCache = prefs.getString(_ilacCacheKey);
      if (ilacCache != null) {
        final ilacList = (jsonDecode(ilacCache) as List)
            .map((item) => IlacModel(
                  ilacAdi: item['ilacAdi'] ?? '',
                  barkod: item['barkod'] ?? '',
                  tip: item['tip'] ?? 'ilac',
                ))
            .toList();

        // ⚡ Atomik swap
        final newIlacMap = <String, IlacModel>{};
        for (final ilac in ilacList) {
          newIlacMap[ilac.barkod] = ilac;
        }
        _ilacListesi = newIlacMap;
      }

      final otcCache = prefs.getString(_otcCacheKey);
      if (otcCache != null) {
        final otcList = (jsonDecode(otcCache) as List)
            .map((item) => IlacModel(
                  ilacAdi: item['ilacAdi'] ?? '',
                  barkod: item['barkod'] ?? '',
                  tip: item['tip'] ?? 'otc',
                ))
            .toList();

        // ⚡ Atomik swap
        final newOtcMap = <String, IlacModel>{};
        for (final otc in otcList) {
          newOtcMap[otc.barkod] = otc;
        }
        _otcListesi = newOtcMap;
      }
      
      _log('📂 Cache\'den yüklendi: ${_ilacListesi.length} ilaç, ${_otcListesi.length} OTC');
      
    } catch (e) {
      _log('❌ Cache yükleme hatası: $e');
    }
  }

  bool get isInitialized => _isInitialized;
  bool get isLoading => _initCompleter != null && !_initCompleter!.isCompleted;
  
  int get ilacSayisi => _ilacListesi.length;
  int get otcSayisi => _otcListesi.length;
  int get toplamUrunSayisi => _ilacListesi.length + _otcListesi.length;
  
  List<IlacModel> get ilacListesi => _ilacListesi.values.toList();
  List<IlacModel> get otcListesi => _otcListesi.values.toList();
  
  Future<DateTime?> get lastUpdate async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastUpdateStr = prefs.getString(_lastUpdateKey);
      return lastUpdateStr != null ? DateTime.parse(lastUpdateStr) : null;
    } catch (e) {
      return null;
    }
  }

  Future<void> cacheTemizle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_ilacCacheKey);
      await prefs.remove(_otcCacheKey);
      await prefs.remove(_lastUpdateKey);
      
      _ilacListesi = {};
      _otcListesi = {};
      _isInitialized = false;
      _initCompleter = null;

      _log('🧹 İlaç cache temizlendi');
      
    } catch (e) {
      _log('❌ Cache temizleme hatası: $e');
    }
  }

  void dispose() {
    _ilacListesi = {};
    _otcListesi = {};
    _isInitialized = false;
    _initCompleter = null;
    _log('♻️ İlaç Yöneticisi temizlendi');
  }

  Future<List<IlacModel>> ilacAraIsmeGore(String aramaKelimesi) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    final sonuclar = <IlacModel>[];
    final kucukArama = aramaKelimesi.toLowerCase();
    
    for (final ilac in _ilacListesi.values) {
      if (ilac.ilacAdi.toLowerCase().contains(kucukArama)) {
        sonuclar.add(ilac);
        if (sonuclar.length >= 10) break;
      }
    }
    
    for (final otc in _otcListesi.values) {
      if (otc.ilacAdi.toLowerCase().contains(kucukArama)) {
        sonuclar.add(otc);
        if (sonuclar.length >= 10) break;
      }
    }
    
    _log('🔍 İsim arama: "$aramaKelimesi" -> ${sonuclar.length} sonuç');
    return sonuclar;
  }

  Future<List<IlacModel>> ilacAraBarkodaGore(String barkodParcasi) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    final sonuclar = <IlacModel>[];
    final normalizedBarkod = _normalizeGTIN(barkodParcasi);
    
    if (normalizedBarkod.isEmpty) {
      return sonuclar;
    }
    
    for (final ilac in _ilacListesi.values) {
      if (ilac.barkod.contains(normalizedBarkod)) {
        sonuclar.add(ilac);
      }
    }
    
    for (final otc in _otcListesi.values) {
      if (otc.barkod.contains(normalizedBarkod)) {
        sonuclar.add(otc);
      }
    }
    
    _log('🔍 Barkod arama: "$barkodParcasi" -> Normalize: $normalizedBarkod -> ${sonuclar.length} sonuç');
    return sonuclar;
  }

  Future<Map<String, dynamic>> detayliIstatistikleriGetir() async {
    try {
      _log('📈 Detaylı istatistikler hesaplanıyor...');
      
      final urunler = await _dbHelper.getTarananUrunler('');
      final scannedItems = urunler.map((map) => ScannedItem.fromMap(map)).toList();
      
      final toplamTaranan = scannedItems.length;
      final toplamMiktar = scannedItems.totalQuantity;
      final benzersizUrun = scannedItems.uniqueBarcodes.length;
      
      final productTypeStats = scannedItems.productTypeStatistics;
      final expirationStats = scannedItems.expirationStatistics;
      final sendStats = scannedItems.sendStatistics;
      
      final rafGruplari = scannedItems.groupByShelf();
      final rafIstatistikleri = <String, Map<String, dynamic>>{};
      
      for (final raf in rafGruplari.keys) {
        final rafUrunleri = rafGruplari[raf]!;
        rafIstatistikleri[raf] = {
          'urun_sayisi': rafUrunleri.length,
          'toplam_miktar': rafUrunleri.totalQuantity,
          'benzersiz_urun': rafUrunleri.uniqueBarcodes.length,
          'ilac_sayisi': rafUrunleri.ilacCount,
          'otc_sayisi': rafUrunleri.otcCount,
          'bilinmeyen_sayisi': rafUrunleri.unknownCount,
        };
      }
      
      return {
        'genel': {
          'toplam_taranan': toplamTaranan,
          'toplam_miktar': toplamMiktar,
          'benzersiz_urun': benzersizUrun,
          'qr_kod_sayisi': scannedItems.qrCount,
          'barkod_sayisi': scannedItems.oneDItems.length,
        },
        'urun_tipleri': productTypeStats,
        'sk_t_durumu': expirationStats,
        'gonderim_durumu': sendStats,
        'raf_istatistikleri': rafIstatistikleri,
        'tamamlanma_orani': scannedItems.completionRate,
        'tamamlanma_yuzdesi': scannedItems.completionRateString,
      };
      
    } catch (e) {
      _log('❌ Detaylı istatistik hesaplama hatası: $e');
      return {
        'genel': {
          'toplam_taranan': 0,
          'toplam_miktar': 0,
          'benzersiz_urun': 0,
          'qr_kod_sayisi': 0,
          'barkod_sayisi': 0,
        },
        'urun_tipleri': {},
        'sk_t_durumu': {},
        'gonderim_durumu': {},
        'raf_istatistikleri': {},
        'tamamlanma_orani': 0.0,
        'tamamlanma_yuzdesi': '0%',
      };
    }
  }

  Future<bool> barkodGecerliMi(String barkod) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    final normalizedBarkod = _normalizeGTIN(barkod);
    return _ilacListesi.containsKey(normalizedBarkod) || _otcListesi.containsKey(normalizedBarkod);
  }

  Future<List<String>> onerilenIlacIsimleri(String baslangic) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    final oneriler = <String>[];
    final kucukBaslangic = baslangic.toLowerCase();
    
    for (final ilac in _ilacListesi.values) {
      if (ilac.ilacAdi.toLowerCase().startsWith(kucukBaslangic)) {
        oneriler.add(ilac.ilacAdi);
        if (oneriler.length >= 10) break;
      }
    }
    
    for (final otc in _otcListesi.values) {
      if (otc.ilacAdi.toLowerCase().startsWith(kucukBaslangic)) {
        oneriler.add(otc.ilacAdi);
        if (oneriler.length >= 10) break;
      }
    }
    
    return oneriler;
  }

  static void _log(String message) {
    // Log devre dışı - production build
  }
}