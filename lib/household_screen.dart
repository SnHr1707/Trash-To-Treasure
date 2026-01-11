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
import 'package:flutter_animate/flutter_animate.dart';

// ------------------------------------------------------------------
// CONFIGURATION KEYS
// ------------------------------------------------------------------
const String CLOUDINARY_CLOUD_NAME = ""; 
const String CLOUDINARY_UPLOAD_PRESET = "";      

// TODO: REPLACE THIS WITH YOUR GEMINI API KEY FROM GOOGLE AI STUDIO
const String GEMINI_API_KEY = ""; 
// ------------------------------------------------------------------

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
        elevation: 10,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.teal[50],
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: [
          NavigationDestination(
            selectedIcon: Icon(Icons.camera_alt, color: Colors.white), 
            icon: Icon(Icons.camera_alt_outlined), 
            label: 'Sell'
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.history, color: Colors.white), 
            icon: Icon(Icons.history_outlined), 
            label: 'Activity'
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.person, color: Colors.white), 
            icon: Icon(Icons.person_outline), 
            label: 'Profile'
          ),
        ],
        indicatorColor: Colors.teal,
      ),
    );
  }
}

// ---------------- TAB 1: SELL WASTE (Gemini Integrated) ---------------- //
class RequestTab extends StatefulWidget {
  @override
  _RequestTabState createState() => _RequestTabState();
}

class _RequestTabState extends State<RequestTab> {
  List<Uint8List> _imageBytesList = [];
  List<XFile> _pickedFiles = [];
  String _aiResult = "Snap photos to see Gemini AI Estimate";
  String _detectedCategory = "General";
  bool _isAnalyzing = false;
  bool _isValidTrash = false; 
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();

  Future<void> _pickImages(ImageSource source) async {
    final picker = ImagePicker();
    if (source == ImageSource.gallery) {
      final List<XFile>? photos = await picker.pickMultiImage();
      if (photos != null && photos.isNotEmpty) {
        for (var photo in photos) {
          var bytes = await photo.readAsBytes();
          setState(() {
            _pickedFiles.add(photo);
            _imageBytesList.add(bytes);
          });
        }
        if (!_isAnalyzing && _imageBytesList.isNotEmpty) _analyzeWithGemini(_imageBytesList.first);
      }
    } else {
      final XFile? photo = await picker.pickImage(source: ImageSource.camera);
      if (photo != null) {
        var bytes = await photo.readAsBytes();
        setState(() {
          _pickedFiles.add(photo);
          _imageBytesList.add(bytes);
        });
        if (!_isAnalyzing) _analyzeWithGemini(bytes);
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      _imageBytesList.removeAt(index);
      _pickedFiles.removeAt(index);
      if(_imageBytesList.isEmpty) {
        _aiResult = "Snap photos to see Gemini AI Estimate";
        _isValidTrash = false;
        _detectedCategory = "General";
      }
    });
  }

  Future<void> _analyzeWithGemini(Uint8List imageBytes) async {
    if (GEMINI_API_KEY.contains("YOUR_") || GEMINI_API_KEY.isEmpty) {
      setState(() => _aiResult = "Error: Gemini API Key not set in code.");
      return;
    }

    setState(() => _isAnalyzing = true);
    
    try {
      String base64Image = base64Encode(imageBytes);
      
      // Gemini 1.5 Flash Endpoint
      final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$GEMINI_API_KEY');

      final response = await http.post(
        url,
        headers: { 'Content-Type': 'application/json' },
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {
                  "text": "You are a recycling expert. Analyze this image. \n"
                          "1. If the image does NOT contain waste/recyclable items (e.g., people, scenery, blurry void), return ONLY the string: NOT_TRASH\n"
                          "2. If it IS waste, return a single line in this EXACT format:\n"
                          "Item: [Name of item] | Est. Price: [₹Price] | Category: [Plastic/Metal/Paper/E-waste/Glass/Other] | Description: [Very brief description]"
                },
                {
                  "inline_data": {
                    "mime_type": "image/jpeg",
                    "data": base64Image
                  }
                }
              ]
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['candidates'] != null && data['candidates'].isNotEmpty) {
           String content = data['candidates'][0]['content']['parts'][0]['text'].toString().trim();

           // Remove markdown if Gemini adds it
           content = content.replaceAll('**', '').replaceAll('*', '');

           if (content.contains("NOT_TRASH")) {
             setState(() {
               _aiResult = "⚠️ Gemini detected no trash. Try a clearer photo.";
               _isValidTrash = false;
               _detectedCategory = "Invalid";
               _isAnalyzing = false;
             });
             return;
           }

           String cat = "General";
           if (content.contains("Category:")) {
             try { 
               var parts = content.split("Category:");
               if(parts.length > 1) cat = parts[1].split("|")[0].trim(); 
             } catch(e) {}
           }
           
           setState(() { 
             _aiResult = content; 
             _detectedCategory = cat; 
             _isValidTrash = true; 
             _isAnalyzing = false; 
           });

        } else {
           setState(() { _aiResult = "AI couldn't identify the object."; _isAnalyzing = false; });
        }
      } else {
        setState(() { _aiResult = "Gemini API Error (${response.statusCode})"; _isAnalyzing = false; });
      }
    } catch (e) { 
      setState(() { _aiResult = "Connection Error: $e"; _isAnalyzing = false; }); 
    }
  }

  Future<void> _submitRequest() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Login required!"))); return; }
    
    // --- VALIDATION ---
    if (_imageBytesList.isEmpty) { 
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text("Please upload a photo of the waste."))); 
      return; 
    }
    
    if (!_isValidTrash && !_aiResult.contains("Item:")) {
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(
         backgroundColor: Colors.red, 
         content: Text("AI did not detect valid trash. Please upload a clear photo.")
       ));
       return;
    }

    if (_priceController.text.isEmpty) { 
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.orange, content: Text("Please enter a selling price."))); 
      return; 
    }

    if (double.tryParse(_priceController.text) == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text("Price must be a valid number."))); 
      return;
    }

    setState(() => _isAnalyzing = true);

    try {
      List<String> uploadedUrls = [];
      for (int i = 0; i < _imageBytesList.length; i++) {
        var request = http.MultipartRequest("POST", Uri.parse("https://api.cloudinary.com/v1_1/$CLOUDINARY_CLOUD_NAME/image/upload"));
        if (kIsWeb) {
          request.files.add(http.MultipartFile.fromBytes('file', _imageBytesList[i], filename: 'waste_$i.jpg'));
        } else {
          request.files.add(await http.MultipartFile.fromPath('file', _pickedFiles[i].path));
        }
        request.fields['upload_preset'] = CLOUDINARY_UPLOAD_PRESET;
        var response = await request.send();
        if(response.statusCode == 200) {
          var responseData = await response.stream.bytesToString();
          uploadedUrls.add(jsonDecode(responseData)['secure_url']);
        }
      }

      if (uploadedUrls.isEmpty) throw Exception("Image upload failed.");

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      String userPhone = userDoc.exists ? (userDoc.data()?['phone'] ?? "Not Provided") : "Not Provided";
      
      Position pos;
      try { pos = await Geolocator.getCurrentPosition(); } catch (e) { 
        pos = Position(longitude: 0, latitude: 0, timestamp: DateTime.now(), accuracy: 0, altitude: 0, heading: 0, speed: 0, speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0); 
      }

      await FirebaseFirestore.instance.collection('requests').add({
        'userId': user.uid,
        'userName': user.displayName ?? 'Anonymous',
        'userPhone': userPhone,
        'wasteInfo': _aiResult, 
        'category': _detectedCategory,
        'askPrice': _priceController.text, 
        'imageUrls': uploadedUrls, 
        'imageUrl': uploadedUrls.first,
        'notes': _notesController.text,
        'status': 'pending', 
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'householdConfirmed': false,
        'collectorConfirmed': false,
        'rated': false,
      });

      setState(() { 
        _isAnalyzing = false; _imageBytesList = []; _pickedFiles = [];
        _aiResult = "Snap photos to see Gemini AI Estimate"; 
        _isValidTrash = false;
        _notesController.clear(); _priceController.clear(); 
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.teal, content: Text("Success! Posted to Market.")));
    } catch (e) {
      setState(() => _isAnalyzing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Sell Waste", style: TextStyle(fontWeight: FontWeight.bold)), 
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.teal, Colors.teal.shade700]))
        ),
      ),
      body: SingleChildScrollView( 
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("1. Upload Photos", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal[800])),
            SizedBox(height: 15),
            Row(
              children: [
                Expanded(child: _buildMediaButton(Icons.camera_alt, "Camera", () => _pickImages(ImageSource.camera), Colors.orange)),
                SizedBox(width: 15),
                Expanded(child: _buildMediaButton(Icons.photo_library, "Gallery", () => _pickImages(ImageSource.gallery), Colors.blue)),
              ],
            ).animate().fade().slideY(begin: 0.2, end: 0),
            
            SizedBox(height: 15),
            if (_imageBytesList.isNotEmpty)
              Container(
                height: 120,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _imageBytesList.length,
                  itemBuilder: (context, index) {
                    return Stack(
                      children: [
                        Container(
                          margin: EdgeInsets.only(right: 15, top: 5, bottom: 5),
                          width: 110, height: 110,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(15), 
                            border: Border.all(color: Colors.teal.shade100),
                            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)]
                          ),
                          child: ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.memory(_imageBytesList[index], fit: BoxFit.cover)),
                        ),
                        Positioned(
                          right: 5, top: 0,
                          child: GestureDetector(
                            onTap: () => _removeImage(index),
                            child: CircleAvatar(radius: 12, backgroundColor: Colors.red, child: Icon(Icons.close, size: 14, color: Colors.white)),
                          ),
                        ),
                      ],
                    ).animate().scale();
                  },
                ),
              ),

            SizedBox(height: 25),
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _isValidTrash ? Colors.green.withOpacity(0.5) : Colors.orange.withOpacity(0.3)),
                boxShadow: [BoxShadow(color: Colors.teal.withOpacity(0.05), blurRadius: 15, offset: Offset(0,5))],
              ),
              child: _isAnalyzing 
                ? Column(children: [CircularProgressIndicator(color: Colors.teal), SizedBox(height: 10), Text("Gemini is analyzing...")])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.auto_awesome, color: _isValidTrash ? Colors.teal : Colors.orange), 
                        SizedBox(width: 10), 
                        Text("Gemini AI Estimate", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
                      ]),
                      Divider(height: 20),
                      Text(_aiResult, style: TextStyle(height: 1.5, color: Colors.black87, fontWeight: _isValidTrash ? FontWeight.w500 : FontWeight.normal)),
                      SizedBox(height: 5),
                      if(_detectedCategory != "General" && _detectedCategory != "Invalid") 
                        Chip(
                          label: Text(_detectedCategory), 
                          backgroundColor: Colors.teal[50], 
                          labelStyle: TextStyle(color: Colors.teal[900], fontWeight: FontWeight.bold),
                          side: BorderSide.none,
                        ),
                    ],
                  ),
            ).animate().fade(delay: 200.ms),
            
            SizedBox(height: 25),
            Text("2. Set Details", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal[800])),
            SizedBox(height: 10),
            TextField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal[900]),
              decoration: InputDecoration(
                labelText: "Expected Price (₹)", 
                prefixIcon: Icon(Icons.currency_rupee, color: Colors.teal),
                filled: true,
                fillColor: Colors.teal.withOpacity(0.05)
              ),
            ),
            SizedBox(height: 15),
            TextField(
              controller: _notesController, 
              maxLines: 2, 
              decoration: InputDecoration(labelText: "Add Notes (Optional)", prefixIcon: Icon(Icons.note_alt_outlined))
            ),
            SizedBox(height: 30),
            
            ElevatedButton.icon(
              onPressed: _submitRequest, 
              icon: Icon(Icons.send_rounded, color: Colors.white),
              label: Text("POST TO MARKET", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal, 
                shadowColor: Colors.tealAccent,
                padding: EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
              ),
            ).animate().fade(delay: 400.ms).slideY(begin: 1, end: 0),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaButton(IconData icon, String label, VoidCallback onTap, Color color) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.circular(20), 
          border: Border.all(color: Colors.grey.shade200), 
          boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 10, offset: Offset(0,4))]
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, 
          children: [
            Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, size: 28, color: color),
            ),
            SizedBox(height: 8), 
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[800]))
          ],
        ),
      ),
    );
  }
}

// ---------------- TAB 2: ACTIVITY (With Cancellation) ---------------- //
class ActivityTab extends StatefulWidget {
  @override
  _ActivityTabState createState() => _ActivityTabState();
}

class _ActivityTabState extends State<ActivityTab> {
  User? get user => FirebaseAuth.instance.currentUser;
  String _searchQuery = "";
  String _selectedCategory = "All";
  bool _showHistory = false;

  void _handleNegotiation(DocumentSnapshot doc, bool accept) async {
    if (accept) {
      await doc.reference.update({'status': 'accepted', 'askPrice': doc['offeredPrice'], 'offeredPrice': FieldValue.delete()});
    } else {
      await doc.reference.update({'status': 'pending', 'offeredPrice': FieldValue.delete(), 'collectorId': FieldValue.delete(), 'collectorName': FieldValue.delete()});
    }
  }

  // NEW: Cancel Request Functionality
  Future<void> _cancelRequest(String docId) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Cancel Request?"),
        content: Text("Are you sure you want to remove this item from the market?"),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(context, false), child: Text("No")),
          TextButton(onPressed: ()=>Navigator.pop(context, true), child: Text("Yes, Cancel", style: TextStyle(color: Colors.red)))
        ],
      )
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('requests').doc(docId).update({'status': 'cancelled'});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Request Cancelled.")));
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
          Text("How was your experience?"),
          SizedBox(height: 10),
          RatingBar.builder(initialRating: 5, minRating: 1, direction: Axis.horizontal, itemCount: 5, itemBuilder: (context, _) => Icon(Icons.star, color: Colors.amber), onRatingUpdate: (rating) { _rating = rating; }),
        ]),
        actions: [TextButton(child: Text("SUBMIT"), onPressed: () async { await FirebaseFirestore.instance.collection('requests').doc(docId).update({'status': 'completed', 'rated': true, 'rating': _rating}); Navigator.pop(context); })],
      ),
    );
  }

  Future<void> _confirmHandover(BuildContext context, DocumentSnapshot doc) async {
    await doc.reference.update({'householdConfirmed': true});
    var fresh = await doc.reference.get();
    bool collConfirmed = fresh['collectorConfirmed'] ?? false;
    bool alreadyRated = fresh['rated'] ?? false;
    if (collConfirmed && !alreadyRated) {
      _showRatingDialog(context, doc.id);
    } else if (!collConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Handover confirmed! Waiting for collector.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) return Center(child: Text("Please log in."));

    return Scaffold(
      appBar: AppBar(
        title: Text("My Activity"),
        centerTitle: true,
        flexibleSpace: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.teal, Colors.teal.shade700]))),
      ),
      body: Column(
        children: [
          Container(
            margin: EdgeInsets.all(16),
            padding: EdgeInsets.all(4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)]),
            child: Row(
              children: [
                Expanded(child: _buildToggleButton("Active", !_showHistory)),
                Expanded(child: _buildToggleButton("History", _showHistory)),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: "Search items...", prefixIcon: Icon(Icons.search),
                    contentPadding: EdgeInsets.symmetric(horizontal: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                    filled: true, fillColor: Colors.white,
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                ),
                SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ["All", "Plastic", "Metal", "E-waste", "Paper", "Glass"].map((cat) {
                      bool isSelected = _selectedCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: FilterChip(
                          label: Text(cat),
                          selected: isSelected,
                          onSelected: (bool s) => setState(() => _selectedCategory = s ? cat : "All"),
                          backgroundColor: Colors.white,
                          selectedColor: Colors.teal[100],
                          labelStyle: TextStyle(color: isSelected ? Colors.teal[900] : Colors.black87),
                          shape: StadiumBorder(side: BorderSide(color: isSelected ? Colors.teal : Colors.transparent)),
                        ),
                      );
                    }).toList(),
                  ),
                )
              ],
            ),
          ),
          
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('requests').where('userId', isEqualTo: user!.uid).orderBy('timestamp', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
                
                var docs = snapshot.data!.docs.where((doc) {
                  var data = doc.data() as Map<String, dynamic>;
                  String status = data['status'];
                  bool isHistory = (status == 'completed' || status == 'cancelled');
                  if (_showHistory != isHistory) return false;
                  String info = data['wasteInfo'].toString().toLowerCase();
                  String cat = (data['category'] ?? "").toString();
                  return info.contains(_searchQuery) && (_selectedCategory == "All" || cat.contains(_selectedCategory));
                }).toList();

                if (docs.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.inbox_outlined, size: 60, color: Colors.grey[300]), SizedBox(height: 10), Text("No requests found.", style: TextStyle(color: Colors.grey))]));

                return ListView.builder(
                  padding: EdgeInsets.fromLTRB(16, 10, 16, 20),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var doc = docs[index];
                    var data = doc.data() as Map<String, dynamic>;
                    String thumbUrl = (data['imageUrls'] != null && (data['imageUrls'] as List).isNotEmpty) ? data['imageUrls'][0] : (data['imageUrl'] ?? "");
                    return _buildActivityCard(doc, data, thumbUrl, data['status']).animate().fade(duration: 400.ms, delay: (50 * index).ms).slideX();
                  }
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton(String text, bool isActive) {
    return GestureDetector(
      onTap: () => setState(() => _showHistory = (text == "History")),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? Colors.teal : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text, style: TextStyle(fontWeight: FontWeight.bold, color: isActive ? Colors.white : Colors.grey)),
      ),
    );
  }

  Widget _buildActivityCard(DocumentSnapshot doc, Map<String, dynamic> data, String thumbUrl, String status) {
    Color statusColor = _getStatusColor(status);
    bool houseConfirmed = data['householdConfirmed'] ?? false;
    bool collectorConfirmed = data['collectorConfirmed'] ?? false;
    bool isRated = data['rated'] ?? false;

    return Card(
      margin: EdgeInsets.only(bottom: 16),
      elevation: 4,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FullHistoryScreen(data: data))),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Container(
                    width: 70, height: 70,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.grey[200]),
                    child: thumbUrl.isNotEmpty 
                      ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(thumbUrl, fit: BoxFit.cover)) 
                      : Icon(Icons.recycling, color: Colors.grey),
                  ),
                  SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(data['wasteInfo'].toString().split('|')[0], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                        SizedBox(height: 5),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(5)),
                          child: Text(status.toUpperCase(), style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("₹${data['askPrice']}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.teal, decoration: status == 'negotiating' ? TextDecoration.lineThrough : null)),
                      if(status == 'negotiating') Text("Offer: ₹${data['offeredPrice']}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red)),
                    ],
                  )
                ],
              ),
            ),
            
            // --- ACTION BUTTONS ---

            // 1. Cancel Button (Only for Pending/Negotiating)
            if (status == 'pending' || status == 'negotiating')
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: Icon(Icons.delete_outline, size: 18, color: Colors.red),
                        label: Text("CANCEL POST", style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.red.withOpacity(0.5))),
                        onPressed: () => _cancelRequest(doc.id),
                      ),
                    ),
                  ],
                ),
              ),

            // 2. Negotiation UI
            if (status == 'negotiating')
              Container(
                decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.vertical(bottom: Radius.circular(16))),
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(child: Text("Counter Offer Received", style: TextStyle(color: Colors.orange[900], fontWeight: FontWeight.bold))),
                    TextButton(onPressed: () => _handleNegotiation(doc, true), child: Text("ACCEPT"), style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.green)),
                    SizedBox(width: 8),
                    TextButton(onPressed: () => _handleNegotiation(doc, false), child: Text("REJECT"), style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.red)),
                  ],
                ),
              ),
            
            // 3. Confirm Handover
            if (status == 'accepted' && !houseConfirmed)
               Padding(
                 padding: const EdgeInsets.all(12.0),
                 child: ElevatedButton.icon(
                    icon: Icon(Icons.check_circle, size: 18, color: Colors.white),
                    label: Text("CONFIRM HANDOVER", style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: EdgeInsets.symmetric(vertical: 12), minimumSize: Size(double.infinity, 45)),
                    onPressed: () => _confirmHandover(context, doc),
                 ),
               ),

             // 4. Waiting for Collector
             if (status == 'accepted' && houseConfirmed && !collectorConfirmed)
                Container(
                   width: double.infinity, padding: EdgeInsets.all(10),
                   decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.vertical(bottom: Radius.circular(16))),
                   child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.hourglass_empty, size: 16, color: Colors.orange[800]), SizedBox(width: 5), Text("Waiting for collector confirmation...", style: TextStyle(color: Colors.orange[800]))])),
                ),

              // 5. Rate Collector
              if (status == 'accepted' && houseConfirmed && collectorConfirmed && !isRated)
                 Padding(
                   padding: const EdgeInsets.all(12.0),
                   child: ElevatedButton.icon(
                      icon: Icon(Icons.star, size: 18, color: Colors.black),
                      label: Text("RATE COLLECTOR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, padding: EdgeInsets.symmetric(vertical: 12), minimumSize: Size(double.infinity, 45)),
                      onPressed: () => _showRatingDialog(context, doc.id),
                   ),
                 ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed': return Colors.green;
      case 'negotiating': return Colors.orange;
      case 'accepted': return Colors.blue;
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }
}

// ---------------- TAB 3: PROFILE (With Validations) ---------------- //
class ProfileTab extends StatefulWidget {
  @override
  _ProfileTabState createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  User? get user => FirebaseAuth.instance.currentUser;
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isEditing = false;

  @override
  void initState() { super.initState(); _loadUserData(); }

  Future<void> _loadUserData() async {
    final currentUser = user;
    if (currentUser == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
      if (doc.exists && mounted) {
        setState(() {
          _nameController.text = doc.data()?['name'] ?? currentUser.displayName ?? "";
          _phoneController.text = doc.data()?['phone'] ?? "";
        });
      }
    } catch (e) {}
  }

  Future<void> _saveProfile() async {
    final currentUser = user;
    if (currentUser == null) return;
    
    // --- VALIDATION ---
    String name = _nameController.text.trim();
    String phone = _phoneController.text.trim();

    if (name.isEmpty) { 
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text("Name cannot be empty"))); 
      return; 
    }
    
    // Check if phone number is exactly 10 digits and numeric
    RegExp phoneRegExp = RegExp(r'^\d{10}$');
    if (!phoneRegExp.hasMatch(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red, 
        content: Text("Phone number must be exactly 10 digits (0-9).")
      )); 
      return; 
    }
    
    try {
      await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).set({
        'name': name,
        'phone': phone,
        'email': currentUser.email,
        'role': 'household',
      }, SetOptions(merge: true));
      
      if (name.isNotEmpty) await currentUser.updateDisplayName(name);
      
      setState(() => _isEditing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.green, content: Text("Profile Updated Successfully!")));
    } catch(e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error saving profile: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = user;
    if (currentUser == null) return Center(child: CircularProgressIndicator());

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.teal, Colors.teal.shade800]),
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
                  ),
                ),
                Positioned(top: 50, right: 20, child: IconButton(icon: Icon(Icons.logout, color: Colors.white), onPressed: () => FirebaseAuth.instance.signOut())),
                Positioned(
                  bottom: -50,
                  child: Container(
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4), boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)]),
                    child: CircleAvatar(
                      radius: 50, backgroundColor: Colors.white,
                      child: Text(currentUser.displayName != null && currentUser.displayName!.isNotEmpty ? currentUser.displayName![0].toUpperCase() : "U", style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.teal)),
                    ),
                  ),
                ),
              ],
            ),
            
            SizedBox(height: 60),
            Text(currentUser.displayName ?? "User", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
            Text(currentUser.email ?? "", style: TextStyle(color: Colors.grey)),
            SizedBox(height: 20),
            
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('requests').where('userId', isEqualTo: currentUser.uid).snapshots(),
              builder: (context, snapshot) {
                if(!snapshot.hasData) return SizedBox();
                int total = snapshot.data!.docs.length;
                int completed = snapshot.data!.docs.where((d) => d['status'] == 'completed').length;
                return Row(mainAxisAlignment: MainAxisAlignment.center, children: [_statBox("Requests", "$total"), SizedBox(width: 20), _statBox("Sold", "$completed")]);
              },
            ),

            Padding(
              padding: EdgeInsets.all(25),
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Personal Details", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), IconButton(icon: Icon(_isEditing ? Icons.save : Icons.edit, color: Colors.teal), onPressed: _isEditing ? _saveProfile : () => setState(() => _isEditing = true))]),
                      Divider(),
                      SizedBox(height: 10),
                      _buildProfileField(_nameController, "Full Name", Icons.person, TextInputType.name),
                      SizedBox(height: 15),
                      _buildProfileField(_phoneController, "Phone Number", Icons.phone, TextInputType.phone),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBox(String label, String value) {
    return Container(
      width: 110, padding: EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
      child: Column(children: [Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.teal)), Text(label, style: TextStyle(color: Colors.grey, fontSize: 12))]),
    );
  }

  Widget _buildProfileField(TextEditingController controller, String label, IconData icon, TextInputType type) {
    return TextField(
      controller: controller, 
      enabled: _isEditing,
      keyboardType: type,
      maxLength: type == TextInputType.phone ? 10 : null, // Limit UI length
      decoration: InputDecoration(
        labelText: label, 
        prefixIcon: Icon(icon, color: Colors.teal), 
        filled: true, 
        fillColor: _isEditing ? Colors.teal.withOpacity(0.05) : Colors.grey[100], 
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        counterText: "" // Hide character counter
      ),
    );
  }
}

class FullHistoryScreen extends StatelessWidget {
  final Map<String, dynamic> data;
  FullHistoryScreen({required this.data});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Details"), flexibleSpace: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.teal, Colors.teal.shade700])))),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20), 
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if(data['imageUrl'] != null) ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.network(data['imageUrl'], height: 250, width: double.infinity, fit: BoxFit.cover)),
          SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                     Text("Status", style: TextStyle(color: Colors.grey)),
                     Text(data['status'].toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                   ]),
                   Divider(height: 30),
                   Text("Item Details", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                   SizedBox(height: 10),
                   Text(data['wasteInfo'].toString(), style: TextStyle(height: 1.4)),
                   SizedBox(height: 20),
                   Text("Selling Price", style: TextStyle(color: Colors.grey)),
                   Text("₹${data['askPrice']}", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green)),
                ],
              ),
            ),
          )
        ])),
    );
  }
}