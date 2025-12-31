import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'ai_scanner.dart';
import 'map_screen.dart';

class HomeScreen extends StatelessWidget {
  final user = FirebaseAuth.instance.currentUser;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green[50],
      appBar: AppBar(
        title: Text("Eco Dashboard"),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          )
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Section
            Text(
              "Hello, ${user?.displayName ?? 'Hero'}! 🌱",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ).animate().fade().slideX(),
            
            Text("Ready to save the planet today?",
                style: TextStyle(color: Colors.grey[700])),
            
            SizedBox(height: 30),

            // Gamified Cards
            _buildGameCard(
              context,
              title: "Scan Waste",
              subtitle: "Identify items & check value",
              icon: Icons.camera_alt,
              color: Colors.blueAccent,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AIScannerPage())),
            ).animate().fade(delay: 300.ms).slideY(),

            SizedBox(height: 15),

            _buildGameCard(
              context,
              title: "Find Collectors",
              subtitle: "Request pickup nearby",
              icon: Icons.map,
              color: Colors.orangeAccent,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MapScreen())),
            ).animate().fade(delay: 600.ms).slideY(),
            
            SizedBox(height: 15),
            
             _buildGameCard(
              context,
              title: "My Earnings",
              subtitle: "You earned \$12.50 this week!",
              icon: Icons.savings,
              color: Colors.green,
              onTap: () {}, // Feature coming soon
            ).animate().fade(delay: 900.ms).slideY(),
          ],
        ),
      ),
    );
  }

  Widget _buildGameCard(BuildContext context, 
      {required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 10,
              offset: Offset(0, 5),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 30),
            ),
            SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(subtitle, style: TextStyle(color: Colors.grey)),
              ],
            ),
            Spacer(),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}