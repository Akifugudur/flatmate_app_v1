// lib/history_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class TaskHistoryPage extends StatelessWidget {
  final String groupId;
  const TaskHistoryPage({super.key, required this.groupId});

  @override
  Widget build(BuildContext context) {
    final baseQuery = FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('taskHistory')
        .withConverter<Map<String, dynamic>>(
          fromFirestore: (snap, _) => snap.data() ?? <String, dynamic>{},
          toFirestore: (data, _) => data,
        );

    return FutureBuilder<bool>(
      future: _hasCreatedAt(baseQuery),
      builder: (context, createdAtSnap) {
        final hasCreatedAt = createdAtSnap.data ?? false;

        final query = hasCreatedAt
            ? baseQuery.orderBy('createdAt', descending: true).limit(100)
            : baseQuery.limit(100);

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: query.snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Scaffold(
                appBar: AppBar(title: const Text('Task History')),
                body: Center(child: Text('Hata: ${snap.error}')),
              );
            }
            if (!snap.hasData) {
              return Scaffold(
                appBar: AppBar(title: const Text('Task History')),
                body: const Center(child: CircularProgressIndicator()),
              );
            }

            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return Scaffold(
                appBar: AppBar(title: const Text('Task History')),
                body: const Center(child: Text('Henüz tarihçe yok.')),
              );
            }

            return Scaffold(
              appBar: AppBar(title: const Text('Task History')),
              body: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final d = docs[i].data();
                  final task = (d['task'] ?? 'task').toString();
                  final room = (d['roomNumber'] ?? '?').toString();
                  final by = (d['doneByEmail'] ?? d['doneBy'] ?? '').toString();
                  final proof = d['proofUrl'] as String?;
                  final ts = d['createdAt'];
                  final timeStr = ts is Timestamp
                      ? ts.toDate().toLocal().toString().split('.').first
                      : '';

                  return ListTile(
                    leading: _ProofThumb(url: proof),
                    title: Text('$task • Room $room'),
                    subtitle: Text([by, timeStr].where((e) => e.isNotEmpty).join('  •  ')),
                    onTap: proof != null
                        ? () => showDialog(
                              context: context,
                              builder: (_) => Dialog(
                                child: InteractiveViewer(
                                  child: Image.network(
                                    proof,
                                    fit: BoxFit.contain,
                                    loadingBuilder: (c, w, p) => p == null
                                        ? w
                                        : const SizedBox(
                                            height: 240,
                                            child: Center(child: CircularProgressIndicator()),
                                          ),
                                    errorBuilder: (c, e, s) => const Padding(
                                      padding: EdgeInsets.all(24),
                                      child: Text('Görsel yüklenemedi.'),
                                    ),
                                  ),
                                ),
                              ),
                            )
                        : null,
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _hasCreatedAt(
    Query<Map<String, dynamic>> col,
  ) async {
    try {
      final one = await col.limit(1).get();
      if (one.docs.isEmpty) return false;
      final d = one.docs.first.data();
      return d.containsKey('createdAt');
    } catch (_) {
      return false;
    }
  }
}

class _ProofThumb extends StatelessWidget {
  final String? url;
  const _ProofThumb({this.url});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return const CircleAvatar(
        child: Icon(Icons.receipt_long),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        url!,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        loadingBuilder: (c, w, p) => p == null
            ? w
            : const SizedBox(
                width: 56,
                height: 56,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
        errorBuilder: (c, e, s) => const SizedBox(
          width: 56,
          height: 56,
          child: Center(child: Icon(Icons.broken_image)),
        ),
      ),
    );
    }
}