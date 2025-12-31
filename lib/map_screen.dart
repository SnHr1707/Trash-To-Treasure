import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class MapScreen extends StatefulWidget {
  final double targetLat;
  final double targetLong;
  final bool isPrivacyMode; // True = Show Circle, False = Show Route

  MapScreen({
    required this.targetLat, 
    required this.targetLong, 
    this.isPrivacyMode = false
  });

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  LatLng? myLocation;
  List<LatLng> routePoints = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeMap();
  }

  Future<void> _initializeMap() async {
    try {
      Position pos = await Geolocator.getCurrentPosition();
      setState(() => myLocation = LatLng(pos.latitude, pos.longitude));

      // Only calculate route if we are NOT in privacy mode (i.e., Job Accepted)
      if (!widget.isPrivacyMode) {
        await _getRoute(myLocation!, LatLng(widget.targetLat, widget.targetLong));
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      // Fallback for emulator/error
      setState(() {
        myLocation = LatLng(widget.targetLat - 0.01, widget.targetLong - 0.01);
        isLoading = false;
      });
    }
  }

  Future<void> _getRoute(LatLng start, LatLng end) async {
    final url = Uri.parse(
        'http://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};'
        '${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final geometry = data['routes'][0]['geometry']['coordinates'] as List;
        setState(() {
          routePoints = geometry.map((p) => LatLng(p[1].toDouble(), p[0].toDouble())).toList();
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading || myLocation == null) return Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isPrivacyMode ? "General Region" : "Navigate to Pickup"),
        backgroundColor: widget.isPrivacyMode ? Colors.orange : Colors.green,
      ),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: widget.isPrivacyMode 
              ? LatLng(widget.targetLat, widget.targetLong) // Center on trash
              : myLocation!, // Center on me
          initialZoom: 13
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.trashtotreasure.app',
          ),
          
          // 1. PRIVACY MODE: Show Circle Only
          if (widget.isPrivacyMode)
            CircleLayer(
              circles: [
                CircleMarker(
                  point: LatLng(widget.targetLat, widget.targetLong),
                  color: Colors.red.withOpacity(0.3),
                  borderColor: Colors.red,
                  borderStrokeWidth: 2,
                  radius: 500, // 500 meter radius (Approx location)
                )
              ],
            ),

          // 2. NAVIGATION MODE: Show Route & Exact Marker
          if (!widget.isPrivacyMode) ...[
            PolylineLayer(
              polylines: [Polyline(points: routePoints, strokeWidth: 5.0, color: Colors.blue)],
            ),
            MarkerLayer(
              markers: [
                Marker(point: myLocation!, child: Icon(Icons.navigation, color: Colors.blue, size: 40)),
                Marker(point: LatLng(widget.targetLat, widget.targetLong), child: Icon(Icons.location_on, color: Colors.red, size: 40)),
              ],
            ),
          ]
        ],
      ),
    );
  }
}