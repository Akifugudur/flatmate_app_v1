import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pie_chart/pie_chart.dart';

class DashboardPage extends StatefulWidget {
  final String groupId; // Örn: "building8_flat3"
  const DashboardPage({super.key, this.groupId = 'building8_flat3'});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _auth = FirebaseAuth.instance;

  // UI renkleri
  static const _trashColor = Color(0xFFFFC107);       // sarı
  static const _kitchenColor = Color(0xFF42A5F5);     // mavi
  static const _livingColor = Color(0xFF66BB6A);      // yeşil
  static final _idleGrey = Colors.grey.shade300;

  // 1..13 odalar
  final List<int> rooms = List<int>.generate(13, (i) => i + 1);

  // PieChart için sabit data (13 dilim, her biri 1)
  late final Map<String, double> _dataMap = {
    for (final r in rooms) 'Room $r': 1.0,
  };

  @override
  Widget build(BuildContext context) {
    final docRef =
        FirebaseFirestore.instance.collection('groups').doc(widget.groupId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: docRef.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _scaffold(body: _centerText('Hata: ${snap.error}'));
        }
        if (!snap.hasData) {
          return _scaffold(body: const Center(child: CircularProgressIndicator()));
        }
        final data = snap.data!.data();
        if (data == null) {
          return _scaffold(body: _centerText('Grup bulunamadı: ${widget.groupId}'));
        }

        // members: [{uid, roomNumber}, ...]
        final members = List<Map<String, dynamic>>.from(
          (data['members'] ?? []) as List,
        );

        // currentTasks: {trash: (uid|room), kitchen: (uid|room), living_room: (uid|room)}
        final Map<String, dynamic> currentTasks =
            Map<String, dynamic>.from(data['currentTasks'] ?? {});

        // yardımcı: uid -> oda
        int? roomOfUid(String? uid) {
          if (uid == null) return null;
          final ix = members.indexWhere((m) => m['uid'] == uid);
          if (ix == -1) return null;
          final rn = (members[ix]['roomNumber'] as num?)?.toInt();
          return rn;
        }

        // her görev için atanmış oda
        int? roomForTask(String taskKey) {
          final v = currentTasks[taskKey];
          if (v == null) return null;
          if (v is num) return v.toInt();
          if (v is String) return roomOfUid(v);
          return null;
        }

        final trashRoom = roomForTask('trash');
        final kitchenRoom = roomForTask('kitchen');
        final livingRoom = roomForTask('living_room');

        // PieChart renk listesi (13 dilim sırayla Room1..Room13)
        final List<Color> colorList = rooms.map((r) {
          if (r == trashRoom) return _trashColor;
          if (r == kitchenRoom) return _kitchenColor;
          if (r == livingRoom) return _livingColor;
          return _idleGrey;
        }).toList();

        return _scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Grafik
                PieChart(
                  dataMap: _dataMap,
                  chartType: ChartType.disc,
                  colorList: colorList,
                  chartLegendSpacing: 28,
                  chartRadius: MediaQuery.of(context).size.width * 0.6,
                  legendOptions: const LegendOptions(
                    showLegends: false, // kendi legend'ımızı çiziyoruz
                  ),
                  chartValuesOptions: const ChartValuesOptions(
                    showChartValues: false,
                  ),
                ),
                const SizedBox(height: 8),
                _legendRow(trashRoom, kitchenRoom, livingRoom),

                const SizedBox(height: 20),

                // Görev kartları
                _taskCard(
                  title: 'trash',
                  color: _trashColor,
                  assignedRoom: trashRoom,
                  onTake: () => _takeTask('trash'),
                  onDone: () => _markDone('trash'),
                ),
                _taskCard(
                  title: 'kitchen',
                  color: _kitchenColor,
                  assignedRoom: kitchenRoom,
                  onTake: () => _takeTask('kitchen'),
                  onDone: () => _markDone('kitchen'),
                ),
                _taskCard(
                  title: 'living_room',
                  color: _livingColor,
                  assignedRoom: livingRoom,
                  onTake: () => _takeTask('living_room'),
                  onDone: () => _markDone('living_room'),
                ),

                const SizedBox(height: 12),

                // Kim olduğunu göster
                Center(
                  child: Text(
                    'You: ${_auth.currentUser?.email ?? _auth.currentUser?.uid ?? '-'}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------- Firestore helpers ----------

  Future<void> _takeTask(String taskKey) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final ref =
        FirebaseFirestore.instance.collection('groups').doc(widget.groupId);
    await ref.update({
      'currentTasks.$taskKey': user.uid,
      'completedTasks.$taskKey': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _markDone(String taskKey) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final ref =
        FirebaseFirestore.instance.collection('groups').doc(widget.groupId);

    // Basit "done" işareti + tarihçe girişi (proof fotoğrafını sonra ekliyoruz)
    await ref.update({
      'completedTasks.$taskKey': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await ref.collection('taskHistory').add({
      'task': taskKey,
      'doneByUid': user.uid,
      'doneByEmail': user.email,
      'createdAt': FieldValue.serverTimestamp(),
      // 'proofUrl': ...  (fotoğraf akışını sonra ekleyeceğiz)
    });
  }

  // ---------- UI bits ----------

  Widget _taskCard({
    required String title,
    required Color color,
    required int? assignedRoom,
    required VoidCallback onTake,
    required VoidCallback onDone,
  }) {
    final youText = assignedRoom == null ? 'Unknown' : 'Room $assignedRoom';
    final isAssignedToYou = false; // atama uid bazlı kontrol istiyorsan genişlet
    return Card(
      elevation: 0,
      color: color.withOpacity(0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        title: Text('$title → $youText',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: onTake,
              child: const Text('Take task'),
            ),
            FilledButton(
              onPressed: onDone,
              child: const Text('Mark as done'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendRow(int? trashRoom, int? kitchenRoom, int? livingRoom) {
    Widget chip(Color c, String label) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: c.withOpacity(0.2),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.withOpacity(0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        );

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: [
        chip(_trashColor, 'trash: ${trashRoom ?? '-'}'),
        chip(_kitchenColor, 'kitchen: ${kitchenRoom ?? '-'}'),
        chip(_livingColor, 'living: ${livingRoom ?? '-'}'),
      ],
    );
  }

  Scaffold _scaffold({required Widget body}) {
    return Scaffold(
      // Sol üstte büyük logo
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 12,
        centerTitle: false,
        title: Image.asset('assets/loogo.png', height: 36),
      ),
      body: body,
    );
  }

  Widget _centerText(String s) =>
      Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(s)));
}
