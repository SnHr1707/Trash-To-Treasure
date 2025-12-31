import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class HouseholdScreen extends StatefulWidget {
  @override
  _HouseholdScreenState createState() => _HouseholdScreenState();
}

class _HouseholdScreenState extends State<HouseholdScreen> {
  int _selectedIndex = 0;
  final List<Widget> _pages = [RequestTab(), ActivityTab(), ProfileTab()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: [
          NavigationDestination(icon: Icon(Icons.add_a_photo), label: 'Sell'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Activity'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

// ---------------- TAB 1: SELL WASTE (Multi-Image Support) ---------------- //
class RequestTab extends StatefulWidget {
  @override
  _RequestTabState createState() => _RequestTabState();
}

class _RequestTabState extends State<RequestTab> {
  List<Uint8List> _imageBytesList = [];
  List<XFile> _pickedFiles = [];
  
  String _aiResult = "Snap photos to see AI Price Estimate";
  String _detectedCategory = "General"; 
  bool _isAnalyzing = false;
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();

  // Env variables
  final String cloudName = dotenv.env['CLOUDINARY_CLOUD_NAME'] ?? "";
  final String uploadPreset = dotenv.env['CLOUDINARY_UPLOAD_PRESET'] ?? "";
  final String openRouterKey = dotenv.env['OPENROUTER_API_KEY'] ?? "";
  final String modelName = "nvidia/nemotron-nano-12b-v2-vl:free"; 

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final List<XFile>? photos = await picker.pickMultiImage();
    
    if (photos != null && photos.isNotEmpty) {
      List<Uint8List> bytesList = [];
      for (var photo in photos) {
        bytesList.add(await photo.readAsBytes());
      }
      
      setState(() { 
        _imageBytesList = bytesList; 
        _pickedFiles = photos; 
        _isAnalyzing = true; 
      });
      
      // Analyze only the first image to save resources/time
      await _analyzeWithNvidia(bytesList.first);
    }
  }

  Future<void> _analyzeWithNvidia(Uint8List imageBytes) async {
    if (openRouterKey.isEmpty) {
      setState(() { _aiResult = "API Key Missing (Check .env)"; _isAnalyzing = false; });
      return;
    }
    try {
      String base64Image = base64Encode(imageBytes);
      final response = await http.post(
        Uri.parse("https://openrouter.ai/api/v1/chat/completions"),
        headers: { "Authorization": "Bearer $openRouterKey", "Content-Type": "application/json" },
        body: jsonEncode({
          "model": modelName,
          "messages": [
            { "role": "user", "content": [
                {"type": "text", "text": "Analyze this waste item. Provide a brief description. format exactly like this: Item: [Name] | Est. Price: [₹X] | Category: [Plastic/Metal/Paper/E-waste/Glass/Other]. | Description: [One short sentence]."},
                {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,$base64Image"}}
              ]
            }
          ]
        }),
      );
      if (response.statusCode == 200) {
        String content = jsonDecode(response.body)['choices'][0]['message']['content'];
        String cat = "General";
        if (content.contains("Category:")) {
          try { cat = content.split("Category:")[1].split("|")[0].trim(); } catch(e) {}
        }
        setState(() { _aiResult = content; _detectedCategory = cat; _isAnalyzing = false; });
      } else {
        setState(() { _aiResult = "AI Error: ${response.statusCode}"; _isAnalyzing = false; });
      }
    } catch (e) { setState(() { _aiResult = "Connection Error"; _isAnalyzing = false; }); }
  }

  Future<void> _submitRequest() async {
    if (_imageBytesList.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No images!"))); return; }
    if (_priceController.text.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Please enter a selling price!"))); return; }
    
    setState(() => _isAnalyzing = true);

    try {
      List<String> uploadedUrls = [];

      // 1. Loop Upload to Cloudinary
      for (int i = 0; i < _imageBytesList.length; i++) {
        var request = http.MultipartRequest("POST", Uri.parse("https://api.cloudinary.com/v1_1/$cloudName/image/upload"));
        if (kIsWeb) {
          request.files.add(http.MultipartFile.fromBytes('file', _imageBytesList[i], filename: 'waste_$i.jpg'));
        } else {
          request.files.add(await http.MultipartFile.fromPath('file', _pickedFiles[i].path));
        }
        request.fields['upload_preset'] = uploadPreset;
        var response = await request.send();
        if(response.statusCode == 200) {
          var jsonMap = jsonDecode(await response.stream.bytesToString());
          uploadedUrls.add(jsonMap['secure_url']);
        }
      }

      // 2. Get User Info
      final user = FirebaseAuth.instance.currentUser!;
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      String userPhone = userDoc.exists ? (userDoc.data()?['phone'] ?? "Not Provided") : "Not Provided";
      
      Position pos;
      try { pos = await Geolocator.getCurrentPosition(); } catch (e) { 
        pos = Position(longitude: 0, latitude: 0, timestamp: DateTime.now(), accuracy: 0, altitude: 0, heading: 0, speed: 0, speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0); 
      }

      // 3. Save Request
      await FirebaseFirestore.instance.collection('requests').add({
        'userId': user.uid,
        'userName': user.displayName ?? 'Anonymous',
        'userPhone': userPhone,
        'wasteInfo': _aiResult, 
        'category': _detectedCategory,
        'askPrice': _priceController.text, 
        'imageUrls': uploadedUrls, // NEW: List of Strings
        'imageUrl': uploadedUrls.isNotEmpty ? uploadedUrls.first : null, // Backward compat
        'notes': _notesController.text,
        'status': 'pending', // pending, negotiating, accepted, completed, cancelled
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'householdConfirmed': false,
        'collectorConfirmed': false,
        'rated': false,
      });

      setState(() { 
        _isAnalyzing = false; _imageBytesList = []; _pickedFiles = [];
        _aiResult = "Snap a photo to see AI Price Estimate"; 
        _notesController.clear(); _priceController.clear(); 
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Request Posted Successfully!")));
    } catch (e) {
      setState(() => _isAnalyzing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Sell Waste"), backgroundColor: Colors.green, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            GestureDetector(
              onTap: _pickImages,
              child: Container(
                height: 200, width: double.infinity,
                decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.green)),
                child: _imageBytesList.isEmpty 
                  ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_photo_alternate, size: 50), Text("1. Tap to select photos")]) 
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _imageBytesList.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(_imageBytesList[index])),
                        );
                      },
                    ),
              ),
            ),
            SizedBox(height: 20),
            
            Container(
              padding: EdgeInsets.all(15),
              decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.shade200)),
              child: _isAnalyzing 
                ? Center(child: CircularProgressIndicator()) 
                : Column(
                    children: [
                      Text("AI Analysis", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[800])),
                      SizedBox(height: 5),
                      Text(_aiResult, textAlign: TextAlign.center),
                    ],
                  ),
            ),
            
            SizedBox(height: 20),
            TextField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: "2. Your Selling Price (₹)",
                hintText: "Enter the amount you want",
                prefixIcon: Icon(Icons.currency_rupee),
                filled: true,
                fillColor: Colors.green[50]
              ),
            ),
            SizedBox(height: 15),
            TextField(controller: _notesController, decoration: InputDecoration(labelText: "3. Notes (Optional)")),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _submitRequest, 
              child: Text("POST FOR SALE"), 
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, minimumSize: Size(double.infinity, 50))
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- TAB 2: ACTIVITY (Toggle Ongoing/History & Negotiation) ---------------- //
class ActivityTab extends StatefulWidget {
  @override
  _ActivityTabState createState() => _ActivityTabState();
}

class _ActivityTabState extends State<ActivityTab> {
  final user = FirebaseAuth.instance.currentUser!;
  String _searchQuery = "";
  String _selectedCategory = "All";
  bool _showHistory = false; // Toggle state

  void _handleNegotiation(DocumentSnapshot doc, bool accept) async {
    if (accept) {
      await doc.reference.update({
        'status': 'accepted',
        'askPrice': doc['offeredPrice'], // Update price to agreed amount
        'offeredPrice': FieldValue.delete(),
      });
    } else {
      await doc.reference.update({
        'status': 'pending', // Go back to pending to find other collectors
        'offeredPrice': FieldValue.delete(), // Remove rejected offer
        'collectorId': FieldValue.delete(),
        'collectorName': FieldValue.delete(),
      });
    }
  }

  void _showRatingDialog(BuildContext context, String docId) {
    double _rating = 5;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text("Rate Collector"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text("Did they pay appropriately?"),
          SizedBox(height: 10),
          RatingBar.builder(
            initialRating: 5, minRating: 1, direction: Axis.horizontal, itemCount: 5,
            itemBuilder: (context, _) => Icon(Icons.star, color: Colors.amber),
            onRatingUpdate: (rating) { _rating = rating; },
          ),
        ]),
        actions: [
          TextButton(
            child: Text("SUBMIT"),
            onPressed: () async {
              await FirebaseFirestore.instance.collection('requests').doc(docId).update({
                'status': 'completed',
                'rated': true,
                'rating': _rating,
              });
              Navigator.pop(context);
            },
          )
        ],
      ),
    );
  }

  Future<void> _confirmHandover(BuildContext context, DocumentSnapshot doc) async {
    final docRef = doc.reference;
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      transaction.update(docRef, {'householdConfirmed': true});
    });

    var fresh = await docRef.get();
    if (fresh['collectorConfirmed'] == true && fresh['rated'] == false) {
      _showRatingDialog(context, doc.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("My Activity"), centerTitle: true),
      body: Column(
        children: [
          // 1. TOGGLE BUTTON (Ongoing vs History)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text('Ongoing'), icon: Icon(Icons.timelapse)),
                ButtonSegment(value: true, label: Text('History'), icon: Icon(Icons.history)),
              ],
              selected: {_showHistory},
              onSelectionChanged: (Set<bool> newSelection) {
                setState(() => _showHistory = newSelection.first);
              },
            ),
          ),

          // 2. SEARCH & FILTER
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: "Search items...",
                    prefixIcon: Icon(Icons.search),
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                ),
                SizedBox(height: 5),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ["All", "Plastic", "Metal", "E-waste", "Paper", "Glass", "Other"].map((cat) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 5.0),
                        child: FilterChip(
                          label: Text(cat),
                          selected: _selectedCategory == cat,
                          onSelected: (bool selected) {
                            setState(() => _selectedCategory = selected ? cat : "All");
                          },
                          visualDensity: VisualDensity.compact,
                        ),
                      );
                    }).toList(),
                  ),
                )
              ],
            ),
          ),
          
          // 3. LIST OF ACTIVITY
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('requests')
                .where('userId', isEqualTo: user.uid)
                .orderBy('timestamp', descending: true)
                .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
                
                // CLIENT SIDE FILTERING (Status + Search + Category)
                var docs = snapshot.data!.docs.where((doc) {
                  var data = doc.data() as Map<String, dynamic>;
                  String status = data['status'];
                  
                  // Toggle Logic
                  bool isHistory = (status == 'completed' || status == 'cancelled');
                  if (_showHistory != isHistory) return false;

                  // Search & Cat Logic
                  String info = data['wasteInfo'].toString().toLowerCase();
                  String cat = (data['category'] ?? "").toString();
                  bool matchesSearch = info.contains(_searchQuery);
                  bool matchesCategory = _selectedCategory == "All" || cat.contains(_selectedCategory);
                  
                  return matchesSearch && matchesCategory;
                }).toList();

                if (docs.isEmpty) return Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inbox, size: 50, color: Colors.grey),
                    Text("No requests found."),
                  ],
                ));

                return ListView(
                  children: docs.map((doc) {
                    var data = doc.data() as Map<String, dynamic>;
                    String status = data['status'];
                    String price = data['askPrice'] ?? "??";
                    String offeredPrice = data['offeredPrice'] ?? "";
                    
                    // Handle image list or single string backward compatibility
                    String thumbUrl = "";
                    if (data['imageUrls'] != null && (data['imageUrls'] as List).isNotEmpty) {
                      thumbUrl = data['imageUrls'][0];
                    } else if (data['imageUrl'] != null) {
                      thumbUrl = data['imageUrl'];
                    }

                    return Card(
                      margin: EdgeInsets.all(10),
                      elevation: 3,
                      child: Column(
                        children: [
                          ListTile(
                            leading: thumbUrl.isNotEmpty 
                              ? ClipRRect(borderRadius: BorderRadius.circular(5), child: Image.network(thumbUrl, width: 60, height: 60, fit: BoxFit.cover)) 
                              : Icon(Icons.recycling, size: 40),
                            title: Text(data['wasteInfo'].toString().split('|')[0], maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(status.toUpperCase(), style: TextStyle(color: _getStatusColor(status), fontWeight: FontWeight.bold, fontSize: 12)),
                                if(data.containsKey('category')) Text("Cat: ${data['category']}", style: TextStyle(fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text("₹$price", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, decoration: status == 'negotiating' ? TextDecoration.lineThrough : null)),
                                if(status == 'negotiating')
                                  Text("Offer: ₹$offeredPrice", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red)),
                              ],
                            ),
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FullHistoryScreen(data: data))),
                          ),
                          
                          // NEGOTIATION UI
                          if (status == 'negotiating')
                            Container(
                              color: Colors.orange[50],
                              padding: EdgeInsets.all(8),
                              child: Column(
                                children: [
                                  Text("Collector offered ₹$offeredPrice. Accept?", style: TextStyle(fontWeight: FontWeight.bold)),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      ElevatedButton(onPressed: () => _handleNegotiation(doc, true), child: Text("ACCEPT"), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white)),
                                      ElevatedButton(onPressed: () => _handleNegotiation(doc, false), child: Text("REJECT"), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white)),
                                    ],
                                  )
                                ],
                              ),
                            ),

                          // CONFIRMATION UI
                          if (status == 'accepted' && !(data['householdConfirmed'] ?? false))
                            Padding(padding: EdgeInsets.all(8), child: ElevatedButton.icon(
                              icon: Icon(Icons.check_circle),
                              label: Text("CONFIRM HANDOVER"), 
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, minimumSize: Size(double.infinity, 40)),
                              onPressed: () => _confirmHandover(context, doc)
                            )),

                          if ((data['householdConfirmed'] ?? false) && (data['collectorConfirmed'] ?? false) && !(data['rated'] ?? false))
                            Padding(padding: EdgeInsets.all(8), child: ElevatedButton(
                              child: Text("RATE COLLECTOR"), style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                              onPressed: () => _showRatingDialog(context, doc.id)
                            )),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed': return Colors.green;
      case 'negotiating': return Colors.red;
      case 'accepted': return Colors.blue;
      default: return Colors.orange;
    }
  }
}

class FullHistoryScreen extends StatelessWidget {
  final Map<String, dynamic> data;
  FullHistoryScreen({required this.data});

  @override
  Widget build(BuildContext context) {
    String price = data['askPrice'] ?? "N/A";
    List<dynamic> images = data['imageUrls'] ?? (data['imageUrl'] != null ? [data['imageUrl']] : []);
    
    return Scaffold(
      appBar: AppBar(title: Text("Details")),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (images.isNotEmpty) 
              SizedBox(
                height: 250,
                child: PageView.builder(
                  itemCount: images.length,
                  itemBuilder: (context, index) {
                    return Image.network(images[index], width: double.infinity, fit: BoxFit.cover);
                  },
                ),
              ),
            if (images.length > 1) Center(child: Padding(padding: EdgeInsets.all(8.0), child: Text("Swipe for more photos", style: TextStyle(color: Colors.grey)))),
            
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Price:", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text("₹$price", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green[800])),
              ],
            ),
            Divider(),
            
            Text("AI Description:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(5)),
              child: Text(data['wasteInfo'] ?? ""),
            ),
            
            SizedBox(height: 10),
            Text("Category: ${data['category'] ?? 'General'}"),
            
            Divider(),
            Text("Collector Info:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text("Name: ${data['collectorName'] ?? 'Pending'}"),
            Text("Phone: ${data['collectorPhone'] ?? 'Not Available'}"), 
            if (data.containsKey('rating')) Text("Your Rating: ${data['rating']} ⭐"),
            SizedBox(height: 20),
            Center(child: Text("Status: ${data['status'].toUpperCase()}", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16))),
          ],
        ),
      ),
    );
  }
}

class ProfileTab extends StatefulWidget {
  @override
  _ProfileTabState createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final user = FirebaseAuth.instance.currentUser!;
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && mounted) {
        setState(() {
          _nameController.text = doc.data()?['name'] ?? user.displayName ?? "";
          _phoneController.text = doc.data()?['phone'] ?? "";
        });
      } else {
        if (mounted) _nameController.text = user.displayName ?? "";
      }
    } catch (e) { print(e); }
  }

  Future<void> _saveProfile() async {
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'email': user.email,
      'role': 'household',
    }, SetOptions(merge: true));
    
    if (_nameController.text.isNotEmpty) {
      await user.updateDisplayName(_nameController.text.trim());
    }
    
    if (mounted) {
      setState(() => _isEditing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Profile Updated!")));
    }
  }

  String _getSafeInitials(String name) {
    String cleanName = name.trim();
    if (cleanName.isEmpty) return "U";
    List<String> parts = cleanName.split(RegExp(r"\s+"));
    String first = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0][0] : "";
    String second = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : "";
    return (first + second).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    String displayName = _nameController.text.isNotEmpty ? _nameController.text : (user.displayName ?? "User");
    String initials = _getSafeInitials(displayName);

    return Scaffold(
      appBar: AppBar(
        title: Text("My Profile"), 
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.save : Icons.edit),
            onPressed: _isEditing ? _saveProfile : () => setState(() => _isEditing = true),
          )
        ]
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(height: 20),
            CircleAvatar(
              radius: 50, 
              backgroundColor: Colors.green[100], 
              child: Text(initials, style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.green[800])),
            ),
            SizedBox(height: 20),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('requests').where('userId', isEqualTo: user.uid).snapshots(),
              builder: (context, snapshot) {
                if(!snapshot.hasData) return SizedBox();
                int total = snapshot.data!.docs.length;
                int completed = snapshot.data!.docs.where((d) => d['status'] == 'completed').length;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _statCard("Requests", "$total"),
                    SizedBox(width: 20),
                    _statCard("Sold", "$completed"),
                  ],
                );
              },
            ),
            SizedBox(height: 20),
            Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  TextField(
                    controller: _nameController, enabled: _isEditing,
                    decoration: InputDecoration(labelText: "Full Name", prefixIcon: Icon(Icons.person), border: OutlineInputBorder()),
                  ),
                  SizedBox(height: 15),
                  TextField(
                    controller: _phoneController, enabled: _isEditing,
                    decoration: InputDecoration(labelText: "Phone Number", prefixIcon: Icon(Icons.phone), border: OutlineInputBorder()),
                  ),
                  SizedBox(height: 15),
                  TextField(
                    enabled: false,
                    controller: TextEditingController(text: user.email),
                    decoration: InputDecoration(labelText: "Email", prefixIcon: Icon(Icons.email), border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => FirebaseAuth.instance.signOut(),
              child: Text("Logout"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            )
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
      decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(10)),
      child: Column(children: [Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), Text(label)]),
    );
  }
}