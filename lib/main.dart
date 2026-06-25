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
  // Input Controllers
  final TextEditingController tonsController = TextEditingController();
  final TextEditingController axlesController = TextEditingController();
  final TextEditingController wagonsController = TextEditingController();

  // Flag to prevent infinite feedback loops when fields update each other
  bool _isUpdatingAxlesOrWagons = false;

  // Selected State Form Values
  String selectedTrainType = 'Mainline';
  String selectedRoute = 'Dbn_Sth_Loop';
  String selectedLoco = '18E_Class';
  int selectedLocoCount = 1;
  bool isAirbrake = true;

  @override
  void initState() {
    super.initState();
    
    // Set up bidirectional listeners to sync Axles and Wagons automatically
    axlesController.addListener(_onAxlesChanged);
    wagonsController.addListener(_onWagonsChanged);
  }

  @override
  void dispose() {
    axlesController.removeListener(_onAxlesChanged);
    wagonsController.removeListener(_onWagonsChanged);
    tonsController.dispose();
    axlesController.dispose();
    wagonsController.dispose();
    super.dispose();
  }

  void _onAxlesChanged() {
    if (_isUpdatingAxlesOrWagons) return;
    _isUpdatingAxlesOrWagons = true;

    final axlesText = axlesController.text;
    if (axlesText.isEmpty) {
      wagonsController.text = "";
    } else {
      final axles = int.tryParse(axlesText);
      if (axles != null) {
        double wagons = axles / 4;
        wagonsController.text = wagons % 1 == 0 ? wagons.toInt().toString() : wagons.toStringAsFixed(1);
      }
    }
    _isUpdatingAxlesOrWagons = false;
  }

  void _onWagonsChanged() {
    if (_isUpdatingAxlesOrWagons) return;
    _isUpdatingAxlesOrWagons = true;

    final wagonsText = wagonsController.text;
    if (wagonsText.isEmpty) {
      axlesController.text = "";
    } else {
      final wagons = double.tryParse(wagonsText);
      if (wagons != null) {
        int axles = (wagons * 4).round();
        axlesController.text = axles.toString();
      }
    }
    _isUpdatingAxlesOrWagons = false;
  }

  void calculate() {
    // 1. MANDATORY FIELDS VALIDATION (Checks all 3 fields)
    if (tonsController.text.trim().isEmpty || 
        axlesController.text.trim().isEmpty || 
        wagonsController.text.trim().isEmpty) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text("⚠️ Missing Information", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
          content: const Text("All input fields are mandatory.\n\nPlease enter values for Total Tons, Axles, and Wagons before verifying."),
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: ElevatedButton(
                  style: ButtonStyle(
                    minimumSize: WidgetStateProperty.all<Size>(const Size(140, 44)),
                    backgroundColor: WidgetStateProperty.all<Color>(Colors.green.shade700),
                    foregroundColor: WidgetStateProperty.all<Color>(Colors.white),
                    shape: WidgetStateProperty.all<OutlinedBorder>(RoundedRectangleBorder(borderRadius: BorderRadius.circular(22.0))),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

    final double? tons = double.tryParse(tonsController.text);
    final int? axles = int.tryParse(axlesController.text);

    if (tons == null || axles == null) return;

    // 2. MULTIPLE OF 4 RAILWAY VALIDATION
    if (axles % 4 != 0) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text("🚂 Operational Input Error", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
          content: Text("Total Axles ($axles) must be a multiple of 4 to match standard wagon configurations (e.g., ${(axles ~/ 4) * 4} or ${((axles ~/ 4) + 1) * 4} axles)."),
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: ElevatedButton(
                  style: ButtonStyle(
                    minimumSize: WidgetStateProperty.all<Size>(const Size(140, 44)),
                    backgroundColor: WidgetStateProperty.all<Color>(Colors.green.shade700),
                    foregroundColor: WidgetStateProperty.all<Color>(Colors.white),
                    shape: WidgetStateProperty.all<OutlinedBorder>(RoundedRectangleBorder(borderRadius: BorderRadius.circular(22.0))),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

    // Baseline calculation engine variables
    double axleMass = tons / axles;
    double targetGC = (isAirbrake) ? 14.0 : 12.0;
    String blockKey = "";

    if (axleMass <= 16.0) {
      blockKey = "16_Ton_Max";
    } else if (axleMass <= 18.5) {
      blockKey = "18.5_Ton_Max";
    } else if (axleMass <= 20.0) {
      blockKey = "20_Ton_Max";
    } else if (axleMass <= 22.0) {
      blockKey = "22_Ton_Max";
    } else {
      blockKey = "Overweight_Error";
    }

    if (blockKey == "Overweight_Error") {
      showDialog(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text("❌ OVERWEIGHT", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          content: Text("The calculated Axle Mass Load (${axleMass.toStringAsFixed(2)} t/a) exceeds structural operating allowances."),
          actions: [
            Center(
              child: ElevatedButton(
                style: ButtonStyle(
                  minimumSize: WidgetStateProperty.all<Size>(const Size(140, 44)),
                  backgroundColor: WidgetStateProperty.all<Color>(Colors.green.shade700),
                  foregroundColor: WidgetStateProperty.all<Color>(Colors.white),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("OK"),
              ),
            ),
          ],
        ),
      );
      return;
    }

    // Lookup row data structures (Using your verified variable: loadTables)
    bool foundRowMatch = false;
    double baselineMaxTons = 0.0;
    double allowanceTons = 0.0;
    double totalAllowedTons = 0.0;
    double estimatedWagons = axles / 4;

    for (var row in loadTables) {
      if (row['loco_class'] == selectedLoco &&
          row['load_type'] == blockKey &&
          row['route_id'] == selectedRoute &&
          row['gc_rating'] == targetGC) {
        
        foundRowMatch = true;
        baselineMaxTons = (row['base_load'] as num).toDouble();
        allowanceTons = (row['allowance_per_wagon'] as num).toDouble() * estimatedWagons;
        
        double totalBaseCapacity = baselineMaxTons * selectedLocoCount;
        totalAllowedTons = totalBaseCapacity + allowanceTons;
        break;
      }
    }

    // Isolation layout rules logic check
    bool showIsolationWarning = false;
    String isolationWarningMessage = "";
    if (selectedLocoCount > 1) {
      for (var rule in isolationRules) {
        if (rule['loco_class'] == selectedLoco && rule['route_id'] == selectedRoute) {
          int maxGroup = rule['max_coupled_group'] as int;
          if (selectedLocoCount > maxGroup) {
            showIsolationWarning = true;
            isolationWarningMessage = rule['warning_text'] as String;
          }
          break;
        }
      }
    }

    String warning = "";
    if (!foundRowMatch) {
      warning = "";
    } else if (selectedLoco == "18E_Class" && selectedLocoCount > 4 && (selectedRoute == "Dbn_Sth_Loop" || selectedRoute == "Wst_Afr_Line")) {
      warning = "Substation capacity limitations restrict running more than 4 active units on this corridor layout.";
    }

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
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: ElevatedButton(
                    style: ButtonStyle(
                      minimumSize: WidgetStateProperty.all<Size>(const Size(160, 48)),
                      backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) => states.contains(WidgetState.pressed) ? Colors.green.shade900 : Colors.green.shade700),
                      foregroundColor: WidgetStateProperty.all<Color>(Colors.white),
                      shape: WidgetStateProperty.all<OutlinedBorder>(RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.0))),
                      elevation: WidgetStateProperty.all<double>(2),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1.1)),
                  ),
                ),
              ),
            ],
          );
        },
      );
    } else {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: const Text("🔍 No Entries Found", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
            content: Text(
              "AAM: ${axleMass.toStringAsFixed(2)} t/a\n"
              "Block Key: $blockKey\n\n"
              "No structural data matching these validation criteria exists in the registry data tables."
            ),
            actions: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: ElevatedButton(
                    style: ButtonStyle(
                      minimumSize: WidgetStateProperty.all<Size>(const Size(160, 48)),
                      backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) => states.contains(WidgetState.pressed) ? Colors.green.shade900 : Colors.green.shade700),
                      foregroundColor: WidgetStateProperty.all<Color>(Colors.white),
                      shape: WidgetStateProperty.all<OutlinedBorder>(RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.0))),
                      elevation: WidgetStateProperty.all<double>(2),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1.1)),
                  ),
                ),
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
        bool isWideScreen = constraints.maxWidth > 600;

        return Form(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isWideScreen) ...[
                        // ===================================================================
                        // DESKTOP WIDE GRID VIEW
                        // ===================================================================
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
                        const SizedBox(height: 20),

                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Brake Type:", style: TextStyle(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 6),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: SizedBox(
                                      width: 440,
                                      child: SegmentedButton<bool>(
                                        showSelectedIcon: true,
                                        segments: const <ButtonSegment<bool>>[
                                          ButtonSegment<bool>(value: true, label: FittedBox(child: Text('AIRBRAKE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.8)))),
                                          ButtonSegment<bool>(value: false, label: FittedBox(child: Text('VACUUM', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.8)))),
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
                                ],
                              ),
                            ),
                            const SizedBox(width: 24),
                            const Expanded(child: SizedBox()),
                          ],
                        ),
                        const SizedBox(height: 24),

                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: tonsController, 
                                keyboardType: TextInputType.number, 
                                onSubmitted: (_) => calculate(),
                                decoration: const InputDecoration(labelText: "Actual Total Tons", border: OutlineInputBorder())
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: axlesController, 
                                      keyboardType: TextInputType.number, 
                                      onSubmitted: (_) => calculate(),
                                      decoration: const InputDecoration(labelText: "Total Axles", border: OutlineInputBorder())
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: wagonsController, 
                                      keyboardType: TextInputType.number, 
                                      onSubmitted: (_) => calculate(),
                                      decoration: const InputDecoration(labelText: "Total Wagons", border: OutlineInputBorder())
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        // ===================================================================
                        // MOBILE PORTRAIT VIEW
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
                        const Text("Brake Type:", style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Center(
                          child: SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<bool>(
                              showSelectedIcon: true,
                              segments: const <ButtonSegment<bool>>[
                                ButtonSegment<bool>(value: true, label: FittedBox(child: Text('AIRBRAKE', style: TextStyle(fontWeight: FontWeight.bold)))),
                                ButtonSegment<bool>(value: false, label: FittedBox(child: Text('VACUUM', style: TextStyle(fontWeight: FontWeight.bold)))),
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
                        TextField(controller: tonsController, keyboardType: TextInputType.number, onSubmitted: (_) => calculate(), decoration: const InputDecoration(labelText: "Actual Total Tons", border: OutlineInputBorder())),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: TextField(controller: axlesController, keyboardType: TextInputType.number, onSubmitted: (_) => calculate(), decoration: const InputDecoration(labelText: "Total Axles", border: OutlineInputBorder()))),
                            const SizedBox(width: 12),
                            Expanded(child: TextField(controller: wagonsController, keyboardType: TextInputType.number, onSubmitted: (_) => calculate(), decoration: const InputDecoration(labelText: "Total Wagons", border: OutlineInputBorder()))),
                          ],
                        ),
                      ],

                      const SizedBox(height: 40),

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

// ===================================================================
// GLOBAL DATA STORAGE ARRAYS (Now securely linked back up)
// ===================================================================
final List<String> trainTypes = ['Mainline', 'Hauler'];
final List<String> mainlineRoutes = ['Dbn_Sth_Loop', 'Ntl_Corridor', 'Gauteng_Main'];
final List<String> haulerRoutes = ['Wst_Afr_Line', 'Sth_Mnd_Link'];
final List<int> locoCounts = [1, 2, 3, 4, 5, 6];

final List<Map<String, String>> locos = [
  {'value': '18E_Class', 'display': '18E (VB10)'},
  {'value': '20E_Class', 'display': '20E (Dual Volt)'},
  {'value': '22E_Class', 'display': '22E (VB14)'},
];

final List<Map<String, dynamic>> isolationRules = [
  {
    'loco_class': '18E_Class',
    'route_id': 'Dbn_Sth_Loop',
    'max_coupled_group': 3,
    'warning_text': 'No provision for more than 3 x 18E locos on this route. Extra locos must be isolated.'
  }
];

final List<Map<String, dynamic>> loadTables = [
  {
    'loco_class': '18E_Class',
    'load_type': '20_Ton_Max',
    'route_id': 'Dbn_Sth_Loop',
    'gc_rating': 14.0,
    'base_load': 1600,
    'allowance_per_wagon': 1.0
  }
];

final String currentAppVersion = "1.0.4";