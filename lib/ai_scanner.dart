import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class AIScannerPage extends StatefulWidget {
  @override
  _AIScannerPageState createState() => _AIScannerPageState();
}

class _AIScannerPageState extends State<AIScannerPage> {
  final ImagePicker _picker = ImagePicker();
  File? _image;
  String? _result;
  bool _isLoading = false;

  // Initialize Gemini
  final model = GenerativeModel(
    model: 'gemini-1.5-flash', 
    apiKey: '',
  );

  Future<void> _analyzeImage() async {
    final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
    if (photo != null) {
      setState(() { _image = File(photo.path); _isLoading = true; });

      // 🚀 FEATURE: Multimodal AI Analysis
      final imageBytes = await _image!.readAsBytes();
      final prompt = TextPart("Identify this waste item. Is it E-waste, plastic, or battery? Estimate its scrap value in USD or INR. Keep it short.");
      final imagePart = DataPart('image/jpeg', imageBytes);

      final response = await model.generateContent([
        Content.multi([prompt, imagePart])
      ]);

      setState(() {
        _result = response.text;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Scan Waste")),
      body: Column(
        children: [
          if (_image != null) Image.file(_image!, height: 300),
          SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _analyzeImage,
            icon: Icon(Icons.camera_alt),
            label: Text("Snap & Price"),
          ),
          if (_isLoading) CircularProgressIndicator(),
          if (_result != null) Padding(
            padding: EdgeInsets.all(16),
            child: Text(_result!, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
