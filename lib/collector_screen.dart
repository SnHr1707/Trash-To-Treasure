import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';

class CollectorScreen extends StatefulWidget {
  @override
  _CollectorScreenState createState() => _CollectorScreenState();
}

class _CollectorScreenState extends State<CollectorScreen> {
  int _selectedIndex = 0;
  final List<Widget> _pages = [AvailableJobsTab(), ActiveJobsTab(), CollectorProfileTab()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: [
          NavigationDestination(selectedIcon: Icon(Icons.search, color: Colors.white), icon: Icon(Icons.search_outlined), label: 'Market'),
          NavigationDestination(selectedIcon: Icon(Icons.local_shipping, color: Colors.white), icon: Icon(Icons.local_shipping_outlined), label: 'Active'),
          NavigationDestination(selectedIcon: Icon(Icons.person, color: Colors.white), icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
        indicatorColor: Colors.teal,
        backgroundColor: Colors.white,
        elevation: 10,
        surfaceTintColor: Colors.teal[50],
      ),
    );
  }
}

// ---------------- TAB 1: FIND JOBS (Market) ---------------- //
class AvailableJobsTab extends StatefulWidget {
  @override
  _AvailableJobsTabState createState() => _AvailableJobsTabState();
}

class _AvailableJobsTabState extends State<AvailableJobsTab> {
  Position? _myPosition;
  @override
  void initState() { super.initState(); _getLocation(); }

  Future<void> _getLocation() async {
    try {
      Position p = await Geolocator.getCurrentPosition();
      if(mounted) setState(() => _myPosition = p);
    } catch(e){}
  }

  String _getDistance(double lat, double long) {
    if(_myPosition == null) return "...";
    return "${(Geolocator.distanceBetween(_myPosition!.latitude, _myPosition!.longitude, lat, long)/1000).toStringAsFixed(1)} km";
  }

  Future<void> _handleJob(String docId, String action, {String? offerPrice}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return; 
    String name = user.displayName ?? "Collector";
    String phone = "Not Provided";
    try {
      var doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) { name = doc['name'] ?? name; phone = doc['phone'] ?? phone; }
    } catch(e) {}
    Map<String, dynamic> updateData = { 'collectorId': user.uid, 'collectorName': name, 'collectorPhone': phone };
    if (action == 'accept') updateData['status'] = 'accepted';
    else if (action == 'offer') { updateData['status'] = 'negotiating'; updateData['offeredPrice'] = offerPrice; }
    await FirebaseFirestore.instance.collection('requests').doc(docId).update(updateData);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(action == 'accept' ? "Job Accepted!" : "Offer Sent!")));
  }

  void _showOfferDialog(BuildContext context, String docId, String currentPrice) {
    TextEditingController offerController = TextEditingController();
    showDialog(context: context, builder: (context) => AlertDialog(
      title: Text("Negotiate Price"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [Text("Current Ask: ₹$currentPrice"), SizedBox(height: 10), TextField(controller: offerController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: "Your Offer (₹)", border: OutlineInputBorder()))]),
      actions: [TextButton(child: Text("CANCEL"), onPressed: () => Navigator.pop(context)), ElevatedButton(child: Text("SEND OFFER"), onPressed: () { if (offerController.text.isNotEmpty) { _handleJob(docId, 'offer', offerPrice: offerController.text); Navigator.pop(context); } })],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Marketplace"), flexibleSpace: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.teal, Colors.teal.shade700])))),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('requests').where('status', isEqualTo: 'pending').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
          if (snapshot.data!.docs.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.storefront, size: 60, color: Colors.grey), Text("No jobs available nearby.", style: TextStyle(color: Colors.grey))]));

          return ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var doc = snapshot.data!.docs[index];
              var data = doc.data() as Map<String, dynamic>;
              String price = data['askPrice'] ?? "N/A";
              String wasteInfo = data['wasteInfo'].toString().split('|')[0];
              String imgUrl = (data['imageUrls'] != null && (data['imageUrls'] as List).isNotEmpty) ? data['imageUrls'][0] : (data['imageUrl'] ?? "");
              bool hasLocation = data['latitude'] != null && data['longitude'] != null;

              return Card(
                elevation: 4,
                margin: EdgeInsets.only(bottom: 16),
                child: Column(
                  children: [
                    Stack(
                      children: [
                        Container(
                          height: 150, width: double.infinity,
                          child: imgUrl.isNotEmpty ? ClipRRect(borderRadius: BorderRadius.vertical(top: Radius.circular(16)), child: Image.network(imgUrl, fit: BoxFit.cover)) : Container(color: Colors.grey[200], child: Icon(Icons.image_not_supported)),
                        ),
                        Positioned(top: 10, right: 10, child: Container(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20)), child: Text("₹$price", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
                        Positioned(bottom: 10, left: 10, child: Container(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)), child: Row(children: [Icon(Icons.location_on, size: 14, color: Colors.red), Text(hasLocation ? " ${_getDistance(data['latitude'], data['longitude'])}" : " N/A", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))]))),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(wasteInfo, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          SizedBox(height: 5),
                          Text(data['wasteInfo'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                          SizedBox(height: 15),
                          Row(
                            children: [
                              Expanded(child: OutlinedButton(onPressed: () => _showOfferDialog(context, doc.id, price), child: Text("Negotiate"), style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.orange), foregroundColor: Colors.orange, padding: EdgeInsets.symmetric(vertical: 12)))),
                              SizedBox(width: 10),
                              Expanded(child: ElevatedButton(onPressed: () => _handleJob(doc.id, 'accept'), child: Text("Accept Job", style: TextStyle(color: Colors.white)), style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: EdgeInsets.symmetric(vertical: 12)))),
                            ],
                          )
                        ],
                      ),
                    )
                  ],
                ),
              ).animate().fade().slideY(begin: 0.1, end: 0);
            },
          );
        },
      ),
    );
  }
}

// ---------------- TAB 2: ACTIVE JOBS ---------------- //
class ActiveJobsTab extends StatelessWidget {
  Future<void> _confirmPickup(DocumentSnapshot doc) async {
    await doc.reference.update({'collectorConfirmed': true});
  }

  Future<void> _launchMaps(double lat, double long) async {
    final Uri url = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$lat,$long");
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final String myId = FirebaseAuth.instance.currentUser?.uid ?? "";
    return Scaffold(
      appBar: AppBar(title: Text("Active Jobs"), flexibleSpace: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.teal, Colors.teal.shade700])))),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('requests').where('collectorId', isEqualTo: myId).where('status', whereIn: ['accepted', 'negotiating']).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
          if (snapshot.data!.docs.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.assignment_turned_in_outlined, size: 60, color: Colors.grey), Text("No active pickups.")]));
          
          return ListView(
            padding: EdgeInsets.all(16),
            children: snapshot.data!.docs.map((doc) {
            var data = doc.data() as Map<String, dynamic>;
            bool meConfirmed = data['collectorConfirmed'] ?? false;
            bool houseConfirmed = data['householdConfirmed'] ?? false;
            String status = data['status'];
            
            if (status == 'negotiating') {
               return Card(
                 color: Colors.orange[50],
                 child: ListTile(title: Text("Negotiation Pending", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[900])), subtitle: Text("Waiting for user... Offer: ₹${data['offeredPrice']}"), leading: Icon(Icons.hourglass_top, color: Colors.orange)),
               );
            }

            return Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(data['userName'] ?? "User", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Container(padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8)), child: Text("₹${data['askPrice']}", style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.bold))),
                      ],
                    ),
                    SizedBox(height: 5),
                    Row(children: [Icon(Icons.phone, size: 14, color: Colors.grey), SizedBox(width: 5), Text(data['userPhone'] ?? "N/A", style: TextStyle(color: Colors.grey))]),
                    SizedBox(height: 10),
                    Text(data['wasteInfo'].toString().split('|')[0]),
                    SizedBox(height: 15),
                    if (houseConfirmed && !meConfirmed) Container(width: double.infinity, padding: EdgeInsets.all(8), color: Colors.green[50], child: Text("✅ Handover Confirmed by User", textAlign: TextAlign.center, style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.bold))),
                    if (meConfirmed) Container(width: double.infinity, padding: EdgeInsets.all(8), color: Colors.blue[50], child: Text("⏳ Waiting for Rating...", textAlign: TextAlign.center, style: TextStyle(color: Colors.blue[800]))),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: ElevatedButton.icon(icon: Icon(Icons.directions, color: Colors.white), label: Text("MAP", style: TextStyle(color: Colors.white)), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue), onPressed: () => _launchMaps(data['latitude'], data['longitude']))),
                        SizedBox(width: 10),
                        Expanded(child: ElevatedButton.icon(icon: Icon(Icons.check, color: Colors.white), label: Text(meConfirmed ? "WAITING" : "CONFIRM"), style: ElevatedButton.styleFrom(backgroundColor: meConfirmed ? Colors.grey : Colors.green), onPressed: meConfirmed ? null : () => _confirmPickup(doc))),
                      ],
                    )
                  ],
                ),
              ),
            );
          }).toList());
        },
      ),
    );
  }
}

// ---------------- TAB 3: COLLECTOR PROFILE ---------------- //
class CollectorProfileTab extends StatefulWidget {
  @override
  _CollectorProfileTabState createState() => _CollectorProfileTabState();
}

class _CollectorProfileTabState extends State<CollectorProfileTab> {
  User? get user => FirebaseAuth.instance.currentUser;
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _vehicleController = TextEditingController();
  bool _isEditing = false;

  @override
  void initState() { super.initState(); _loadProfile(); }

  Future<void> _loadProfile() async {
    final currentUser = user;
    if (currentUser == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
      if (doc.exists && mounted) {
        setState(() {
          _nameController.text = doc['name'] ?? currentUser.displayName ?? "";
          _phoneController.text = doc['phone'] ?? "";
          _vehicleController.text = doc['vehicle'] ?? "";
        });
      }
    } catch (e) {}
  }

  Future<void> _saveProfile() async {
    final currentUser = user;
    if (currentUser == null) return;
    try {
        await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).set({
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'vehicle': _vehicleController.text.trim(),
        'role': 'collector',
        'email': currentUser.email,
        }, SetOptions(merge: true));
        setState(() => _isEditing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Profile Updated!")));
    } catch(e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error saving profile.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = user;
    if (currentUser == null) return Center(child: CircularProgressIndicator());

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('requests').where('collectorId', isEqualTo: currentUser.uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
          
          final completed = snapshot.data!.docs.where((d) => d['status'] == 'completed').toList();
          
          double totalRating = 0;
          int ratedCount = 0;
          for (var doc in completed) {
             var data = doc.data() as Map<String, dynamic>;
             if (data.containsKey('rating')) { totalRating += (data['rating'] as num).toDouble(); ratedCount++; }
          }
          double avgRating = ratedCount > 0 ? totalRating / ratedCount : 5.0;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 220,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    padding: EdgeInsets.only(top: 50),
                    decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.teal, Colors.teal.shade800])),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(radius: 40, backgroundColor: Colors.white, child: Text(currentUser.displayName != null && currentUser.displayName!.isNotEmpty ? currentUser.displayName![0].toUpperCase() : "C", style: TextStyle(fontSize: 30, color: Colors.teal, fontWeight: FontWeight.bold))),
                        SizedBox(height: 10),
                        Text(currentUser.displayName ?? "Collector", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                        Text("Vehicle: ${_vehicleController.text}", style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                ),
                actions: [IconButton(icon: Icon(_isEditing ? Icons.save : Icons.edit, color: Colors.white), onPressed: _isEditing ? _saveProfile : () => setState(() => _isEditing = true))],
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _buildStatCard("Jobs Done", "${completed.length}", Icons.check_circle_outline)),
                          SizedBox(width: 15),
                          Expanded(child: _buildStatCard("Rating", avgRating.toStringAsFixed(1), Icons.star, isRating: true)),
                        ],
                      ),
                      
                      SizedBox(height: 20),
                      
                      Card(
                        elevation: 2,
                        child: ExpansionTile(
                          title: Text("Edit Profile Details", style: TextStyle(fontWeight: FontWeight.bold)),
                          leading: Icon(Icons.person, color: Colors.teal),
                          children: [
                            Padding(
                              padding: EdgeInsets.all(15),
                              child: Column(
                                children: [
                                  TextField(controller: _nameController, enabled: _isEditing, decoration: InputDecoration(labelText: "Full Name", prefixIcon: Icon(Icons.person))),
                                  SizedBox(height: 10),
                                  TextField(controller: _phoneController, enabled: _isEditing, decoration: InputDecoration(labelText: "Phone", prefixIcon: Icon(Icons.phone))),
                                  SizedBox(height: 10),
                                  TextField(controller: _vehicleController, enabled: _isEditing, decoration: InputDecoration(labelText: "Vehicle", prefixIcon: Icon(Icons.local_shipping))),
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                      
                      SizedBox(height: 25),
                      Align(alignment: Alignment.centerLeft, child: Text("Transaction History", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800]))),
                      SizedBox(height: 10),
                    ],
                  ),
                ),
              ),

              if (completed.isEmpty)
                SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(20), child: Center(child: Text("No completed jobs yet.", style: TextStyle(color: Colors.grey)))))
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      var data = completed[index].data() as Map<String, dynamic>;
                      String dateStr = data['timestamp'] != null ? DateFormat('dd MMM yyyy').format((data['timestamp'] as Timestamp).toDate()) : "";
                      return Card(
                        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                        elevation: 1,
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: Colors.teal[50], child: Icon(Icons.receipt, color: Colors.teal)),
                          title: Text(data['wasteInfo'].toString().split('|')[0], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(dateStr),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text("₹${data['askPrice']}", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16)),
                              if(data.containsKey('rating')) Row(mainAxisSize: MainAxisSize.min, children: [Text("${data['rating']}", style: TextStyle(fontSize: 12)), Icon(Icons.star, size: 12, color: Colors.amber)]),
                            ],
                          ),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => JobDetailScreen(data: data))),
                        ),
                      );
                    },
                    childCount: completed.length,
                  ),
                ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: ElevatedButton(onPressed: () => FirebaseAuth.instance.signOut(), child: Text("Logout"), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, minimumSize: Size(double.infinity, 50))),
                ),
              )
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, {bool isRating = false}) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)]),
      child: Column(
        children: [
          Icon(icon, color: isRating ? Colors.amber : Colors.teal, size: 30),
          SizedBox(height: 5),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text(title, style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

class JobDetailScreen extends StatelessWidget {
  final Map<String, dynamic> data;
  JobDetailScreen({required this.data});
  @override
  Widget build(BuildContext context) {
    String thumbUrl = (data['imageUrls'] != null && (data['imageUrls'] as List).isNotEmpty) ? data['imageUrls'][0] : (data['imageUrl'] ?? "");
    return Scaffold(
      appBar: AppBar(title: Text("Job Details")),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if(thumbUrl.isNotEmpty) ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(thumbUrl, width: double.infinity, height: 250, fit: BoxFit.cover)),
            SizedBox(height: 20),
            Text(data['wasteInfo'].toString(), style: TextStyle(fontSize: 16)),
            SizedBox(height: 10),
            Divider(),
            Text("Price Paid: ₹${data['askPrice']}", style: TextStyle(fontSize: 24, color: Colors.green, fontWeight: FontWeight.bold)),
            Text("Customer: ${data['userName']}"),
          ],
        ),
      ),
    );
  }
}