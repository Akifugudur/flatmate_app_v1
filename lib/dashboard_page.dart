import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pie_chart/pie_chart.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({Key? key}) : super(key: key);

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final user = FirebaseAuth.instance.currentUser;
  Map<String, dynamic>? groupData;
  List<Map<String, dynamic>> members = [];
  String groupID = "building8_flat3";
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchGroupData();
  }

  Future<void> fetchGroupData() async {
    final doc = await FirebaseFirestore.instance.collection('groups').doc(groupID).get();
    final data = doc.data();
    if (data != null) {
      setState(() {
        groupData = data;
        members = List<Map<String, dynamic>>.from(data['members']);
        isLoading = false;
      });
    }
  }

  Future<void> completeTask(String taskName) async {
    if (groupData == null) return;

    final currentUid = groupData!['currentTasks'][taskName];
    final currentIndex = members.indexWhere((m) => m['uid'] == currentUid);
    final nextIndex = (currentIndex + 1) % members.length;
    final nextUid = members[nextIndex]['uid'];

    await FirebaseFirestore.instance.collection('groups').doc(groupID).update({
      'currentTasks.$taskName': nextUid,
      'taskRotation.$taskName': nextIndex,
      'completedTasks.$taskName': false
    });

    setState(() {
      groupData!['currentTasks'][taskName] = nextUid;
      groupData!['taskRotation'][taskName] = nextIndex;
      groupData!['completedTasks'][taskName] = false;
    });
  }

  Map<String, double> generateChartData() {
    Map<String, double> dataMap = {};
    for (var member in members) {
      final name = "Room ${member['roomNumber']}";
      dataMap[name] = 1;
    }
    return dataMap;
  }

  Map<String, Color> generateColorMap() {
    Map<String, Color> colorMap = {};
    for (var member in members) {
      final name = "Room ${member['roomNumber']}";
      if (groupData != null &&
          groupData!['currentTasks'].containsValue(member['uid'])) {
        if (groupData!['currentTasks']['trash'] == member['uid']) {
          colorMap[name] = Colors.yellow;
        } else if (groupData!['currentTasks']['kitchen'] == member['uid']) {
          colorMap[name] = Colors.blue;
        } else if (groupData!['currentTasks']['living_room'] == member['uid']) {
          colorMap[name] = Colors.green;
        }
      } else {
        colorMap[name] = Colors.grey[300]!;
      }
    }
    return colorMap;
  }

  Widget buildTaskCard(String task, Color color) {
    final assignedUid = groupData?['currentTasks'][task];
    final isMe = assignedUid == user?.uid;
    final room = members.firstWhere((m) => m['uid'] == assignedUid, orElse: () => {})['roomNumber'];
    final label = room != null ? "Room $room" : "Unknown";

    return Card(
      color: color.withOpacity(0.2),
      child: ListTile(
        title: Text("$task → $label"),
        trailing: isMe
            ? ElevatedButton(
                onPressed: () => completeTask(task),
                child: const Text("Mark Done"),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Dashboard")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            PieChart(
              dataMap: generateChartData(),
              colorList: generateColorMap().values.toList(),
              chartRadius: MediaQuery.of(context).size.width / 1.5,
              chartType: ChartType.disc,
              chartLegendSpacing: 32,
              legendOptions: const LegendOptions(
                showLegendsInRow: false,
                legendPosition: LegendPosition.bottom,
              ),
              chartValuesOptions: const ChartValuesOptions(
                showChartValues: false,
              ),
            ),
            const SizedBox(height: 24),
            buildTaskCard("trash", Colors.yellow),
            buildTaskCard("kitchen", Colors.blue),
            buildTaskCard("living_room", Colors.green),
          ],
        ),
      ),
    );
  }
}
