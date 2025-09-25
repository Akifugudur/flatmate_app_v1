import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ExpensesPage extends StatefulWidget {
  final String groupId;
  final List<int> roomNumbers; // örn: [1,2,3,4,...] – üyelerden doldur
  const ExpensesPage({
    super.key,
    required this.groupId,
    required this.roomNumbers,
  });

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  late final CollectionReference<Map<String, dynamic>> _col;

  @override
  void initState() {
    super.initState();
    _col = FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('expenses');
  }

  Future<void> _addExpenseDialog() async {
    final descCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    int? buyerRoom = widget.roomNumbers.isNotEmpty ? widget.roomNumbers.first : null;

    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Yeni Harcama', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                TextFormField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Açıklama (örn. Bulaşık deterjanı)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Açıklama zorunlu' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Tutar (₺)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Tutar zorunlu';
                    final x = double.tryParse(v.replaceAll(',', '.'));
                    if (x == null || x <= 0) return 'Geçerli bir tutar gir';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: buyerRoom,
                  items: widget.roomNumbers.map((r) {
                    return DropdownMenuItem(value: r, child: Text('Oda $r'));
                  }).toList(),
                  onChanged: (v) => buyerRoom = v,
                  decoration: const InputDecoration(
                    labelText: 'Kim aldı? (Oda)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null ? 'Oda seç' : null,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text('Ekle'),
                    onPressed: () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      final user = FirebaseAuth.instance.currentUser;
                      final amount = double.parse(priceCtrl.text.replaceAll(',', '.'));

                      await _col.add({
                        'description': descCtrl.text.trim(),
                        'amount': amount,
                        'buyerRoom': buyerRoom,
                        'createdAt': FieldValue.serverTimestamp(),
                        'createdByUid': user?.uid,
                        'createdByEmail': user?.email,
                      });

                      if (mounted) Navigator.pop(ctx);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteExpense(String docId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Silinsin mi?'),
        content: const Text('Bu harcamayı silmek istediğine emin misin?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok == true) {
      await _col.doc(docId).delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    // createdAt yoksa orderBy patlamasın diye küçük güvenlik:
    final baseQuery = _col;
    return FutureBuilder<bool>(
      future: _hasCreatedAt(baseQuery),
      builder: (context, snap) {
        final hasCreatedAt = snap.data ?? false;
        final q = hasCreatedAt
            ? baseQuery.orderBy('createdAt', descending: true).limit(200)
            : baseQuery.limit(200);

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Row(
              children: [
                // Minimal logo
                Image.asset('assets/loogo.png', height: 28),
                const SizedBox(width: 8),
                const Text('Expenses'),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _addExpenseDialog,
            icon: const Icon(Icons.add),
            label: const Text('Ekle'),
          ),
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: q.snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Hata: ${snap.error}'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return const Center(child: Text('Henüz harcama yok.'));
              }

              // Toplam ve oda bazlı toplam
              final totalsByRoom = <int, double>{};
              double grandTotal = 0;
              for (final d in docs) {
                final m = d.data();
                final amount = (m['amount'] as num?)?.toDouble() ?? 0;
                final room = (m['buyerRoom'] as num?)?.toInt();
                grandTotal += amount;
                if (room != null) {
                  totalsByRoom.update(room, (v) => v + amount, ifAbsent: () => amount);
                }
              }

              return Column(
                children: [
                  // Üstte küçük toplam özet barı
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Row(
                      children: [
                        Text('Toplam: ₺${grandTotal.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        // İlk 3 odayı kısaca göster
                        Wrap(
                          spacing: 12,
                          children: widget.roomNumbers.take(3).map((r) {
                            final t = totalsByRoom[r] ?? 0;
                            return Text('Oda $r: ₺${t.toStringAsFixed(0)}');
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final doc = docs[i];
                        final m = doc.data();
                        final amount = (m['amount'] as num?)?.toDouble() ?? 0;
                        final desc = (m['description'] as String?) ?? '';
                        final room = (m['buyerRoom'] as num?)?.toInt();
                        final email = (m['createdByEmail'] as String?) ?? '';
                        final ts = (m['createdAt'] as Timestamp?)?.toDate();
                        final timeStr = ts == null
                            ? ''
                            : '${ts.toLocal()}'.split('.').first;

                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(room == null ? '?' : room.toString()),
                          ),
                          title: Text(desc, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('$email  •  $timeStr'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('₺${amount.toStringAsFixed(2)}',
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deleteExpense(doc.id),
                                tooltip: 'Sil',
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<bool> _hasCreatedAt(CollectionReference col) async {
    try {
      final s = await col.limit(1).get();
      if (s.docs.isEmpty) return false;
      final m = s.docs.first.data() as Map<String, dynamic>;
      return m.containsKey('createdAt');
    } catch (_) {
      return false;
    }
  }
}
