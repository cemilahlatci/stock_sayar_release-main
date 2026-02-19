// lib/database_helper.dart - RAF BAZLI KAYIT SİSTEMİ DÜZELTMELİ VERSİYON

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'scanned_item_model.dart';
import 'ui_helpers.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'stok_sayim.db');
    return await openDatabase(
      path,
      version: 7, // ✅ Versiyon artırıldı (7 yapıldı)
      onCreate: _createTables,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createTables(Database db, int version) async {
    // Kullanıcı tablosu
    await db.execute('''
      CREATE TABLE users(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT UNIQUE NOT NULL,
        password TEXT NOT NULL,
        username TEXT NOT NULL,
        eczane_gln TEXT NOT NULL,
        role TEXT NOT NULL,
        login_date TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Sayım oturumları tablosu
    await db.execute('''
      CREATE TABLE sayim_oturumlari(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sayim_kodu TEXT NOT NULL,
        baslama_tarihi TEXT NOT NULL,
        bitis_tarihi TEXT,
        durum TEXT NOT NULL,
        toplam_urun INTEGER DEFAULT 0,
        tamamlanan_urun INTEGER DEFAULT 0,
        raf_kodu TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Taranan ürünler tablosu - ✅ RAF BAZLI İNDEKS EKLENDİ
    await db.execute('''
      CREATE TABLE taranan_urunler (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sayim_kodu TEXT,
        barkod TEXT,
        is_qr INTEGER,
        adet INTEGER,
        raf_kodu TEXT,
        tarama_tarihi TEXT,
        durum INTEGER,
        sunucuya_gonderildi INTEGER,
        product_type TEXT,
        product_name TEXT,
        expiration_date TEXT,
        batch_number TEXT,
        is_updated INTEGER DEFAULT 0,
        sync_tarihi TEXT
      )
    ''');

    // ✅ RAF BAZLI İNDEKSLER EKLENDİ
    await db.execute('''
      CREATE INDEX idx_taranan_urunler_raf_kodu 
      ON taranan_urunler(raf_kodu)
    ''');
    
    await db.execute('''
      CREATE INDEX idx_taranan_urunler_barkod_raf
      ON taranan_urunler(barkod, raf_kodu)
    ''');

    // ⚡ PERFORMANS İNDEKSLERİ
    await db.execute('CREATE INDEX idx_taranan_urunler_sayim ON taranan_urunler(sayim_kodu)');
    await db.execute('CREATE INDEX idx_taranan_urunler_gonderim ON taranan_urunler(sunucuya_gonderildi)');

    // Ayarlar tablosu
    await db.execute('''
      CREATE TABLE ayarlar(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ayar_adi TEXT UNIQUE NOT NULL,
        ayar_degeri TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      await db.execute('''
        ALTER TABLE taranan_urunler ADD COLUMN product_type TEXT DEFAULT 'unknown'
      ''');
    }
    
    if (oldVersion < 4) {
      await db.execute('''
        ALTER TABLE taranan_urunler ADD COLUMN product_name TEXT
      ''');
      await db.execute('''
        ALTER TABLE taranan_urunler ADD COLUMN expiration_date TEXT
      ''');
      await db.execute('''
        ALTER TABLE taranan_urunler ADD COLUMN batch_number TEXT
      ''');
    }
    
    if (oldVersion < 5) {
      await db.execute('''
        ALTER TABLE taranan_urunler ADD COLUMN is_updated INTEGER DEFAULT 0
      ''');
    }
    
    if (oldVersion < 6) {
      // ✅ RAF BAZLI İNDEKSLER EKLENDİ
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_taranan_urunler_raf_kodu
        ON taranan_urunler(raf_kodu)
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_taranan_urunler_barkod_raf
        ON taranan_urunler(barkod, raf_kodu)
      ''');
    }
    
    if (oldVersion < 7) {
      // ⚡ PERFORMANS İNDEKSLERİ
      await db.execute('CREATE INDEX IF NOT EXISTS idx_taranan_urunler_sayim ON taranan_urunler(sayim_kodu)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_taranan_urunler_gonderim ON taranan_urunler(sunucuya_gonderildi)');
    }
  }

  // ========== KULLANICI İŞLEMLERİ ==========
  Future<int> insertUser(Map<String, dynamic> user) async {
    final db = await database;
    return await db.insert('users', user);
  }

  Future<Map<String, dynamic>?> getUser(String email) async {
    final db = await database;
    final result = await db.query(
      'users',
      where: 'email = ?',
      whereArgs: [email],
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final db = await database;
    return await db.query('users', orderBy: 'created_at DESC');
  }

  Future<int> updateUser(String email, Map<String, dynamic> userData) async {
    final db = await database;
    return await db.update(
      'users',
      userData,
      where: 'email = ?',
      whereArgs: [email],
    );
  }

  Future<int> deleteUser(String email) async {
    final db = await database;
    return await db.delete(
      'users',
      where: 'email = ?',
      whereArgs: [email],
    );
  }

  Future<Map<String, dynamic>?> getLastLoggedInUser() async {
    final db = await database;
    final result = await db.query(
      'users',
      orderBy: 'login_date DESC',
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<int> updateUserLoginDate(String email) async {
    final db = await database;
    return await db.update(
      'users',
      {'login_date': DateTimeHelper.nowIso8601()},
      where: 'email = ?',
      whereArgs: [email],
    );
  }

  // ========== SAYIM OTURUMU İŞLEMLERİ ==========
  Future<int> createSayimOturumu(Map<String, dynamic> oturum) async {
    final db = await database;
    return await db.insert('sayim_oturumlari', oturum);
  }

  Future<List<Map<String, dynamic>>> getSayimOturumlari() async {
    final db = await database;
    return await db.query(
      'sayim_oturumlari',
      orderBy: 'baslama_tarihi DESC',
    );
  }

  Future<Map<String, dynamic>?> getAktifSayimOturumu() async {
    final db = await database;
    final result = await db.query(
      'sayim_oturumlari',
      where: 'durum = ?',
      whereArgs: ['aktif'],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<int> updateSayimOturumu(int id, Map<String, dynamic> data) async {
    final db = await database;
    return await db.update(
      'sayim_oturumlari',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> completeSayimOturumu(int id) async {
    final db = await database;
    return await db.update(
      'sayim_oturumlari',
      {
        'durum': 'tamamlandı',
        'bitis_tarihi': DateTimeHelper.nowIso8601(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteSayimOturumu(int id) async {
    final db = await database;
    await db.delete(
      'taranan_urunler',
      where: 'sayim_kodu IN (SELECT sayim_kodu FROM sayim_oturumlari WHERE id = ?)',
      whereArgs: [id],
    );
    
    return await db.delete(
      'sayim_oturumlari',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> getAktifSayimSayisi() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM sayim_oturumlari WHERE durum = ?',
      ['aktif']
    );
    return result.first['count'] as int;
  }

  // ========== TARANAN ÜRÜN İŞLEMLERİ - RAF BAZLI SİSTEM ==========

  // ✅ RAF BAZLI KAYIT SİSTEMİ - GÜNCELLENDİ
// ✅ RAF BAZLI KAYIT SİSTEMİ - GÜNCELLENDİ (Miktar 0 olanlar siliniyor)
Future<int> insertScannedItem(ScannedItem item, {String? sayimKodu, String? shelfCode}) async {
  final db = await database;
  final rafKodu = shelfCode ?? item.shelfCode ?? 'SGAA01C';
  final kod = sayimKodu ?? 'AKTIF_SAYIM';

  // ⚡ TRANSACTION ile race condition onleme
  return await db.transaction((txn) async {
    final existing = await txn.query(
      'taranan_urunler',
      where: 'barkod = ? AND raf_kodu = ? AND sayim_kodu = ? AND is_qr = ?',
      whereArgs: [item.barcode, rafKodu, kod, item.isQR ? 1 : 0],
    );

    if (existing.isNotEmpty && !item.isQR) {
      final existingId = existing.first['id'] as int;
      final newProductName = item.productName ?? existing.first['product_name'] as String?;
      final newProductType = item.productType ?? existing.first['product_type'] as String? ?? 'unknown';

      if (item.quantity <= 0) {
        await txn.delete('taranan_urunler', where: 'id = ?', whereArgs: [existingId]);
        return -2;
      } else {
        await txn.update(
          'taranan_urunler',
          {
            'adet': item.quantity,
            'tarama_tarihi': item.timestamp.toIso8601String(),
            'is_updated': 1,
            'product_name': newProductName,
            'product_type': newProductType,
          },
          where: 'id = ?',
          whereArgs: [existingId],
        );
        return existingId;
      }
    } else if (existing.isNotEmpty && item.isQR) {
      return -1;
    } else {
      if (!item.isQR && item.quantity <= 0) return -2;

      return await txn.insert('taranan_urunler', {
        'sayim_kodu': kod,
        'barkod': item.barcode,
        'is_qr': item.isQR ? 1 : 0,
        'adet': item.quantity,
        'raf_kodu': rafKodu,
        'tarama_tarihi': item.timestamp.toIso8601String(),
        'durum': item.success ? 1 : 0,
        'sunucuya_gonderildi': item.isSentToServer ? 1 : 0,
        'product_type': item.productType ?? 'unknown',
        'product_name': item.productName,
        'expiration_date': item.expirationDate,
        'batch_number': item.batchNumber,
        'is_updated': item.isUpdated ? 1 : 0,
      });
    }
  });
}

  Future<int> insertTarananUrun(Map<String, dynamic> urun) async {
    final db = await database;
    return await db.insert('taranan_urunler', urun);
  }

  Future<List<Map<String, dynamic>>> getTarananUrunler([String? sayimKodu]) async {
    final db = await database;
    if (sayimKodu == null || sayimKodu.isEmpty) {
      return await db.query(
        'taranan_urunler',
        orderBy: 'tarama_tarihi DESC',
      );
    } else {
      return await db.query(
        'taranan_urunler',
        where: 'sayim_kodu = ?',
        whereArgs: [sayimKodu],
        orderBy: 'tarama_tarihi DESC',
      );
    }
  }

  // ✅ YENİ: RAF BAZLI VERİ ÇEKME
  Future<List<ScannedItem>> getScannedItemsByShelf(String shelfCode, {String? sayimKodu}) async {
    final db = await database;
    
    final result = await db.query(
      'taranan_urunler',
      where: 'raf_kodu = ? AND sayim_kodu = ?',
      whereArgs: [shelfCode, sayimKodu ?? 'AKTIF_SAYIM'],
      orderBy: 'tarama_tarihi DESC',
    );
    
    return result.map((map) => _mapToScannedItem(map)).toList();
  }

  Future<List<ScannedItem>> getScannedItems([String? sayimKodu]) async {
    final urunler = await getTarananUrunler(sayimKodu);
    return urunler.map((map) => _mapToScannedItem(map)).toList();
  }

  ScannedItem _mapToScannedItem(Map<String, dynamic> map) {
    return ScannedItem(
      id: map['id'].toString(),
      barcode: map['barkod'] as String? ?? '',
      quantity: (map['adet'] as num?)?.toInt() ?? 1,
      isQR: (map['is_qr'] as int?) == 1,
      success: (map['durum'] as int?) == 1,
      timestamp: DateTime.tryParse(map['tarama_tarihi']?.toString() ?? '') ?? DateTime.now(),
      productType: map['product_type'] as String?,
      shelfCode: map['raf_kodu'] as String?,
      isSentToServer: (map['sunucuya_gonderildi'] as int?) == 1,
      isUpdated: (map['is_updated'] as int?) == 1,
      productName: map['product_name'] as String?,
      expirationDate: map['expiration_date'] as String?,
      batchNumber: map['batch_number'] as String?,
    );
  }

  Future<List<ScannedItem>> getItemsByProductType(String productType, {String? shelfCode}) async {
    final db = await database;
    
    String whereClause = 'product_type = ?';
    List<dynamic> whereArgs = [productType];
    
    if (shelfCode != null) {
      whereClause += ' AND raf_kodu = ?';
      whereArgs.add(shelfCode);
    }
    
    final result = await db.query(
      'taranan_urunler',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'tarama_tarihi DESC',
    );
    
    return result.map((map) => _mapToScannedItem(map)).toList();
  }

  Future<int> updateProductType(String barkod, String newProductType) async {
    final db = await database;
    return await db.update(
      'taranan_urunler',
      {'product_type': newProductType},
      where: 'barkod = ?',
      whereArgs: [barkod],
    );
  }

  Future<List<Map<String, dynamic>>> getTarananUrunlerByRaf(String rafKodu) async {
    final db = await database;
    return await db.query(
      'taranan_urunler',
      where: 'raf_kodu = ?',
      whereArgs: [rafKodu],
      orderBy: 'tarama_tarihi DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getGonderilmeyenUrunler() async {
    final db = await database;
    return await db.query(
      'taranan_urunler',
      where: 'sunucuya_gonderildi = ? OR is_updated = ?',
      whereArgs: [0, 1],
      orderBy: 'tarama_tarihi ASC',
    );
  }

  Future<List<ScannedItem>> getGonderilmeyenScannedItems() async {
    final db = await database;
    final result = await db.query(
      'taranan_urunler',
      where: 'sunucuya_gonderildi = ? OR is_updated = ?',
      whereArgs: [0, 1],
      orderBy: 'tarama_tarihi ASC',
    );
    return result.map((map) => _mapToScannedItem(map)).toList();
  }

  // ✅ YENİ: RAF BAZLI İSTATİSTİKLER
  Future<int> getToplamUrunSayisiByShelf(String shelfCode, {String? sayimKodu}) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM taranan_urunler WHERE raf_kodu = ? AND sayim_kodu = ?',
      [shelfCode, sayimKodu ?? 'AKTIF_SAYIM']
    );
    return result.first['count'] as int;
  }

  Future<int> getToplamUrunSayisi(String sayimKodu) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM taranan_urunler WHERE sayim_kodu = ?',
      [sayimKodu]
    );
    return result.first['count'] as int;
  }

  Future<int> getToplamAdetSayisi(String sayimKodu) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT SUM(adet) as total FROM taranan_urunler WHERE sayim_kodu = ?',
      [sayimKodu]
    );
    return (result.first['total'] as int?) ?? 0;
  }

  Future<Map<String, dynamic>> getSayimIstatistikleri(String sayimKodu) async {
    final db = await database;

    // ⚡ TEK BİRLEŞİK SORGU - 7 ayrı sorgu yerine
    final result = await db.rawQuery('''
      SELECT
        COUNT(*) as toplamUrun,
        COALESCE(SUM(adet), 0) as toplamAdet,
        SUM(CASE WHEN is_qr = 1 THEN 1 ELSE 0 END) as qrSayisi,
        SUM(CASE WHEN is_qr = 0 THEN 1 ELSE 0 END) as barkodSayisi,
        SUM(CASE WHEN sunucuya_gonderildi = 1 THEN 1 ELSE 0 END) as gonderilenSayisi,
        SUM(CASE WHEN is_updated = 1 THEN 1 ELSE 0 END) as guncellenenSayisi,
        COUNT(DISTINCT raf_kodu) as rafSayisi,
        COUNT(DISTINCT barkod) as farkliUrun
      FROM taranan_urunler
      WHERE sayim_kodu = ?
    ''', [sayimKodu]);

    final row = result.first;
    return {
      'toplam_urun': row['toplamUrun'] as int,
      'toplam_adet': row['toplamAdet'] as int,
      'qr_sayisi': row['qrSayisi'] as int,
      'barkod_sayisi': row['barkodSayisi'] as int,
      'gonderilen_sayisi': row['gonderilenSayisi'] as int,
      'guncellenen_sayisi': row['guncellenenSayisi'] as int,
      'raf_sayisi': row['rafSayisi'] as int,
      'farkli_urun': row['farkliUrun'] as int,
    };
  }

  // ✅ RAF BAZLI İSTATİSTİKLER - TEK BİRLEŞİK SORGU
  Future<Map<String, dynamic>> getShelfStatistics(String shelfCode, {String? sayimKodu}) async {
    final db = await database;
    final kod = sayimKodu ?? 'AKTIF_SAYIM';

    final result = await db.rawQuery('''
      SELECT
        COUNT(*) as toplamUrun,
        COALESCE(SUM(adet), 0) as toplamAdet,
        SUM(CASE WHEN is_qr = 1 THEN 1 ELSE 0 END) as qrSayisi,
        SUM(CASE WHEN is_qr = 0 THEN 1 ELSE 0 END) as barkodSayisi,
        SUM(CASE WHEN sunucuya_gonderildi = 1 THEN 1 ELSE 0 END) as gonderilenSayisi,
        SUM(CASE WHEN is_updated = 1 THEN 1 ELSE 0 END) as guncellenenSayisi,
        COUNT(DISTINCT barkod) as farkliUrun
      FROM taranan_urunler
      WHERE raf_kodu = ? AND sayim_kodu = ?
    ''', [shelfCode, kod]);

    final row = result.first;
    return {
      'raf_kodu': shelfCode,
      'toplam_urun': row['toplamUrun'] as int,
      'toplam_adet': row['toplamAdet'] as int,
      'qr_sayisi': row['qrSayisi'] as int,
      'barkod_sayisi': row['barkodSayisi'] as int,
      'gonderilen_sayisi': row['gonderilenSayisi'] as int,
      'guncellenen_sayisi': row['guncellenenSayisi'] as int,
      'farkli_urun': row['farkliUrun'] as int,
    };
  }

  Future<int> getFarkliUrunSayisi(String sayimKodu) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(DISTINCT barkod) as count FROM taranan_urunler WHERE sayim_kodu = ?',
      [sayimKodu]
    );
    return result.first['count'] as int;
  }

  Future<void> markAsSentToServer(int id) async {
    final db = await database;
    await db.update(
      'taranan_urunler',
      {
        'sunucuya_gonderildi': 1,
        'is_updated': 0,
        'sync_tarihi': DateTimeHelper.nowIso8601(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markAllAsSentToServer(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final now = DateTimeHelper.nowIso8601();

    // ⚡ BATCH UPDATE - tek sorgu ile tum kayitlari guncelle
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE taranan_urunler SET sunucuya_gonderildi = 1, is_updated = 0, sync_tarihi = ? WHERE id IN ($placeholders)',
      [now, ...ids],
    );
  }

  Future<int> updateTarananUrun(int id, Map<String, dynamic> data) async {
    final db = await database;
    return await db.update(
      'taranan_urunler',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

Future<int> updateScannedItem(ScannedItem item) async {
  final db = await database;
  
  // Miktar kontrolü
  if (!item.isQR && item.quantity <= 0) {
    // Miktar 0 veya negatif ise SİL
    return await db.delete(
      'taranan_urunler',
      where: 'id = ?',
      whereArgs: [int.tryParse(item.id)],
    );
  }
  
  // Normal güncelleme
  return await db.update(
    'taranan_urunler',
    {
      'barkod': item.barcode,
      'is_qr': item.isQR ? 1 : 0,
      'adet': item.quantity,
      'raf_kodu': item.shelfCode,
      'tarama_tarihi': item.timestamp.toIso8601String(),
      'durum': item.success ? 1 : 0,
      'sunucuya_gonderildi': item.isSentToServer ? 1 : 0,
      'product_type': item.productType,
      'product_name': item.productName,
      'expiration_date': item.expirationDate,
      'batch_number': item.batchNumber,
      'is_updated': item.isUpdated ? 1 : 0,
    },
    where: 'id = ?',
    whereArgs: [int.tryParse(item.id)],
  );
}

  Future<int> deleteTarananUrun(int id) async {
    final db = await database;
    return await db.delete(
      'taranan_urunler',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteTarananUrunlerBySayimKodu(String sayimKodu) async {
    final db = await database;
    return await db.delete(
      'taranan_urunler',
      where: 'sayim_kodu = ?',
      whereArgs: [sayimKodu],
    );
  }

  Future<int> deleteTarananUrunlerByRafKodu(String rafKodu) async {
    final db = await database;
    return await db.delete(
      'taranan_urunler',
      where: 'raf_kodu = ?',
      whereArgs: [rafKodu],
    );
  }

  Future<int> deleteTarananUrunlerByBarkod(String barkod) async {
    final db = await database;
    return await db.delete(
      'taranan_urunler',
      where: 'barkod = ?',
      whereArgs: [barkod],
    );
  }

  // ✅ YENİ: BARKOD BAZLI SİLME METODU - EKLENDİ
  Future<int> deleteScannedItemByBarcode(String barkod, {String? shelfCode, String? sayimKodu}) async {
    final db = await database;
    
    try {
      String whereClause = 'barkod = ?';
      List<dynamic> whereArgs = [barkod];
      
      if (shelfCode != null && shelfCode.isNotEmpty) {
        whereClause += ' AND raf_kodu = ?';
        whereArgs.add(shelfCode);
      }
      
      if (sayimKodu != null) {
        whereClause += ' AND sayim_kodu = ?';
        whereArgs.add(sayimKodu);
      } else {
        whereClause += ' AND sayim_kodu = ?';
        whereArgs.add('AKTIF_SAYIM');
      }

      return await db.delete(
        'taranan_urunler',
        where: whereClause,
        whereArgs: whereArgs,
      );
    } catch (e) {
      return 0;
    }
  }

  // ✅ YENİ: BARKOD BAZLI ÜRÜN GETİRME METODU - EKLENDİ
  Future<ScannedItem?> getScannedItemByBarcode(String barkod, {String? shelfCode, String? sayimKodu}) async {
    final db = await database;
    
    try {
      String whereClause = 'barkod = ?';
      List<dynamic> whereArgs = [barkod];
      
      if (shelfCode != null && shelfCode.isNotEmpty) {
        whereClause += ' AND raf_kodu = ?';
        whereArgs.add(shelfCode);
      }
      
      if (sayimKodu != null) {
        whereClause += ' AND sayim_kodu = ?';
        whereArgs.add(sayimKodu);
      } else {
        whereClause += ' AND sayim_kodu = ?';
        whereArgs.add('AKTIF_SAYIM');
      }
      
      final result = await db.query(
        'taranan_urunler',
        where: whereClause,
        whereArgs: whereArgs,
        limit: 1,
      );
      
      if (result.isNotEmpty) {
        return _mapToScannedItem(result.first);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ✅ YENİ: RAF DEĞİŞİMİ İÇİN VERİ TRANSFERİ
  Future<int> transferItemsToNewShelf(String oldShelfCode, String newShelfCode, {String? sayimKodu}) async {
    final db = await database;
    
    return await db.update(
      'taranan_urunler',
      {
        'raf_kodu': newShelfCode,
        'is_updated': 1,
      },
      where: 'raf_kodu = ? AND sayim_kodu = ?',
      whereArgs: [oldShelfCode, sayimKodu ?? 'AKTIF_SAYIM'],
    );
  }

  // ========== AYAR İŞLEMLERİ ==========
  Future<void> saveAyar(String ayarAdi, String ayarDegeri) async {
    final db = await database;
    await db.insert(
      'ayarlar',
      {
        'ayar_adi': ayarAdi,
        'ayar_degeri': ayarDegeri,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getAyar(String ayarAdi) async {
    final db = await database;
    final result = await db.query(
      'ayarlar',
      where: 'ayar_adi = ?',
      whereArgs: [ayarAdi],
      limit: 1,
    );
    return result.isNotEmpty ? result.first['ayar_degeri'] as String? : null;
  }

  Future<Map<String, String>> getAllAyarlar() async {
    final db = await database;
    final result = await db.query('ayarlar');
    final ayarlar = <String, String>{};
    
    for (final row in result) {
      ayarlar[row['ayar_adi'] as String] = row['ayar_degeri'] as String;
    }
    
    return ayarlar;
  }

  Future<int> deleteAyar(String ayarAdi) async {
    final db = await database;
    return await db.delete(
      'ayarlar',
      where: 'ayar_adi = ?',
      whereArgs: [ayarAdi],
    );
  }

  // ========== İSTATİSTİKLER ==========
  Future<Map<String, dynamic>> getStatistics({String? shelfCode, String? sayimKodu}) async {
    final db = await database;
    
    String whereClause = 'sayim_kodu = ?';
    List<dynamic> whereArgs = [sayimKodu ?? 'AKTIF_SAYIM'];
    
    if (shelfCode != null) {
      whereClause += ' AND raf_kodu = ?';
      whereArgs.add(shelfCode);
    }
    
    final totalResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM taranan_urunler WHERE $whereClause',
      whereArgs
    );
    final totalItems = totalResult.first['count'] as int;
    
    final quantityResult = await db.rawQuery(
      'SELECT SUM(adet) as total FROM taranan_urunler WHERE $whereClause',
      whereArgs
    );
    final totalQuantity = (quantityResult.first['total'] as int?) ?? 0;
    
    final uniqueResult = await db.rawQuery(
      'SELECT COUNT(DISTINCT barkod) as count FROM taranan_urunler WHERE $whereClause',
      whereArgs
    );
    final uniqueItems = uniqueResult.first['count'] as int;
    
    final qrResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM taranan_urunler WHERE is_qr = 1 AND $whereClause',
      whereArgs
    );
    final qrCount = qrResult.first['count'] as int;
    
    final oneDResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM taranan_urunler WHERE is_qr = 0 AND $whereClause',
      whereArgs
    );
    final oneDCount = oneDResult.first['count'] as int;
    
    final sentResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM taranan_urunler WHERE sunucuya_gonderildi = 1 AND $whereClause',
      whereArgs
    );
    final sentCount = sentResult.first['count'] as int;
    
    final updatedResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM taranan_urunler WHERE is_updated = 1 AND $whereClause',
      whereArgs
    );
    final updatedCount = updatedResult.first['count'] as int;
    
    final productTypeResult = await db.rawQuery('''
      SELECT product_type, COUNT(*) as count 
      FROM taranan_urunler 
      WHERE $whereClause 
      GROUP BY product_type
    ''', whereArgs);
    
    final productTypes = <String, int>{};
    for (final row in productTypeResult) {
      productTypes[row['product_type'] as String] = row['count'] as int;
    }
    
    final rafResult = await db.rawQuery('''
      SELECT raf_kodu, COUNT(*) as count 
      FROM taranan_urunler 
      WHERE $whereClause 
      GROUP BY raf_kodu
    ''', whereArgs);
    
    final rafCounts = <String, int>{};
    for (final row in rafResult) {
      rafCounts[row['raf_kodu'] as String] = row['count'] as int;
    }

    return {
      'total_items': totalItems,
      'total_quantity': totalQuantity,
      'unique_items': uniqueItems,
      'qr_count': qrCount,
      'one_d_count': oneDCount,
      'sent_count': sentCount,
      'updated_count': updatedCount,
      'product_types': productTypes,
      'raf_counts': rafCounts,
    };
  }

  // ========== GENEL İŞLEMLER ==========
  Future<void> clearDatabase() async {
    final db = await database;
    await db.delete('users');
    await db.delete('sayim_oturumlari');
    await db.delete('taranan_urunler');
    await db.delete('ayarlar');
  }

  Future<void> clearTarananUrunler() async {
    final db = await database;
    await db.delete('taranan_urunler');
  }

  Future<void> clearUsers() async {
    final db = await database;
    await db.delete('users');
  }

  Future<void> clearSayimOturumlari() async {
    final db = await database;
    await db.delete('sayim_oturumlari');
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  Future<int> getDatabaseSize() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT page_count * page_size as size 
      FROM pragma_page_count(), pragma_page_size()
    ''');
    return result.first['size'] as int;
  }

  Future<Map<String, dynamic>> getDatabaseInfo() async {
    final db = await database;
    
    final userCount = await db.rawQuery('SELECT COUNT(*) as count FROM users');
    final sayimCount = await db.rawQuery('SELECT COUNT(*) as count FROM sayim_oturumlari');
    final urunCount = await db.rawQuery('SELECT COUNT(*) as count FROM taranan_urunler');
    final gonderilmeyenCount = await db.rawQuery(
      'SELECT COUNT(*) as count FROM taranan_urunler WHERE sunucuya_gonderildi = 0 OR is_updated = 1'
    );
    
    final databaseSize = await getDatabaseSize();
    
    return {
      'user_count': userCount.first['count'] as int,
      'sayim_count': sayimCount.first['count'] as int,
      'urun_count': urunCount.first['count'] as int,
      'gonderilmeyen_count': gonderilmeyenCount.first['count'] as int,
      'database_size': databaseSize,
      'database_size_mb': (databaseSize / (1024 * 1024)).toStringAsFixed(2),
    };
  }

  // ========== BACKUP ve RESTORE ==========
  Future<bool> backupDatabase(String backupPath) async {
    try {
      final db = await database;
      await db.execute('VACUUM');
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> exportDatabase(String exportPath) async {
    try {
      final db = await database;
      await db.execute('VACUUM');
      return true;
    } catch (e) {
      return false;
    }
  }

  // ========== TRANSACTION İŞLEMLERİ ==========
  Future<void> executeInTransaction(Function(Transaction) operation) async {
    final db = await database;
    await db.transaction((txn) async {
      await operation(txn);
    });
  }

  Future<void> batchInsertScannedItems(List<ScannedItem> items, {String? sayimKodu}) async {
    final db = await database;
    final batch = db.batch();
    
    for (final item in items) {
      batch.insert('taranan_urunler', {
        'sayim_kodu': sayimKodu ?? 'AKTIF_SAYIM',
        'barkod': item.barcode,
        'is_qr': item.isQR ? 1 : 0,
        'adet': item.quantity,
        'raf_kodu': item.shelfCode ?? 'SGAA01C',
        'tarama_tarihi': item.timestamp.toIso8601String(),
        'durum': item.success ? 1 : 0,
        'sunucuya_gonderildi': item.isSentToServer ? 1 : 0,
        'product_type': item.productType ?? 'unknown',
        'product_name': item.productName,
        'expiration_date': item.expirationDate,
        'batch_number': item.batchNumber,
        'is_updated': item.isUpdated ? 1 : 0,
      });
    }
    
    await batch.commit(noResult: true);
  }

  Future<int> updateShelfCodeForAll(String oldShelfCode, String newShelfCode, {String? sayimKodu}) async {
    final db = await database;
    
    String whereClause = 'raf_kodu = ?';
    List<dynamic> whereArgs = [oldShelfCode];
    
    if (sayimKodu != null) {
      whereClause += ' AND sayim_kodu = ?';
      whereArgs.add(sayimKodu);
    }
    
    return await db.update(
      'taranan_urunler',
      {
        'raf_kodu': newShelfCode,
        'is_updated': 1,
      },
      where: whereClause,
      whereArgs: whereArgs,
    );
  }

  Future<List<String>> getUniqueRafKodlari({String? sayimKodu}) async {
    final db = await database;
    
    String whereClause = '1=1';
    List<dynamic> whereArgs = [];
    
    if (sayimKodu != null) {
      whereClause = 'sayim_kodu = ?';
      whereArgs.add(sayimKodu);
    }
    
    final result = await db.rawQuery('''
      SELECT DISTINCT raf_kodu 
      FROM taranan_urunler 
      WHERE $whereClause 
      ORDER BY raf_kodu
    ''', whereArgs);
    
    return result.map((row) => row['raf_kodu'] as String).toList();
  }

  Future<List<String>> getUniqueBarkodlar({String? sayimKodu, String? rafKodu}) async {
    final db = await database;
    
    String whereClause = '1=1';
    List<dynamic> whereArgs = [];
    
    if (sayimKodu != null) {
      whereClause = 'sayim_kodu = ?';
      whereArgs.add(sayimKodu);
    }
    
    if (rafKodu != null) {
      whereClause += whereClause == '1=1' ? ' raf_kodu = ?' : ' AND raf_kodu = ?';
      whereArgs.add(rafKodu);
    }
    
    final result = await db.rawQuery('''
      SELECT DISTINCT barkod 
      FROM taranan_urunler 
      WHERE $whereClause 
      ORDER BY barkod
    ''', whereArgs);
    
    return result.map((row) => row['barkod'] as String).toList();
  }

  Future<Map<String, int>> getUrunSayilariByRaf({String? sayimKodu}) async {
    final db = await database;
    
    String whereClause = '1=1';
    List<dynamic> whereArgs = [];
    
    if (sayimKodu != null) {
      whereClause = 'sayim_kodu = ?';
      whereArgs.add(sayimKodu);
    }
    
    final result = await db.rawQuery('''
      SELECT raf_kodu, COUNT(*) as count 
      FROM taranan_urunler 
      WHERE $whereClause 
      GROUP BY raf_kodu 
      ORDER BY count DESC
    ''', whereArgs);
    
    final rafCounts = <String, int>{};
    for (final row in result) {
      rafCounts[row['raf_kodu'] as String] = row['count'] as int;
    }
    
    return rafCounts;
  }

  Future<void> optimizeDatabase() async {
    final db = await database;
    await db.execute('VACUUM');
    await db.execute('ANALYZE');
  }

  // ✅ YENİ: RAF BAZLI SİSTEM KONTROL METODLARI
  Future<bool> checkRafBazliSistem() async {
    try {
      final db = await database;
      
      // Raf bazlı kayıt kontrolü
      final rafKayitlari = await db.rawQuery('''
        SELECT raf_kodu, COUNT(*) as count 
        FROM taranan_urunler 
        GROUP BY raf_kodu
      ''');
      
      // İndeks kontrolü
      final indeksler = await db.rawQuery('''
        SELECT name FROM sqlite_master
        WHERE type = 'index' AND name LIKE 'idx_taranan_urunler%'
      ''');

      return rafKayitlari.isNotEmpty && indeksler.length >= 2;
    } catch (e) {
      return false;
    }
  }
}