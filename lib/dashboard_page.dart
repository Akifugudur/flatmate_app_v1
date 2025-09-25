import 'dart:math' as math;

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
          return _statusScaffold('Error: ${snap.error}');
        }
        if (!snap.hasData) {
          return _statusScaffold(null);
        }
        final data = snap.data!.data();
        if (data == null) {
          return _statusScaffold('Group not found: ${widget.groupId}');
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
          roomNumbers.addAll(List.generate(13, (i) => i + 1));
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
                label: const Text('Add expense'),
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
                tooltip: 'Sign out',
                icon: const Icon(Icons.logout),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.dashboard_outlined), text: 'Overview'),
                Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Expenses'),
                Tab(icon: Icon(Icons.history), text: 'History'),
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
      _TaskConfig(key: 'trash', title: 'Trash', color: Color(0xFFFFC107)),
      _TaskConfig(key: 'kitchen', title: 'Kitchen', color: Color(0xFF42A5F5)),
      _TaskConfig(key: 'living_room', title: 'Living Room', color: Color(0xFF66BB6A)),
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
      _showSnack('This task is already assigned to you.');
      return;
    }

    if (assignment != null) {
      final assignedRoom = _assignmentToRoom(assignment, members);
      final who = assignedRoom == null ? 'someone else' : 'Room $assignedRoom';
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Take over the task'),
          content: Text('This task is currently handled by $who. Do you want to take it over?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Take over')),
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
      _showSnack('The task is now assigned to you.');
    } catch (e) {
      _showSnack('Unable to take the task: $e');
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
      _showSnack('This task is not assigned to you.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark task as done'),
        content: const Text('Do you confirm that you have completed this task?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes')),
        ],
      ),
    );
    if (confirm != true) {
      return;
    }

    final ref = FirebaseFirestore.instance.collection('groups').doc(widget.groupId);
    try {
      final orderedRooms = members
          .map((m) => m.roomNumber)
          .whereType<int>()
          .toSet()
          .toList()
        ..sort();
      if (orderedRooms.isEmpty) {
        orderedRooms.addAll(List.generate(13, (index) => index + 1));
      }
      final currentRoom = _assignmentToRoom(assignment, members);
      final nextRoom = _nextRoom(currentRoom, orderedRooms);
      final nextUid = nextRoom == null ? null : _uidForRoom(nextRoom, members);

      final Map<String, dynamic> updates = {
        'completedTasks.$taskKey': false,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (nextUid != null) {
        updates['currentTasks.$taskKey'] = nextUid;
      } else if (nextRoom != null) {
        updates['currentTasks.$taskKey'] = nextRoom;
      } else {
        updates['currentTasks.$taskKey'] = FieldValue.delete();
      }

      await ref.set(updates, SetOptions(merge: true));

      await ref.collection('taskHistory').add({
        'task': taskKey,
        'doneByUid': user.uid,
        'doneByEmail': user.email,
        'roomNumber': userRoom,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _showSnack('Great! Task marked as complete.');
    } catch (e) {
      _showSnack('Unable to mark the task as complete: $e');
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

  int? _nextRoom(int? currentRoom, List<int> orderedRooms) {
    if (orderedRooms.isEmpty) return currentRoom;
    if (currentRoom == null) {
      return orderedRooms.first;
    }
    final index = orderedRooms.indexOf(currentRoom);
    if (index == -1) {
      return orderedRooms.first;
    }
    return orderedRooms[(index + 1) % orderedRooms.length];
  }

  String? _uidForRoom(int room, List<_Member> members) {
    for (final member in members) {
      if (member.roomNumber == room) {
        return member.uid.isEmpty ? null : member.uid;
      }
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
        _TaskRotationCard(
          tasks: tasks,
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
        Text('Recent activity', style: theme.textTheme.titleMedium),
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
                Expanded(child: Text('You: $yourEmail')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.meeting_room_outlined, size: 20),
                const SizedBox(width: 8),
                Text('Your room: ${yourRoom ?? '-'}'),
              ],
            ),
            const SizedBox(height: 16),
            Text('Room distribution', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            if (occupiedRooms.isEmpty)
              const Text('No registered members yet.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: occupiedRooms
                    .map((room) => Chip(
                          label: Text('Room $room'),
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

class _TaskRotationCard extends StatelessWidget {
  const _TaskRotationCard({required this.tasks});

  final List<_TaskTileData> tasks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roomColors = <int, Color>{};
    for (final task in tasks) {
      final room = task.assignedRoom;
      if (room != null && !roomColors.containsKey(room)) {
        roomColors[room] = task.color;
      }
    }

    final assignedChips = tasks
        .where((task) => task.assignedRoom != null)
        .map(
          (task) => Chip(
            avatar: CircleAvatar(backgroundColor: task.color),
            label: Text('${task.title} • Room ${task.assignedRoom!}'),
          ),
        )
        .toList();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rotation overview',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = math.min(constraints.maxWidth, constraints.maxHeight);
                  return Center(
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: CustomPaint(
                        painter: _RotationPiePainter(roomColors: roomColors),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'The pie chart is divided into 13 rooms. Rooms with an active task are colored with that task\'s color.',
              style: theme.textTheme.bodySmall,
            ),
            if (assignedChips.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: assignedChips,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RotationPiePainter extends CustomPainter {
  _RotationPiePainter({required this.roomColors});

  final Map<int, Color> roomColors;

  static const int _segmentCount = 13;
  static const Color _defaultColor = Color(0xFFE0E0E0);
  static const Color _borderColor = Colors.white;
  static const Color _textColor = Colors.black87;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweepAngle = (2 * math.pi) / _segmentCount;
    final fillPaint = Paint()..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = _borderColor;

    for (int i = 0; i < _segmentCount; i++) {
      final startAngle = -math.pi / 2 + (sweepAngle * i);
      final roomNumber = i + 1;
      fillPaint.color = roomColors[roomNumber] ?? _defaultColor;
      canvas.drawArc(rect, startAngle, sweepAngle, true, fillPaint);
      canvas.drawArc(rect, startAngle, sweepAngle, true, borderPaint);

      final angle = startAngle + sweepAngle / 2;
      final labelRadius = radius * 0.65;
      final labelOffset = center + Offset(math.cos(angle), math.sin(angle)) * labelRadius;
      final textPainter = TextPainter(
        text: TextSpan(
          text: '$roomNumber',
          style: TextStyle(
            color: _textColor,
            fontWeight: FontWeight.w600,
            fontSize: radius * 0.16,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final textOffset = labelOffset - Offset(textPainter.width / 2, textPainter.height / 2);
      textPainter.paint(canvas, textOffset);
    }
  }

  @override
  bool shouldRepaint(covariant _RotationPiePainter oldDelegate) {
    if (identical(this, oldDelegate)) return false;
    if (roomColors.length != oldDelegate.roomColors.length) return true;
    for (final entry in roomColors.entries) {
      if (oldDelegate.roomColors[entry.key] != entry.value) {
        return true;
      }
    }
    return false;
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
        data.assignedRoom == null ? 'Unassigned' : 'Room ${data.assignedRoom}';

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
            Text('Assigned to: $assignedText'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: data.takenByAnother && !data.assignedToYou ? null : onTake,
                    child: const Text('Take task'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: data.assignedToYou ? onDone : null,
                    child: const Text('Mark done'),
                  ),
                ),
              ],
            ),
            if (data.assignedToYou)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'You are currently responsible for this task.',
                  style: theme.textTheme.bodySmall?.copyWith(color: data.color),
                ),
              )
            else if (data.takenByAnother)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'This task is currently assigned to another room.',
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
            return _CardMessage('Unable to load history: ${snap.error}');
          }
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const _CardMessage('There are no task records yet.');
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
                title: Text(task.isEmpty ? 'Task' : task),
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
