import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'expenses_page.dart';
import 'history_page.dart';

class DashboardPage extends StatefulWidget {
  final String groupId;
  const DashboardPage({super.key, this.groupId = 'building8_flat3'});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  late final TabController _tabController;
  final _expensesKey = GlobalKey<ExpensesPageState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);
  }

  void _handleTabChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final docRef = FirebaseFirestore.instance.collection('groups').doc(widget.groupId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: docRef.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _statusScaffold('Hata: ${snap.error}');
        }
        if (!snap.hasData) {
          return _statusScaffold(null);
        }
        final data = snap.data!.data();
        if (data == null) {
          return _statusScaffold('Grup bulunamadı: ${widget.groupId}');
        }

        final members = _parseMembers(data['members']);
        final currentTasks = Map<String, dynamic>.from(data['currentTasks'] ?? {});
        final user = _auth.currentUser;
        final userRoom = _roomForUid(user?.uid, members);

        final tasks = _buildTasks(currentTasks, members);

        final roomNumbers = members
            .map((m) => m.roomNumber)
            .whereType<int>()
            .toSet()
            .toList()
          ..sort();
        if (roomNumbers.isEmpty) {
          roomNumbers.addAll(List.generate(10, (i) => i + 1));
        }

        final overviewTab = _OverviewTab(
          groupName: data['name'] as String? ?? 'FlatMate',
          members: members,
          yourEmail: user?.email ?? user?.uid ?? '-',
          yourRoom: userRoom,
          tasks: tasks,
          historyStream: docRef
              .collection('taskHistory')
              .orderBy('createdAt', descending: true)
              .limit(20)
              .snapshots(),
        );

        final expensesTab = ExpensesPage(
          key: _expensesKey,
          groupId: widget.groupId,
          roomNumbers: roomNumbers,
          embedded: true,
        );

        final historyTab = TaskHistoryPage(
          groupId: widget.groupId,
          embedded: true,
        );

        final fab = _tabController.index == 1
            ? FloatingActionButton.extended(
                onPressed: () => _expensesKey.currentState?.openAddExpenseSheet(),
                icon: const Icon(Icons.add),
                label: const Text('Harcama ekle'),
              )
            : null;

        final groupName = data['name'] as String? ?? 'FlatMate';

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Image.asset('assets/loogo.png', height: 34),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    groupName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                onPressed: _signOut,
                tooltip: 'Çıkış yap',
                icon: const Icon(Icons.logout),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.dashboard_outlined), text: 'Genel'),
                Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Giderler'),
                Tab(icon: Icon(Icons.history), text: 'Tarihçe'),
              ],
            ),
          ),
          floatingActionButton: fab,
          body: TabBarView(
            controller: _tabController,
            children: [
              overviewTab,
              expensesTab,
              historyTab,
            ],
          ),
        );
      },
    );
  }

  List<_TaskTileData> _buildTasks(
    Map<String, dynamic> currentTasks,
    List<_Member> members,
  ) {
    final configs = const [
      _TaskConfig(key: 'trash', title: 'Çöp', color: Color(0xFFFFC107)),
      _TaskConfig(key: 'kitchen', title: 'Mutfak', color: Color(0xFF42A5F5)),
      _TaskConfig(key: 'living_room', title: 'Salon', color: Color(0xFF66BB6A)),
    ];

    final user = _auth.currentUser;
    final userRoom = _roomForUid(user?.uid, members);

    return configs.map((config) {
      final assignment = currentTasks[config.key];
      final assignedRoom = _assignmentToRoom(assignment, members);
      final assignedToYou = _isAssignmentForUser(assignment, user, userRoom);
      final takenBySomeoneElse = assignment != null && !assignedToYou;

      return _TaskTileData(
        key: config.key,
        title: config.title,
        color: config.color,
        assignedRoom: assignedRoom,
        assignedToYou: assignedToYou,
        takenByAnother: takenBySomeoneElse,
        takeTask: () => _takeTask(
          taskKey: config.key,
          currentTasks: currentTasks,
          members: members,
        ),
        completeTask: () => _markDone(
          taskKey: config.key,
          currentTasks: currentTasks,
          members: members,
        ),
      );
    }).toList();
  }

  Future<void> _takeTask({
    required String taskKey,
    required Map<String, dynamic> currentTasks,
    required List<_Member> members,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final assignment = currentTasks[taskKey];
    final userRoom = _roomForUid(user.uid, members);
    final alreadyYours = _isAssignmentForUser(assignment, user, userRoom);
    if (alreadyYours) {
      _showSnack('Görev zaten sende.');
      return;
    }

    if (assignment != null) {
      final assignedRoom = _assignmentToRoom(assignment, members);
      final who = assignedRoom == null ? 'başkası' : 'Oda $assignedRoom';
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Görevi devral'),
          content: Text('Görev şu anda $who tarafından üstlenilmiş. Devralmak istiyor musun?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Devral')),
          ],
        ),
      );
      if (confirm != true) {
        return;
      }
    }

    final ref = FirebaseFirestore.instance.collection('groups').doc(widget.groupId);
    try {
      await ref.set({
        'currentTasks.$taskKey': user.uid,
        'completedTasks.$taskKey': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _showSnack('Görev sana atandı.');
    } catch (e) {
      _showSnack('Görev alınamadı: $e');
    }
  }

  Future<void> _markDone({
    required String taskKey,
    required Map<String, dynamic> currentTasks,
    required List<_Member> members,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final assignment = currentTasks[taskKey];
    final userRoom = _roomForUid(user.uid, members);
    final assignedToYou = _isAssignmentForUser(assignment, user, userRoom);
    if (!assignedToYou) {
      _showSnack('Görev senin üzerinde değil.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Görev tamamlandı mı?'),
        content: const Text('Bu görevi tamamladığını onaylıyor musun?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hayır')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Evet')),
        ],
      ),
    );
    if (confirm != true) {
      return;
    }

    final ref = FirebaseFirestore.instance.collection('groups').doc(widget.groupId);
    try {
      await ref.set({
        'completedTasks.$taskKey': true,
        'currentTasks.$taskKey': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await ref.collection('taskHistory').add({
        'task': taskKey,
        'doneByUid': user.uid,
        'doneByEmail': user.email,
        'roomNumber': userRoom,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _showSnack('Harika! Görev tamamlandı.');
    } catch (e) {
      _showSnack('Görev işaretlenemedi: $e');
    }
  }

  void _signOut() {
    _auth.signOut();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  int? _roomForUid(String? uid, List<_Member> members) {
    if (uid == null) return null;
    for (final member in members) {
      if (member.uid == uid) {
        return member.roomNumber;
      }
    }
    return null;
  }

  int? _assignmentToRoom(dynamic assignment, List<_Member> members) {
    if (assignment == null) return null;
    if (assignment is num) return assignment.toInt();
    if (assignment is String) {
      return _roomForUid(assignment, members);
    }
    return null;
  }

  bool _isAssignmentForUser(dynamic assignment, User? user, int? userRoom) {
    if (assignment == null || user == null) return false;
    if (assignment == user.uid) return true;
    if (assignment is num && userRoom != null) {
      return assignment.toInt() == userRoom;
    }
    if (assignment is String) {
      return assignment == user.uid;
    }
    return false;
  }

  List<_Member> _parseMembers(dynamic raw) {
    if (raw is! List) return const [];
    final result = <_Member>[];
    for (final item in raw) {
      if (item is Map) {
        final map = Map<String, dynamic>.from(item as Map);
        result.add(
          _Member(
            uid: map['uid'] as String? ?? '',
            roomNumber: (map['roomNumber'] as num?)?.toInt(),
          ),
        );
      }
    }
    return result;
  }

  Widget _statusScaffold(String? message) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/loogo.png', height: 34),
            const SizedBox(width: 12),
            const Text('FlatMate'),
          ],
        ),
      ),
      body: message == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(message, textAlign: TextAlign.center),
              ),
            ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.groupName,
    required this.members,
    required this.yourEmail,
    required this.yourRoom,
    required this.tasks,
    required this.historyStream,
  });

  final String groupName;
  final List<_Member> members;
  final String yourEmail;
  final int? yourRoom;
  final List<_TaskTileData> tasks;
  final Stream<QuerySnapshot<Map<String, dynamic>>> historyStream;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final occupiedRooms = members
        .map((m) => m.roomNumber)
        .whereType<int>()
        .toList()
      ..sort();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _SummaryCard(
          groupName: groupName,
          yourEmail: yourEmail,
          yourRoom: yourRoom,
          occupiedRooms: occupiedRooms,
        ),
        const SizedBox(height: 20),
        for (final task in tasks) ...[
          _TaskCard(
            data: task,
            onTake: task.takeTask,
            onDone: task.completeTask,
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 8),
        Text('Son aktiviteler', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _RecentActivityList(stream: historyStream),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.groupName,
    required this.yourEmail,
    required this.yourRoom,
    required this.occupiedRooms,
  });

  final String groupName;
  final String yourEmail;
  final int? yourRoom;
  final List<int> occupiedRooms;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              groupName,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.person_pin_circle_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('Sen: $yourEmail')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.meeting_room_outlined, size: 20),
                const SizedBox(width: 8),
                Text('Odan: ${yourRoom ?? '-'}'),
              ],
            ),
            const SizedBox(height: 16),
            Text('Oda dağılımı', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            if (occupiedRooms.isEmpty)
              const Text('Henüz kayıtlı üye yok.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: occupiedRooms
                    .map((room) => Chip(
                          label: Text('Oda $room'),
                          avatar: const Icon(Icons.bed_outlined, size: 18),
                        ))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.data,
    required this.onTake,
    required this.onDone,
  });

  final _TaskTileData data;
  final VoidCallback onTake;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assignedText =
        data.assignedRoom == null ? 'Henüz atanmamış' : 'Oda ${data.assignedRoom}';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      color: data.color.withOpacity(0.08),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  data.title,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: data.color, shape: BoxShape.circle),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Atanan: $assignedText'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: data.takenByAnother && !data.assignedToYou ? null : onTake,
                    child: const Text('Görevi al'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: data.assignedToYou ? onDone : null,
                    child: const Text('Tamamlandı'),
                  ),
                ),
              ],
            ),
            if (data.assignedToYou)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Bu görev senin sorumluluğunda.',
                  style: theme.textTheme.bodySmall?.copyWith(color: data.color),
                ),
              )
            else if (data.takenByAnother)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Görev şu anda başka bir odada.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RecentActivityList extends StatelessWidget {
  const _RecentActivityList({required this.stream});

  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 0,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return _CardMessage('Tarihçe yüklenemedi: ${snap.error}');
          }
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const _CardMessage('Henüz görev kaydı yok.');
          }

          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final m = docs[index].data();
              final task = (m['task'] ?? '').toString();
              final room = (m['roomNumber'] ?? '').toString();
              final email = (m['doneByEmail'] ?? '').toString();
              final ts = m['createdAt'];
              String timeLabel = '';
              if (ts is Timestamp) {
                timeLabel = ts.toDate().toLocal().toString().split('.').first;
              }
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    room == 'null' || room.isEmpty ? '?' : room,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                title: Text(task.isEmpty ? 'Görev' : task),
                subtitle: Text([
                  if (email.isNotEmpty) email,
                  if (timeLabel.isNotEmpty) timeLabel,
                ].join(' • ')),
              );
            },
          );
        },
      ),
    );
  }
}

class _CardMessage extends StatelessWidget {
  const _CardMessage(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _TaskTileData {
  const _TaskTileData({
    required this.key,
    required this.title,
    required this.color,
    required this.assignedRoom,
    required this.assignedToYou,
    required this.takenByAnother,
    required this.takeTask,
    required this.completeTask,
  });

  final String key;
  final String title;
  final Color color;
  final int? assignedRoom;
  final bool assignedToYou;
  final bool takenByAnother;
  final VoidCallback takeTask;
  final VoidCallback completeTask;
}

class _TaskConfig {
  const _TaskConfig({required this.key, required this.title, required this.color});

  final String key;
  final String title;
  final Color color;
}

class _Member {
  const _Member({required this.uid, required this.roomNumber});

  final String uid;
  final int? roomNumber;
}
