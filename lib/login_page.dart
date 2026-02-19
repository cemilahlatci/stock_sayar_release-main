// lib/login_page.dart - TAM GÜNCELLENMİŞ VERSİYON

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'main_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _rememberMe = true;

  // Renkler
  final Color _primaryColor = const Color(0xFF0EA14B); // Yeşil
  final Color _backgroundColor = Colors.white;
  final Color _textColor = Colors.black;
  final Color _hintColor = Colors.grey[600]!;

  @override
  void initState() {
    super.initState();
    _checkRememberedUser();
  }

  void _checkRememberedUser() async {
    try {
      // ⚡ OPTİMİZASYON: "Beni hatırla" için artık Database KULLANILMIYOR
      // SharedPreferences'tan email'i al
      final prefs = await SharedPreferences.getInstance();
      final rememberedEmail = prefs.getString('last_user_email');
      
      if (rememberedEmail != null && rememberedEmail.isNotEmpty && mounted) {
        setState(() {
          _emailController.text = rememberedEmail;
        });
      }
    } catch (_) {
      // Hatırlanan kullanıcı kontrolü başarısız - sessizce devam et
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final result = await AuthService.login(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (result['status'] == 'success') {
        // ⚡ OPTİMİZASYON: Kullanıcı bilgileri AuthService ile SharedPreferences'a kaydedildi
        // Database'e KAYIT YOK - ÇİFTE KAYIT ÖNLENDİ
        
        // ⚡ OPTİMİZASYON: "Beni hatırla" için sadece SharedPreferences kullan
        if (_rememberMe) {
          // Email'i SharedPreferences'da tut (AuthService zaten kaydetti)
          // Ekstra Database işlemi YOK
        } else {
          // Remember me kapalıysa, AuthService.clearUserInfo() çağrılacak
          // Bu logout sırasında yapılır
        }

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainPage()),
        );
      } else {
        if (!mounted) return;
        _showErrorDialog(result['message']);
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog('Bağlantı hatası oluştu. Lütfen internet bağlantınızı kontrol edin.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ⚡ OPTİMİZASYON: Kullanıcı bilgileri artık Database'e kaydedilmiyor
  // Sadece SharedPreferences'ta tutuluyor - ÇİFTE KAYIT ÖNLENDİ

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Giriş Hatası',
          style: TextStyle(
            fontFamily: 'DIN',
            color: _textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(fontFamily: 'DIN', color: _textColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Tamam',
              style: TextStyle(
                fontFamily: 'DIN',
                color: _primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Üst Logo - Alphega
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: Image.asset('assets/images/alphega_logo120.png'),
                  ),
                  const SizedBox(height: 32),
                  
                  // Başlık
                  Text(
                    'Stok Sayım Sistemi',
                    style: TextStyle(
                      fontSize: 28,
                      fontFamily: 'DIN',
                      fontWeight: FontWeight.bold,
                      color: _primaryColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Lütfen giriş yapın',
                    style: TextStyle(
                      fontSize: 16,
                      fontFamily: 'DIN',
                      color: _hintColor,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Email
                  TextFormField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      labelStyle: TextStyle(
                        fontFamily: 'DIN',
                        color: _hintColor,
                      ),
                      prefixIcon: Icon(Icons.email, color: _primaryColor),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: _primaryColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: _primaryColor, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    style: TextStyle(
                      fontFamily: 'DIN',
                      color: _textColor,
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Lütfen email adresinizi girin';
                      }
                      if (!value.contains('@')) {
                        return 'Geçerli bir email adresi girin';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Şifre
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Şifre',
                      labelStyle: TextStyle(
                        fontFamily: 'DIN',
                        color: _hintColor,
                      ),
                      prefixIcon: Icon(Icons.lock, color: _primaryColor),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: _primaryColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: _primaryColor, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    style: TextStyle(
                      fontFamily: 'DIN',
                      color: _textColor,
                    ),
                    obscureText: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Lütfen şifrenizi girin';
                      }
                      if (value.length < 3) {
                        return 'Şifre en az 3 karakter olmalıdır';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Beni Hatırla
                  Row(
                    children: [
                      Theme(
                        data: ThemeData(
                          checkboxTheme: CheckboxThemeData(
                            fillColor: WidgetStateProperty.resolveWith<Color>(
                              (Set<WidgetState> states) {
                                if (states.contains(WidgetState.selected)) {
                                  return _primaryColor;
                                }
                                return Colors.grey.shade400;
                              },
                            ),
                          ),
                        ),
                        child: Checkbox(
                          value: _rememberMe,
                          onChanged: (value) {
                            setState(() => _rememberMe = value!);
                          },
                        ),
                      ),
                      Text(
                        'Beni Hatırla',
                        style: TextStyle(
                          fontFamily: 'DIN',
                          color: _textColor,
                        ),
                      ),
                      const Spacer(),
                      // Şifremi Unuttum
                      TextButton(
                        onPressed: () {
                          _showPasswordResetInfo();
                        },
                        child: Text(
                          'Şifremi Unuttum',
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'DIN',
                            color: _primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Giriş Butonu
                  if (_isLoading)
                    CircularProgressIndicator(color: _primaryColor)
                  else
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 2,
                        ),
                        child: const Text(
                          'GİRİŞ YAP',
                          style: TextStyle(
                            fontSize: 16,
                            fontFamily: 'DIN',
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 20),

                  // Alt Logo - Crossist
                  SizedBox(
                    width: 120,
                    height: 42,
                    child: Image.asset('assets/images/crossist_stok_sayim120.png'),
                  ),
                  const SizedBox(height: 16),
                  
                  // Versiyon
                  Text(
                    'v1.21.02',
                    style: TextStyle(
                      fontFamily: 'DIN',
                      color: _hintColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showPasswordResetInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Şifre Sıfırlama',
          style: TextStyle(
            fontFamily: 'DIN',
            color: _textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Şifre sıfırlama işlemi için sistem yöneticinizle iletişime geçiniz.',
          style: TextStyle(fontFamily: 'DIN', color: _textColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Tamam',
              style: TextStyle(
                fontFamily: 'DIN',
                color: _primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}