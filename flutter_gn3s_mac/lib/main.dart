import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math' as math;

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'S\u{2084} Computed Maps',
      debugShowCheckedModeBanner: false, // ปิดป้าย debug มุมขวาบน
      theme: ThemeData(primaryColor: Colors.blue[900]),
      home: SatelliteMapPage(),
      // Scaffold(body: Center(child: Text('ดร.สมกิจ โสพันธ์'))),
    );
  }
}

// สร้าง StatefulWidget เพื่อให้หน้าจอสามารถอัปเดตตัวเลขสถานะซูมได้
class SatelliteMapPage extends StatefulWidget {
  const SatelliteMapPage({super.key});

  @override
  State<SatelliteMapPage> createState() => _SatelliteMapPageState();
}

// 1. สร้าง Model สำหรับเก็บข้อมูลดาวเทียม
class SatelliteData {
  final String prn; // รหัสดาวเทียม เช่น G01, R05
  LatLng position; // พิกัดปัจจุบัน
  int status; // สถานะ:1=Low,2=Medium,3=High (ใช้สำหรับกำหนดสี)

  SatelliteData({
    required this.prn,
    required this.position,
    required this.status,
  });
}

class _SatelliteMapPageState extends State<SatelliteMapPage> {
  //สร้าง MapController สำหรับเป็นรีโมทสั่งงานแผนที่
  final MapController _mapController = MapController();
  final List<int> _scaleLevelsKm = [
    10,
    20,
    50,
    100,
    150,
    200,
    250,
    300,
    350,
    400,
    450,
    500,
    600,
    700,
    800,
    900,
    1000,
  ];
  // กำหนดความกว้างของสเกลบาร์ที่ 100 พิกเซล
  final double _scaleBarWidthPixels = 100.0;
  // เตรียม List สำหรับเก็บข้อมูลดาวเทียมจำลอง
  final List<SatelliteData> _satellites = [];

  //กำหนดตัวแปรเก็บค่าระดับซูมปัจจุบัน
  double _currentZoom = 4.91; // ค่าเริ่มต้นที่คำนวณมาให้สำหรับ 500 km
  double _currentLat = 13.8600; // ตัวแปรเก็บละติจูดใช้คำนวณสเกล

  // ตัวแปรสำหรับแถบเวลา
  DateTime _currentTime = DateTime.now(); // เวลาเริ่มต้น
  double _timeSliderValue = 0.0; // ค่าของ Slider (0.0 ถึง 100.0)
  bool _isPlaying = false; // สถานะการเล่น Animation เวลา

  @override
  void initState() {
    super.initState();
    // คำนวณระดับซูมเริ่มต้นสำหรับ 500 km
    _currentZoom = _calculateZoomForScale(500, _currentLat);
    _generateMockSatellites();
  }

  // ฟังก์ชันคำนวณหาระดับ Zoom จากระยะทางกิโลเมตรที่ต้องการ
  double _calculateZoomForScale(int targetScaleKm, double latitude) {
    double distanceMeters = targetScaleKm * 1000.0;
    double resolution = distanceMeters / _scaleBarWidthPixels;
    // ใช้สูตร Log2 คำนวณย้อนกลับหาค่า Zoom
    double zoom =
        math.log(156543.03 * math.cos(latitude * math.pi / 180) / resolution) /
        math.ln2;
    return zoom;
  }

  // ฟังก์ชันซูมเข้า
  void _zoomIn() {
    double currentDistanceKm = _getCurrentDistanceKm();
    int targetScale = _scaleLevelsKm.first;

    // หาค่าสเกลที่เล็กกว่าค่าปัจจุบัน
    for (int i = _scaleLevelsKm.length - 1; i >= 0; i--) {
      if (_scaleLevelsKm[i] < currentDistanceKm - 1) {
        // -1 เผื่อทศนิยมคลาดเคลื่อน
        targetScale = _scaleLevelsKm[i];
        break;
      }
    }
    _applyScale(targetScale);
  }

  // ฟังก์ชันซูมออก
  void _zoomOut() {
    double currentDistanceKm = _getCurrentDistanceKm();
    int targetScale = _scaleLevelsKm.last;

    // หาค่าสเกลที่ใหญ่กว่าค่าปัจจุบัน
    for (int i = 0; i < _scaleLevelsKm.length; i++) {
      if (_scaleLevelsKm[i] > currentDistanceKm + 1) {
        // +1 เผื่อทศนิยมคลาดเคลื่อน
        targetScale = _scaleLevelsKm[i];
        break;
      }
    }
    _applyScale(targetScale);
  }

  // สั่งให้แผนที่ซูมไปยังสเกลที่คำนวณได้
  void _applyScale(int scaleKm) {
    double newZoom = _calculateZoomForScale(scaleKm, _currentLat);
    _mapController.move(_mapController.camera.center, newZoom);
  }

  // คำนวณระยะทางปัจจุบัน (เพื่อแสดงบนสเกลบาร์และใช้เปรียบเทียบ)
  double _getCurrentDistanceKm() {
    double resolution =
        156543.03 *
        math.cos(_currentLat * math.pi / 180) /
        math.pow(2, _currentZoom);
    double distanceMeters = resolution * _scaleBarWidthPixels;
    return distanceMeters / 1000.0;
  }

  // 2. ฟังก์ชันคำนวณระยะทางสำหรับสเกลบาร์
  String _getScaleText() {
    double distanceKm = _getCurrentDistanceKm();
    // ถ้าตัวเลขใกล้เคียงสเกลที่ตั้งไว้มากๆ ให้ปัดเศษให้สวยงาม (เช่น 499.8 -> 500)
    for (int scale in _scaleLevelsKm) {
      if ((distanceKm - scale).abs() < 5) {
        return '$scale km';
      }
    }
    // ถ้าผู้ใช้ใช้นิ้วซูมเองจนได้สเกลแปลกๆ ให้แสดงตามจริง
    return '${distanceKm.toStringAsFixed(1)} km';
  }

  // ฟังก์ชันสร้างข้อมูลดาวเทียมจำลองรอบๆ ประเทศไทย
  void _generateMockSatellites() {
    _satellites.addAll([
      SatelliteData(prn: 'G01', position: const LatLng(16.5, 100.0), status: 1),
      SatelliteData(prn: 'G08', position: const LatLng(18.8, 99.0), status: 2),
      SatelliteData(prn: 'R05', position: const LatLng(14.0, 102.5), status: 1),
      SatelliteData(prn: 'E12', position: const LatLng(8.5, 99.5), status: 3),
      SatelliteData(prn: 'G23', position: const LatLng(15.0, 105.0), status: 1),
      SatelliteData(prn: 'C03', position: const LatLng(12.0, 97.0), status: 2),
    ]);
  }

  // ฟังก์ชันช่วยเลือกสีจากค่า status
  Color _getStatusColor(int status) {
    switch (status) {
      case 1:
        return const Color.fromARGB(255, 59, 130, 246);
      case 2:
        return const Color.fromARGB(255, 251, 191, 36);
      case 3:
        return const Color.fromARGB(255, 239, 68, 68);
      default:
        return const Color.fromARGB(255, 128, 128, 128);
    }
  }

  // ฟังก์ชันสร้าง Legend อธิบายสัญลักษณ์สี
  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 0),
          _buildLegendItem(Color.fromARGB(255, 59, 130, 246), 'Low'),
          const SizedBox(width: 8),
          _buildLegendItem(Color.fromARGB(255, 251, 191, 36), 'Medium'),
          const SizedBox(width: 8),
          _buildLegendItem(Color.fromARGB(255, 239, 68, 68), 'High'),
          const SizedBox(width: 0),
        ],
      ),
    );
  }

  // ฟังก์ชันย่อยสำหรับสร้างบรรทัดใน Legend
  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1),
          ),
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  // ฟังก์ชันสร้างแถบเวลาด้านล่าง
  Widget _buildTimeBar() {
    // จัดฟอร์แมตวันที่แบบง่ายๆ (DD/MM/YYYY HH:MM:SS)
    String formattedDate =
        '${_currentTime.day.toString().padLeft(2, '0')}/${_currentTime.month.toString().padLeft(2, '0')}/${_currentTime.year} '
        '${_currentTime.hour.toString().padLeft(2, '0')}:${_currentTime.minute.toString().padLeft(2, '0')}:${_currentTime.second.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 6,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // ปุ่ม Play/Pause
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
            ),
            color: Colors.blue[900],
            iconSize: 36,
            onPressed: () {
              setState(() {
                _isPlaying = !_isPlaying;
                // (ในอนาคตเราจะใส่ Timer สำหรับให้เวลาเดินอัตโนมัติที่นี่)
              });
            },
          ),
          // แถบเลื่อน (Slider)
          Expanded(
            child: Slider(
              value: _timeSliderValue,
              min: 0.0,
              max: 100.0,
              activeColor: Colors.blue[900],
              inactiveColor: Colors.blue[200],
              onChanged: (value) {
                setState(() {
                  _timeSliderValue = value;
                  // จำลองการเปลี่ยนเวลาเมื่อเลื่อน Slider (เช่น เลื่อน 1% = เปลี่ยน 10 นาที)
                  _currentTime = DateTime.now().add(
                    Duration(minutes: (value * 10).toInt()),
                  );
                });
              },
            ),
          ),
          // ข้อความแสดงเวลา
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Text(
              formattedDate,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue[900],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ส่วนที่ 1: แผนที่
          FlutterMap(
            mapController: _mapController, // ใส่ Controller ให้แผนที่
            options: MapOptions(
              initialCenter: const LatLng(
                13.4500,
                100.5200,
              ), // จุดศูนย์กลางของแผนที่ (ประเทศไทย)
              initialZoom: _currentZoom,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
              // 3. ดักจับเหตุการณ์เมื่อแผนที่ถูกซูมหรือเลื่อนด้วยเมาส์/นิ้ว
              onPositionChanged: (camera, hasGesture) {
                setState(() {
                  _currentZoom = camera.zoom; // อัปเดตตัวเลขซูม
                  _currentLat = camera
                      .center
                      .latitude; // อัปเดตละติจูดทุกครั้งที่ขยับแผนที่
                });
              },
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
              // วาดจุดดาวเทียม (MarkerLayer) ซ้อนบนแผนที่
              MarkerLayer(
                markers: _satellites.map((sat) {
                  return Marker(
                    point: sat.position,
                    width: 30, // ความกว้างของจุด
                    height: 30, // ความสูงของจุด
                    child: Container(
                      decoration: BoxDecoration(
                        color: _getStatusColor(
                          sat.status,
                        ).withValues(alpha: 0.8), // สีพื้นหลังโปร่งแสงนิดๆ
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white, // ขอบสีขาวให้จุดดูโดดเด่น
                          width: 1,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          sat.prn, // แสดงรหัส PRN
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          // 2. Legend (อยู่มุมซ้ายล่าง ลอยขึ้นมาเหนือ Time Bar)
          Positioned(
            left: 20,
            bottom: 90, // เว้นที่ให้ Time Bar
            child: _buildLegend(),
          ),
          // ส่วนที่ 2: UI ควบคุมการซูม (วางทับบนแผนที่มุมขวาล่าง)
          Positioned(
            right: 20,
            bottom: 90,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // กลุ่มปุ่มกด ซูมเข้า/ออก
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: _zoomIn,
                        tooltip: 'Zoom In',
                        color: Colors.black87,
                      ),
                      const Divider(
                        height: 1,
                        thickness: 1,
                        indent: 8,
                        endIndent: 8,
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: _zoomOut,
                        tooltip: 'Zoom Out',
                        color: Colors.black87,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8), // เว้นระยะห่างระหว่างปุ่มกับสเกลบาร์
                // สเกลบาร์
                Container(
                  padding: const EdgeInsets.only(
                    left: 8,
                    right: 8,
                    top: 4,
                    bottom: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        _getScaleText(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        width: _scaleBarWidthPixels,
                        height: 6,
                        decoration: const BoxDecoration(
                          border: Border(
                            left: BorderSide(color: Colors.black54, width: 2),
                            right: BorderSide(color: Colors.black54, width: 2),
                            bottom: BorderSide(color: Colors.black54, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 4. แถบควบคุมเวลา (Time Bar) ยึดติดขอบล่างสุด
          Positioned(left: 0, right: 0, bottom: 0, child: _buildTimeBar()),
        ],
      ),
    );
  }
}
