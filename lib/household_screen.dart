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

// ------------------------------------------------------------------
// ⚠️ IMPORTANT: PASTE YOUR KEYS HERE FOR DEPLOYMENT TO WORK
// ------------------------------------------------------------------      // e.g. "sk-or-v1-..."
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

// ---------------- TAB 1: SELL WASTE ---------------- //
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

  final String modelName = "nvidia/nemotron-nano-12b-v2-vl:free";

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
        if (!_isAnalyzing && _imageBytesList.isNotEmpty) {
           _analyzeWithNvidia(_imageBytesList.first);
        }
      }
    } else {
      final XFile? photo = await picker.pickImage(source: ImageSource.camera);
      if (photo != null) {
        var bytes = await photo.readAsBytes();
        setState(() {
          _pickedFiles.add(photo);
          _imageBytesList.add(bytes);
        });
        if (!_isAnalyzing) {
           _analyzeWithNvidia(bytes);
        }
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      _imageBytesList.removeAt(index);
      _pickedFiles.removeAt(index);
    });
  }

  Future<void> _analyzeWithNvidia(Uint8List imageBytes) async {
    // 1. Check Key
    if (OPENROUTER_API_KEY.contains("YOUR_") || OPENROUTER_API_KEY.isEmpty) {
      setState(() => _aiResult = "Error: OpenRouter API Key not set in code.");
      return;
    }

    setState(() => _isAnalyzing = true);

    try {
      String base64Image = base64Encode(imageBytes);
      final response = await http.post(
        Uri.parse("https://openrouter.ai/api/v1/chat/completions"),
        headers: { 
          "Authorization": "Bearer $OPENROUTER_API_KEY", 
          "Content-Type": "application/json",
          "HTTP-Referer": "https://waste-market.web.app", // Optional: Your site URL
          "X-Title": "Waste Market", // Optional: Your app name
        },
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
          try { 
            var parts = content.split("Category:");
            if(parts.length > 1) cat = parts[1].split("|")[0].trim(); 
          } catch(e) {}
        }
        setState(() { _aiResult = content; _detectedCategory = cat; _isAnalyzing = false; });
      } else {
        setState(() { _aiResult = "AI Error (${response.statusCode}). Check Quota/Key."; _isAnalyzing = false; });
      }
    } catch (e) { 
      setState(() { _aiResult = "Connection Error: $e"; _isAnalyzing = false; }); 
    }
  }

  Future<void> _submitRequest() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("You must be logged in!")));
      return;
    }

    // 2. Check Cloudinary Keys
    if (CLOUDINARY_CLOUD_NAME.contains("YOUR_") || CLOUDINARY_UPLOAD_PRESET.contains("YOUR_")) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: Cloudinary keys not set in code!")));
      return;
    }

    if (_imageBytesList.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("No images!"))); return; }
    if (_priceController.text.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Please enter a selling price!"))); return; }

    setState(() => _isAnalyzing = true);

    try {
      List<String> uploadedUrls = [];

      // UPLOAD IMAGES
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
          var jsonMap = jsonDecode(responseData);
          uploadedUrls.add(jsonMap['secure_url']);
        } else {
          print("Upload Failed: ${response.statusCode}");
        }
      }

      if (uploadedUrls.isEmpty) {
        throw Exception("Image upload failed. Check Cloudinary settings.");
      }

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
        'imageUrl': uploadedUrls.first, // Legacy support
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
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImages(ImageSource.camera),
                    icon: Icon(Icons.camera_alt),
                    label: Text("Camera"),
                    style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 15), backgroundColor: Colors.blue[50]),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImages(ImageSource.gallery),
                    icon: Icon(Icons.photo_library),
                    label: Text("Gallery"),
                    style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 15), backgroundColor: Colors.blue[50]),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            
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
                          margin: EdgeInsets.only(right: 10, top: 10),
                          width: 100, height: 100,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.memory(_imageBytesList[index], fit: BoxFit.cover),
                          ),
                        ),
                        Positioned(
                          right: 0, top: 0,
                          child: GestureDetector(
                            onTap: () => _removeImage(index),
                            child: CircleAvatar(
                              radius: 12, backgroundColor: Colors.red,
                              child: Icon(Icons.close, size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

            if (_imageBytesList.isEmpty)
              Container(
                height: 100, width: double.infinity,
                margin: EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(10)),
                child: Center(child: Text("No images selected", style: TextStyle(color: Colors.grey))),
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

// ---------------- TAB 2: ACTIVITY ---------------- //
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
      await doc.reference.update({
        'status': 'accepted',
        'askPrice': doc['offeredPrice'],
        'offeredPrice': FieldValue.delete(),
      });
    } else {
      await doc.reference.update({
        'status': 'pending',
        'offeredPrice': FieldValue.delete(),
        'collectorId': FieldValue.delete(),
        'collectorName': FieldValue.delete(),
      });
    }
  }

  Future<void> _cancelRequest(String docId) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Cancel Request?"),
        content: Text("Are you sure you want to remove this listing?"),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(context, false), child: Text("No")),
          TextButton(onPressed: ()=>Navigator.pop(context, true), child: Text("Yes, Cancel")),
        ],
      )
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('requests').doc(docId).update({
        'status': 'cancelled'
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Request Cancelled")));
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
    final currentUser = user;
    if (currentUser == null) return Center(child: Text("Please log in."));

    return Scaffold(
      appBar: AppBar(title: Text("My Activity"), centerTitle: true),
      body: Column(
        children: [
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
          
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('requests')
                .where('userId', isEqualTo: currentUser.uid)
                .orderBy('timestamp', descending: true)
                .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
                
                var docs = snapshot.data!.docs.where((doc) {
                  var data = doc.data() as Map<String, dynamic>;
                  String status = data['status'];
                  
                  bool isHistory = (status == 'completed' || status == 'cancelled');
                  if (_showHistory != isHistory) return false;

                  String info = data['wasteInfo'].toString().toLowerCase();
                  String cat = (data['category'] ?? "").toString();
                  bool matchesSearch = info.contains(_searchQuery);
                  bool matchesCategory = _selectedCategory == "All" || cat.contains(_selectedCategory);
                  
                  return matchesSearch && matchesCategory;
                }).toList();

                if (docs.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.inbox, size: 50, color: Colors.grey), Text("No requests found.")]));

                return ListView(
                  children: docs.map((doc) {
                    var data = doc.data() as Map<String, dynamic>;
                    String status = data['status'];
                    String price = data['askPrice'] ?? "??";
                    String offeredPrice = data['offeredPrice'] ?? "";
                    
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
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(5), 
                                  child: Image.network(
                                    thumbUrl, width: 60, height: 60, fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Icon(Icons.broken_image, size: 40, color: Colors.grey),
                                  )
                                ) 
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

                          if (status == 'pending' || status == 'negotiating')
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: OutlinedButton.icon(
                                icon: Icon(Icons.cancel, size: 16),
                                label: Text("CANCEL REQUEST"),
                                style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: BorderSide(color: Colors.red)),
                                onPressed: () => _cancelRequest(doc.id),
                              ),
                            ),

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
      case 'cancelled': return Colors.grey;
      default: return Colors.orange;
    }
  }
}

class FullHistoryScreen extends StatefulWidget {
  final Map<String, dynamic> data;
  FullHistoryScreen({required this.data});

  @override
  _FullHistoryScreenState createState() => _FullHistoryScreenState();
}

class _FullHistoryScreenState extends State<FullHistoryScreen> {
  int _currentImageIndex = 0;

  @override
  Widget build(BuildContext context) {
    String price = widget.data['askPrice'] ?? "N/A";
    List<String> images = [];
    if (widget.data['imageUrls'] != null) {
      images = List<String>.from(widget.data['imageUrls']);
    } else if (widget.data['imageUrl'] != null) {
      images = [widget.data['imageUrl']];
    }

    return Scaffold(
      appBar: AppBar(title: Text("Details")),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
              child: Text(widget.data['wasteInfo'] ?? ""),
            ),
            SizedBox(height: 10),
            Text("Category: ${widget.data['category'] ?? 'General'}"),
            Divider(),
            Text("Collector Info:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text("Name: ${widget.data['collectorName'] ?? 'Pending'}"),
            Text("Phone: ${widget.data['collectorPhone'] ?? 'Not Available'}"), 
            if (widget.data.containsKey('rating')) Text("Your Rating: ${widget.data['rating']} ⭐"),
            SizedBox(height: 20),
            Center(child: Text("Status: ${widget.data['status'].toUpperCase()}", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16))),
          ],
        ),
      ),
    );
  }
}

// ---------------- TAB 3: PROFILE ---------------- //
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
  void initState() {
    super.initState();
    _loadUserData();
  }

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
      } else {
        if (mounted) _nameController.text = currentUser.displayName ?? "";
      }
    } catch (e) { print(e); }
  }

  Future<void> _saveProfile() async {
    final currentUser = user;
    if (currentUser == null) return;

    await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).set({
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'email': currentUser.email,
      'role': 'household',
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
    if (cleanName.isEmpty) return "U";
    List<String> parts = cleanName.split(RegExp(r"\s+"));
    String first = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0][0] : "";
    String second = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : "";
    return (first + second).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = user;
    if (currentUser == null) return Center(child: CircularProgressIndicator());

    String displayName = _nameController.text.isNotEmpty ? _nameController.text : (currentUser.displayName ?? "User");
    String initials = _getSafeInitials(displayName);

    return Scaffold(
      appBar: AppBar(title: Text("My Profile"), actions: [IconButton(icon: Icon(_isEditing ? Icons.save : Icons.edit), onPressed: _isEditing ? _saveProfile : () => setState(() => _isEditing = true))]),
      body: SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(height: 20),
            CircleAvatar(radius: 50, backgroundColor: Colors.green[100], child: Text(initials, style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.green[800]))),
            SizedBox(height: 20),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('requests').where('userId', isEqualTo: currentUser.uid).snapshots(),
              builder: (context, snapshot) {
                if(!snapshot.hasData) return SizedBox();
                int total = snapshot.data!.docs.length;
                int completed = snapshot.data!.docs.where((d) => d['status'] == 'completed').length;
                return Row(mainAxisAlignment: MainAxisAlignment.center, children: [_statCard("Requests", "$total"), SizedBox(width: 20), _statCard("Sold", "$completed")]);
              },
            ),
            SizedBox(height: 20),
            Padding(padding: EdgeInsets.all(20), child: Column(children: [
              TextField(controller: _nameController, enabled: _isEditing, decoration: InputDecoration(labelText: "Full Name", prefixIcon: Icon(Icons.person), border: OutlineInputBorder())),
              SizedBox(height: 15),
              TextField(controller: _phoneController, enabled: _isEditing, decoration: InputDecoration(labelText: "Phone Number", prefixIcon: Icon(Icons.phone), border: OutlineInputBorder())),
              SizedBox(height: 15),
              TextField(enabled: false, controller: TextEditingController(text: currentUser.email), decoration: InputDecoration(labelText: "Email", prefixIcon: Icon(Icons.email), border: OutlineInputBorder())),
            ])),
            SizedBox(height: 20),
            ElevatedButton(onPressed: () => FirebaseAuth.instance.signOut(), child: Text("Logout"), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white))
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value) {
    return Container(padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15), decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(10)), child: Column(children: [Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), Text(label)]));
  }
}