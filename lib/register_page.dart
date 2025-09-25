import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dashboard_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _auth = FirebaseAuth.instance;
  final _fs = FirebaseFirestore.instance;

  // Sabit grup id – istersen setting ekranına taşırsın
  final String groupId = 'building8_flat3';

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  int? _roomNo;

  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final email = _email.text.trim();
    final pass = _password.text.trim();
    final name = _name.text.trim();

    if (email.isEmpty || pass.isEmpty || name.isEmpty || _roomNo == null) {
      _toast('Tüm alanları doldur.');
      return;
    }

    setState(() => _loading = true);
    try {
      // 1) auth oluştur
      final cred = await _auth.createUserWithEmailAndPassword(email: email, password: pass);
      final uid = cred.user!.uid;

      // 2) oda boş mu? – transaction ile garanti
      await _fs.runTransaction((tx) async {
        final groupRef = _fs.collection('groups').doc(groupId);
        final snap = await tx.get(groupRef);
        final data = snap.data() ?? {};

        final List members = List.from(data['members'] ?? []);
        final taken = members.any((m) => (m['roomNumber'] as num?)?.toInt() == _roomNo);
        if (taken) {
          throw Exception('Seçtiğin oda dolu.');
        }

        // users koleksiyonu (opsiyonel)
        tx.set(_fs.collection('users').doc(uid), {
          'email': email,
          'name': name,
          'groupId': groupId,
          'roomNumber': _roomNo,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // members’a ekle
        members.add({'uid': uid, 'roomNumber': _roomNo});
        tx.set(groupRef, {
          'members': members,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // currentTasks hiç yoksa başlangıçta boş kalsın; dashboard “Take task” ile atanır
        tx.set(groupRef, {
          'currentTasks': {
            'trash': (data['currentTasks'] ?? const {})['trash'],
            'kitchen': (data['currentTasks'] ?? const {})['kitchen'],
            'living_room': (data['currentTasks'] ?? const {})['living_room'],
          }
        }, SetOptions(merge: true));
      });

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DashboardPage()),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      _toast(e.message ?? 'Kayıt başarısız.');
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF2E335A), Color(0xFF1C1B33)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 30,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 10, bottom: 24),
                          child: Image.asset('assets/logo.png', height: 72),
                        ),
                        const Text(
                          'Create account',
                          style: TextStyle(
                            fontSize: 22,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _frostedField(
                          controller: _name,
                          hint: 'Full name',
                          icon: Icons.person_outline,
                        ),
                        const SizedBox(height: 14),
                        _frostedField(
                          controller: _email,
                          hint: 'Email',
                          icon: Icons.alternate_email,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 14),
                        _frostedField(
                          controller: _password,
                          hint: 'Password',
                          icon: Icons.lock_outline,
                          obscure: _obscure,
                          trailing: IconButton(
                            onPressed: () => setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _roomSelector(),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _register,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6C63FF),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: _loading
                                ? const SizedBox(
                                    width: 22, height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Sign up', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _loading ? null : () => Navigator.pop(context),
                          child: const Text('Back to sign in'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _roomSelector() {
    // 1..20 (dilersen artır)
    final items = List.generate(20, (i) => i + 1);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _roomNo,
          isExpanded: true,
          dropdownColor: const Color(0xFF2B2A49),
          iconEnabledColor: Colors.white70,
          hint: Text('Select room number',
              style: TextStyle(color: Colors.white.withOpacity(0.7))),
          items: items
              .map((n) => DropdownMenuItem(
                    value: n,
                    child: Text('Room $n', style: const TextStyle(color: Colors.white)),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _roomNo = v),
        ),
      ),
    );
  }

  Widget _frostedField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(icon, color: Colors.white70),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboardType,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          if (trailing != null) trailing,
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
