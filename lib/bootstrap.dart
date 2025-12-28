// lib/services/bootstrap.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> bootstrapGroup({
  required String groupId,
  String groupName = "FlatMate Group",
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) throw Exception("Not signed in");

  final groupRef = FirebaseFirestore.instance.collection('groups').doc(groupId);

  // 1) Create or merge the group without reading it.
  await groupRef.set({
    'name': groupName,
    'createdBy': uid,
    'createdAt': FieldValue.serverTimestamp(),
    'rotationStart': {'trash': 1, 'living_room': 5, 'kitchen': 10},
  }, SetOptions(merge: true)); // <-- no read, write directly

  // 2) Add yourself as a member (allowed by the write rules).
  final memberRef = groupRef.collection('members').doc(uid);
  await memberRef.set({
    'roomNumber': 1,
    'role': 'admin',
    'joinedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  // 3) You are now a member -> create tasks.
  final tasksRef = groupRef.collection('tasks');

  // Write each doc with merge (no overwrite if present, creates if missing).
  await tasksRef.doc('trash').set({
    'name': 'trash',
    'assignedRoomNumber': 1,
    'lastCompletedAt': null,
  }, SetOptions(merge: true));

  await tasksRef.doc('living_room').set({
    'name': 'living_room',
    'assignedRoomNumber': 5,
    'lastCompletedAt': null,
  }, SetOptions(merge: true));

  await tasksRef.doc('kitchen').set({
    'name': 'kitchen',
    'assignedRoomNumber': 10,
    'lastCompletedAt': null,
  }, SetOptions(merge: true));
}
