import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

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
  final String sv; // รหัสดาวเทียม เช่น G01, R05
  LatLng position; // พิกัดปัจจุบัน
  double s4c; // สถานะ:1=Low,2=Medium,3=High (ใช้สำหรับกำหนดสี)
  DateTime datetime; // เวลาที่บันทึกข้อมูล
  final String station; // สถานีที่บันทึกข้อมูล

  SatelliteData({
    required this.sv,
    required this.position,
    required this.s4c,
    required this.datetime,
    required this.station,
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
  // List สำหรับเก็บข้อมูลดาวเทียมทั้งหมดจาก JSON
  final List<SatelliteData> _allSatellites = [];
  List<DateTime> _uniqueTimes = [];
  DateTime _minTime = DateTime(2026); // Placeholder, will be set from data

  //กำหนดตัวแปรเก็บค่าระดับซูมปัจจุบัน
  double _currentZoom = 4.91; // ค่าเริ่มต้นที่คำนวณมาให้สำหรับ 500 km
  double _currentLat = 13.8600; // ตัวแปรเก็บละติจูดใช้คำนวณสเกล

  //ค่า Threshold สำหรับกำหนดสีของสถานะ (สามารถปรับได้ตามต้องการ)
  double _lowThreshold = 0.2;
  double _highThreshold = 0.4;

  //ค่าเปอร์เซ็นต์การแจ้งเตือน (ค่าเริ่มต้น 75%)
  double _alertPercentageThreshold = 75.0;

  // ตัวแปรสำหรับแถบเวลา
  DateTime _currentTime = DateTime(2026); // Placeholder, will be set from data
  double _timeSliderValue = 0.0; // ค่าของ Slider (0.0 ถึง 80.0)
  bool _isPlaying = false; // สถานะการเล่น Animation เวลา
  Timer? _timer; // Timer สำหรับเล่นอัตโนมัติ

  // --- เปลี่ยนตัวแปรให้รองรับ Multi-select ---
  Timer? _reloadTimer;
  List<String> _selectedStations = [
    'All',
  ]; // ตัวแปรเก็บสถานีที่เลือก (หลายรายการ)
  List<String> _availableStations = [
    'All',
  ]; // รายชื่อสถานีทั้งหมด (ดึงอัตโนมัติ)

  @override
  void initState() {
    super.initState();
    // ตั้งค่าเริ่มต้นสำหรับ Web: ให้เล่น Animation อัตโนมัติ
    if (kIsWeb) {
      _isPlaying = true;
    }
    // คำนวณระดับซูมเริ่มต้นสำหรับ 500 km
    _currentZoom = _calculateZoomForScale(350, _currentLat);
    _loadData().then((_) {
      // หลังจากโหลดข้อมูลเสร็จแล้ว ถ้า _isPlaying เป็น true (เช่นบน Web) ให้เริ่มเล่นอัตโนมัติ
      if (_isPlaying && _uniqueTimes.isNotEmpty) {
        _startTimer();
      }
    });

    // เริ่ม Timer สำหรับรีโหลดข้อมูลอัตโนมัติทุกๆ 1 นาที (ตามคอมเมนต์ในโค้ดเดิม)
    _reloadTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      debugPrint('Auto-reloading data every 1 minute...');
      _loadData();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _reloadTimer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      setState(() {
        if (_uniqueTimes.isEmpty) {
          _isPlaying = false;
          _timer?.cancel();
          _timer = null;
          return;
        }

        _timeSliderValue += 1.0;
        if (_timeSliderValue > (_uniqueTimes.length - 1)) {
          _timeSliderValue = 0.0;
        }
        _currentTime = _uniqueTimes[_timeSliderValue.toInt()];
      });
    });
  }

  Future<void> _loadData() async {
    final List<String> assetFiles = [
      'assets/TP00_S4C_last15min.json',
      'assets/CHAN_S4C_last15min.json',
      'assets/CHMA_S4C_last15min.json',
      'assets/DPT9_S4C_last15min.json',
      'assets/NKSW_S4C_last15min.json',
      'assets/PJRK_S4C_last15min.json',
      'assets/SISK_S4C_last15min.json',
      'assets/SOKA_S4C_last15min.json',
      'assets/SRTN_S4C_last15min.json',
      'assets/UDON_S4C_last15min.json',
      'assets/UTTD_S4C_last15min.json',
    ];

    _allSatellites.clear();
    final List<SatelliteData> tp00Satellites = [];

    for (final asset in assetFiles) {
      try {
        final jsonString = await rootBundle.loadString(asset);
        final List<dynamic> jsonData = json.decode(jsonString);
        final List<SatelliteData> loaded = jsonData.map((item) {
          return SatelliteData(
            sv: item['sv'],
            position: LatLng(item['lat'], item['lon']),
            s4c: item['s4c'].toDouble(),
            datetime: _parseUtcToBangkok(item['utc'] as String),
            station: item['station'] as String,
          );
        }).toList();

        _allSatellites.addAll(loaded);
        if (asset.contains('TP00_S4C_last15min.json')) {
          tp00Satellites.addAll(loaded);
        }
      } catch (e) {
        debugPrint('Failed to load asset $asset: $e');
      }
    }

    if (tp00Satellites.isNotEmpty) {
      _uniqueTimes = tp00Satellites.map((s) => s.datetime).toSet().toList()
        ..sort();
      _minTime = _uniqueTimes.first;

      if (_currentTime.year == 2026 && _uniqueTimes.isNotEmpty) {
        _currentTime = _minTime;
        _timeSliderValue = 0.0;
      }
    } else {
      _uniqueTimes = [];
    }

    // อัปเดตรายชื่อสถานีสำหรับ Filter
    if (_allSatellites.isNotEmpty) {
      final stations = _allSatellites.map((s) => s.station).toSet().toList()
        ..sort();
      _availableStations = ['All', ...stations];

      // ล้างค่าสถานีที่เลือกไว้แต่ไม่มีในข้อมูลใหม่ (ยกเว้น 'All')
      _selectedStations.removeWhere(
        (s) => !_availableStations.contains(s) && s != 'All',
      );
      if (_selectedStations.isEmpty) {
        _selectedStations = ['All'];
      }
    }

    setState(() {});
  }

  DateTime _parseUtcToBangkok(String utcString) {
    final normalized = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(utcString)
        ? utcString
        : '${utcString}Z';
    final utcTime = DateTime.parse(normalized).toUtc();
    return utcTime.add(const Duration(hours: 7));
  }

  double _calculateZoomForScale(int targetScaleKm, double latitude) {
    double distanceMeters = targetScaleKm * 1000.0;
    double resolution = distanceMeters / _scaleBarWidthPixels;
    double zoom =
        math.log(156543.03 * math.cos(latitude * math.pi / 180) / resolution) /
        math.ln2;
    return zoom;
  }

  void _zoomIn() {
    double currentDistanceKm = _getCurrentDistanceKm();
    int targetScale = _scaleLevelsKm.first;
    for (int i = _scaleLevelsKm.length - 1; i >= 0; i--) {
      if (_scaleLevelsKm[i] < currentDistanceKm - 1) {
        targetScale = _scaleLevelsKm[i];
        break;
      }
    }
    _applyScale(targetScale);
  }

  void _zoomOut() {
    double currentDistanceKm = _getCurrentDistanceKm();
    int targetScale = _scaleLevelsKm.last;
    for (int i = 0; i < _scaleLevelsKm.length; i++) {
      if (_scaleLevelsKm[i] > currentDistanceKm + 1) {
        targetScale = _scaleLevelsKm[i];
        break;
      }
    }
    _applyScale(targetScale);
  }

  void _applyScale(int scaleKm) {
    double newZoom = _calculateZoomForScale(scaleKm, _currentLat);
    _mapController.move(_mapController.camera.center, newZoom);
  }

  double _getCurrentDistanceKm() {
    double resolution =
        156543.03 *
        math.cos(_currentLat * math.pi / 180) /
        math.pow(2, _currentZoom);
    double distanceMeters = resolution * _scaleBarWidthPixels;
    return distanceMeters / 1000.0;
  }

  String _getScaleText() {
    double distanceKm = _getCurrentDistanceKm();
    for (int scale in _scaleLevelsKm) {
      if ((distanceKm - scale).abs() < 5) {
        return '$scale km';
      }
    }
    return '${distanceKm.toStringAsFixed(1)} km';
  }

  Color _getStatusColor(double s4c) {
    // 1. เงื่อนไข Low: ค่า S4 น้อยกว่าหรือเท่ากับ 0.2
    if (s4c <= _lowThreshold) {
      return const Color.fromARGB(255, 59, 130, 246); // สีน้ำเงิน
    }
    // 2. เงื่อนไข Medium: ค่า S4 อยู่ระหว่าง 0.2 ถึง 0.4
    else if (s4c > _lowThreshold && s4c < _highThreshold) {
      return const Color.fromARGB(255, 251, 191, 36); // สีเหลือง
    }
    // 3. เงื่อนไข High: ค่า S4 มากกว่าหรือเท่ากับ 0.4
    else if (s4c >= _highThreshold) {
      return const Color.fromARGB(255, 239, 68, 68); // สีแดง
    }
    // 4. เงื่อนไขเริ่มต้น/กำหนดเอง (Default) สำหรับกรณีค่าผิดปกติ หรือค่า Null (ถ้ามี)
    else {
      return const Color.fromARGB(255, 128, 128, 128); // สีเทา
    }
  }

  // ฟังก์ชันสำหรับแสดง Dialog ตั้งค่า Thresholds
  void _showThresholdSettingsDialog() {
    final lowController = TextEditingController(text: _lowThreshold.toString());
    final highController = TextEditingController(
      text: _highThreshold.toString(),
    );
    final alertPercentController = TextEditingController(
      text: _alertPercentageThreshold.toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Threshold setup:'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: lowController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Threshold between Low and Medium',
              ),
            ),
            TextField(
              controller: highController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Threshold between Medium and High',
              ),
            ),
            TextField(
              controller: alertPercentController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Threshold for Alert',
                suffixText: '%',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _lowThreshold =
                    double.tryParse(lowController.text) ?? _lowThreshold;
                _highThreshold =
                    double.tryParse(highController.text) ?? _highThreshold;
                _alertPercentageThreshold =
                    double.tryParse(alertPercentController.text) ??
                    _alertPercentageThreshold;
              });
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // --- ฟังก์ชันสำหรับเปิด Dialog เลือกหลายสถานี ---
  void _showMultiSelectDialog() {
    // สร้าง List ชั่วคราวสำหรับเก็บค่าระหว่างที่ยังไม่ได้กด Apply
    List<String> tempSelected = List.from(_selectedStations);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        // ใช้ StatefulBuilder เพื่อให้ Checkbox อัปเดตสถานะใน Dialog ได้ทันที
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Data selection:'),
              backgroundColor: Colors.white.withValues(alpha: 0.8),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _availableStations.length,
                  itemBuilder: (context, index) {
                    final station = _availableStations[index];
                    return CheckboxListTile(
                      title: Text(station == 'All' ? 'All Stations' : station),
                      value: tempSelected.contains(station),
                      activeColor: const Color(0xFF000000),
                      onChanged: (bool? checked) {
                        setStateDialog(() {
                          if (checked == true) {
                            if (station == 'All') {
                              tempSelected = [
                                'All',
                              ]; // ถ้าเลือก All ให้ล้างค่าอื่นออก
                            } else {
                              tempSelected.remove(
                                'All',
                              ); // ถ้าเลือกสถานีอื่น ให้เอา All ออก
                              tempSelected.add(station);
                            }
                          } else {
                            tempSelected.remove(station);
                            if (tempSelected.isEmpty) {
                              tempSelected.add(
                                'All',
                              ); // ถ้าเอาออกหมด ให้กลับไปเป็น All
                            }
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(), // Cancel
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Apply: นำค่าชั่วคราวไปใส่ในตัวแปรหลักแล้วรีเฟรชหน้าจอหลัก
                    setState(() {
                      _selectedStations = tempSelected;
                    });
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF000000),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- อัปเดตปุ่ม Filter ให้กดแล้วเปิด Dialog ---
  Widget _buildStationFilter() {
    // กำหนดข้อความที่จะแสดงบนปุ่ม
    String buttonText;
    if (_selectedStations.contains('All')) {
      buttonText = 'All Stations';
    } else if (_selectedStations.length == 1) {
      buttonText = _selectedStations.first;
    } else {
      buttonText = '${_selectedStations.length} Stations';
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _showMultiSelectDialog, // เรียก Dialog เมื่อกด
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on, color: Color(0xFF000000), size: 20),
              const SizedBox(width: 8),
              Text(
                buttonText,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down, color: Color(0xFF000000)),
            ],
          ),
        ),
      ),
    );
  }

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
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 0),
          _buildLegendItem(
            Color.fromARGB(255, 59, 130, 246),
            'Low',
            'S\u{2084} computed values lower than or equal to $_lowThreshold',
          ),
          const SizedBox(width: 8),
          _buildLegendItem(
            Color.fromARGB(255, 251, 191, 36),
            'Medium',
            'S\u{2084} computed values between $_lowThreshold and $_highThreshold',
          ),
          const SizedBox(width: 8),
          _buildLegendItem(
            Color.fromARGB(255, 239, 68, 68),
            'High',
            'S\u{2084} computed values greater than or equal to $_highThreshold',
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.settings, size: 20),
            color: Colors.black87,
            tooltip: 'Threshold setup',
            onPressed: _showThresholdSettingsDialog,
          ),
          // IconButton(
          //   icon: const Icon(Icons.info_outline),
          //   color: Colors.black87,
          //   tooltip: 'Feature Information',
          //   onPressed: () {},
          // ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, String tooltip) {
    return Row(
      children: [
        Tooltip(
          message: tooltip,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1),
            ),
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

  Widget _buildTimeBar() {
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
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
            ),
            color: const Color(0xFF3D3D3D),
            iconSize: 36,
            onPressed: () {
              setState(() {
                _isPlaying = !_isPlaying;
                if (_isPlaying) {
                  _startTimer();
                } else {
                  _timer?.cancel();
                  _timer = null;
                }
              });
            },
          ),
          Expanded(
            child: Slider(
              value: _uniqueTimes.isEmpty
                  ? 0.0
                  : _timeSliderValue.clamp(
                      0.0,
                      (_uniqueTimes.length - 1).toDouble(),
                    ),
              min: 0.0,
              max: (_uniqueTimes.isNotEmpty
                  ? (_uniqueTimes.length - 1).toDouble()
                  : 0.0),
              divisions: (_uniqueTimes.length > 1
                  ? _uniqueTimes.length - 1
                  : 1),
              activeColor: Color(0xFF3D3D3D),
              inactiveColor: Color(0xFFBABABA),
              onChanged: _uniqueTimes.isEmpty
                  ? null
                  : (value) {
                      setState(() {
                        _timeSliderValue = value;
                        _currentTime = _uniqueTimes[value.toInt()];
                      });
                    },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Color(0xFF3D3D3D),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              formattedDate,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: const Color(0xFFFFFFFF),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ฟังก์ชันดึงข้อมูลดาวเทียมที่กำลังแสดงผลบนหน้าจอ ณ เวลานั้นๆ
  List<SatelliteData> get _currentVisibleSatellites {
    return _allSatellites
        .where((sat) => sat.datetime == _currentTime)
        .where(
          (sat) =>
              _selectedStations.contains('All') ||
              _selectedStations.contains(sat.station),
        )
        .toList();
  }

  // Widget สำหรับแสดงการแจ้งเตือนเมื่อมีดาวเทียมที่มีสถานะ High เกินเปอร์เซ็นต์ที่กำหนด
  Widget _buildHighScintillationAlert(List<SatelliteData> visibleSats) {
    if (visibleSats.isEmpty) return const SizedBox.shrink();

    // นับจำนวนดาวเทียมทั้งหมดที่แสดงผล
    int totalCount = visibleSats.length;
    // นับจำนวนดาวเทียมที่มีสถานะ High (S4C >= _highThreshold)
    int highCount = visibleSats
        .where((sat) => sat.s4c >= _highThreshold)
        .length;

    // คำนวณเปอร์เซ็นต์
    double highPercentage = (highCount / totalCount) * 100;

    // ถ้าเปอร์เซ็นต์มากกว่า _alertPercentageThreshold ให้แสดงแถบแจ้งเตือน
    if (highPercentage > _alertPercentageThreshold) {
      return Container(
        margin: const EdgeInsets.only(top: 40), // ระยะห่างจากด้านบน
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Color(0xFFEF4444).withValues(alpha: 0.8), // พื้นหลังสีแดง
          borderRadius: BorderRadius.circular(30),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_rounded, color: Colors.white, size: 24),
            const SizedBox(width: 8),
            Text(
              'Alert: High Status > ${_alertPercentageThreshold.toStringAsFixed(1)}% (${highPercentage.toStringAsFixed(1)}% | $highCount/$totalCount)',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    // โหลดตัวแปรเก็บดาวเทียมรอบนี้ เพื่อส่งให้ Marker และ Alert คำนวณ
    final currentVisibleSats = _currentVisibleSatellites;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(13.4500, 100.5200),
              initialZoom: _currentZoom,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
              onPositionChanged: (camera, hasGesture) {
                setState(() {
                  _currentZoom = camera.zoom;
                  _currentLat = camera.center.latitude;
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.example.gnss_monitor',
              ),
              MarkerLayer(
                markers: currentVisibleSats.map((sat) {
                  return Marker(
                    point: sat.position,
                    width: 30,
                    height: 30,
                    child: Tooltip(
                      message: sat.station,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _getStatusColor(
                            sat.s4c,
                          ).withValues(alpha: 0.8),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1),
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
                            sat.sv,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              child: _buildHighScintillationAlert(currentVisibleSats),
            ),
          ),
          Positioned(
            top: 40,
            right: 20,
            child: SafeArea(child: _buildStationFilter()),
          ),
          Positioned(left: 20, bottom: 90, child: _buildLegend()),
          Positioned(
            right: 20,
            bottom: 90,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
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
                const SizedBox(height: 8),
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
          Positioned(left: 0, right: 0, bottom: 0, child: _buildTimeBar()),
        ],
      ),
    );
  }
}
