import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'login_page.dart';
import 'dashboard_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const FlatMateApp());
}

class FlatMateApp extends StatelessWidget {
  const FlatMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlatMate',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      debugShowCheckedModeBanner: false,
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snap.data != null) {
            return const DashboardPage();   
          }
          return const LoginPage();         
        },
      ),
    );
  }
}
