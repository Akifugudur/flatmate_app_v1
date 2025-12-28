import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'dashboard_page.dart';
import 'widgets/auth_shell.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _auth = FirebaseAuth.instance;
  final _fs = FirebaseFirestore.instance;

  final _formKey = GlobalKey<FormState>();

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
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final email = _email.text.trim();
    final pass = _password.text.trim();
    final name = _name.text.trim();

    setState(() => _loading = true);
    try {
      final cred = await _auth.createUserWithEmailAndPassword(email: email, password: pass);
      final uid = cred.user!.uid;

      await _fs.runTransaction((tx) async {
        final groupRef = _fs.collection('groups').doc(groupId);
        final snap = await tx.get(groupRef);
        final data = snap.data() ?? {};

        final List members = List.from(data['members'] ?? []);
        final taken = members.any((m) => (m['roomNumber'] as num?)?.toInt() == _roomNo);
        if (taken) {
          throw Exception('That room is already taken.');
        }

        tx.set(_fs.collection('users').doc(uid), {
          'email': email,
          'name': name,
          'groupId': groupId,
          'roomNumber': _roomNo,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        members.add({'uid': uid, 'roomNumber': _roomNo});
        tx.set(groupRef, {
          'members': members,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

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
      _toast(e.message ?? 'Registration failed.');
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
    return AuthShell(
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Image.asset('assets/loogo.png', height: 88)),
              const SizedBox(height: 12),
              Text(
                'Create a new FlatMate account',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              _frostedField(
                controller: _name,
                label: 'Full name',
                icon: Icons.person_outline,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
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
                    return 'Email is required';
                  }
                  if (!text.contains('@') || !text.contains('.')) {
                    return 'Enter a valid email';
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
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                validator: (value) {
                  final text = value ?? '';
                  if (text.isEmpty) {
                    return 'Password is required';
                  }
                  if (text.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
                trailing: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                ),
              ),
              const SizedBox(height: 14),
              _roomSelector(),
              const SizedBox(height: 22),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _loading ? null : _register,
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Complete signup'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _loading ? null : () => Navigator.pop(context),
                child: const Text('I already have an account'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roomSelector() {
    final items = List.generate(20, (i) => i + 1);
    return FormField<int>(
      validator: (_) => _roomNo == null ? 'You must select a room' : null,
      builder: (state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.18)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _roomNo,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF2B2A49),
                  iconEnabledColor: Colors.white70,
                  hint: Text(
                    'Select a room number',
                    style: TextStyle(color: Colors.white.withOpacity(0.72)),
                  ),
                  items: items
                      .map((n) => DropdownMenuItem(
                            value: n,
                            child: Text('Room $n', style: const TextStyle(color: Colors.white)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _roomNo = v);
                    state.didChange(v);
                  },
                ),
              ),
            ),
            if (state.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  state.errorText!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
          ],
        );
      },
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
              obscureText: obscure,
              keyboardType: keyboardType,
              textInputAction: textInputAction,
              autofillHints: autofillHints,
              validator: validator,
              style: const TextStyle(color: Colors.white),
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
