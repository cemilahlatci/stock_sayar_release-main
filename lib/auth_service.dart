// lib/auth_service.dart - TAM GÜNCELLENMİŞ VERSİYON
import 'dart:convert';
import 'dart:developer';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String baseUrl = 'https://stokdurum.com/cemil'; // Sunucu URL'nizi buraya ekleyin
  
  // Kullanıcı bilgilerini saklama anahtarları
  static const String _userEmailKey = 'user_email';
  static const String _userNameKey = 'user_name';
  static const String _userGlnKey = 'user_gln';
  static const String _userRoleKey = 'user_role';
  
  // Oturum açmış kullanıcı bilgilerini al
  static Future<Map<String, String>?> getCurrentUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final email = prefs.getString(_userEmailKey);
      final name = prefs.getString(_userNameKey);
      final gln = prefs.getString(_userGlnKey);
      final role = prefs.getString(_userRoleKey);
      
      if (email == null || gln == null) {
        log('⚠️ Kullanıcı bilgileri bulunamadı veya eksik');
        return null;
      }
      
      log('✅ Kullanıcı bilgileri alındı: $email - GLN: $gln');
      
      return {
        'email': email,
        'person_name': name ?? '',
        'eczane_gln': gln,
        'role': role ?? 'user',
      };
    } catch (e) {
      log('❌ Kullanıcı bilgisi alınamadı: $e');
      return null;
    }
  }
  
  // Kullanıcı bilgilerini kaydet
  static Future<void> saveUserInfo(Map<String, dynamic> userData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.setString(_userEmailKey, userData['email'] ?? '');
      await prefs.setString(_userNameKey, userData['person_name'] ?? '');
      await prefs.setString(_userGlnKey, userData['eczane_gln'] ?? '');
      await prefs.setString(_userRoleKey, userData['role'] ?? 'user');
      
      log('✅ Kullanıcı bilgileri kaydedildi: ${userData['email']} - GLN: ${userData['eczane_gln']}');
    } catch (e) {
      log('❌ Kullanıcı bilgileri kaydedilemedi: $e');
    }
  }
  
  // Kullanıcı bilgilerini temizle (çıkış yapınca)
  static Future<void> clearUserInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.remove(_userEmailKey);
      await prefs.remove(_userNameKey);
      await prefs.remove(_userGlnKey);
      await prefs.remove(_userRoleKey);
      
      log('✅ Kullanıcı bilgileri temizlendi');
    } catch (e) {
      log('❌ Kullanıcı bilgileri temizlenemedi: $e');
    }
  }
  
  // Kullanıcı giriş yapmış mı kontrol et
  static Future<bool> isLoggedIn() async {
    try {
      final user = await getCurrentUser();
      return user != null && user['email'] != null && user['eczane_gln'] != null;
    } catch (e) {
      log('❌ Oturum kontrol hatası: $e');
      return false;
    }
  }
  
  static Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      log('🔐 Giriş denemesi: $email');
      
      final response = await http.post(
        Uri.parse('$baseUrl/android_login.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 10));

      log('📡 Giriş yanıtı: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['status'] == 'success' && data['user'] != null) {
          // Giriş başarılıysa kullanıcı bilgilerini kaydet
          await saveUserInfo(data['user']);
          log('✅ Giriş başarılı: ${data['user']['email']}');
          return data;
        } else {
          log('❌ Giriş başarısız: ${data['message']}');
          return data;
        }
      } else {
        log('❌ Sunucu hatası: ${response.statusCode}');
        return {'status': 'error', 'message': 'Sunucu hatası: ${response.statusCode}'};
      }
    } catch (e) {
      log('❌ Bağlantı hatası: $e');
      return {'status': 'error', 'message': 'Bağlantı hatası: $e'};
    }
  }

  static Future<Map<String, dynamic>> sendStockData(Map<String, dynamic> data) async {
    try {
      // Önce kullanıcı bilgilerini kontrol et
      final user = await getCurrentUser();
      
      if (user == null) {
        return {
          'status': 'error', 
          'message': 'Kullanıcı oturumu bulunamadı. Lütfen tekrar giriş yapın.'
        };
      }
      
      log('📤 Stok verisi gönderiliyor (Kullanıcı: ${user['person_name']})');
      
      final response = await http.post(
        Uri.parse('$baseUrl/android_api.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 15));

      log('📡 Stok yanıtı: ${response.statusCode}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        log('✅ Stok gönderimi sonucu: ${result['status']}');
        return result;
      } else {
        log('❌ Stok gönderim hatası: ${response.statusCode}');
        return {'status': 'error', 'message': 'Sunucu hatası: ${response.statusCode}'};
      }
    } catch (e) {
      log('❌ Stok gönderim bağlantı hatası: $e');
      return {'status': 'error', 'message': 'Bağlantı hatası: $e'};
    }
  }
}