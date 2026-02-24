import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GNSS Monitor',
      debugShowCheckedModeBanner: false, // ปิดป้าย debug มุมขวาบน
      theme: ThemeData(primaryColor: Colors.blue[900]),
      home: SatelliteMapPage(),
      // Scaffold(body: Center(child: Text('ดร.สมกิจ โสพันธ์'))),
    );
  }
}

// class MyApp extends StatelessWidget {
//   const MyApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'GNSS Monitor',
//       debugShowCheckedModeBanner: false, // ปิดป้าย debug มุมขวาบน
//       theme: ThemeData(primaryColor: Colors.blue[900]),
//       home: const SatelliteMapPage(), // เรียกใช้งานหน้าแผนที่ตรงนี้ครับ
//     );
//   }
// }

class SatelliteMapPage extends StatelessWidget {
  const SatelliteMapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GNSS Satellite Monitor'),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
      ),
      // ใช้ Stack เพื่อเตรียมวาง UI ควบคุมซ้อนบนแผนที่ในภายหลัง
      body: Stack(
        children: [
          FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(
                15.8700,
                100.9925,
              ), // พิกัดกึ่งกลางประเทศไทย
              initialZoom: 5.0, // ระดับการซูมเริ่มต้น
              // เปิดใช้งานการโต้ตอบทั้งหมด เช่น เลื่อน (Pan) และ ซูม (Zoom)
              interactionOptions: InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              // เลเยอร์สำหรับแสดงภาพแผนที่จาก OpenStreetMap
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                subdomains: const [
                  'a',
                  'b',
                  'c',
                  'd',
                ], // ตัวแปรสำหรับ {s} เพื่อโหลดภาพได้เร็วขึ้น
                userAgentPackageName: 'com.example.gnss_monitor',
              ),
              // TODO: เราจะเพิ่ม MarkerLayer สำหรับวาดจุดดาวเทียมที่นี่ในสเตปต่อไป
            ],
          ),
        ],
      ),
    );
  }
}
