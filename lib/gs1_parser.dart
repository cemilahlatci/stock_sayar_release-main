// lib/gs1_parser.dart - REFACTORED

class _AIField {
  final String ai;
  final String value;
  const _AIField(this.ai, this.value);
}

class GS1Parser {
  static const _gsSeparator = 29; // GS separator character code

  // Sabit uzunluklu AI'lar: AI kodu -> toplam uzunluk (AI dahil)
  static const _fixedLengthAIs = {
    '01': 16, // GTIN (2 AI + 14 data)
    '17': 8,  // Son Kullanma Tarihi (2 AI + 6 data)
    '11': 8,  // Üretim Tarihi (2 AI + 6 data)
    '15': 8,  // En İyi Kullanma Tarihi (2 AI + 6 data)
  };

  // Değişken uzunluklu AI'lar
  static const _variableLengthAIs = {'10', '21', '30', '37'};

  /// Ortak AI ayrıştırma metodu - tüm parsing işlemleri bunu kullanır
  static List<_AIField> _extractAIFields(String barkod) {
    final fields = <_AIField>[];
    int index = 0;

    while (index < barkod.length) {
      if (index + 2 > barkod.length) break;

      final ai = barkod.substring(index, index + 2);

      if (_fixedLengthAIs.containsKey(ai)) {
        final totalLen = _fixedLengthAIs[ai]!;
        if (index + totalLen <= barkod.length) {
          fields.add(_AIField(ai, barkod.substring(index + 2, index + totalLen)));
          index += totalLen;
        } else {
          index++;
        }
      } else if (_variableLengthAIs.contains(ai)) {
        if (index + 2 < barkod.length) {
          final remaining = barkod.substring(index + 2);
          final endIndex = remaining.indexOf(String.fromCharCode(_gsSeparator));
          if (endIndex != -1) {
            fields.add(_AIField(ai, remaining.substring(0, endIndex)));
            index += 2 + endIndex + 1;
          } else {
            fields.add(_AIField(ai, remaining));
            index = barkod.length;
          }
        } else {
          index++;
        }
      } else {
        index++;
      }
    }

    return fields;
  }

  /// AI alanlarından belirli bir AI değerini döndürür
  static String? _getFieldValue(List<_AIField> fields, String ai) {
    for (final field in fields) {
      if (field.ai == ai) return field.value;
    }
    return null;
  }

  static ({String? gtin, String? sonKullanmaTarihi, String? partiNo}) parseBarkod(String barkod) {
    try {
      final fields = _extractAIFields(barkod);
      final sktRaw = _getFieldValue(fields, '17');
      return (
        gtin: _getFieldValue(fields, '01'),
        sonKullanmaTarihi: sktRaw != null ? _formatSKT(sktRaw) : null,
        partiNo: _getFieldValue(fields, '10'),
      );
    } catch (e) {
      return (gtin: null, sonKullanmaTarihi: null, partiNo: null);
    }
  }

  static String _formatSKT(String skt) {
    if (skt.length != 6) return skt;
    try {
      final yil = skt.substring(0, 2);
      final ay = skt.substring(2, 4);
      final gun = skt.substring(4, 6);
      return '20$yil-$ay-$gun';
    } catch (e) {
      return skt;
    }
  }

  static String? convertToGtin13(String? gtin14) {
    if (gtin14 == null || gtin14.length != 14) return gtin14;
    if (gtin14.startsWith('0')) return gtin14.substring(1);
    return gtin14;
  }

  static String? formatSKTForDisplay(String? skt) {
    if (skt == null) return null;
    try {
      final parts = skt.split('-');
      if (parts.length == 3) {
        return '${parts[2]}/${parts[1]}/${parts[0]}';
      }
      return skt;
    } catch (e) {
      return skt;
    }
  }

  static bool isSKTExpired(String? skt) {
    if (skt == null) return false;
    try {
      final date = _parseDateString(skt);
      return date?.isBefore(DateTime.now()) ?? false;
    } catch (e) {
      return false;
    }
  }

  static int? getDaysUntilExpiry(String? skt) {
    if (skt == null) return null;
    try {
      final date = _parseDateString(skt);
      return date?.difference(DateTime.now()).inDays;
    } catch (e) {
      return null;
    }
  }

  /// Ortak tarih parse metodu
  static DateTime? _parseDateString(String skt) {
    final parts = skt.split('-');
    if (parts.length != 3) return null;
    final yil = int.tryParse(parts[0]);
    final ay = int.tryParse(parts[1]);
    final gun = int.tryParse(parts[2]);
    if (yil == null || ay == null || gun == null) return null;
    return DateTime(yil, ay, gun);
  }

  static Map<String, dynamic> parseFullBarcode(String barkod) {
    try {
      final fields = _extractAIFields(barkod);
      final result = <String, dynamic>{};

      for (final field in fields) {
        switch (field.ai) {
          case '01':
            result['gtin'] = field.value;
            break;
          case '17':
            result['son_kullanma_tarihi'] = _formatSKT(field.value);
            break;
          case '10':
            result['parti_no'] = field.value;
            break;
          case '21':
            result['seri_no'] = field.value;
            break;
          case '11':
            result['uretim_tarihi'] = _formatSKT(field.value);
            break;
          case '15':
            result['en_iyi_kullanma_tarihi'] = _formatSKT(field.value);
            break;
          case '30':
            result['degisken_miktar'] = field.value;
            break;
          case '37':
            result['miktar'] = field.value;
            break;
        }
      }

      return result;
    } catch (e) {
      return {};
    }
  }

  static bool isValidGS1Barcode(String barkod) {
    if (barkod.isEmpty) return false;
    return barkod.contains('01');
  }

  static String? extractGTIN(String barkod) {
    return parseBarkod(barkod).gtin;
  }

  static String? extractExpirationDate(String barkod) {
    return parseBarkod(barkod).sonKullanmaTarihi;
  }

  static String? extractBatchNumber(String barkod) {
    return parseBarkod(barkod).partiNo;
  }

  static List<String> extractAllAIs(String barkod) {
    try {
      return _extractAIFields(barkod).map((f) => f.ai).toList();
    } catch (e) {
      return [];
    }
  }

  static String getAIDescription(String ai) {
    const aiDescriptions = {
      '01': 'GTIN',
      '17': 'Son Kullanma Tarihi',
      '10': 'Parti Numarası',
      '21': 'Seri Numarası',
      '11': 'Üretim Tarihi',
      '15': 'En İyi Kullanma Tarihi',
      '30': 'Değişken Miktar',
      '37': 'Miktar',
    };
    return aiDescriptions[ai] ?? 'Bilinmeyen AI ($ai)';
  }

  static Map<String, String> parseBarcodeWithDetails(String barkod) {
    try {
      final fields = _extractAIFields(barkod);
      final details = <String, String>{};

      for (final field in fields) {
        final desc = getAIDescription(field.ai);
        switch (field.ai) {
          case '01':
            details[desc] = field.value;
            break;
          case '17':
          case '11':
          case '15':
            details[desc] = '${field.value} → ${_formatSKT(field.value)}';
            break;
          default:
            details[desc] = field.value;
            break;
        }
      }

      return details;
    } catch (e) {
      return {};
    }
  }

  static String formatBarcodeForDisplay(String barkod) {
    try {
      final details = parseBarcodeWithDetails(barkod);
      if (details.isEmpty) return barkod;

      final buffer = StringBuffer();
      buffer.writeln('GS1 Barkod Detayları:');
      buffer.writeln('────────────────────');
      details.forEach((key, value) {
        buffer.writeln('• $key: $value');
      });
      buffer.writeln('────────────────────');
      buffer.writeln('Orijinal: $barkod');
      return buffer.toString();
    } catch (e) {
      return barkod;
    }
  }

  static bool isQRCodeContainsGS1(String qrData) {
    return qrData.contains('01') &&
        (qrData.contains(')') ||
            qrData.contains(String.fromCharCode(_gsSeparator)) ||
            qrData.length >= 20);
  }

  static Map<String, dynamic> parseQRCode(String qrData) {
    try {
      if (isQRCodeContainsGS1(qrData)) {
        return parseFullBarcode(qrData);
      } else {
        return {
          'gtin': qrData,
          'tip': 'BASIT_BARKOD',
        };
      }
    } catch (e) {
      return {
        'hata': 'Parse edilemedi: $e',
        'orjinal_veri': qrData,
      };
    }
  }

  static String validateBarcode(String barkod) {
    if (barkod.isEmpty) return 'Barkod boş';
    if (!isValidGS1Barcode(barkod)) return 'Geçersiz GS1 barkod formatı';

    final gtin = extractGTIN(barkod);
    if (gtin == null) return 'GTIN bulunamadı';
    if (gtin.length != 14) return 'GTIN 14 haneli olmalı: $gtin';
    if (!_validateGTINChecksum(gtin)) return 'GTIN checksum hatası';

    return 'Geçerli GS1 barkod';
  }

  static bool _validateGTINChecksum(String gtin) {
    if (gtin.length != 14) return false;
    try {
      int sum = 0;
      for (int i = 0; i < 13; i++) {
        final digit = int.parse(gtin[i]);
        final multiplier = (i % 2 == 0) ? 3 : 1;
        sum += digit * multiplier;
      }
      final checksum = (10 - (sum % 10)) % 10;
      return checksum == int.parse(gtin[13]);
    } catch (e) {
      return false;
    }
  }

  static String cleanBarcode(String barkod) {
    var cleaned = barkod.replaceAll(String.fromCharCode(_gsSeparator), '');
    cleaned = cleaned.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
    return cleaned.trim();
  }

  static Map<String, dynamic> getBarcodeInfo(String barkod) {
    try {
      final cleanedBarcode = cleanBarcode(barkod);
      final parsedData = parseFullBarcode(cleanedBarcode);
      final validationResult = validateBarcode(cleanedBarcode);
      final expirationDate = extractExpirationDate(cleanedBarcode);

      return {
        'orjinal_barkod': barkod,
        'temizlenmis_barkod': cleanedBarcode,
        'gecerli_mi': validationResult.contains('Geçerli'),
        'dogrulama_sonucu': validationResult,
        'gtin': parsedData['gtin'],
        'gtin13': convertToGtin13(parsedData['gtin']),
        'son_kullanma_tarihi': expirationDate,
        'parti_no': parsedData['parti_no'],
        'seri_no': parsedData['seri_no'],
        'uretim_tarihi': parsedData['uretim_tarihi'],
        'sk_t_gecerlilik': expirationDate != null ? getDaysUntilExpiry(expirationDate) : null,
        'sk_t_durumu': expirationDate != null
            ? (isSKTExpired(expirationDate) ? 'SÜRESİ DOLMUŞ' : 'GEÇERLİ')
            : 'BİLİNMİYOR',
        'ai_listesi': extractAllAIs(cleanedBarcode),
        'detayli_veri': parsedData,
      };
    } catch (e) {
      return {
        'orjinal_barkod': barkod,
        'hata': 'İşlenirken hata oluştu: $e',
        'gecerli_mi': false,
        'dogrulama_sonucu': 'Hata: $e',
      };
    }
  }
}
