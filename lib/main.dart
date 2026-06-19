import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart'; 
import 'package:url_launcher/url_launcher.dart'; 

void main() {
  runApp(const RailCalcApp());
}

class RailCalcApp extends StatelessWidget {
  const RailCalcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color.fromRGBO(76, 175, 80, 1),
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text(
            'TFR Load Calculator', 
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
          ),
          backgroundColor: const Color.fromRGBO(76, 175, 80, 1),
          elevation: 2,
        ),
        body: const LoadCalculatorForm(),
      ),
    );
  }
}

class LoadCalculatorForm extends StatefulWidget {
  const LoadCalculatorForm({super.key});

  @override
  State<LoadCalculatorForm> createState() => _LoadCalculatorFormState();
}

class _LoadCalculatorFormState extends State<LoadCalculatorForm> {
  // CONFIGURATION CONSTANTS
  final String currentAppVersion = "1.0.8"; 
  bool _hasDeferredUpdate = false;

  // Controllers for text inputs
  final TextEditingController tonsController = TextEditingController();
  final TextEditingController axlesController = TextEditingController();

  // Dropdown states
  String? selectedMode;
  String? selectedRoute;
  String? selectedLocoClass;
  String? selectedLocoQty;
  String? selectedAirbrake;
  String? selectedVacuum;

  // Data storage
  List<dynamic> locoData = [];

  @override
  void initState() {
    super.initState();
    // Clean sequential loading sequence
    loadJsonData().then((_) { 
      if (!kIsWeb) {
        WidgetsBinding.instance.addPostFrameCallback((_) => checkForUpdates());
      }
    });
  }

  Future<void> loadJsonData() async {
    try {
      final String response = await rootBundle.loadString('assets/test_data.json');
      final data = await json.decode(response);
      setState(() {
        locoData = data;
      });
    } catch (e) {
      debugPrint("Failed to load local asset data: $e");
    }
  }

  Future<void> checkForUpdates() async {
    if (_hasDeferredUpdate) return; 

    final String url = "https://leonbhoman.github.io/TFR-Load-Tables/version.json?v=${DateTime.now().millisecondsSinceEpoch}";

    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (!mounted) return;
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        String latestVersion = data['version'] ?? '1.0.0';
        String downloadUrl = data['url'] ?? 'https://github.com/leonbhoman/TFR-Load-Tables';

        if (latestVersion != currentAppVersion && mounted) {
          showUpdateDialog(latestVersion, downloadUrl);
        }
      }
    } catch (e) {
      debugPrint("Update check skipped or failed: $e");
    }
  }

  void showUpdateDialog(String version, String downloadUrl) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Update Available'),
          content: Text('A new version ($version) is available. Would you like to download it now?'),
          actions: [
            TextButton(
              child: const Text('Later'),
              onPressed: () {
                setState(() {
                  _hasDeferredUpdate = true;
                });
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              child: const Text('Update'),
              onPressed: () async {
                Navigator.of(context).pop();
                final Uri url = Uri.parse(downloadUrl);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                } else {
                  await Clipboard.setData(ClipboardData(text: downloadUrl));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not launch browser. Download link copied to clipboard.')),
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  void calculate() {
    // Placeholder calculation logic matching your existing application verify trigger
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Verifying Load Profiles...')),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Hardcoded demo lists for inputs matching your configuration goals
    final modes = ['Mode A', 'Mode B'];
    final routes = ['Route 1', 'Route 2'];
    final locos = ['Class 39', 'Class 43'];
    final qtys = ['1', '2', '3', '4'];
    final brakes = ['Yes', 'No'];
    final vacuums = ['Yes', 'No'];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Determine view state based on screen width
        bool isWideScreen = constraints.maxWidth > 650;

        return Column(
          children: [
            // Main Input Container Area
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isWideScreen) ...[
                      // DESKTOP/LAPTOP WEB GRID CONFIGURATION
                      Row(
                        children: [
                          Expanded(child: DropdownButtonFormField<String>(decoration: const InputDecoration(labelText: "Train Operation Mode"), items: modes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => selectedMode = v)),
                          const SizedBox(width: 16),
                          Expanded(child: DropdownButtonFormField<String>(decoration: const InputDecoration(labelText: "Route"), items: routes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => selectedRoute = v)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: DropdownButtonFormField<String>(decoration: const InputDecoration(labelText: "Loco Class"), items: locos.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => selectedLocoClass = v)),
                          const SizedBox(width: 16),
                          Expanded(child: DropdownButtonFormField<String>(decoration: const InputDecoration(labelText: "Loco Qty"), items: qtys.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => selectedLocoQty = v)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: DropdownButtonFormField<String>(decoration: const InputDecoration(labelText: "Airbrake"), items: brakes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => selectedAirbrake = v)),
                          const SizedBox(width: 16),
                          Expanded(child: DropdownButtonFormField<String>(decoration: const InputDecoration(labelText: "Vacuum"), items: vacuums.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => selectedVacuum = v)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: tonsController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Tons"))),
                          const SizedBox(width: 16),
                          Expanded(child: TextField(controller: axlesController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Total Axles"))),
                        ],
                      ),
                    ] else ...[
                      // MOBILE STACKED VIEW
                      DropdownButtonFormField<String>(decoration: const InputDecoration(labelText: "Train Operation Mode"), items: modes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => selectedMode = v),
                      DropdownButtonFormField<String>(decoration: const InputDecoration(labelText: "Route"), items: routes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => selectedRoute = v),
                      DropdownButtonFormField<String>(decoration: const InputDecoration(labelText: "Loco Class"), items: locos.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => selectedLocoClass = v),
                      DropdownButtonFormField<String>(decoration: const InputDecoration(labelText: "Loco Qty"), items: qtys.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => selectedLocoQty = v),
                      DropdownButtonFormField<String>(decoration: const InputDecoration(labelText: "Airbrake"), items: brakes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => selectedAirbrake = v),
                      DropdownButtonFormField<String>(decoration: const InputDecoration(labelText: "Vacuum"), items: vacuums.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => selectedVacuum = v),
                      TextField(controller: tonsController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Tons")),
                      TextField(controller: axlesController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Total Axles")),
                    ],
                    
                    const SizedBox(height: 32),
                    
                    // Calculation Trigger Button
                    Center(
                      child: ElevatedButton(
                        style: ButtonStyle(
                          minimumSize: WidgetStateProperty.all<Size>(const Size(240, 54)),
                          backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
                            if (states.contains(WidgetState.pressed)) return Colors.green.shade900;
                            return Colors.green.shade700;
                          }),
                          foregroundColor: WidgetStateProperty.all<Color>(Colors.white),
                          shape: WidgetStateProperty.all<OutlinedBorder>(
                            RoundedRectangleBorder(borderRadius: BorderRadius.circular(28.0)),
                          ),
                          elevation: WidgetStateProperty.all<double>(3),
                        ),
                        onPressed: calculate, 
                        child: const Text(
                          "VERIFY LOAD", 
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Clean Bottom Sticky Footer Credit
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              color: Colors.grey.shade100,
              child: Text(
                "v$currentAppVersion | Built by Leon",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12, 
                  fontWeight: FontWeight.w500, 
                  color: Colors.grey.shade600,
                  letterSpacing: 0.5
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}