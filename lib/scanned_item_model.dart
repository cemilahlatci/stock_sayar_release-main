// lib/scanned_item_model.dart - HATALAR DÜZELTİLMİŞ VERSİYON

import 'dart:convert';
import 'package:flutter/material.dart';

class ScannedItem {
  final String id;
  final String barcode;
  final int quantity;
  final bool isQR;
  final bool success;
  final DateTime timestamp;
  final String? productType;
  final String? shelfCode;
  final bool isSentToServer;
  final bool isUpdated;
  final String? productName;
  final String? expirationDate;
  final String? batchNumber;

  ScannedItem({
    String? id,
    required this.barcode,
    this.quantity = 1,
    this.isQR = false,
    this.success = true,
    DateTime? timestamp,
    this.productType,
    this.shelfCode,
    this.isSentToServer = false,
    this.isUpdated = false,
    this.productName,
    this.expirationDate,
    this.batchNumber,
  }) : id = id ?? '${DateTime.now().millisecondsSinceEpoch}_$barcode',
       timestamp = timestamp ?? DateTime.now();

  // Database Map'ten ScannedItem oluşturma
  static ScannedItem fromMap(Map<String, dynamic> map) {
    try {
      return ScannedItem(
        id: map['id']?.toString() ?? '${DateTime.now().millisecondsSinceEpoch}_${map['barkod']}',
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
    } catch (_) {
      return ScannedItem(
        barcode: map['barkod']?.toString() ?? '',
        quantity: 1,
        isQR: false,
        success: true,
        productType: map['product_type'] as String?,
        shelfCode: map['raf_kodu'] as String?,
        productName: map['product_name'] as String?,
        expirationDate: map['expiration_date'] as String?,
        batchNumber: map['batch_number'] as String?,
      );
    }
  }

  // Database'e kaydetmek için Map'e dönüştürme
  Map<String, dynamic> toMap() => {
        'id': id,
        'barkod': barcode,
        'adet': quantity,
        'is_qr': isQR ? 1 : 0,
        'durum': success ? 1 : 0,
        'tarama_tarihi': timestamp.toIso8601String(),
        'product_type': productType,
        'raf_kodu': shelfCode,
        'sunucuya_gonderildi': isSentToServer ? 1 : 0,
        'is_updated': isUpdated ? 1 : 0,
        'product_name': productName,
        'expiration_date': expirationDate,
        'batch_number': batchNumber,
      };

  // JSON için Map'e dönüştürme (API gönderimi için)
  Map<String, dynamic> toApiMap() => {
        'id': id,
        'barcode': barcode,
        'quantity': quantity,
        'isQR': isQR,
        'success': success,
        'timestamp': timestamp.toIso8601String(),
        'productType': productType,
        'shelfCode': shelfCode,
        'isSentToServer': isSentToServer,
        'isUpdated': isUpdated,
        'productName': productName,
        'expirationDate': expirationDate,
        'batchNumber': batchNumber,
      };

  ScannedItem copyWith({
    String? id,
    String? barcode,
    int? quantity,
    bool? isQR,
    bool? success,
    DateTime? timestamp,
    String? productType,
    String? shelfCode,
    bool? isSentToServer,
    bool? isUpdated,
    String? productName,
    String? expirationDate,
    String? batchNumber,
  }) {
    return ScannedItem(
      id: id ?? this.id,
      barcode: barcode ?? this.barcode,
      quantity: quantity ?? this.quantity,
      isQR: isQR ?? this.isQR,
      success: success ?? this.success,
      timestamp: timestamp ?? this.timestamp,
      productType: productType ?? this.productType,
      shelfCode: shelfCode ?? this.shelfCode,
      isSentToServer: isSentToServer ?? this.isSentToServer,
      isUpdated: isUpdated ?? this.isUpdated,
      productName: productName ?? this.productName,
      expirationDate: expirationDate ?? this.expirationDate,
      batchNumber: batchNumber ?? this.batchNumber,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    
    return other is ScannedItem &&
        runtimeType == other.runtimeType &&
        id == other.id &&
        barcode == other.barcode &&
        quantity == other.quantity &&
        isQR == other.isQR &&
        success == other.success &&
        timestamp == other.timestamp &&
        productType == other.productType &&
        shelfCode == other.shelfCode &&
        isSentToServer == other.isSentToServer &&
        isUpdated == other.isUpdated &&
        productName == other.productName &&
        expirationDate == other.expirationDate &&
        batchNumber == other.batchNumber;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        barcode.hashCode ^
        quantity.hashCode ^
        isQR.hashCode ^
        success.hashCode ^
        timestamp.hashCode ^
        productType.hashCode ^
        shelfCode.hashCode ^
        isSentToServer.hashCode ^
        isUpdated.hashCode ^
        productName.hashCode ^
        expirationDate.hashCode ^
        batchNumber.hashCode;
  }

  @override
  String toString() {
    return 'ScannedItem{id: $id, barcode: $barcode, quantity: $quantity, isQR: $isQR, success: $success, timestamp: $timestamp, productType: $productType, shelfCode: $shelfCode, isSentToServer: $isSentToServer, isUpdated: $isUpdated, productName: $productName, expirationDate: $expirationDate, batchNumber: $batchNumber}';
  }

  // Yardımcı metodlar
  bool get is1DBarcode => !isQR;
  
  String get typeString => isQR ? 'QR Kod' : '1D Barkod';
  
  String get statusString => success ? 'Başarılı' : 'Başarısız';
  
  String get displayQuantity => isQR ? '1' : quantity.toString();
  
  String get productTypeString {
    switch (productType) {
      case 'ilac':
        return 'İlaç';
      case 'otc':
        return 'OTC';
      case 'unknown':
        return 'Bilinmiyor';
      default:
        return productType ?? 'Tanımsız';
    }
  }
  
  String get displayProductName {
    if (productName != null && productName!.isNotEmpty) {
      return productName!;
    }
    return shortBarcode;
  }
  
  String? get formattedExpirationDate {
    if (expirationDate == null) return null;
    
    try {
      if (expirationDate!.length == 6) {
        final year = '20${expirationDate!.substring(0, 2)}';
        final month = expirationDate!.substring(2, 4);
        final day = expirationDate!.substring(4, 6);
        return '$day/$month/$year';
      } else if (expirationDate!.contains('-')) {
        final parts = expirationDate!.split('-');
        if (parts.length == 3) {
          return '${parts[2]}/${parts[1]}/${parts[0]}';
        }
      } else if (expirationDate!.length == 8) {
        final year = expirationDate!.substring(0, 4);
        final month = expirationDate!.substring(4, 6);
        final day = expirationDate!.substring(6, 8);
        return '$day/$month/$year';
      }
      return expirationDate;
    } catch (_) {
      return expirationDate;
    }
  }

  String? get displayBatchNumber {
    if (batchNumber != null && batchNumber!.isNotEmpty) {
      return batchNumber!;
    }
    return 'Belirtilmemiş';
  }
  
  String get expirationStatus {
    if (expirationDate == null) return 'Bilinmiyor';
    
    final days = daysUntilExpiry;
    if (days == null) return 'Bilinmiyor';
    
    if (days < 0) return 'Süresi Dolmuş';
    if (days < 30) return 'Yakında Dolacak';
    if (days < 90) return 'Yaklaşıyor';
    return 'Uygun';
  }
  
  Color get expirationStatusColor {
    if (expirationDate == null) return Colors.grey;
    
    final days = daysUntilExpiry;
    if (days == null) return Colors.grey;
    
    if (days < 0) return Colors.red;
    if (days < 30) return Colors.orange;
    if (days < 90) return Colors.blue;
    return Colors.green;
  }
  
  int? get daysUntilExpiry {
    if (expirationDate == null) return null;
    
    try {
      DateTime? expiryDate;
      
      if (expirationDate!.length == 6) {
        final year = int.parse('20${expirationDate!.substring(0, 2)}');
        final month = int.parse(expirationDate!.substring(2, 4));
        final day = int.parse(expirationDate!.substring(4, 6));
        expiryDate = DateTime(year, month, day);
      } else if (expirationDate!.contains('-')) {
        expiryDate = DateTime.tryParse(expirationDate!);
      } else if (expirationDate!.length == 8) {
        final year = int.parse(expirationDate!.substring(0, 4));
        final month = int.parse(expirationDate!.substring(4, 6));
        final day = int.parse(expirationDate!.substring(6, 8));
        expiryDate = DateTime(year, month, day);
      }
      
      if (expiryDate != null) {
        final now = DateTime.now();
        final difference = expiryDate.difference(now);
        return difference.inDays;
      }
    } catch (_) {
      // SKT hesaplama başarısız
    }
    
    return null;
  }
  
  String get formattedTime {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inSeconds < 60) {
      return '${difference.inSeconds} sn önce';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} dk önce';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} sa önce';
    } else {
      return '${difference.inDays} gün önce';
    }
  }
  
  String get shortBarcode {
    if (barcode.length <= 12) return barcode;
    return '${barcode.substring(0, 8)}...${barcode.substring(barcode.length - 4)}';
  }
  
  String get statusIconName {
    if (isSentToServer && !isUpdated) {
      return 'check_circle';
    } else if (isUpdated) {
      return 'edit';
    } else if (isQR) {
      return 'qr_code';
    } else {
      return 'barcode_reader';
    }
  }
  
  Color get statusColor {
    if (isSentToServer && !isUpdated) {
      return Colors.green;
    } else if (isUpdated) {
      return Colors.orange;
    } else if (success) {
      return Colors.blue;
    } else {
      return Colors.red;
    }
  }
  
  String get statusColorName {
    if (isSentToServer && !isUpdated) {
      return 'green';
    } else if (isUpdated) {
      return 'orange';
    } else if (success) {
      return 'blue';
    } else {
      return 'red';
    }
  }

  // Database durum kontrolü
  bool get isInDatabase => id.contains('_') && !id.startsWith('temp_');
  
  bool get needsSync => !isSentToServer || isUpdated;
  
  bool get canBeUpdated => !isSentToServer || isUpdated;
  
  String toJson() {
    return jsonEncode(toApiMap());
  }

  static ScannedItem fromJson(String jsonString) {
    try {
      final Map<String, dynamic> map = json.decode(jsonString);
      return fromMap(map);
    } catch (_) {
      return ScannedItem(barcode: '');
    }
  }

  // Yeni metod: Geçerli bir raf kodu mu?
  bool get hasValidShelfCode {
    if (shelfCode == null || shelfCode!.isEmpty) return false;
    final rafKoduPattern = RegExp(r'^SG[A-Z][0-9]{2}C$');
    return rafKoduPattern.hasMatch(shelfCode!);
  }

  // Yeni metod: Ürün tipine göre ikon
  IconData get productTypeIcon {
    switch (productType) {
      case 'ilac':
        return Icons.medical_services;
      case 'otc':
        return Icons.local_pharmacy;
      case 'unknown':
        return Icons.help_outline;
      default:
        return Icons.inventory_2;
    }
  }

  // Yeni metod: Özet bilgi
  String get summary {
    return '$displayProductName - $quantity adet - $formattedTime';
  }

  // Yeni metod: Hızlı kopya oluşturma
  ScannedItem quickCopy({int? newQuantity, String? newShelfCode}) {
    return copyWith(
      quantity: newQuantity ?? quantity,
      shelfCode: newShelfCode ?? shelfCode,
      isUpdated: newQuantity != quantity || newShelfCode != shelfCode,
    );
  }
}

extension ScannedItemListExtensions on List<ScannedItem> {
  List<ScannedItem> whereBarcode(String barcode) {
    return where((item) => item.barcode == barcode).toList();
  }

  List<ScannedItem> get qrItems {
    return where((item) => item.isQR).toList();
  }

  List<ScannedItem> get oneDItems {
    return where((item) => !item.isQR).toList();
  }

  List<ScannedItem> get successfulItems {
    return where((item) => item.success).toList();
  }

  List<ScannedItem> get failedItems {
    return where((item) => !item.success).toList();
  }

  List<String> get uniqueBarcodes {
    return map((item) => item.barcode).toSet().toList();
  }

  List<String> get uniqueShelfCodes {
    return map((item) => item.shelfCode ?? 'RAF_BELİRTİLMEMİŞ')
        .where((raf) => raf.isNotEmpty)
        .toSet()
        .toList();
  }

  int get totalQuantity {
    return fold(0, (sum, item) => sum + (item.isQR ? 1 : item.quantity));
  }

  int get qrCount {
    return where((item) => item.isQR && item.success).length;
  }

  int get oneDTotalQuantity {
    return where((item) => !item.isQR).fold(0, (sum, item) => sum + item.quantity);
  }

  List<ScannedItem> whereProductType(String productType) {
    return where((item) => item.productType == productType).toList();
  }

  List<ScannedItem> whereShelfCode(String shelfCode) {
    return where((item) => item.shelfCode == shelfCode).toList();
  }

  int get ilacCount {
    return where((item) => item.productType == 'ilac').length;
  }

  int get otcCount {
    return where((item) => item.productType == 'otc').length;
  }

  int get unknownCount {
    return where((item) => item.productType == 'unknown' || item.productType == null).length;
  }

  List<ScannedItem> get sentItems {
    return where((item) => item.isSentToServer).toList();
  }

  List<ScannedItem> get unsentItems {
    return where((item) => !item.isSentToServer).toList();
  }

  List<ScannedItem> get updatedItems {
    return where((item) => item.isUpdated).toList();
  }

  List<ScannedItem> get pendingItems {
    return where((item) => !item.isSentToServer || item.isUpdated).toList();
  }

  Map<String, List<ScannedItem>> groupByShelf() {
    final gruplar = <String, List<ScannedItem>>{};
    
    for (final item in this) {
      final rafKodu = item.shelfCode ?? 'RAF_BELİRTİLMEMİŞ';
      if (!gruplar.containsKey(rafKodu)) {
        gruplar[rafKodu] = [];
      }
      gruplar[rafKodu]!.add(item);
    }
    
    return gruplar;
  }

  Map<String, int> get sendStatistics {
    final total = length;
    final sent = where((item) => item.isSentToServer && !item.isUpdated).length;
    final updated = where((item) => item.isUpdated).length;
    final pending = where((item) => !item.isSentToServer).length;
    
    return {
      'total': total,
      'sent': sent,
      'updated': updated,
      'pending': pending,
    };
  }

  List<ScannedItem> sortedByTime({bool ascending = false}) {
    final sortedList = List<ScannedItem>.from(this);
    sortedList.sort((a, b) {
      if (ascending) {
        return a.timestamp.compareTo(b.timestamp);
      } else {
        return b.timestamp.compareTo(a.timestamp);
      }
    });
    return sortedList;
  }

  List<ScannedItem> sortedBySendStatus() {
    final sortedList = List<ScannedItem>.from(this);
    sortedList.sort((a, b) {
      if (a.isUpdated && !b.isUpdated) return -1;
      if (!a.isUpdated && b.isUpdated) return 1;
      if (!a.isSentToServer && b.isSentToServer) return -1;
      if (a.isSentToServer && !b.isSentToServer) return 1;
      return 0;
    });
    return sortedList;
  }

  List<Map<String, dynamic>> toMapList() {
    return map((item) => item.toMap()).toList();
  }

  List<Map<String, dynamic>> toApiMapList() {
    return map((item) => item.toApiMap()).toList();
  }

  String toJsonList() {
    return json.encode(toApiMapList());
  }

  static List<ScannedItem> fromJsonList(String jsonList) {
    try {
      final List<dynamic> list = json.decode(jsonList);
      return list.map((item) => ScannedItem.fromMap(Map<String, dynamic>.from(item))).toList();
    } catch (_) {
      return [];
    }
  }

  ScannedItem? findById(String id) {
    try {
      return firstWhere((item) => item.id == id);
    } catch (e) {
      return null;
    }
  }

  ScannedItem? findByBarcodeAndShelf(String barcode, String shelfCode) {
    try {
      return firstWhere((item) => 
        item.barcode == barcode && item.shelfCode == shelfCode);
    } catch (e) {
      return null;
    }
  }

  bool hasDuplicate(String barcode, String shelfCode) {
    return any((item) => 
      item.barcode == barcode && item.shelfCode == shelfCode);
  }

  List<ScannedItem> removeDuplicates() {
    final uniqueItems = <String, ScannedItem>{};
    
    for (final item in this) {
      final key = '${item.barcode}_${item.shelfCode}';
      if (!uniqueItems.containsKey(key) || 
          item.timestamp.isAfter(uniqueItems[key]!.timestamp)) {
        uniqueItems[key] = item;
      }
    }
    
    return uniqueItems.values.toList();
  }

  List<ScannedItem> get readyForSend {
    return where((item) => !item.isSentToServer || item.isUpdated).toList();
  }

  List<ScannedItem> get expiringSoonItems {
    return where((item) {
      final days = item.daysUntilExpiry;
      return days != null && days >= 0 && days < 30;
    }).toList();
  }
  
  List<ScannedItem> get expiredItems {
    return where((item) {
      final days = item.daysUntilExpiry;
      return days != null && days < 0;
    }).toList();
  }
  
  List<ScannedItem> whereProductNameContains(String query) {
    return where((item) => 
      item.productName?.toLowerCase().contains(query.toLowerCase()) ?? false)
      .toList();
  }

  Map<String, int> get expirationStatistics {
    final totalItems = length;
    final expiringSoon = expiringSoonItems.length;
    final expired = expiredItems.length;
    final noExpiration = where((item) => item.expirationDate == null).length;
    final valid = totalItems - expiringSoon - expired - noExpiration;
    
    return {
      'total': totalItems,
      'expiring_soon': expiringSoon,
      'expired': expired,
      'no_expiration': noExpiration,
      'valid': valid,
    };
  }

  List<ScannedItem> get itemsWithExpiration {
    return where((item) => item.expirationDate != null).toList();
  }

  List<ScannedItem> get itemsWithoutExpiration {
    return where((item) => item.expirationDate == null).toList();
  }

  List<ScannedItem> sortedByExpiration({bool ascending = true}) {
    final sortedList = List<ScannedItem>.from(this);
    sortedList.sort((a, b) {
      final aDays = a.daysUntilExpiry ?? 99999;
      final bDays = b.daysUntilExpiry ?? 99999;
      
      if (ascending) {
        return aDays.compareTo(bDays);
      } else {
        return bDays.compareTo(aDays);
      }
    });
    return sortedList;
  }

  Map<String, List<ScannedItem>> groupByProductType() {
    final gruplar = <String, List<ScannedItem>>{};
    
    for (final item in this) {
      final tip = item.productType ?? 'unknown';
      if (!gruplar.containsKey(tip)) {
        gruplar[tip] = [];
      }
      gruplar[tip]!.add(item);
    }
    
    return gruplar;
  }

  Map<String, int> get productTypeStatistics {
    final gruplar = groupByProductType();
    final istatistikler = <String, int>{};
    
    gruplar.forEach((tip, urunler) {
      istatistikler[tip] = urunler.length;
    });
    
    return istatistikler;
  }

  List<ScannedItem> get itemsWithProductName {
    return where((item) => item.productName != null && item.productName!.isNotEmpty).toList();
  }

  List<ScannedItem> get itemsWithoutProductName {
    return where((item) => item.productName == null || item.productName!.isEmpty).toList();
  }

  double get completionRate {
    if (isEmpty) return 0.0;
    final sentCount = where((item) => item.isSentToServer && !item.isUpdated).length;
    return sentCount / length;
  }

  String get completionRateString {
    final rate = completionRate;
    return '${(rate * 100).toStringAsFixed(1)}%';
  }

  List<ScannedItem> get needsAttention {
    return where((item) => 
      !item.isSentToServer || 
      item.isUpdated || 
      (item.daysUntilExpiry != null && item.daysUntilExpiry! < 30)
    ).toList();
  }

  Map<String, dynamic> get comprehensiveStatistics {
    final totalItems = length;
    final sent = where((item) => item.isSentToServer && !item.isUpdated).length;
    final updated = where((item) => item.isUpdated).length;
    final pending = where((item) => !item.isSentToServer).length;
    final qrCount = qrItems.length;
    final oneDCount = oneDItems.length;
    final totalQty = totalQuantity;
    final uniqueBarcodesList = uniqueBarcodes.length;
    final expiringSoon = expiringSoonItems.length;
    final expired = expiredItems.length;
    final completion = completionRate;

    return {
      'total_items': totalItems,
      'sent_items': sent,
      'updated_items': updated,
      'pending_items': pending,
      'qr_count': qrCount,
      'one_d_count': oneDCount,
      'total_quantity': totalQty,
      'unique_barcodes': uniqueBarcodesList,
      'expiring_soon': expiringSoon,
      'expired': expired,
      'completion_rate': completion,
      'product_types': productTypeStatistics,
      'expiration_stats': expirationStatistics,
    };
  }

  // Yeni metod: Database ID'lerini alma
  List<int> get databaseIds {
    return where((item) => item.id.contains('_'))
        .map((item) => int.tryParse(item.id.split('_').first) ?? 0)
        .where((id) => id > 0)
        .toList();
  }

  // Yeni metod: Belirli bir raf için istatistik - DÜZELTİLDİ
  Map<String, dynamic> getStatisticsForShelf(String shelfCode) {
    final shelfItems = where((item) => item.shelfCode == shelfCode).toList();
    return _calculateShelfStatistics(shelfItems);
  }

  // Yeni metod: Tarihe göre filtreleme
  List<ScannedItem> whereDateRange(DateTime start, DateTime end) {
    return where((item) => 
      item.timestamp.isAfter(start) && item.timestamp.isBefore(end)
    ).toList();
  }

  // Yeni metod: Bugünkü öğeler
  List<ScannedItem> get todayItems {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    return whereDateRange(todayStart, todayEnd);
  }

  // Yeni metod: Bu haftanın öğeleri
  List<ScannedItem> get thisWeekItems {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final start = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    final end = start.add(const Duration(days: 7));
    return whereDateRange(start, end);
  }

  // Yeni metod: Batch işlemler için güncelleme
  List<ScannedItem> markAllAsSent() {
    return map((item) => item.copyWith(
      isSentToServer: true,
      isUpdated: false,
    )).toList();
  }

  // Yeni metod: Raf kodunu toplu güncelleme
  List<ScannedItem> updateShelfCodeForAll(String newShelfCode) {
    return map((item) => item.copyWith(
      shelfCode: newShelfCode,
      isUpdated: item.shelfCode != newShelfCode,
    )).toList();
  }

  // Yeni metod: Miktarı toplu güncelleme (sadece 1D barkodlar için)
  List<ScannedItem> updateQuantityForBarcode(String barcode, int newQuantity) {
    return map((item) {
      if (item.barcode == barcode && !item.isQR) {
        return item.copyWith(
          quantity: newQuantity,
          isUpdated: item.quantity != newQuantity,
        );
      }
      return item;
    }).toList();
  }

  // Yeni metod: Geçersiz öğeleri filtreleme
  List<ScannedItem> get validItems {
    return where((item) => 
      item.barcode.isNotEmpty && 
      item.success && 
      item.hasValidShelfCode
    ).toList();
  }

  // Yeni metod: Hatalı öğeler
  List<ScannedItem> get invalidItems {
    return where((item) => 
      item.barcode.isEmpty || 
      !item.success || 
      !item.hasValidShelfCode
    ).toList();
  }

  // Yeni metod: Performans optimizasyonu için batch işlemler
  Map<String, List<ScannedItem>> groupByBarcode() {
    final gruplar = <String, List<ScannedItem>>{};
    
    for (final item in this) {
      if (!gruplar.containsKey(item.barcode)) {
        gruplar[item.barcode] = [];
      }
      gruplar[item.barcode]!.add(item);
    }
    
    return gruplar;
  }

  // Yeni metod: En çok taranan ürünler
  List<Map<String, dynamic>> get mostScannedProducts {
    final gruplar = groupByBarcode();
    final result = <Map<String, dynamic>>[];
    
    gruplar.forEach((barcode, items) {
      final totalQuantity = items.fold(0, (sum, item) => sum + item.quantity);
      result.add({
        'barcode': barcode,
        'productName': items.first.productName ?? barcode,
        'totalQuantity': totalQuantity,
        'scanCount': items.length,
        'lastScanned': items.sortedByTime().first.timestamp,
      });
    });
    
    result.sort((a, b) => b['totalQuantity'].compareTo(a['totalQuantity']));
    return result.take(10).toList();
  }

  // YARDIMCI METOD: Raf istatistikleri hesaplama
  Map<String, dynamic> _calculateShelfStatistics(List<ScannedItem> shelfItems) {
    final totalItems = shelfItems.length;
    final sent = shelfItems.where((item) => item.isSentToServer && !item.isUpdated).length;
    final updated = shelfItems.where((item) => item.isUpdated).length;
    final pending = shelfItems.where((item) => !item.isSentToServer).length;
    final qrCount = shelfItems.where((item) => item.isQR).length;
    final oneDCount = shelfItems.where((item) => !item.isQR).length;
    final totalQty = shelfItems.fold(0, (sum, item) => sum + (item.isQR ? 1 : item.quantity));

    return {
      'total_items': totalItems,
      'sent_items': sent,
      'updated_items': updated,
      'pending_items': pending,
      'qr_count': qrCount,
      'one_d_count': oneDCount,
      'total_quantity': totalQty,
    };
  }
}