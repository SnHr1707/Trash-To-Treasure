import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider;
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:firebase_ui_oauth_google/firebase_ui_oauth_google.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // NEW
import 'firebase_options.dart';
import 'household_screen.dart';
import 'collector_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  // Load Environment variables
  await dotenv.load(fileName: ".env");

  FirebaseUIAuth.configureProviders([
    EmailAuthProvider(),
    GoogleProvider(clientId: dotenv.env['GOOGLE_CLIENT_ID'] ?? ""), 
  ]);

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true, 
        colorSchemeSeed: Colors.green,
        inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white),
      ),
      home: AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return SignInScreen(
            providers: [EmailAuthProvider(), GoogleProvider(clientId: dotenv.env['GOOGLE_CLIENT_ID'] ?? "")],
            headerBuilder: (context, constraints, _) => 
              Padding(padding: EdgeInsets.all(20), child: Icon(Icons.recycling, size: 80, color: Colors.green)),
          );
        }
        return RoleCheck(user: snapshot.data!);
      },
    );
  }
}

class RoleCheck extends StatefulWidget {
  final User user;
  RoleCheck({required this.user});
  @override
  _RoleCheckState createState() => _RoleCheckState();
}

class _RoleCheckState extends State<RoleCheck> {
  String? role;

  @override
  void initState() {
    super.initState();
    _checkRole();
  }

  Future<void> _checkRole() async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).get();
    if (doc.exists) {
      setState(() => role = doc['role']);
    } else {
      setState(() => role = 'new');
    }
  }

  Future<void> _setRole(String newRole) async {
    await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).set({
      'email': widget.user.email,
      'role': newRole,
    }, SetOptions(merge: true));
    setState(() => role = newRole);
  }

  @override
  Widget build(BuildContext context) {
    if (role == null) return Scaffold(body: Center(child: CircularProgressIndicator()));
    
    if (role == 'new') {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.eco, size: 80, color: Colors.green),
              SizedBox(height: 20),
              Text("Select Your Role", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              SizedBox(height: 30),
              ElevatedButton.icon(
                icon: Icon(Icons.home, size: 30),
                label: Text("I am a Household (Seller)"),
                style: ElevatedButton.styleFrom(padding: EdgeInsets.all(20)),
                onPressed: () => _setRole('household'),
              ),
              SizedBox(height: 20),
              ElevatedButton.icon(
                icon: Icon(Icons.local_shipping, size: 30),
                label: Text("I am a Collector (Buyer)"),
                style: ElevatedButton.styleFrom(padding: EdgeInsets.all(20)),
                onPressed: () => _setRole('collector'),
              ),
            ],
          ),
        ),
      );
    }

    if (role == 'household') return HouseholdScreen();
    return CollectorScreen();
  }
}