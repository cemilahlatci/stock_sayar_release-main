// lib/sayim_list_page.dart - GÜNCELLENMİŞ VERSİYON (İstatistikler düzeltildi)
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'scanned_item_model.dart';
import 'database_helper.dart';
import 'ui_helpers.dart';

class SayimListPage extends StatefulWidget {
  final List<ScannedItem> scannedItems;
  final Function(List<ScannedItem>) onItemsUpdated;

  const SayimListPage({
    super.key,
    required this.scannedItems,
    required this.onItemsUpdated,
  });

  @override
  State<SayimListPage> createState() => _SayimListPageState();
}

class _SayimListPageState extends State<SayimListPage> with SnackBarMixin {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<ScannedItem> _scannedItems = [];
  bool _isLoading = false;
  bool _isExporting = false;
  String _currentFilter = 'all';
  final String _currentSort = 'time_desc';
  String _searchQuery = '';
  bool _groupByShelf = true;
  final Map<String, bool> _expandedShelves = {};

  @override
  void initState() {
    super.initState();
    _loadDataFromDatabase();
  }

  // DATABASE'DEN VERİ YÜKLE
  Future<void> _loadDataFromDatabase() async {
    setState(() { _isLoading = true; });
    
    try {
      final items = await _dbHelper.getScannedItems('AKTIF_SAYIM');
      if (mounted) {
        setState(() {
          _scannedItems = items;
          _initializeExpandedShelves();
        });
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Veriler yüklenirken hata oluştu: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  void _initializeExpandedShelves() {
    final shelfGroups = _getShelfGroups();
    for (final shelf in shelfGroups.keys) {
      _expandedShelves[shelf] = true;
    }
  }

  // RAF KODU STANDARTLAŞTIRMA FONKSİYONU
  String _standardizeShelfCode(String shelfCode) {
    if (shelfCode == 'RAF_BELİRTİLMEMİŞ') {
      return '1'; // Varsayılan değer
    }
    
    // SGA01C → A01 dönüşümü
    if (shelfCode.startsWith('SG') && shelfCode.length >= 5) {
      return shelfCode.substring(2, 5); // 'SGA01C' → 'A01'
    }
    
    return shelfCode;
  }

  // RAF GRUPLARINI AL
  Map<String, List<ScannedItem>> _getShelfGroups() {
    final groups = <String, List<ScannedItem>>{};
    
    for (final item in _filteredAndSortedItems) {
      final rawShelf = item.shelfCode ?? 'RAF_BELİRTİLMEMİŞ';
      final standardizedShelf = _standardizeShelfCode(rawShelf);
      
      if (!groups.containsKey(standardizedShelf)) {
        groups[standardizedShelf] = [];
      }
      groups[standardizedShelf]!.add(item);
    }
    
    return groups;
  }

  // FİLTRELE VE SIRALA
  List<ScannedItem> get _filteredAndSortedItems {
    List<ScannedItem> filtered = _scannedItems;

    // Arama filtresi
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((item) =>
        item.barcode.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        (item.productName?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
        (item.shelfCode?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false)
      ).toList();
    }

    // Filtreleme
    switch (_currentFilter) {
      case 'unsent':
        filtered = filtered.where((item) => !item.isSentToServer || item.isUpdated).toList();
        break;
      case 'qr_only':
        filtered = filtered.where((item) => item.isQR).toList();
        break;
      case 'barcode_only':
        filtered = filtered.where((item) => !item.isQR).toList();
        break;
      case 'expiring_soon':
        filtered = filtered.where((item) => item.daysUntilExpiry != null && item.daysUntilExpiry! < 30).toList();
        break;
      case 'expired':
        filtered = filtered.where((item) => item.daysUntilExpiry != null && item.daysUntilExpiry! < 0).toList();
        break;
    }

    // Sıralama
    switch (_currentSort) {
      case 'time_desc':
        filtered = filtered.sortedByTime(ascending: false);
        break;
      case 'time_asc':
        filtered = filtered.sortedByTime(ascending: true);
        break;
      case 'quantity_desc':
        filtered.sort((a, b) => b.quantity.compareTo(a.quantity));
        break;
      case 'name_asc':
        filtered.sort((a, b) => (a.productName ?? a.barcode).compareTo(b.productName ?? b.barcode));
        break;
      case 'shelf_asc':
        filtered.sort((a, b) => (a.shelfCode ?? '').compareTo(b.shelfCode ?? ''));
        break;
    }

    return filtered;
  }


// ÜRÜN MİKTARINI GÜNCELLE (SADECE 1D BARKOD)
Future<void> _updateItemQuantity(ScannedItem item, int newQuantity) async {
  try {
    if (newQuantity <= 0) {
      // Miktar 0 veya negatif ise SİL
      await _dbHelper.deleteTarananUrun(int.parse(item.id));
      await _loadDataFromDatabase();
      
      if (mounted) {
        _showSnackBar('Ürün silindi (miktar 0)');
      }
    } else {
      // Normal güncelleme
      final updatedItem = item.copyWith(
        quantity: newQuantity,
        isUpdated: item.quantity != newQuantity,
      );
      
      await _dbHelper.updateScannedItem(updatedItem);
      await _loadDataFromDatabase();
      
      if (mounted) {
        _showSnackBar('$newQuantity adet olarak güncellendi');
      }
    }
  } catch (e) {
    if (mounted) {
      _showSnackBar('Güncelleme başarısız: $e', isError: true);
    }
  }
}

  // ÜRÜN SİL
Future<void> _deleteItem(ScannedItem item) async {
  try {
    await _dbHelper.deleteTarananUrun(int.parse(item.id));
    await _loadDataFromDatabase();
    
    // ✅ YENİ EKLENDİ: Ana sayfayı güncellemek için callback çağır
    widget.onItemsUpdated(_scannedItems);
    
    if (mounted) {
      _showSnackBar('Ürün silindi');
    }
  } catch (e) {
    if (mounted) {
      _showSnackBar('Silme başarısız: $e', isError: true);
    }
  }
}

  // TÜM HAM KODLARI İNDİR
  Future<void> _exportDataToFiles() async {
    if (_scannedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('İndirilecek veri bulunamadı'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final timestamp = DateTimeHelper.nowFileTimestamp();
      
      // BARKODLARI FİLTRELE (SADECE 1D BARKOD)
      final barkodItems = _scannedItems.where((item) => !item.isQR).toList();
      // KAREKODLARI FİLTRELE (SADECE QR KOD)
      final qrItems = _scannedItems.where((item) => item.isQR).toList();
      
      if (barkodItems.isEmpty && qrItems.isEmpty) {
        _showSnackBar('İndirilecek barkod veya karekod bulunmuyor');
        return;
      }

      // KESİN PUBLIC DOWNLOAD KLASÖRÜ YOLU
      Directory? directory = await _getPublicDownloadDirectory();

      if (directory == null) {
        throw Exception('Public Download klasörü bulunamadı');
      }

      // Klasör yoksa oluştur
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      // HAM BARKOD DOSYASI (SADECE BARKOD NUMARALARI)
      if (barkodItems.isNotEmpty) {
        final barkodContent = barkodItems.map((item) => item.barcode).join('\n');
        final barkodFilePath = '${directory.path}/ham_barkodlar_$timestamp.txt';
        await File(barkodFilePath).writeAsString(barkodContent, encoding: utf8);
      }

      // HAM KAREKOD DOSYASI (SADECE QR KOD NUMARALARI)
      if (qrItems.isNotEmpty) {
        final qrContent = qrItems.map((item) => item.barcode).join('\n');
        final qrFilePath = '${directory.path}/ham_karekodlar_$timestamp.txt';
        await File(qrFilePath).writeAsString(qrContent, encoding: utf8);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (barkodItems.isNotEmpty && qrItems.isNotEmpty)
                  Text('${barkodItems.length} ham barkod, ${qrItems.length} ham karekod PUBLIC Download klasörüne kaydedildi'),
                if (barkodItems.isNotEmpty && qrItems.isEmpty)
                  Text('${barkodItems.length} ham barkod PUBLIC Download klasörüne kaydedildi'),
                if (barkodItems.isEmpty && qrItems.isNotEmpty)
                  Text('${qrItems.length} ham karekod PUBLIC Download klasörüne kaydedildi'),
                Text('Klasör: ${directory.path}', style: const TextStyle(fontSize: 12)),
                const Text('Dosya Yöneticisi → İndirilenler (Downloads) klasöründe bulabilirsiniz', 
                    style: TextStyle(fontSize: 10)),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 6),
          ),
        );
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Public Download klasörüne kaydetme hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  // SADECE HAM BARKODLARI İNDİR
  Future<void> _downloadHamBarcodes() async {
    if (_scannedItems.isEmpty) {
      _showSnackBar('İndirilecek veri bulunmuyor');
      return;
    }

    setState(() => _isExporting = true);

    try {
      final barkodItems = _scannedItems.where((item) => !item.isQR).toList();
      
      if (barkodItems.isEmpty) {
        _showSnackBar('İndirilecek ham barkod bulunmuyor');
        return;
      }

      final timestamp = DateTimeHelper.nowFileTimestamp();
      final barkodContent = barkodItems.map((item) => item.barcode).join('\n');

      Directory? directory = await _getPublicDownloadDirectory();
      if (directory == null) {
        _showSnackBar('Download klasörü bulunamadı', isError: true);
        return;
      }

      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final barkodFilePath = '${directory.path}/ham_barkodlar_$timestamp.txt';
      await File(barkodFilePath).writeAsString(barkodContent, encoding: utf8);

      _showSnackBar('${barkodItems.length} ham barkod indirildi: $barkodFilePath');

    } catch (e) {
      _showSnackBar('Ham barkod indirme başarısız: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  // SADECE HAM KAREKODLARI İNDİR
  Future<void> _downloadHamQRCodes() async {
    if (_scannedItems.isEmpty) {
      _showSnackBar('İndirilecek veri bulunmuyor');
      return;
    }

    setState(() => _isExporting = true);

    try {
      final qrItems = _scannedItems.where((item) => item.isQR).toList();
      
      if (qrItems.isEmpty) {
        _showSnackBar('İndirilecek ham karekod bulunmuyor');
        return;
      }

      final timestamp = DateTimeHelper.nowFileTimestamp();
      final qrContent = qrItems.map((item) => item.barcode).join('\n');

      Directory? directory = await _getPublicDownloadDirectory();
      if (directory == null) {
        _showSnackBar('Download klasörü bulunamadı', isError: true);
        return;
      }

      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final qrFilePath = '${directory.path}/ham_karekodlar_$timestamp.txt';
      await File(qrFilePath).writeAsString(qrContent, encoding: utf8);

      _showSnackBar('${qrItems.length} ham karekod indirildi: $qrFilePath');


    } catch (e) {
      _showSnackBar('Ham karekod indirme başarısız: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  // PUBLIC DOWNLOAD KLASÖRÜNÜ BULMA FONKSİYONU - GELİŞTİRİLMİŞ
  Future<Directory?> _getPublicDownloadDirectory() async {
    try {
      // Yöntem 1: getExternalStorageDirectories - En güvenilir
      final externalDirs = await getExternalStorageDirectories();
      if (externalDirs != null && externalDirs.isNotEmpty) {
        for (final dir in externalDirs) {
          // Public Download klasörünü oluştur
          final publicDownloadPath = '${dir.path.replaceAll(RegExp(r'/Android/.*'), '')}/Download';
          final publicDownload = Directory(publicDownloadPath);

          if (await publicDownload.exists() || publicDownloadPath.contains('emulated')) {
            return publicDownload;
          }
        }
      }

      // Yöntem 2: Doğrudan yol denemesi - Android 10+
      const List<String> possiblePaths = [
        '/storage/emulated/0/Download',
        '/sdcard/Download',
        '/storage/sdcard0/Download',
      ];
      
      for (final path in possiblePaths) {
        final dir = Directory(path);
        if (await dir.exists()) {
          return dir;
        }
      }

      // Yöntem 3: getDownloadsDirectory - Sistem Download klasörü
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir != null) {
        return downloadsDir;
      }

      // Yöntem 4: External storage directory fallback
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final downloadPath = '${externalDir.path.replaceAll(RegExp(r'/Android/.*'), '')}/Download';
        final downloadDir = Directory(downloadPath);
        return downloadDir;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // DETAYLI TXT İNDİRME FONKSİYONLARI
  Future<void> _downloadDetailedBarcodesAsTxt() async {
    try {
      final barcodeItems = _scannedItems.where((item) => !item.isQR).toList();
      if (barcodeItems.isEmpty) {
        _showSnackBar('İndirilecek barkod bulunmuyor');
        return;
      }

      final content = StringBuffer();
      content.writeln('=== BARKOD LİSTESİ ===');
      content.writeln('Oluşturulma: ${DateTime.now()}');
      content.writeln('Toplam: ${barcodeItems.length} barkod');
      content.writeln('');
      
      for (final item in barcodeItems) {
        content.writeln('Barkod: ${item.barcode}');
        content.writeln('Ürün Adı: ${item.productName ?? "Belirtilmemiş"}');
        content.writeln('Miktar: ${item.quantity} adet');
        content.writeln('Raf: ${item.shelfCode ?? "Belirtilmemiş"}');
        content.writeln('Tip: ${item.productTypeString}');
        if (item.expirationDate != null) {
          content.writeln('SKT: ${item.formattedExpirationDate}');
        }
        content.writeln('---');
      }

      final directory = await _getPublicDownloadDirectory();
      if (directory == null) {
        _showSnackBar('Download klasörü bulunamadı', isError: true);
        return;
      }

      final fileName = 'detayli_barkodlar_${DateTimeHelper.nowShortTimestamp()}.txt';
      final filePath = '${directory.path}/$fileName';
      
      await File(filePath).writeAsString(content.toString(), encoding: utf8);

      _showSnackBar('Detaylı barkodlar PUBLIC Download klasörüne kaydedildi: $fileName');

    } catch (e) {
      _showSnackBar('İndirme başarısız: $e', isError: true);
    }
  }

  Future<void> _downloadDetailedQRCodesAsTxt() async {
    try {
      final qrItems = _scannedItems.where((item) => item.isQR).toList();
      if (qrItems.isEmpty) {
        _showSnackBar('İndirilecek karekod bulunmuyor');
        return;
      }

      final content = StringBuffer();
      content.writeln('=== KAREKOD LİSTESİ ===');
      content.writeln('Oluşturulma: ${DateTime.now()}');
      content.writeln('Toplam: ${qrItems.length} karekod');
      content.writeln('');
      
      for (final item in qrItems) {
        content.writeln('Karekod: ${item.barcode}');
        content.writeln('Ürün Adı: ${item.productName ?? "Belirtilmemiş"}');
        content.writeln('Raf: ${item.shelfCode ?? "Belirtilmemiş"}');
        content.writeln('Tip: ${item.productTypeString}');
        if (item.expirationDate != null) {
          content.writeln('SKT: ${item.formattedExpirationDate}');
        }
        if (item.batchNumber != null) {
          content.writeln('Parti: ${item.batchNumber}');
        }
        content.writeln('---');
      }

      final directory = await _getPublicDownloadDirectory();
      if (directory == null) {
        _showSnackBar('Download klasörü bulunamadı', isError: true);
        return;
      }

      final fileName = 'detayli_karekodlar_${DateTimeHelper.nowShortTimestamp()}.txt';
      final filePath = '${directory.path}/$fileName';
      
      await File(filePath).writeAsString(content.toString(), encoding: utf8);

      _showSnackBar('Detaylı karekodlar PUBLIC Download klasörüne kaydedildi: $fileName');

    } catch (e) {
      _showSnackBar('İndirme başarısız: $e', isError: true);
    }
  }


  void _showSnackBar(String message, {bool isError = false}) {
    showAppSnackBar(message, isError: isError);
  }

  @override
  Widget build(BuildContext context) {
    final filteredItems = _filteredAndSortedItems;
    final shelfGroups = _getShelfGroups();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sayım Listesi'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          // İNDİRME MENÜSÜ - GÜNCELLENMİŞ
          PopupMenuButton<String>(
            icon: _isExporting 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            onSelected: (value) {
              switch (value) {
                case 'ham_barkodlar':
                  _downloadHamBarcodes();
                  break;
                case 'ham_karekodlar':
                  _downloadHamQRCodes();
                  break;
                case 'ham_hepsi':
                  _exportDataToFiles();
                  break;
                case 'detailed_barcodes':
                  _downloadDetailedBarcodesAsTxt();
                  break;
                case 'detailed_qrcodes':
                  _downloadDetailedQRCodesAsTxt();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'ham_hepsi',
                child: Row(
                  children: [
                    Icon(Icons.file_download, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Tüm Ham Kodları İndir'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'ham_barkodlar',
                child: Row(
                  children: [
                    Icon(Icons.barcode_reader, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Barkodları İndir'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'ham_karekodlar',
                child: Row(
                  children: [
                    Icon(Icons.qr_code, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Karekodları İndir'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'detailed_barcodes',
                child: Row(
                  children: [
                    Icon(Icons.description, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Detaylı Barkodları İndir (TXT)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'detailed_qrcodes',
                child: Row(
                  children: [
                    Icon(Icons.description, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Detaylı Karekodları İndir (TXT)'),
                  ],
                ),
              ),
            ],
          ),
          // GRUPLAMA BUTONU
          IconButton(
            icon: Icon(_groupByShelf ? Icons.view_list : Icons.view_module),
            onPressed: () {
              setState(() {
                _groupByShelf = !_groupByShelf;
              });
            },
            tooltip: _groupByShelf ? 'Liste Görünümü' : 'Raf Gruplama',
          ),
          // ARAMA BUTONU
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _showSearchDialog(),
            tooltip: 'Ara',
          ),
          // FİLTRE MENÜSÜ
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() { _currentFilter = value; });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('Tümü')),
              const PopupMenuItem(value: 'unsent', child: Text('Gönderilmeyenler')),
              const PopupMenuItem(value: 'qr_only', child: Text('Sadece QR Kodlar')),
              const PopupMenuItem(value: 'barcode_only', child: Text('Sadece Barkodlar')),
              const PopupMenuItem(value: 'expiring_soon', child: Text('Yakında Dolacaklar')),
              const PopupMenuItem(value: 'expired', child: Text('Süresi Dolmuşlar')),
            ],
          ),
        ],
      ),
      backgroundColor: AppColors.scaffoldBackground,
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(filteredItems, shelfGroups),
      // FloatingActionButton kaldırıldı
    );
  }

  Widget _buildContent(List<ScannedItem> items, Map<String, List<ScannedItem>> shelfGroups) {
    return Column(
      children: [
        // İSTATİSTİK KARTI - DÜZELTİLMİŞ
        _buildStatisticsCard(),
        
        // FİLTRE BİLGİSİ
        if (_currentFilter != 'all' || _searchQuery.isNotEmpty)
          _buildFilterInfo(items.length),
        
        // LİSTE
        Expanded(
          child: items.isEmpty
              ? _buildEmptyState()
              : _groupByShelf 
                  ? _buildShelfGroupedList(shelfGroups)
                  : _buildFlatList(items),
        ),
      ],
    );
  }

Widget _buildStatisticsCard() {
  // Barkod toplam miktarı (1D barkodların quantity değerlerinin toplamı)
  final barcodeTotalQuantity = _scannedItems
      .where((item) => !item.isQR)
      .fold(0, (sum, item) => sum + item.quantity);
  
  // Karekod toplamı (her biri 1 adet)
  final qrTotalCount = _scannedItems.where((item) => item.isQR).length;
  
  // TOPLAM ADET: Barkod miktarları + Karekod sayısı
  final totalItems = barcodeTotalQuantity + qrTotalCount;
  
  // BEKLEYEN ADET: Sunucuya gönderilmemiş veya güncellenmiş öğelerin TOPLAM ADEDİ
  final pendingQuantity = _scannedItems
      .where((item) => !item.isSentToServer || item.isUpdated)
      .fold(0, (sum, item) => sum + (item.isQR ? 1 : item.quantity));
  
  return Card(
    margin: const EdgeInsets.all(8),
    color: AppColors.cardBackground,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Toplam ADET
          _buildStatItem('Toplam', totalItems.toString(), Icons.inventory_2),
          
          // Barkod: Toplam adet miktarı
          _buildStatItem('Barkod', barcodeTotalQuantity.toString(), Icons.barcode_reader, color: Colors.blue),
          
          // Karekod: Çeşit sayısı (her biri 1 adet)
          _buildStatItem('Karekod', qrTotalCount.toString(), Icons.qr_code, color: Colors.green),
          
          // Bekleyen: Gönderilmemiş TOPLAM ADET
          _buildStatItem('Bekleyen', pendingQuantity.toString(), Icons.pending, color: Colors.orange),
        ],
      ),
    ),
  );
}

  Widget _buildStatItem(String title, String value, IconData icon, {Color color = Colors.white}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        Text(title, style: const TextStyle(color: Colors.grey, fontSize: 10)),
      ],
    );
  }

  Widget _buildFilterInfo(int itemCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.blue.withAlpha(30),
      child: Row(
        children: [
          const Icon(Icons.filter_alt, size: 16, color: Colors.blue),
          const SizedBox(width: 8),
          Text(
            '$itemCount ürün bulundu',
            style: const TextStyle(color: Colors.blue, fontSize: 12),
          ),
          const Spacer(),
          TextButton(
            onPressed: () {
              setState(() {
                _currentFilter = 'all';
                _searchQuery = '';
              });
            },
            child: const Text('Filtreyi Temizle', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inventory_2,
            size: 80,
            color: AppColors.textSubtle,
          ),
          SizedBox(height: 16),
          Text(
            'Henüz ürün bulunmuyor',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          SizedBox(height: 8),
          Text(
            'Scanner sayfasından tarama yaparak başlayın',
            style: TextStyle(fontSize: 14, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // RAF BAZLI GRUPLANMIŞ LİSTE - ListView.builder ile
  Widget _buildShelfGroupedList(Map<String, List<ScannedItem>> shelfGroups) {
    final shelfList = shelfGroups.entries.toList();
    
    return RefreshIndicator(
      onRefresh: _loadDataFromDatabase,
      child: ListView.builder(
        itemCount: shelfList.length,
        itemBuilder: (context, index) {
          final shelfEntry = shelfList[index];
          return KeyedSubtree(
            key: ValueKey(shelfEntry.key),
            child: _buildShelfGroup(shelfEntry.key, shelfEntry.value),
          );
        },
      ),
    );
  }

Widget _buildShelfGroup(String shelf, List<ScannedItem> items) {
  final isExpanded = _expandedShelves[shelf] ?? true;
  // Raf için bekleyen ADETİNİ hesapla (çeşit değil)
  final pendingQuantity = items
      .where((item) => !item.isSentToServer || item.isUpdated)
      .fold(0, (sum, item) => sum + (item.isQR ? 1 : item.quantity));

  return Card(
    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    color: AppColors.cardBackground,
    child: ExpansionTile(
      key: Key(shelf),
      initiallyExpanded: isExpanded,
      onExpansionChanged: (expanded) {
        setState(() {
          _expandedShelves[shelf] = expanded;
        });
      },
      leading: const Icon(Icons.shelves, color: Colors.orange),
      title: Row(
        children: [
          Text(
            shelf,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 8),
          if (pendingQuantity > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$pendingQuantity bekleyen',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
        ],
      ),
      subtitle: Text(
        '${items.length} ürün • ${items.fold(0, (sum, item) => sum + (item.isQR ? 1 : item.quantity))} adet',
        style: const TextStyle(color: Colors.grey),
      ),
      trailing: Icon(
        isExpanded ? Icons.expand_less : Icons.expand_more,
        color: Colors.white,
      ),
      children: [
        for (final item in items)
          _buildGroupedListItem(item),
      ],
    ),
  );
}

  Widget _buildGroupedListItem(ScannedItem item) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.listItemBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: _buildItemLeading(item),
        title: Text(
          item.displayProductName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${item.typeString} • ${item.formattedTime}', 
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
            if (item.expirationDate != null) 
              Text('SKT: ${item.formattedExpirationDate}', 
                style: TextStyle(
                  color: item.expirationStatusColor,
                  fontSize: 11,
                )),
          ],
        ),
        trailing: _buildItemActions(item),
        onLongPress: () => _showItemOptions(item),
      ),
    );
  }

  // ÜRÜN AKSİYONLARI - TİPE GÖRE
  Widget _buildItemActions(ScannedItem item) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // MİKTAR GÖSTERİMİ (SADECE 1D BARKOD)
        if (!item.isQR)
          GestureDetector(
            onTap: () => _showQuantityDialog(item),
            child: Chip(
              label: Text('${item.quantity} adet', 
                style: const TextStyle(fontSize: 11)),
              backgroundColor: Colors.blue.withAlpha(50),
              side: const BorderSide(color: Colors.blue),
            ),
          ),
        if (item.isQR)
          Chip(
            label: const Text('1 adet', 
              style: TextStyle(fontSize: 11)),
            backgroundColor: Colors.green.withAlpha(50),
            side: const BorderSide(color: Colors.green),
          ),
        const SizedBox(width: 4),
        // DURUM
        _buildStatusIcon(item),
      ],
    );
  }

  // ÜRÜN SEÇENEKLERİ - TİPE GÖRE
  void _showItemOptions(ScannedItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBackground,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Sil', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showDeleteConfirmation(item);
              },
            ),
            if (!item.isQR) // SADECE 1D BARKOD İÇİN DÜZENLE
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text('Miktarı Düzenle', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showQuantityDialog(item);
                },
              ),
            ListTile(
              leading: const Icon(Icons.cancel, color: Colors.grey),
              title: const Text('İptal', style: TextStyle(color: Colors.grey)),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(ScannedItem item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text('Ürünü Sil', style: TextStyle(color: Colors.white)),
        content: Text('"${item.displayProductName}" ürününü silmek istediğinizden emin misiniz?', 
          style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteItem(item);
            },
            child: const Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // DÜZ LİSTE (GRUPLAMA OLMADAN) - ListView.builder ile
  Widget _buildFlatList(List<ScannedItem> items) {
    return RefreshIndicator(
      onRefresh: _loadDataFromDatabase,
      child: ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return KeyedSubtree(
            key: ValueKey(item.id),
            child: _buildFlatListItem(item),
          );
        },
      ),
    );
  }

  Widget _buildFlatListItem(ScannedItem item) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: AppColors.cardBackground,
      child: ListTile(
        leading: _buildItemLeading(item),
        title: Text(
          item.displayProductName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${item.typeString} • ${item.formattedTime}', 
              style: const TextStyle(color: Colors.grey)),
            if (item.shelfCode != null) 
              Text('Raf: ${item.shelfCode}', 
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            if (item.expirationDate != null) 
              Text('SKT: ${item.formattedExpirationDate}', 
                style: TextStyle(
                  color: item.expirationStatusColor,
                  fontSize: 12,
                )),
          ],
        ),
        trailing: _buildItemActions(item),
        onLongPress: () => _showItemOptions(item),
      ),
    );
  }

  Widget _buildItemLeading(ScannedItem item) {
    IconData icon;
    Color color;

    if (item.isSentToServer && !item.isUpdated) {
      icon = Icons.check_circle;
      color = Colors.green;
    } else if (item.isUpdated) {
      icon = Icons.edit;
      color = Colors.orange;
    } else if (item.isQR) {
      icon = Icons.qr_code;
      color = Colors.green;
    } else {
      icon = Icons.barcode_reader;
      color = Colors.blue;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _buildStatusIcon(ScannedItem item) {
    if (item.isUpdated) {
      return const Tooltip(
        message: 'Güncellendi - Tekrar gönderilmeli',
        child: Icon(Icons.edit, color: Colors.orange, size: 20),
      );
    } else if (!item.isSentToServer) {
      return const Tooltip(
        message: 'Sunucuya gönderilmedi',
        child: Icon(Icons.pending, color: Colors.orange, size: 20),
      );
    } else {
      return const Tooltip(
        message: 'Sunucuya gönderildi',
        child: Icon(Icons.check_circle, color: Colors.green, size: 20),
      );
    }
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text('Ürün Ara', style: TextStyle(color: Colors.white)),
        content: TextField(
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Barkod, ürün adı veya raf kodu...',
            hintStyle: TextStyle(color: Colors.grey),
          ),
          onChanged: (value) {
            setState(() { _searchQuery = value; });
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() { _searchQuery = ''; });
              Navigator.pop(context);
            },
            child: const Text('Temizle', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showQuantityDialog(ScannedItem item) {
    final controller = TextEditingController(text: item.quantity.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text('Miktarı Güncelle', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Yeni Miktar',
            labelStyle: TextStyle(color: Colors.grey),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => _handleQuantityUpdate(item, controller.text),
            child: const Text('Kaydet', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  Future<void> _handleQuantityUpdate(ScannedItem item, String quantityText) async {
  final newQuantity = int.tryParse(quantityText) ?? item.quantity;
  await _updateItemQuantity(item, newQuantity);
  
  // ✅ YENİ EKLENDİ: Ana sayfayı güncellemek için callback çağır
  widget.onItemsUpdated(_scannedItems);
  
  // ✅ YENİ EKLENDİ: Verileri yeniden yükle
  await _loadDataFromDatabase();
}
}