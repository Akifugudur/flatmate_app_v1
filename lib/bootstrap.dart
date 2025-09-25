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

  // 1) GRUBU OKUMADAN OLUŞTUR / MERGE ET
  await groupRef.set({
    'name': groupName,
    'createdBy': uid,
    'createdAt': FieldValue.serverTimestamp(),
    'rotationStart': {'trash': 1, 'living_room': 5, 'kitchen': 10},
  }, SetOptions(merge: true)); // <-- okuma yok, direkt yaz

  // 2) KENDİNİ ÜYE OLARAK EKLE (bu yazma kurallara göre serbest)
  final memberRef = groupRef.collection('members').doc(uid);
  await memberRef.set({
    'roomNumber': 1,
    'role': 'admin',
    'joinedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  // 3) ARTIK ÜYESİN → TASKS OLUŞTUR
  final tasksRef = groupRef.collection('tasks');

  // tek tek merge ile yaz (varsa üstüne yazmaz, yoksa oluşturur)
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
