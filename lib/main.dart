import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

void main() {
  runApp(const LoadTableApp());
}

class LoadTableApp extends StatelessWidget {
  const LoadTableApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TFR Load Tables',
      theme: ThemeData(
        primarySwatch: Colors.green,
        useMaterial3: true,
      ),
      home: const LoadTableScreen(),
    );
  }
}

class LoadTableScreen extends StatefulWidget {
  const LoadTableScreen({super.key});

  @override
  State<LoadTableScreen> createState() => _LoadTableScreenState();
}

class _LoadTableScreenState extends State<LoadTableScreen> {
  // State variables for user inputs
  String selectedLocoClass = '18E_Class';
  String selectedRoute = 'Durban Complex';
  String selectedTrainType = 'Mainline';
  bool isAirbrake = true;
  int numLocos = 1;
  double tons = 0.0;
  double axles = 0.0;
  bool isFlyover = true; // New state variable for Hauler route selection

  // State variables for calculation results
  int calculatedLoad = 0;
  double axleMass = 0.0;
  String warningMessage = "";
  int targetGC = 5;

  // JSON Data storage
  Map<String, dynamic>? jsonData;

  // Static catalog mappings
  final List<String> locoClasses = ['18E_Class', '5E1_Class'];
  final List<String> trainTypes = ['Mainline', 'Hauler', 'LightAirbrake'];

  final Map<String, Map<String, int>> routeCatalog = {
    'Durban Complex': {'Airbrake': 5, 'Vacuum': 5},
    'North Coast': {'Airbrake': 6, 'Vacuum': 6},
    'South Coast': {'Airbrake': 7, 'Vacuum': 7},
    'Mainline Up': {'Airbrake': 8, 'Vacuum': 8},
  };

  @override
  void initState() {
    super.initState();
    loadJsonData();
  }

  // Load and parse the JSON file from assets
Future<void> loadJsonData() async {
      try {
      String jsonString = await rootBundle.loadString('assets/test_data.json');
      setState(() {
        jsonData = json.decode(jsonString);
      });
      calculate();
    } catch (e) {
      setState(() {
        warningMessage = "Error loading data file.";
      });
    }
  }

  // Core Calculation Engine
  void calculate() {
    // Calculate raw axle mass safely
    if (axles > 0) {
      axleMass = tons / axles;
    } else {
      axleMass = 0.0;
    }

    // 1. Dynamic Brake Safety Boundary Check (18.5 t/a for Vacuum, 20 t/a for Airbrake)
    double maxAllowedAxleMass = isAirbrake ? 20.0 : 18.5;

    if (axleMass > maxAllowedAxleMass) {
      setState(() {
        warningMessage = "⚠️ EXCEEDS MAX ${maxAllowedAxleMass.toStringAsFixed(1)} t/a FOR ${isAirbrake ? 'AIRBRAKE' : 'VACUUM'} TRAINS";
        calculatedLoad = 0;
      });
      return;
    } else {
      warningMessage = "";
    }

    // 2. Routed Matrix Lookup (Hauler vs Mainline Branches)
    if (selectedTrainType == 'Hauler') {
      targetGC = isFlyover ? 8 : 12;
    } else {
      String brakeKey = isAirbrake ? 'Airbrake' : 'Vacuum';
      targetGC = routeCatalog[selectedRoute]?[brakeKey] ?? 5;
    }

    // 3. Find matching section in JSON data
    if (jsonData == null || !jsonData!.containsKey(selectedLocoClass)) {
      setState(() {
        calculatedLoad = 0;
      });
      return;
    }

    var locoData = jsonData![selectedLocoClass];
    String brakeCategory = isAirbrake
        ? "AIRBRAKE TRAINS >12.5 to 17 t/a"
        : "VACUUM BRAKED TRAINS > 10 TONS PER AXLE";

    if (locoData is Map && locoData.containsKey(brakeCategory)) {
      var rows = locoData[brakeCategory] as List;
      var matchingRow = rows.firstWhere(
        (row) => row['GC'] == targetGC,
        orElse: () => null,
      );

      if (matchingRow != null) {
        String consistKey = numLocos.toString();
        if (matchingRow.containsKey(consistKey)) {
          setState(() {
            calculatedLoad = matchingRow[consistKey];
          });
          return;
        }
      }
    }

    setState(() {
      calculatedLoad = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TFR Load Tables'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. LOCOMOTIVE CLASS DROPDOWN
            DropdownButtonFormField<String>(
              initialValue: selectedLocoClass,
              decoration: const InputDecoration(labelText: 'Locomotive Class'),
              items: locoClasses.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value.replaceAll('_', ' ')),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  selectedLocoClass = newValue!;
                  calculate();
                });
              },
            ),
            const SizedBox(height: 16),

            // 2. ROUTE DROPDOWN
            DropdownButtonFormField<String>(
              initialValue: selectedRoute,
              decoration: const InputDecoration(labelText: 'Route'),
              items: routeCatalog.keys.map((String route) {
                return DropdownMenuItem<String>(
                  value: route,
                  child: Text(route),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  selectedRoute = newValue!;
                  calculate();
                });
              },
            ),
            const SizedBox(height: 16),

            // DYNAMIC HAULER ROUTE TYPE TOGGLE (Flyover vs Non-Flyover)
            if (selectedTrainType == 'Hauler') ...[
              const Text(
                "Hauler Route Type:",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ToggleButtons(
                  isSelected: [isFlyover, !isFlyover],
                  onPressed: (int index) {
                    setState(() {
                      isFlyover = index == 0;
                      calculate();
                    });
                  },
                  borderRadius: BorderRadius.circular(25.0),
                  fillColor: Colors.green.shade700,
                  selectedColor: Colors.white,
                  color: Colors.green.shade900,
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text('FLYOVER (GC 8)', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text('NON-FLYOVER (GC 12)', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 3. TRAIN OPERATION MODE
            DropdownButtonFormField<String>(
              initialValue: selectedTrainType,
              decoration: const InputDecoration(labelText: 'Train Operation Mode'),
              items: trainTypes.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  selectedTrainType = newValue!;
                  calculate();
                });
              },
            ),
            const SizedBox(height: 16),

            // 4. AIRBRAKE VS VACUUM PILL SLIDER
            const Text(
              "Brake System:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ToggleButtons(
                isSelected: [isAirbrake, !isAirbrake],
                onPressed: (int index) {
                  setState(() {
                    isAirbrake = index == 0;
                    calculate();
                  });
                },
                borderRadius: BorderRadius.circular(25.0),
                fillColor: Colors.green.shade700,
                selectedColor: Colors.white,
                color: Colors.green.shade900,
                children: const [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text('AIRBRAKE', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text('VACUUM', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 5. NUMBER OF LOCOS IN CONSIST
            DropdownButtonFormField<int>(
              initialValue: numLocos,
              decoration: const InputDecoration(labelText: 'Number of Locos in Consist'),
              items: [1, 2, 3, 4].map((int value) {
                return DropdownMenuItem<int>(
                  value: value,
                  child: Text('$value'),
                );
              }).toList(),
              onChanged: (int? newValue) {
                setState(() {
                  numLocos = newValue!;
                  calculate();
                });
              },
            ),
            const SizedBox(height: 16),

            // 6. TOTAL TONS INPUT
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Total Tons',
                hintText: 'Enter total train mass',
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                setState(() {
                  tons = double.tryParse(value) ?? 0.0;
                  calculate();
                });
              },
            ),
            const SizedBox(height: 16),

            // 7. TOTAL AXLES INPUT
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Total Axles',
                hintText: 'Enter total number of axles',
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                setState(() {
                  axles = double.tryParse(value) ?? 0.0;
                  calculate();
                });
              },
            ),
            const SizedBox(height: 24),

            // WARNING ALERT DISPLAY
            if (warningMessage.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade400),
                ),
                child: Text(
                  warningMessage,
                  style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold),
                ),
              ),

            // OUTPUT INFOPANEL CARDS
            Card(
              elevation: 4,
              color: Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Target Route Gradient:', style: TextStyle(fontSize: 16)),
                        Text('GC $targetGC', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Average Axle Mass:', style: TextStyle(fontSize: 16)),
                        Text('${axleMass.toStringAsFixed(2)} t/a', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // VERIFY LOAD RESULT BOX
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: warningMessage.isNotEmpty ? Colors.grey : Colors.green.shade800,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: warningMessage.isNotEmpty ? null : () {},
                child: Text(
                  calculatedLoad > 0 
                      ? 'MAX AUTHORIZED LOAD: $calculatedLoad TONS'
                      : 'CALCULATE LOAD LIMIT',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}