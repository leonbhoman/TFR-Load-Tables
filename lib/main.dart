import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart'; // <-- Add this to access kIsWeb
import 'package:url_launcher/url_launcher.dart'; // <-- Add this import at the very top of main.dart

void main() {
  runApp(const RailCalcApp());
}

class RailCalcApp extends StatelessWidget {
  const RailCalcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true,
        colorSchemeSeed: const Color.fromRGBO(76, 175, 80, 1),),
      home: Scaffold(
        appBar: AppBar(title: const Text(
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
  final tonsController = TextEditingController();
  final axlesController = TextEditingController();

  // The version hardcoded into this specific build string
  final String currentAppVersion = "1.0.11";
  // Track if the user clicked "Later" so we don't spam them during this app session
  bool _hasDeferredUpdate = false;
  
  // Train Operational Types
  String selectedTrainType = 'Mainline';
  final List<String> trainTypes = ['Mainline', 'Hauler', 'LightAirbrake'];

  // Single Route selection string used for both Mainline pairs and Hauler complexes
  String selectedRoute = 'Durban to Reef';

  // Mainline Route Definitions
  final List<String> mainlineRoutes = [
    'Durban to Reef',
    'Reef to Durban',
    'Durban to Richards Bay',
    'Richards Bay to Durban',
    'Richards Bay to Golela',
    'Golela to Richards Bay',
    'Richards Bay to Ermelo',
    'Ermelo to Richards Bay'
  ];

  // Embedded Mainline Route Lookup Matrix
  final Map<String, Map<String, int>> routeCatalog = {
    'Durban to Reef': {'Airbrake': 5, 'Vacuum': 4},
    'Reef to Durban': {'Airbrake': 7, 'Vacuum': 6},
    'Durban to Richards Bay': {'Airbrake': 5, 'Vacuum': 5},
    'Richards Bay to Durban': {'Airbrake': 8, 'Vacuum': 8},
    'Richards Bay to Golela': {'Airbrake': 6, 'Vacuum': 6},
    'Golela to Richards Bay': {'Airbrake': 9, 'Vacuum': 9},
    'Richards Bay to Ermelo': {'Airbrake': 8, 'Vacuum': 8},
    'Ermelo to Richards Bay': {'Airbrake': 9, 'Vacuum': 9},
  };

  // Hauler Regional Definitions
  final List<String> haulerRoutes = ['Durban Complex', 'Richards Bay Complex', 'Reef Complex'];

  // Embedded Hauler Area Lookup (Maps directly to a static GC)
  final Map<String, int> haulerCatalog = {
    'Durban Complex': 8,
    'Richards Bay Complex': 15,
    'Reef Complex': 12,
  };

  // Locomotive Selection Configuration
  String selectedLoco = '18E_Class'; // Holds the active backend JSON key value
  
  final List<Map<String, String>> locos = [
    {'display': '5E1', 'value': '5E1_Class'},
    {'display': '6E', 'value': '6E_Class'},
    {'display': '6E1', 'value': '6E1_16E_17E_Class'}, 
    {'display': '16E', 'value': '6E1_16E_17E_Class'}, 
    {'display': '17E', 'value': '6E1_16E_17E_Class'}, 
    {'display': '7E', 'value': '7E_10E_Class'},       
    {'display': '10E', 'value': '7E_10E_Class'},      
    {'display': '8E', 'value': '8E_Class'},
    {'display': '14E', 'value': '14E_Class'},
    {'display': '18E', 'value': '18E_Class'},
    {'display': '19E', 'value': '19E_Class'},
    {'display': '33D', 'value': '33D_Class'},
    {'display': '34D', 'value': '34D_Class'},          
    {'display': '35D', 'value': '35D_Class'},
    {'display': '36D', 'value': '36D_Class'},
    {'display': '37D', 'value': '37D_Class'},
    {'display': '38D', 'value': '38D_Class'},
    {'display': '39-000D', 'value': '39-000D_Class'},
    {'display': '39-200D', 'value': '39-200D_Class'},
    {'display': '43D', 'value': '43D_Class'}, 
  ];
  
  // Consist Sizing
  int selectedLocoCount = 4; 
  final List<int> locoCounts = [1, 2, 3, 4, 5, 6];

  bool isAirbrake = true; 
  Map<String, dynamic> locoData = {};

    @override
    void initState() {
      super.initState();
    loadJsonData().then((_) { 
      if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => checkForUpdates());
    }
    });
      // ONLY check for updates if the application is NOT running in a web browser
      if (!kIsWeb) {
        WidgetsBinding.instance.addPostFrameCallback((_) => checkForUpdates());
      }
      }

  Future<void> checkForUpdates() async {
    if (_hasDeferredUpdate) return; // Silent exit if they already clicked Later
          // FIXED: Pointing to the exact repository name casing
      final String url = "https://leonbhoman.github.io/TFR-Load-Tables/version.json?v=${DateTime.now().millisecondsSinceEpoch}";

    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        String latestVersion = data['version'];
        String downloadUrl = data['url'];

        if (latestVersion != currentAppVersion && mounted) {
          showUpdateDialog(latestVersion, downloadUrl);
        }
      }
    } catch (e) {
      debugPrint("Update check failed: $e");
    }
  }

  void showUpdateDialog(String newVersion, String downloadUrl) {
    showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.system_update, color: Colors.blue),
            SizedBox(width: 10),
            Text("Update Available"),
          ],
        ),
        content: Text(
          "A new database configuration version ($newVersion) is available. "
          "Please download the latest version to ensure calculation parameters match field guidelines."
        ),
actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _hasDeferredUpdate = true; // Block dialog until app restarts
              });
              Navigator.pop(dialogContext);
            },
            child: const Text("Later"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final Uri downloadUri = Uri.parse(downloadUrl);
              
              // Try launching the native browser directly
              if (await canLaunchUrl(downloadUri)) {
                await launchUrl(downloadUri, mode: LaunchMode.externalApplication);
              } else {
                // Fallback plan if browser routing fails: copy to clipboard
                await Clipboard.setData(ClipboardData(text: downloadUrl));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Could not launch browser. Download link copied to clipboard!")),
                  );
                }
              }
              
              if (mounted && dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            },
            child: const Text("Get Update"),
          ),
        ],
      ),
    );
  }
  
  Future<void> loadJsonData() async {
    try {
      final String response = await rootBundle.loadString('assets/test_data.json');
      final data = await json.decode(response);
      setState(() {
        locoData = data;
      });
    } catch (e) {
      // Gracefully handled during processing if data is missing
    }
  }
  
  void calculate() {
    double tons = double.tryParse(tonsController.text) ?? 0;
    double axles = double.tryParse(axlesController.text) ?? 1;
    double axleMass = (axles > 0) ? tons / axles : 0;
    
    String blockKey = "";
    String warning = "";
    String isolationWarningMessage = "";
    bool showIsolationWarning = false;
    int targetGC = 5; 

    // 1. Dynamic Safety Boundary Check based on Brake Type
    double maxAllowedAxleMass = isAirbrake ? 20.0 : 18.5;
    int maxAllowedAxles = isAirbrake ? 200 : 160;
    int maxAllowedWagons = isAirbrake ? 50 : 40;
    String brakeName = isAirbrake ? "AIRBRAKE" : "VACUUM";

    // Check Axle Mass Threshold
    if (axleMass > maxAllowedAxleMass) {
      warning = "⚠️ EXCEEDS MAX $maxAllowedAxleMass t/a FOR $brakeName";
    }

    // Check Consist Length / Axle Count Threshold
    double estimatedWagons = axles / 4;
    if (axles > maxAllowedAxles || estimatedWagons > maxAllowedWagons) {
      if (warning.isNotEmpty) warning += "\n";
      warning += "⚠️ $brakeName LIMIT EXCEEDED:\nMax $maxAllowedWagons Wagons / $maxAllowedAxles Axles allowed.";
    }
    // 1. Safety Boundary Check
    // if (axleMass > 20) {
    //  warning = "⚠️ EXCEEDS MAX 20 t/a";
    // }

    // 2. Routed Matrix Lookup (Hauler vs Mainline Branches)
    if (selectedTrainType == 'Hauler') {
      targetGC = haulerCatalog[selectedRoute] ?? 8;
    } else {
      String brakeKey = isAirbrake ? 'Airbrake' : 'Vacuum';
      targetGC = routeCatalog[selectedRoute]?[brakeKey] ?? 5;
    }

    // 3. Determine Block Token based on Brake Type and Calculated Axle Mass (AAM)
    if (isAirbrake) {
      if (axleMass <= 7) { blockKey = "AB27"; }
      else if (axleMass <= 12.5) { blockKey = "AB712"; }
      else if (axleMass <= 17) { blockKey = "AB1217"; }
      else if (axleMass <= 19) { blockKey = "AB1719"; }
      else { blockKey = "AB1920"; }
    } else {
      if (axleMass <= 10) { blockKey = "VB10"; }
      else { blockKey = "VB10P"; }
    }

    int baselineMaxTons = 0;
    bool foundRowMatch = false;

    // 4. Extract Load Ceiling from Dataset with Auto-Isolation Guard
    if (locoData.containsKey(selectedLoco)) {
      var classData = locoData[selectedLoco];
      if (classData != null && classData.containsKey(blockKey)) {
        List<dynamic> blockDataList = classData[blockKey];
        Map<String, dynamic>? rowMatch;
        for (var row in blockDataList) {
          if (row['GC'] == targetGC) {
            rowMatch = Map<String, dynamic>.from(row);
            break;
          }
        }
        
        if (rowMatch != null) {
          foundRowMatch = true;
          int requestedCount = selectedLocoCount;
          
          int maxAvailableCount = rowMatch.keys
              .where((key) => int.tryParse(key) != null)
              .map((key) => int.parse(key))
              .fold(0, (max, element) => element > max ? element : max);

          int actualLookupKey = requestedCount;
          String displayLocoName = locos.firstWhere((l) => l['value'] == selectedLoco)['display']!;

          if (requestedCount > maxAvailableCount && maxAvailableCount > 0) {
            actualLookupKey = maxAvailableCount;
            showIsolationWarning = true;
            isolationWarningMessage = "No provision for more than $maxAvailableCount x $displayLocoName locos on this route. Extra locos must be isolated.";
          }

          String countKey = actualLookupKey.toString();
          if (rowMatch.containsKey(countKey)) {
            baselineMaxTons = rowMatch[countKey];
          }
        }
      }
    }

    // 5. Apply Wagon Allowance
    double safetyWagonsCheck = axles / 4;
    int allowanceTons = safetyWagonsCheck.floor(); 
    int totalAllowedTons = baselineMaxTons + allowanceTons;

    // 6. Trigger Centered Pop-up Modal Window
    if (warning.isNotEmpty || foundRowMatch) {
      bool overWeight = warning.isEmpty && (tons > totalAllowedTons);
      String titleText = warning.isNotEmpty ? "⚠️ SYSTEM WARNING" : (overWeight ? "❌ OVERWEIGHT" : "✅ CLEAR TO RUN");
      Color headerColor = warning.isNotEmpty ? Colors.orange : (overWeight ? Colors.red : Colors.green);
      
      String displayLocoName = locos.firstWhere((l) => l['value'] == selectedLoco)['display']!;
      
      String dialogBody = warning.isNotEmpty 
          ? warning 
          : "Consist: $selectedLocoCount x $displayLocoName ($blockKey)\n"
            "Setting: $selectedRoute (GC $targetGC)\n"
            "Base Capacity: ${baselineMaxTons}t\n"
            "Wagon Allowance: +${allowanceTons}t (${estimatedWagons.toStringAsFixed(0)} wagons)\n"
            "Total Limit: ${totalAllowedTons}t\n"
            "---------------------------\n"
            "${overWeight ? "Over max limit by" : "Remaining margin"}: ${(totalAllowedTons - tons).abs().toInt()}t";

      showDialog(
        context: context,
        barrierDismissible: false, 
        builder: (BuildContext context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: Text(titleText, style: TextStyle(color: headerColor, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dialogBody, style: const TextStyle(fontSize: 16, height: 1.4)),
                if (showIsolationWarning && warning.isEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      border: Border.all(color: Colors.amber.shade600),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isolationWarningMessage,
                      style: TextStyle(
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                child: const Text("OK"),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        },
      );
    } else {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text("🔍 No Entries Found"),
            content: Text("AAM: ${axleMass.toStringAsFixed(2)} t/a\nBlock Key: $blockKey\n\nNo data matching these configuration parameters was found in the database."),
            actions: [
              TextButton(
                child: const Text("OK"),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        },
      );
    }
  }

@override
  Widget build(BuildContext context) {
    List<String> activeRouteOptions = (selectedTrainType == 'Hauler') ? haulerRoutes : mainlineRoutes;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Triggers wide desktop grid mode if the window width is over 600 pixels
        bool isWideScreen = constraints.maxWidth > 600;

        return Form( // Invisible wrapper enabling clean web keyboard submission
          child: Column(
            children: [
              // Scrollable Input Area
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isWideScreen) ...[
                        // ===================================================================
                        // DESKTOP WIDE GRID VIEW (Grouped Pairs)
                        // ===================================================================
                        
                        // GROUP 1: Train Operation Mode & Route
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Train Operation Mode:", style: TextStyle(fontWeight: FontWeight.bold)),
                                  DropdownButton<String>(
                                    value: selectedTrainType,
                                    isExpanded: true,
                                    items: trainTypes.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                                    onChanged: (val) {
                                      setState(() {
                                        selectedTrainType = val!;
                                        List<String> nextOptions = (selectedTrainType == 'Hauler') ? haulerRoutes : mainlineRoutes;
                                        selectedRoute = nextOptions.first;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Route:", style: TextStyle(fontWeight: FontWeight.bold)),
                                  DropdownButton<String>(
                                    value: selectedRoute,
                                    isExpanded: true,
                                    items: activeRouteOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                                    onChanged: (val) => setState(() => selectedRoute = val!),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // GROUP 2: Locomotive Class & Number of Locomotives
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Locomotive Class:", style: TextStyle(fontWeight: FontWeight.bold)),
                                  DropdownButton<String>(
                                    value: selectedLoco,
                                    isExpanded: true,
                                    items: locos.map((loco) => DropdownMenuItem<String>(
                                      value: loco['value'], 
                                      child: Text(loco['display']!),
                                    )).toList(),
                                    onChanged: (val) => setState(() => selectedLoco = val!),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Number of Locos in Consist (Live locomotives only):", style: TextStyle(fontWeight: FontWeight.bold)),
                                  DropdownButton<int>(
                                    value: selectedLocoCount,
                                    isExpanded: true,
                                    items: locoCounts.map((int value) {
                                      return DropdownMenuItem<int>(
                                        value: value,
                                        child: Text("$value Locomotive${value > 1 ? 's' : ''}"),
                                      );
                                    }).toList(),
                                    onChanged: (val) => setState(() => selectedLocoCount = val!),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // GROUP 3: Brake Type (Narrow width matches the action button)
                        Center(
                          child: SizedBox(
                            width: 240, 
                            child: SegmentedButton<bool>(
                              segments: const <ButtonSegment<bool>>[
                                ButtonSegment<bool>(value: true, label: Text('AIRBRAKE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.0))),
                                ButtonSegment<bool>(value: false, label: Text('VACUUM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.0))),
                              ],
                              selected: <bool>{isAirbrake},
                              onSelectionChanged: (Set<bool> newSelection) => setState(() => isAirbrake = newSelection.first),
                              style: ButtonStyle(
                                backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) => states.contains(WidgetState.selected) ? Colors.green.shade700 : Colors.grey.shade200),
                                foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) => states.contains(WidgetState.selected) ? Colors.white : Colors.green.shade900),
                                shape: WidgetStateProperty.all<OutlinedBorder>(RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.0))),
                                side: WidgetStateProperty.all<BorderSide>(BorderSide.none),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // GROUP 4: Tons & Axles
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: tonsController, 
                                keyboardType: TextInputType.number, 
                                onSubmitted: (_) => calculate(), // Fire calculation on Enter
                                decoration: const InputDecoration(labelText: "Actual Total Tons", border: OutlineInputBorder())
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: TextField(
                                controller: axlesController, 
                                keyboardType: TextInputType.number, 
                                onSubmitted: (_) => calculate(), // Fire calculation on Enter
                                decoration: const InputDecoration(labelText: "Total Axles", border: OutlineInputBorder())
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        // ===================================================================
                        // MOBILE PORTRAIT VIEW (Compact Single Stack)
                        // ===================================================================
                        const Text("Train Operation Mode:", style: TextStyle(fontWeight: FontWeight.bold)),
                        DropdownButton<String>(
                          value: selectedTrainType,
                          isExpanded: true,
                          items: trainTypes.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                          onChanged: (val) {
                            setState(() {
                              selectedTrainType = val!;
                              List<String> nextOptions = (selectedTrainType == 'Hauler') ? haulerRoutes : mainlineRoutes;
                              selectedRoute = nextOptions.first;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        const Text("Route:", style: TextStyle(fontWeight: FontWeight.bold)),
                        DropdownButton<String>(
                          value: selectedRoute,
                          isExpanded: true,
                          items: activeRouteOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                          onChanged: (val) => setState(() => selectedRoute = val!),
                        ),
                        const SizedBox(height: 12),
                        const Text("Locomotive Class:", style: TextStyle(fontWeight: FontWeight.bold)),
                        DropdownButton<String>(
                          value: selectedLoco,
                          isExpanded: true,
                          items: locos.map((loco) => DropdownMenuItem<String>(
                            value: loco['value'], 
                            child: Text(loco['display']!),
                          )).toList(),
                          onChanged: (val) => setState(() => selectedLoco = val!),
                        ),
                        const SizedBox(height: 12),
                        const Text("Number of Locos in Consist (Live locomotives only):", style: TextStyle(fontWeight: FontWeight.bold)),
                        DropdownButton<int>(
                          value: selectedLocoCount,
                          isExpanded: true,
                          items: locoCounts.map((int value) {
                            return DropdownMenuItem<int>(
                              value: value,
                              child: Text("$value Locomotive${value > 1 ? 's' : ''}"),
                            );
                          }).toList(),
                          onChanged: (val) => setState(() => selectedLocoCount = val!),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: SizedBox(
                            width: 440,
                            child: SegmentedButton<bool>(
                              segments: const <ButtonSegment<bool>>[
                                ButtonSegment<bool>(value: true, label: Text('AIRBRAKE', style: TextStyle(fontWeight: FontWeight.bold))),
                                ButtonSegment<bool>(value: false, label: Text('VACUUM', style: TextStyle(fontWeight: FontWeight.bold))),
                              ],
                              selected: <bool>{isAirbrake},
                              onSelectionChanged: (Set<bool> newSelection) => setState(() => isAirbrake = newSelection.first),
                              style: ButtonStyle(
                                backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) => states.contains(WidgetState.selected) ? Colors.green.shade700 : Colors.grey.shade200),
                                foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) => states.contains(WidgetState.selected) ? Colors.white : Colors.green.shade900),
                                shape: WidgetStateProperty.all<OutlinedBorder>(RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.0))),
                                side: WidgetStateProperty.all<BorderSide>(BorderSide.none),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(controller: tonsController, keyboardType: TextInputType.number, onSubmitted: (_) => calculate(), decoration: const InputDecoration(labelText: "Actual Total Tons")),
                        const SizedBox(height: 12),
                        TextField(controller: axlesController, keyboardType: TextInputType.number, onSubmitted: (_) => calculate(), decoration: const InputDecoration(labelText: "Total Axles")),
                      ],

                      const SizedBox(height: 40),

                      // GROUP 5: Verify Load Button
                      Center(
                        child: ElevatedButton(
                          style: ButtonStyle(
                            minimumSize: WidgetStateProperty.all<Size>(const Size(240, 54)),
                            backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) => states.contains(WidgetState.pressed) ? Colors.green.shade900 : Colors.green.shade700),
                            foregroundColor: WidgetStateProperty.all<Color>(Colors.white),
                            shape: WidgetStateProperty.all<OutlinedBorder>(RoundedRectangleBorder(borderRadius: BorderRadius.circular(28.0))),
                            elevation: WidgetStateProperty.all<double>(3),
                          ),
                          onPressed: calculate, 
                          child: const Text("VERIFY LOAD", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.2)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Co-authored Footer Bar
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10.0),
                color: Colors.grey.shade100,
                child: Text(
                  "v$currentAppVersion | Developed by Leon and Gemini",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade600, letterSpacing: 0.5),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
