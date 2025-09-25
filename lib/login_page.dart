import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'dashboard_page.dart';
import 'register_page.dart';
import 'widgets/auth_shell.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _auth = FirebaseAuth.instance;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _email.text.trim();
    final pass = _password.text.trim();
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _loading = true);
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: pass);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardPage()),
      );
    } on FirebaseAuthException catch (e) {
      _toast(e.message ?? 'Giriş başarısız.');
    } catch (e) {
      _toast('Giriş hatası: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      _toast('Şifre sıfırlamak için email gir.');
      return;
    }
    try {
      await _auth.sendPasswordResetEmail(email: email);
      _toast('Sıfırlama maili gönderildi.');
    } on FirebaseAuthException catch (e) {
      _toast(e.message ?? 'Sıfırlama başarısız.');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Image.asset(
                  'assets/loogo.png',
                  height: 160,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Tekrar hoş geldin 👋',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              _frostedField(
                controller: _email,
                label: 'Email',
                icon: Icons.alternate_email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) {
                    return 'Email gerekli';
                  }
                  if (!text.contains('@') || !text.contains('.')) {
                    return 'Geçerli bir email gir';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              _frostedField(
                controller: _password,
                label: 'Password',
                icon: Icons.lock_outline,
                obscure: _obscure,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _login(),
                validator: (value) {
                  final text = value ?? '';
                  if (text.isEmpty) {
                    return 'Şifre gerekli';
                  }
                  if (text.length < 6) {
                    return 'Şifre en az 6 karakter olmalı';
                  }
                  return null;
                },
                trailing: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _loading ? null : _resetPassword,
                  child: const Text('Şifremi unuttum'),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _loading ? null : _login,
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Giriş yap'),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Hesabın yok mu? '),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const RegisterPage()),
                            ),
                    child: const Text('Hemen kaydol'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _frostedField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? trailing,
    TextInputAction? textInputAction,
    void Function(String)? onFieldSubmitted,
    Iterable<String>? autofillHints,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(icon),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: controller,
              keyboardType: keyboardType,
              obscureText: obscure,
              style: const TextStyle(color: Colors.white),
              textInputAction: textInputAction,
              onFieldSubmitted: onFieldSubmitted,
              autofillHints: autofillHints,
              validator: validator,
              decoration: InputDecoration(
                labelText: label,
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.72)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 18),
              ),
            ),
          ),
          if (trailing != null) trailing,
          const SizedBox(width: 10),
        ],
      ),
    );
  }
}
