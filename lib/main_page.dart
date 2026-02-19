// lib/main_page.dart - TÜM SAYIMLARI KAPSAYAN İSTATİSTİKLER

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'scanner_widgets.dart';
import 'sayim_list_page.dart';
import 'scanned_item_model.dart';
import 'login_page.dart';
import 'database_helper.dart';
import 'ilac_manager.dart';
import 'auth_service.dart';
import 'ui_helpers.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with SnackBarMixin {
  int _currentIndex = 0;
  String _currentShelfCode = "";
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final IlacManager _ilacManager = IlacManager();
  
  List<ScannedItem> _scannedItems = [];
  List<ScannedItem> _allScannedItems = [];
  bool _waitingForShelfCode = false;
  bool _isSendingData = false;
  bool _miadUyarisiAktif = true;

  // YENİ EKLENEN: Geri tuşu için zaman değişkeni
  DateTime? _lastBackPressTime;

  // ⚡ HESAPLAMA CACHE - her render'da yeniden hesaplanmaz
  Map<String, int>? _cachedStatistics;
  List<ScannedItem>? _cachedRecentItems;

  void _invalidateCache() {
    _cachedStatistics = null;
    _cachedRecentItems = null;
  }

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      await _loadLastShelfCode();
      await _loadMiadAyari();
      await _loadDataFromDatabase(); // ⚡ OPTİMİZASYON: Tek fonksiyon
      await _initializeIlacDatabase();
      _checkShelfStatus();
    } catch (_) {
      // Uygulama başlatma hatası - sessizce devam et
    }
  }

  Future<void> _loadLastShelfCode() async {
    String shelfCode = "";
    bool waiting = true;

    try {
      // ⚡ OPTİMİZASYON: Raf kodu artık SharedPreferences'ta TUTULMUYOR
      // Database'den mevcut raftaki ürünlerin raf kodunu al
      final db = DatabaseHelper();
      final allItems = await db.getScannedItems('AKTIF_SAYIM');

      if (allItems.isNotEmpty) {
        final firstItemShelfCode = allItems.first.shelfCode;
        if (firstItemShelfCode != null && firstItemShelfCode.isNotEmpty) {
          shelfCode = firstItemShelfCode;
          waiting = false;
        }
      }
    } catch (_) {
      // Hata durumunda varsayılan değerler kullanılır
    }

    if (mounted) {
      setState(() {
        _currentShelfCode = shelfCode;
        _waitingForShelfCode = waiting;
      });
    }
  }

  Future<void> _loadMiadAyari() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _miadUyarisiAktif = prefs.getBool('miad_uyarisi_aktif') ?? true;
      });
    } catch (_) {}
  }

  Future<void> _saveMiadAyari(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('miad_uyarisi_aktif', value);
    } catch (_) {}
  }

  // ⚡ OPTİMİZASYON: Raf kodu artık SharedPreferences'ta TUTULMUYOR
  // Database'de her üründe zaten var - ÇİFTE KAYIT ÖNLENDİ

  void _checkShelfStatus() {
    if (_currentShelfCode.isEmpty && _allScannedItems.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showShelfWarningDialog();
        }
      });
    }
  }

  void _showShelfWarningDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text(
              'Raf Kodu Eksik',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Taranmış ${_allScannedItems.length} ürün bulunuyor ancak raf kodu kayıtlı değil.\n\n'
          'Lütfen önceki raftaki sayıma devam etmek için o rafın barkodunu taratın '
          'veya yeni sayım başlatın.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (mounted) {
                setState(() {
                  _waitingForShelfCode = true;
                  _currentIndex = 1;
                });
              }
              _showSnackBar('Lütfen raf barkodunu taratın', isError: false);
            },
            child: const Text('RAF TARA', style: TextStyle(color: Colors.orange)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _startNewSayim();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('YENİ SAYIM', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _loadDataFromDatabase() async {
    try {
      // ⚡ OPTİMİZASYON: Tüm verileri TEK SEFERDE al
      final allItems = await _dbHelper.getScannedItems('AKTIF_SAYIM');
      
      if (mounted) {
        setState(() {
          _allScannedItems = allItems;

          // MEVCUT RAF'A GÖRE FİLTRELE
          if (_currentShelfCode.isEmpty || _waitingForShelfCode) {
            _scannedItems = allItems;
          } else {
            _scannedItems = allItems.where(
              (item) => item.shelfCode == _currentShelfCode
            ).toList();
          }
          _invalidateCache();
        });
      }

    } catch (e) {
      // Hata durumunda boş liste ata
      if (mounted) {
        setState(() {
          _scannedItems = [];
          _allScannedItems = [];
          _invalidateCache();
        });
      }
    }
  }

  // ⚡ OPTİMİZASYON: _loadAllDataFromDatabase KALDIRILDI
  // Artık _loadDataFromDatabase hem tüm verileri hem filtrelenmiş verileri yüklüyor

  Future<void> _initializeIlacDatabase() async {
    try {
      if (_ilacManager.toplamUrunSayisi == 0) {
        await _ilacManager.initialize();
      }
    } catch (_) {
      // İlaç veritabanı başlatma başarısız - tarama yine çalışır
    }
  }

  Future<void> _addItemToDatabase(ScannedItem item) async {
    try {
      await _dbHelper.insertScannedItem(item, shelfCode: _currentShelfCode);
    } catch (e) {
      _showSnackBar('Ürün eklenirken hata oluştu', isError: true);
    }
  }

  void _onShelfCodeDetected(String newShelfCode) async {
    try {
      if (_scannedItems.isNotEmpty && _currentShelfCode.isNotEmpty) {
        await _sendCurrentShelfToServer();
      }
      
      // ⚡ OPTİMİZASYON: Raf kodu SharedPreferences'a KAYDEDİLMİYOR
      // Database'de her üründe zaten var
      
      final newShelfItems = await _dbHelper.getScannedItemsByShelf(newShelfCode, sayimKodu: 'AKTIF_SAYIM');
      
      if (mounted) {
        setState(() {
          _currentShelfCode = newShelfCode;
          _scannedItems = newShelfItems;
          _waitingForShelfCode = false;
          _invalidateCache();
        });
      }
      
      _showSnackBar('Raf değiştirildi: $newShelfCode - Önceki raf verileri sunucuya gönderildi');
      
    } catch (e) {
      _showSnackBar('Raf değiştirilirken hata oluştu', isError: true);
    }
  }

  Future<void> _sendCurrentShelfToServer() async {
    if (_scannedItems.isEmpty) return;
    
    try {
      if (mounted) {
        setState(() {
          _isSendingData = true;
        });
      }
      
      final unsentItems = _scannedItems.where((item) => !item.isSentToServer || item.isUpdated).toList();
      
      if (unsentItems.isEmpty) {
        return;
      }

      final success = await _sendToServerAPI(unsentItems, _currentShelfCode);
      
      if (success) {
        for (final item in unsentItems) {
          await _dbHelper.updateScannedItem(item.copyWith(
            isSentToServer: true,
            isUpdated: false,
          ));
        }
        
        _showSnackBar('${unsentItems.length} ürün sunucuya otomatik gönderildi (Raf: $_currentShelfCode)');
        
        await _loadDataFromDatabase(); // ⚡ OPTİMİZASYON: Tek fonksiyon
      } else {
        _showSnackBar('Otomatik gönderim başarısız oldu', isError: true);
      }
      
    } catch (e) {
      _showSnackBar('Otomatik gönderim hatası: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSendingData = false;
        });
      }
    }
  }

  Future<bool> _sendToServerAPI(List<ScannedItem> items, String shelfCode) async {
    try {
      final userData = await AuthService.getCurrentUser();
      
      if (userData == null) {
        _showSnackBar('Kullanıcı bilgileri bulunamadı. Lütfen tekrar giriş yapın.', isError: true);
        return false;
      }
      
      const apiUrl = 'https://stokdurum.com/cemil/android_api.php';
      
      final glnno = userData['eczane_gln'] ?? '8680001999999';
      const sayimkodu = '1';
      const tabletid = '1';
      final username = userData['person_name'] ?? 'bilge';
      
      String standardizeShelfCode(String code) {
        if (code == 'RAF_BELİRTİLMEMİŞ') {
          return '1';
        }
        if (code.startsWith('SG') && code.length >= 5) {
          return code.substring(2, 5);
        }
        return code;
      }
      
      final standardizedShelfCode = standardizeShelfCode(shelfCode);

      final products = items.map((item) {
        return {
          'barkod': item.barcode,
          'adet': item.isQR ? 1 : item.quantity,
          'durum': '1',
          'scandate': item.timestamp.toIso8601String(),
        };
      }).toList();

      final requestBody = {
        'glnno': glnno,
        'sayimkodu': sayimkodu,
        'tabletid': tabletid,
        'username': username,
        'rafkodu': standardizedShelfCode,
        'products': products,
      };

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        
        if (responseData['status'] == 'success') {
          return true;
        } else {
          return false;
        }
      } else {
        return false;
      }

    } catch (e) {
      return false;
    }
  }

  Map<String, int> _calculateStatistics() {
    int totalQuantity = 0;
    int qrQuantity = 0;
    int barcodeQuantity = 0;
    
    for (final item in _allScannedItems) {
      if (item.success) {
        final quantity = item.isQR ? 1 : item.quantity;
        totalQuantity += quantity;
        
        if (item.isQR) {
          qrQuantity += quantity;
        } else {
          barcodeQuantity += quantity;
        }
      }
    }
    
    final sentCount = _allScannedItems.where((item) => item.isSentToServer && !item.isUpdated).length;
    final pendingCount = _allScannedItems.where((item) => !item.isSentToServer || item.isUpdated).length;
    
    return {
      'total': totalQuantity,       // Toplam adet miktarı
      'qr': qrQuantity,            // QR kodlu ürün adet miktarı
      'barcode': barcodeQuantity,  // Barkodlu ürün adet miktarı
      'sent': sentCount,           // Gönderilen ürün çeşidi sayısı
      'pending': pendingCount,     // Bekleyen ürün çeşidi sayısı
    };
  }

  void _showSnackBar(String message, {bool isError = false}) {
    showAppSnackBar(message, isError: isError);
  }

  @override
Widget build(BuildContext context) {
  return PopScope(
    canPop: false,
    onPopInvokedWithResult: (bool didPop, Object? result) async {
      if (didPop) return;
      
      // Scanner veya liste sayfasındaysak ana sayfaya dön
      if (_currentIndex != 0) {
        if (mounted) {
          setState(() {
            _currentIndex = 0;
          });
        }
        return;
      }
      
      // Ana sayfadaysa çift tıklama kontrolü
      final now = DateTime.now();
      
      if (_lastBackPressTime == null || 
          now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
        // İlk tıklama
        _lastBackPressTime = now;
        if (mounted) {
          _showSnackBar('Çıkmak için tekrar dokunun', isError: false);
        }
        return;
      }
      
      // İkinci tıklama - login sayfasına yönlendir
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Stok Sayım'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isSendingData)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Gönderiliyor...',
                    style: TextStyle(
                      color: Colors.orange[400],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout, size: 20),
            onPressed: _logout,
          ),
        ],
      ),
      backgroundColor: AppColors.scaffoldBackground,
      body: _buildCurrentPage(),
      bottomNavigationBar: _buildBottomNavBar(),
    ),
  );
}

  Widget _buildCurrentPage() {
    switch (_currentIndex) {
      case 0:
        return _buildHomePage();
      case 1:
        return UnifiedScannerWidget(
          onBarcodeDetected: _onBarcodeDetected,
          currentShelfItems: _scannedItems,
          currentShelfCode: _currentShelfCode,
          onShelfCodeDetected: _onShelfCodeDetected,
          waitingForShelfCode: _waitingForShelfCode,
          miadUyarisiAktif: _miadUyarisiAktif,
        );
      case 2:
        return SayimListPage(
          scannedItems: _scannedItems,
          onItemsUpdated: _onItemsUpdated,
        );
      default:
        return _buildHomePage();
    }
  }

  BottomNavigationBar _buildBottomNavBar() {
    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: (index) => setState(() => _currentIndex = index),
      backgroundColor: Colors.black,
      selectedItemColor: Colors.blue,
      unselectedItemColor: Colors.grey,
      selectedFontSize: 12,
      unselectedFontSize: 12,
      iconSize: 20,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: 'Ana Sayfa',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.qr_code_scanner),
          label: 'Scanner',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.list),
          label: 'Liste',
        ),
      ],
    );
  }

  Widget _buildHomePage() {
    final statistics = _cachedStatistics ??= _calculateStatistics();
    
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _buildShelfInfo(),
          const SizedBox(height: 12),
          _buildCompactStatsRow(statistics),
          const SizedBox(height: 16),
          _buildActionButtons(),
          const SizedBox(height: 8),
          _buildMiadToggle(),
          const SizedBox(height: 16),
          _buildRecentItemsHeader(),
          const SizedBox(height: 8),
          Expanded(
            child: _scannedItems.isNotEmpty 
                ? _buildCompactRecentItemsList() 
                : _buildEmptyState(),
          ),
        ],
      ),
    );
  }

  Widget _buildShelfInfo() {
    final isWaitingForShelfCode = _waitingForShelfCode && _currentShelfCode.isEmpty;
    final hasNoShelfButItems = _currentShelfCode.isEmpty && _allScannedItems.isNotEmpty;
    
    Color bgColor;
    Color textColor;
    String statusText;
    String shelfText;
    
    if (hasNoShelfButItems) {
      bgColor = Colors.red.withAlpha(40);
      textColor = Colors.red;
      statusText = 'RAF KODU EKSİK!';
      shelfText = '${_allScannedItems.length} ürün bekliyor';
    } else if (isWaitingForShelfCode) {
      bgColor = Colors.orange.withAlpha(40);
      textColor = Colors.orange;
      statusText = 'RAF BEKLENİYOR';
      shelfText = 'Lütfen raf kodunu taratın';
    } else {
      bgColor = AppColors.cardBackground;
      textColor = Colors.white;
      statusText = 'Mevcut Raf';
      shelfText = _currentShelfCode;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasNoShelfButItems ? Colors.red : (isWaitingForShelfCode ? Colors.orange : Colors.transparent),
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasNoShelfButItems ? Icons.error : Icons.shelves, 
            color: hasNoShelfButItems ? Colors.red : (isWaitingForShelfCode ? Colors.orange : Colors.orange[400]), 
            size: 20
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  shelfText,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (_currentShelfCode.isNotEmpty && !hasNoShelfButItems)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(30),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${_scannedItems.length} ürün',
                style: TextStyle(
                  color: Colors.orange[400],
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (hasNoShelfButItems)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(30),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${_allScannedItems.length} ürün',
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompactStatsRow(Map<String, int> statistics) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildCompactStatItem('Toplam', statistics['total']?.toString() ?? '0', Icons.inventory_2, Colors.blue),
          const SizedBox(width: 8),
          _buildCompactStatItem('QR', statistics['qr']?.toString() ?? '0', Icons.qr_code, Colors.green),
          const SizedBox(width: 8),
          _buildCompactStatItem('Barkod', statistics['barcode']?.toString() ?? '0', Icons.barcode_reader, Colors.blue),
          const SizedBox(width: 8),
          _buildCompactStatItem('Bekleyen', statistics['pending']?.toString() ?? '0', Icons.pending, Colors.orange),
          const SizedBox(width: 8),
          _buildCompactStatItem('Gönderilen', statistics['sent']?.toString() ?? '0', Icons.cloud_done, Colors.green),
        ],
      ),
    );
  }

  Widget _buildCompactStatItem(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          height: 45,
          child: ElevatedButton(
            onPressed: _continueCurrentSayim,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_arrow, size: 18),
                SizedBox(width: 6),
                Text(
                  'SAYIMA DEVAM ET',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: OutlinedButton(
                  onPressed: _startNewSayim,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'YENİ SAYIM',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 40,
                child: ElevatedButton(
                  onPressed: _finishSayim,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'SAYIMI BİTİR',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMiadToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_busy, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Miad Uyar\u0131s\u0131',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          SizedBox(
            height: 32,
            child: Switch(
              value: _miadUyarisiAktif,
              activeThumbColor: Colors.red,
              onChanged: (value) {
                setState(() { _miadUyarisiAktif = value; });
                _saveMiadAyari(value);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentItemsHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Son Ürünler (Mevcut Raf)',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'İstatistikler tüm sayımlardaki toplam verileri gösterir',
          style: TextStyle(
            color: AppColors.textDimmed,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Spacer(),
            if (_scannedItems.isNotEmpty)
              Text(
                '${_scannedItems.length} ürün',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompactRecentItemsList() {
    final recentItems = _cachedRecentItems ??= _scannedItems.sortedByTime(ascending: false).take(8).toList();
    
    return ListView.builder(
      itemCount: recentItems.length,
      itemBuilder: (context, index) {
        final item = recentItems[index];
        return Container(
          key: ValueKey(item.id),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: _getStatusColor(item).withAlpha(40),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getItemIcon(item),
                  color: _getStatusColor(item),
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.shortBarcode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.productName != null && item.productName!.isNotEmpty)
                      Text(
                        item.productName!,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      '${item.typeString} • ${item.formattedTime}',
                      style: const TextStyle(
                        color: AppColors.textDimmed,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!item.isQR)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.withAlpha(30),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${item.quantity} adet',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const SizedBox(height: 2),
                  if (item.isUpdated)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.orange.withAlpha(30),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        'Güncellendi',
                        style: TextStyle(
                          color: Colors.orange[700],
                          fontSize: 8,
                        ),
                      ),
                    ),
                  if (!item.isSentToServer)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.orange.withAlpha(30),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        'Gönderilmedi',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 8,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.qr_code_scanner,
            size: 60,
            color: AppColors.textSubtle,
          ),
          const SizedBox(height: 12),
          const Text(
            'Henüz tarama yapılmadı',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSubtle,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Scanner sayfasından başlayın',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textDimmed,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _waitingForShelfCode 
                ? 'Raf Kodu Bekleniyor...' 
                : 'Raf: $_currentShelfCode',
            style: TextStyle(
              fontSize: 12,
              color: _waitingForShelfCode ? Colors.orange : Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_waitingForShelfCode)
            const SizedBox(height: 8),
            const Text(
              'Yeni sayım için raf barkodunu taratın',
              style: TextStyle(
                fontSize: 11,
                color: Colors.orange,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  IconData _getItemIcon(ScannedItem item) {
    if (item.isSentToServer && !item.isUpdated) return Icons.check_circle;
    if (item.isUpdated) return Icons.edit;
    if (item.isQR) return Icons.qr_code;
    return Icons.barcode_reader;
  }

  Color _getStatusColor(ScannedItem item) {
    if (item.isSentToServer && !item.isUpdated) return Colors.green;
    if (item.isUpdated) return Colors.orange;
    if (item.success) return Colors.blue;
    return Colors.red;
  }

  void _onBarcodeDetected(
    String barcode, 
    bool isQR, 
    int quantity, {
    String? urunAdi,
    String? urunTipi,
    String? sonKullanmaTarihi,
    String? partiNo
  }) async {
    try {
      if (barcode == 'STATS_UPDATE') {
      await _loadDataFromDatabase(); // ⚡ OPTİMİZASYON: Tek fonksiyon
        return;
      }
      
      final newItem = ScannedItem(
        barcode: barcode,
        isQR: isQR,
        quantity: quantity,
        success: true,
        shelfCode: _currentShelfCode,
        isSentToServer: false,
        isUpdated: false,
        productName: urunAdi,
        productType: urunTipi,
        expirationDate: sonKullanmaTarihi,
        batchNumber: partiNo,
      );

      await _addItemToDatabase(newItem);
      await _loadDataFromDatabase(); // ⚡ OPTİMİZASYON: Tek fonksiyon

    } catch (e) {
      _showSnackBar('Barkod işlenirken hata oluştu', isError: true);
    }
  }

  // main_page.dart dosyasında _onItemsUpdated metodunu güncelleyin
  Future<void> _onItemsUpdated(List<ScannedItem> updatedItems) async {
    try {
      // ✅ ÖNEMLİ: Tüm verileri yeniden yükle
      await _loadDataFromDatabase(); // ⚡ OPTİMİZASYON: Tek fonksiyon
      
      if (mounted) {
        setState(() {
          // UI'ı güncellemek için setState kullan
          // _scannedItems ve _allScannedItems zaten _loadDataFromDatabase'de güncellendi
        });
      }
      
      // ✅ SCANNER SAYFASINI DA GÜNCELLEMEK İÇİN
      // Scanner'ın UI'ını güncellemek için bir callback tetikleyin
      _onBarcodeDetected(
        'STATS_UPDATE', 
        false, 
        0,
        urunAdi: null,
        urunTipi: null,
        sonKullanmaTarihi: null,
        partiNo: null
      );
      
      _showSnackBar('Liste güncellendi');
    } catch (e) {
      _showSnackBar('Güncelleme başarısız', isError: true);
    }
  }

  void _continueCurrentSayim() {
    setState(() {
      _currentIndex = 1;
    });
  }

  void _startNewSayim() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text(
          'YENİ SAYIM',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        content: Text(
          'Tüm veriler silinecek. Emin misiniz?\n\n'
          '${_allScannedItems.length} ürün kaydı silinecek\n'
          'Son raf kodu: ${_currentShelfCode.isNotEmpty ? _currentShelfCode : "Kayıtlı değil"}',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('VAZGEÇ'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _clearAllDataAndWaitForShelfCode();
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('SİL VE YENİDEN BAŞLA'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllDataAndWaitForShelfCode() async {
    try {
      await _dbHelper.deleteTarananUrunlerBySayimKodu('AKTIF_SAYIM');
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_shelf_code');
      
      await _loadDataFromDatabase(); // ⚡ OPTİMİZASYON: Tek fonksiyon
      
      if (mounted) {
        setState(() {
          _currentShelfCode = "";
          _waitingForShelfCode = true;
          _currentIndex = 1;
        });
      }
      
      _showSnackBar('Yeni sayım başlatıldı. Lütfen raf kodunu taratın.');

    } catch (e) {
      _showSnackBar('Temizleme başarısız', isError: true);
    }
  }

  void _logout() {
    final navigator = Navigator.of(context);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text('Çıkış', style: TextStyle(color: Colors.white)),
        content: const Text('Çıkış yapmak istediğinize emin misiniz?', 
          style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _handleLogout(navigator);
            },
            child: const Text('Çıkış', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout(NavigatorState navigator) async {
    try {
      // ⚡ OPTİMİZASYON: Raf kodu artık SharedPreferences'a KAYDEDİLMİYOR
      // Database'de her üründe zaten var
      
      // Kısa bir bekleme
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Login sayfasına yönlendir
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (route) => false,
      );
      
      if (mounted) {
        _showSnackBar('Çıkış yapıldı', isError: false);
      }

    } catch (e) {
      if (mounted) {
        _showSnackBar('Çıkış sırasında hata oluştu', isError: true);
      }
    }
  }

  // YENİ EKLENEN SAYIMI BİTİR METODLARI
  void _finishSayim() {
    final pendingCount = _allScannedItems
        .where((item) => !item.isSentToServer || item.isUpdated)
        .length;
    
    if (pendingCount == 0) {
      _showSnackBar('Tüm veriler zaten gönderilmiş', isError: false);
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: const Text(
          'SAYIMI BİTİR',
          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        content: Text(
          'Sayımı bitirmek istediğinize emin misiniz?\n\n'
          '• $pendingCount bekleyen ürün sunucuya gönderilecek\n'
          '• Duplike gönderim olmayacak\n'
          '• Tüm raftaki ürünler kontrol edilecek',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İPTAL'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _finishSayimAndSendAllData();
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('BİTİR VE GÖNDER'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _finishSayimAndSendAllData() async {
    try {
      if (mounted) {
        setState(() {
          _isSendingData = true;
        });
      }
      
      // 1. Tüm raftaki gönderilmemiş ürünleri bul
      final unsentItems = _allScannedItems
          .where((item) => !item.isSentToServer || item.isUpdated)
          .toList();
      
      if (unsentItems.isEmpty) {
        _showSnackBar('Gönderilecek veri bulunamadı', isError: false);
        return;
      }
      
      // 2. Raf kodlarına göre grupla (duplike gönderimi önlemek için)
      final Map<String, List<ScannedItem>> itemsByShelf = {};
      
      for (final item in unsentItems) {
        // Null safety kontrolü: eğer item.shelfCode null ise boş string kullan
        final shelfCode = (item.shelfCode?.isNotEmpty ?? false) ? item.shelfCode! : 'RAF_BELİRTİLMEMİŞ';
        if (!itemsByShelf.containsKey(shelfCode)) {
          itemsByShelf[shelfCode] = [];
        }
        itemsByShelf[shelfCode]!.add(item);
      }

      // 3. Her raf için teker teker gönder
      int totalSent = 0;
      int failedShelves = 0;
      
      for (final entry in itemsByShelf.entries) {
        final shelfCode = entry.key;
        final shelfItems = entry.value;

        final success = await _sendToServerAPI(shelfItems, shelfCode);
        
        if (success) {
          // Başarılı gönderimde ürünleri güncelle
          for (final item in shelfItems) {
            await _dbHelper.updateScannedItem(item.copyWith(
              isSentToServer: true,
              isUpdated: false,
            ));
          }
          totalSent += shelfItems.length;
          _showSnackBar('Raf $shelfCode: ${shelfItems.length} ürün gönderildi');
        } else {
          failedShelves++;
          _showSnackBar('Raf $shelfCode gönderimi başarısız', isError: true);
        }
        
        // Kısa bekleme (sunucu yükünü azaltmak için)
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      // 4. Sonuçları göster ve verileri yenile
      await _loadDataFromDatabase(); // ⚡ OPTİMİZASYON: Tek fonksiyon
      
      if (failedShelves == 0) {
        _showSnackBar(
          '✅ Sayım başarıyla tamamlandı! $totalSent ürün gönderildi',
          isError: false,
        );
      } else {
        _showSnackBar(
          '⚠️ $failedShelves raftaki ürünler gönderilemedi. Lütfen manuel gönderim yapın.',
          isError: true,
        );
      }

    } catch (e) {
      _showSnackBar('Sayım bitirme hatası: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSendingData = false;
        });
      }
    }
  }
}