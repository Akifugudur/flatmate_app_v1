import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ExpensesPage extends StatefulWidget {
  final String groupId;
  final List<int> roomNumbers;
  final bool embedded;
  const ExpensesPage({
    super.key,
    required this.groupId,
    required this.roomNumbers,
    this.embedded = false,
  });

  @override
  ExpensesPageState createState() => ExpensesPageState();
}

class ExpensesPageState extends State<ExpensesPage> {
  late final CollectionReference<Map<String, dynamic>> _col;

  @override
  void initState() {
    super.initState();
    _col = FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('expenses');
  }

  Future<void> openAddExpenseSheet() => _addExpenseDialog();

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
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Yeni harcama',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Açıklama',
                    hintText: 'Örn. Bulaşık deterjanı',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.sentences,
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
                    final amount = double.tryParse(v.replaceAll(',', '.'));
                    if (amount == null || amount <= 0) return 'Geçerli bir tutar gir';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: buyerRoom,
                  items: widget.roomNumbers.map((room) {
                    return DropdownMenuItem(value: room, child: Text('Oda $room'));
                  }).toList(),
                  onChanged: (v) => buyerRoom = v,
                  decoration: const InputDecoration(
                    labelText: 'Kim aldı? (Oda)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null ? 'Oda seç' : null,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
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
                  icon: const Icon(Icons.save),
                  label: const Text('Kaydet'),
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
      builder: (context) => AlertDialog(
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
    final baseQuery = _col;
    return FutureBuilder<bool>(
      future: _hasCreatedAt(baseQuery),
      builder: (context, snap) {
        final hasCreatedAt = snap.data ?? false;
        final q = hasCreatedAt
            ? baseQuery.orderBy('createdAt', descending: true).limit(200)
            : baseQuery.limit(200);

        final content = _buildContent(q);

        if (widget.embedded) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
            child: content,
          );
        }

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Row(
              children: [
                Image.asset('assets/loogo.png', height: 28),
                const SizedBox(width: 8),
                const Text('Giderler'),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _addExpenseDialog,
            icon: const Icon(Icons.add),
            label: const Text('Harcama ekle'),
          ),
          body: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            child: content,
          ),
        );
      },
    );
  }

  Widget _buildContent(Query<Map<String, dynamic>> q) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
          return const _EmptyExpensesState();
        }

        final totalsByRoom = <int, double>{};
        double grandTotal = 0;
        for (final d in docs) {
          final m = d.data();
          final amount = (m['amount'] as num?)?.toDouble() ?? 0;
          final room = (m['buyerRoom'] as num?)?.toInt();
          grandTotal += amount;
          if (room != null) {
            totalsByRoom.update(room, (value) => value + amount, ifAbsent: () => amount);
          }
        }

        return Column(
          children: [
            _ExpensesSummary(
              grandTotal: grandTotal,
              totalsByRoom: totalsByRoom,
              rooms: widget.roomNumbers,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final m = doc.data();
                  final amount = (m['amount'] as num?)?.toDouble() ?? 0;
                  final desc = (m['description'] as String?) ?? '';
                  final room = (m['buyerRoom'] as num?)?.toInt();
                  final email = (m['createdByEmail'] as String?) ?? '';
                  final ts = (m['createdAt'] as Timestamp?)?.toDate();
                  final timeStr = ts == null ? '' : ts.toLocal().toString().split('.').first;

                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(room == null ? '?' : room.toString()),
                    ),
                    title: Text(desc, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text([
                      if (email.isNotEmpty) email,
                      if (timeStr.isNotEmpty) timeStr,
                    ].join(' • ')),
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

class _ExpensesSummary extends StatelessWidget {
  const _ExpensesSummary({
    required this.grandTotal,
    required this.totalsByRoom,
    required this.rooms,
  });

  final double grandTotal;
  final Map<int, double> totalsByRoom;
  final List<int> rooms;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleRooms = rooms.take(4).toList();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Toplam: ₺${grandTotal.toStringAsFixed(2)}',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: visibleRooms.map((room) {
                final amount = totalsByRoom[room] ?? 0;
                return Chip(
                  label: Text('Oda $room • ₺${amount.toStringAsFixed(0)}'),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyExpensesState extends StatelessWidget {
  const _EmptyExpensesState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.receipt_long_outlined, size: 48),
          SizedBox(height: 12),
          Text('Henüz harcama eklenmemiş.'),
          SizedBox(height: 4),
          Text('Sağ alttaki butonla ilk harcamanı kaydet.'),
        ],
      ),
    );
  }
}
