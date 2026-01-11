import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider;
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:firebase_ui_oauth_google/firebase_ui_oauth_google.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'firebase_options.dart';
import 'household_screen.dart';
import 'collector_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  try {
    await dotenv.load(fileName: ".env");
  } catch(e) {
    print("Warning: .env not found (expected in production).");
  }

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
      title: 'EcoMarket',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto', 
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF009688), // Teal 500
          primary: const Color(0xFF009688),
          secondary: const Color(0xFFFF9800), // Orange
          tertiary: const Color(0xFF2196F3), // Blue
          surface: const Color(0xFFFAFAFA),
          background: const Color(0xFFF0F4F4),
        ),
        scaffoldBackgroundColor: const Color(0xFFF0F4F4),
        appBarTheme: AppBarTheme(
          elevation: 0,
          centerTitle: true,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        // Fixed Input Styling
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.grey.shade300)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Color(0xFF009688), width: 2)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.red, width: 1)),
          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          labelStyle: TextStyle(color: Colors.grey[700]),
        ),
        // Fixed Button Styling
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            elevation: 4,
            shadowColor: Colors.teal.withOpacity(0.4),
          ),
        ),
        // Removed 'cardTheme' block to fix the "CardThemeData" error.
        // The app will now use the default Material 3 card styles, which are compatible with all versions.
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
          // KEYBOARD FIX: Wrapped in Scaffold + SingleChildScrollView
          return Scaffold(
            resizeToAvoidBottomInset: true,
            body: Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.recycling_rounded, size: 100, color: Color(0xFF009688)),
                      SizedBox(height: 20),
                      Text("EcoMarket", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF004D40))),
                      SizedBox(height: 40),
                      Container(
                        height: 400, 
                        child: SignInScreen(
                          providers: [EmailAuthProvider(), GoogleProvider(clientId: dotenv.env['GOOGLE_CLIENT_ID'] ?? "")],
                          showAuthActionSwitch: false, 
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).get();
      if (doc.exists) {
        if (mounted) setState(() => role = doc['role']);
      } else {
        if (mounted) setState(() => role = 'new');
      }
    } catch(e) {
      print("Error checking role: $e");
    }
  }

  Future<void> _setRole(String newRole) async {
    await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).set({
      'email': widget.user.email,
      'role': newRole,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (mounted) setState(() => role = newRole);
  }

  @override
  Widget build(BuildContext context) {
    if (role == null) return Scaffold(body: Center(child: CircularProgressIndicator()));

    if (role == 'new') {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE0F2F1), Colors.white])
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.public, size: 100, color: Color(0xFF009688)),
                SizedBox(height: 30),
                Text("Welcome to EcoMarket", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF004D40))),
                Text("Turn your waste into wealth.", style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                SizedBox(height: 50),
                _buildRoleButton(Icons.home_work_outlined, "Household", "I want to sell waste", () => _setRole('household'), Colors.teal),
                SizedBox(height: 20),
                _buildRoleButton(Icons.local_shipping_outlined, "Collector", "I want to buy waste", () => _setRole('collector'), Colors.orange),
              ],
            ),
          ),
        ),
      );
    }

    if (role == 'household') return HouseholdScreen();
    return CollectorScreen();
  }

  Widget _buildRoleButton(IconData icon, String title, String subtitle, VoidCallback onTap, Color color) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3), width: 2),
          boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 15, offset: Offset(0, 5))],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 30),
            ),
            SizedBox(width: 20),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
              Text(subtitle, style: TextStyle(color: Colors.grey[600])),
            ]),
            Spacer(),
            Icon(Icons.arrow_forward_ios, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}