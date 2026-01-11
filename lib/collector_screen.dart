import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

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
          NavigationDestination(icon: Icon(Icons.search), label: 'Market'),
          NavigationDestination(icon: Icon(Icons.electric_rickshaw), label: 'Active'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

// ---------------- TAB 1: FIND JOBS ---------------- //
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

    Map<String, dynamic> updateData = {
      'collectorId': user.uid,
      'collectorName': name,
      'collectorPhone': phone,
    };

    if (action == 'accept') {
      updateData['status'] = 'accepted';
    } else if (action == 'offer') {
      updateData['status'] = 'negotiating';
      updateData['offeredPrice'] = offerPrice;
    }

    await FirebaseFirestore.instance.collection('requests').doc(docId).update(updateData);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(action == 'accept' ? "Job Accepted!" : "Offer Sent!")));
  }

  void _showOfferDialog(BuildContext context, String docId, String currentPrice) {
    TextEditingController offerController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Negotiate Price"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Current Ask: ₹$currentPrice"),
            TextField(
              controller: offerController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: "Your Offer (₹)"),
            )
          ],
        ),
        actions: [
          TextButton(child: Text("CANCEL"), onPressed: () => Navigator.pop(context)),
          ElevatedButton(
            child: Text("SEND OFFER"),
            onPressed: () {
              if (offerController.text.isNotEmpty) {
                _handleJob(docId, 'offer', offerPrice: offerController.text);
                Navigator.pop(context);
              }
            },
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Waste Market"), backgroundColor: Colors.teal, foregroundColor: Colors.white),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('requests').where('status', isEqualTo: 'pending').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
          if (snapshot.data!.docs.isEmpty) return Center(child: Text("No jobs available nearby."));

          return ListView(children: snapshot.data!.docs.map((doc) {
            var data = doc.data() as Map<String, dynamic>;
            String price = data['askPrice'] ?? "N/A";
            String wasteInfo = data['wasteInfo'].toString().split('|')[0];
            
            // Safe Parsing
            String estPrice = "??";
            String fullInfo = data['wasteInfo'].toString();
            if (fullInfo.contains("Price:")) {
              List<String> parts = fullInfo.split("Price:");
              if (parts.length > 1) {
                estPrice = parts[1].split("|")[0].trim();
              }
            }

            String imgUrl = "";
            if (data['imageUrls'] != null && (data['imageUrls'] as List).isNotEmpty) imgUrl = data['imageUrls'][0];
            else if (data['imageUrl'] != null) imgUrl = data['imageUrl'];

            bool hasLocation = data['latitude'] != null && data['longitude'] != null;

            return Card(
              margin: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              elevation: 4,
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.all(10),
                    leading: imgUrl.isNotEmpty 
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(5), 
                          child: Image.network(
                            imgUrl, width: 70, height: 70, fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Icon(Icons.broken_image, color: Colors.grey),
                          )
                        )
                      : CircleAvatar(backgroundColor: Colors.grey[200], child: Icon(Icons.recycling)),
                    title: Text(wasteInfo, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 5),
                        Row(children: [
                          Icon(Icons.location_on, size: 14, color: Colors.grey), 
                          Text(hasLocation ? " ${_getDistance(data['latitude'], data['longitude'])}" : " Loc N/A")
                        ]),
                        Text("AI Est: $estPrice", style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("₹$price", style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.bold, fontSize: 18)),
                        Text("Asking", style: TextStyle(fontSize: 10, color: Colors.green)),
                      ],
                    ),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => JobDetailScreen(data: data))),
                  ),
                  Divider(height: 1),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          icon: Icon(Icons.handshake, color: Colors.orange),
                          label: Text("MAKE OFFER", style: TextStyle(color: Colors.orange)),
                          onPressed: () => _showOfferDialog(context, doc.id, price),
                        ),
                      ),
                      Container(width: 1, height: 40, color: Colors.grey[300]),
                      Expanded(
                        child: TextButton.icon(
                          icon: Icon(Icons.check_circle, color: Colors.teal),
                          label: Text("ACCEPT PRICE", style: TextStyle(color: Colors.teal)),
                          onPressed: () => _handleJob(doc.id, 'accept'),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            );
          }).toList());
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
      appBar: AppBar(title: Text("Active Jobs"), backgroundColor: Colors.orange),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('requests')
          .where('collectorId', isEqualTo: myId)
          .where('status', whereIn: ['accepted', 'negotiating']).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
          if (snapshot.data!.docs.isEmpty) return Center(child: Text("No active jobs."));
          
          return ListView(children: snapshot.data!.docs.map((doc) {
            var data = doc.data() as Map<String, dynamic>;
            bool meConfirmed = data['collectorConfirmed'] ?? false;
            bool houseConfirmed = data['householdConfirmed'] ?? false;
            String status = data['status'];
            String price = data['askPrice'] ?? "??";
            
            if (status == 'negotiating') {
               return Card(
                 margin: EdgeInsets.all(10), color: Colors.orange[50],
                 child: ListTile(
                   title: Text("Negotiation Pending"),
                   subtitle: Text("Waiting for user to accept offer: ₹${data['offeredPrice']}"),
                   trailing: Icon(Icons.hourglass_top),
                 ),
               );
            }

            return Card(
              margin: EdgeInsets.all(10),
              child: Column(
                children: [
                  ListTile(
                    title: Text(data['userName']),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(data['wasteInfo'].toString().split('|')[0]),
                        Text("Phone: ${data['userPhone'] ?? 'N/A'}", style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("₹$price", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green[800])),
                        Text("To Pay", style: TextStyle(fontSize: 10)),
                      ],
                    ),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => JobDetailScreen(data: data))),
                  ),
                  
                  if (houseConfirmed && !meConfirmed)
                     Container(color: Colors.green[50], padding: EdgeInsets.all(10), child: Text("✅ User Confirmed! Please confirm payment.", style: TextStyle(color: Colors.green))),
                  if (houseConfirmed && meConfirmed)
                     Container(color: Colors.blue[50], padding: EdgeInsets.all(10), child: Text("Wait for User Rating...", style: TextStyle(color: Colors.blue))),

                  Padding(padding: EdgeInsets.all(10), child: Row(children: [
                    Expanded(child: ElevatedButton.icon(icon: Icon(Icons.map), label: Text("NAV"), onPressed: () => _launchMaps(data['latitude'], data['longitude']))),
                    SizedBox(width: 10),
                    Expanded(child: ElevatedButton.icon(
                      icon: Icon(Icons.check),
                      label: Text(meConfirmed ? "WAITING" : "CONFIRM"),
                      style: ElevatedButton.styleFrom(backgroundColor: meConfirmed ? Colors.grey : Colors.green, foregroundColor: Colors.white),
                      onPressed: meConfirmed ? null : () => _confirmPickup(doc),
                    )),
                  ]))
                ],
              ),
            );
          }).toList());
        },
      ),
    );
  }
}

class JobDetailScreen extends StatefulWidget {
  final Map<String, dynamic> data;
  JobDetailScreen({required this.data});

  @override
  _JobDetailScreenState createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  int _currentImageIndex = 0;

  @override
  Widget build(BuildContext context) {
    List<String> images = [];
    if (widget.data['imageUrls'] != null) {
      images = List<String>.from(widget.data['imageUrls']);
    } else if (widget.data['imageUrl'] != null) {
      images = [widget.data['imageUrl']];
    }

    return Scaffold(
      appBar: AppBar(title: Text("Job Info")),
      body: SingleChildScrollView(padding: EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (images.isNotEmpty) 
          Column(
            children: [
              SizedBox(
                height: 300,
                child: PageView.builder(
                  itemCount: images.length,
                  onPageChanged: (index) => setState(() => _currentImageIndex = index),
                  itemBuilder: (context, index) {
                    return Container(
                      margin: EdgeInsets.symmetric(horizontal: 5),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10), 
                        child: Image.network(
                          images[index], fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Center(child: Icon(Icons.broken_image, size: 50, color: Colors.grey)),
                        )
                      ),
                    );
                  },
                ),
              ),
              if (images.length > 1) 
                 Padding(padding: EdgeInsets.only(top: 5), child: Text("${_currentImageIndex + 1}/${images.length} - Swipe for more", style: TextStyle(fontSize: 12, color: Colors.grey))),
            ],
          ),
        
        SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
             Text("Price:", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
             Text("₹${widget.data['askPrice']}", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green)),
          ],
        ),
        Divider(),
        Text("Customer Info:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text("Name: ${widget.data['userName']}"),
        Text("Phone: ${widget.data['userPhone'] ?? 'Not Available'}"), 
        Divider(),
        Text("Waste Info:", style: TextStyle(fontWeight: FontWeight.bold)),
        Text(widget.data['wasteInfo']),
        SizedBox(height: 10),
        Text("User Note:", style: TextStyle(fontWeight: FontWeight.bold)),
        Text("${widget.data['notes']}"),
      ])),
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
  void initState() {
    super.initState();
    _loadProfile();
  }

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
      } else if (mounted) {
        _nameController.text = currentUser.displayName ?? "";
      }
    } catch (e) { print(e); }
  }

  Future<void> _saveProfile() async {
    final currentUser = user;
    if (currentUser == null) return;

    await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).set({
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'vehicle': _vehicleController.text.trim(),
      'role': 'collector',
      'email': currentUser.email,
    }, SetOptions(merge: true));

    if (_nameController.text.isNotEmpty) {
      await currentUser.updateDisplayName(_nameController.text.trim());
    }

    if (mounted) {
      setState(() => _isEditing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Profile Updated!")));
    }
  }

  String _getSafeInitials(String name) {
    String cleanName = name.trim();
    if (cleanName.isEmpty) return "C";
    List<String> parts = cleanName.split(RegExp(r"\s+"));
    String first = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0][0] : "";
    String second = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : "";
    String result = (first + second).toUpperCase();
    return result.isEmpty ? "C" : result;
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = user;
    if (currentUser == null) return Scaffold(body: Center(child: CircularProgressIndicator()));

    String displayName = _nameController.text.isNotEmpty ? _nameController.text : (currentUser.displayName ?? "Collector");
    String initials = _getSafeInitials(displayName);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text("Collector Profile"),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.save : Icons.edit),
            onPressed: _isEditing ? _saveProfile : () => setState(() => _isEditing = true),
          )
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('requests')
            .where('collectorId', isEqualTo: currentUser.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
          
          final docs = snapshot.data!.docs;
          final completed = docs.where((d) => d['status'] == 'completed');
          
          double totalRating = 0;
          int ratedCount = 0;
          for (var doc in completed) {
            var data = doc.data() as Map<String, dynamic>;
            if (data.containsKey('rating')) {
              totalRating += (data['rating'] as num).toDouble(); 
              ratedCount++;
            }
          }
          double avgRating = ratedCount > 0 ? totalRating / ratedCount : 5.0;

          return SingleChildScrollView(
            child: Column(
              children: [
                // Header
                Container(
                  padding: EdgeInsets.all(20),
                  color: Colors.teal,
                  child: Row(
                    children: [
                      CircleAvatar(radius: 40, backgroundColor: Colors.white, 
                        child: Text(initials, style: TextStyle(fontSize: 30, color: Colors.teal, fontWeight: FontWeight.bold))),
                      SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(displayName, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                            Text("Vehicle: ${_vehicleController.text.isEmpty ? 'Not Set' : _vehicleController.text}", style: TextStyle(color: Colors.teal[100])),
                          ],
                        ),
                      )
                    ],
                  ),
                ),

                // Stats Dashboard
                Padding(
                  padding: EdgeInsets.all(15),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStatBox("Jobs Done", "${completed.length}", Icons.check_circle),
                      _buildStatBox("Rating", avgRating.toStringAsFixed(1), Icons.star, isRating: true),
                    ],
                  ),
                ),

                // Editable Fields
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(15),
                      child: Column(
                        children: [
                          Text("Personal Details", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          SizedBox(height: 10),
                          TextField(
                            controller: _nameController, enabled: _isEditing,
                            decoration: InputDecoration(labelText: "Full Name", prefixIcon: Icon(Icons.person)),
                          ),
                          TextField(
                            controller: _phoneController, enabled: _isEditing,
                            decoration: InputDecoration(labelText: "Phone Number", prefixIcon: Icon(Icons.phone)),
                          ),
                          TextField(
                            controller: _vehicleController, enabled: _isEditing,
                            decoration: InputDecoration(labelText: "Vehicle Details", prefixIcon: Icon(Icons.local_shipping)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 15),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Align(alignment: Alignment.centerLeft, child: Text("Work History", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                ),

                // History List
                ListView.builder(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  itemCount: completed.length,
                  itemBuilder: (context, index) {
                    var data = completed.elementAt(index).data() as Map<String, dynamic>;
                    String price = data['askPrice'] ?? "??";
                    
                    String imgUrl = "";
                    if (data['imageUrls'] != null && (data['imageUrls'] as List).isNotEmpty) imgUrl = data['imageUrls'][0];
                    else if (data['imageUrl'] != null) imgUrl = data['imageUrl'];

                    return Card(
                      margin: EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                      child: ListTile(
                        leading: imgUrl.isNotEmpty
                            ? ClipRRect(borderRadius: BorderRadius.circular(5), child: Image.network(imgUrl, width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => Icon(Icons.history))) 
                            : Icon(Icons.history),
                        title: Text(data['wasteInfo'].toString().split('|')[0]),
                        subtitle: Text(DateFormat('MMM d').format((data['timestamp'] as Timestamp).toDate())),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text("₹$price", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                            if(data.containsKey('rating')) Row(mainAxisSize: MainAxisSize.min, children: [Text("${data['rating']}"), Icon(Icons.star, size: 14, color: Colors.amber)]),
                          ],
                        ),
                        onTap: () {
                           Navigator.push(context, MaterialPageRoute(builder: (_) => JobDetailScreen(data: data)));
                        },
                      ),
                    );
                  },
                ),
                
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  child: Text("Logout"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                ),
                SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatBox(String label, String value, IconData icon, {bool isRating = false}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)]),
      child: Column(
        children: [
          Icon(icon, color: isRating ? Colors.amber : Colors.teal, size: 30),
          SizedBox(height: 5),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}