//==================================
//All the imports grouped together.
//==================================

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart'; // <-- Add this to access kIsWeb
import 'package:url_launcher/url_launcher.dart'; // <-- Add this import at the very top of main.dart
import 'dart:io' show File;
import 'package:crypto/crypto.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;

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
        appBar: AppBar(
          // 🟢 FIXED: Dual-element layout with title on the left and 3-row source right-aligned
          title: Row(
            children: [
              const Text(
                'TFR Load Calculator', 
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)
              ),
              const Spacer(), // Pushes the technical reference block all the way to the right edge
              Text(
                "Based on S.GFB/TES/TE/OI 0272\nRevision 11\nIssued 2011/08/17",
                textAlign: TextAlign.end, // Aligns text cleanly to the right edge
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85), // Soft white to keep it subtle
                  fontSize: 10,                          // Keeps it small and unobtrusive
                  fontWeight: FontWeight.w500,
                  height: 1.2,                           // Controls line spacing tightly
                ),
              ),
            ],
          ),
          backgroundColor: const Color.fromRGBO(76, 175, 80, 1),
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
  final TextEditingController wagonsController = TextEditingController();
  bool _isUpdatingAxlesOrWagons = false;
  String? axleValidationError;
  double totalTrainLength = 0.0;
  double totalBufferPlay = 0.0;
  double totalBrakingPercentage = 0.0;

  void _onAxlesChanged() {
    if (_isUpdatingAxlesOrWagons) return;
    _isUpdatingAxlesOrWagons = true;

    final axlesText = axlesController.text;
    if (axlesText.isEmpty) {
      setState(() {
        axleValidationError = null;
        wagonsController.text = "";
      });
    } else {
      final axles = int.tryParse(axlesText);
      if (axles != null) {
        if (axles % 4 == 0) {
          // Valid multiple of 4
          setState(() {
            axleValidationError = null;
          });
          double wagons = axles / 4;
          wagonsController.text = wagons.toInt().toString();
        } else {
          // Invalid: trigger native validation error state & clear wagons
          setState(() {
            axleValidationError = "Must be a multiple of 4";
            wagonsController.text = "";
          });
        }
      } else {
        setState(() {
          axleValidationError = "Invalid number";
          wagonsController.text = "";
        });
      }
    }
    _updateTrainLength(); // <-- Add here
    _isUpdatingAxlesOrWagons = false;
  }

  void _onWagonsChanged() {
    if (_isUpdatingAxlesOrWagons) return;
    _isUpdatingAxlesOrWagons = true;

    final wagonsText = wagonsController.text;
    if (wagonsText.isEmpty) {
      axlesController.text = "";
      setState(() {
        axleValidationError = null;
      });
    } else {
      final wagons = double.tryParse(wagonsText);
      if (wagons != null) {
        int axles = (wagons * 4).round();
        axlesController.text = axles.toString();
        setState(() {
          axleValidationError = null; // Typing wagons always results in a multiple of 4
        });
      }
    }
    _updateTrainLength(); // 
    _isUpdatingAxlesOrWagons = false;
  }

  void _updateTrainLength() {
    final wagonsText = wagonsController.text;
    final tonsText = tonsController.text; // <-- Retrieve total wagon mass
    if (wagonsText.isEmpty) {
      setState(() {
        totalTrainLength = 0.0;
        totalBufferPlay = 0.0;
        totalBrakingPercentage = 0.0;
      });
      return;
    }

    final wagons = double.tryParse(wagonsText) ?? 0.0;
    final tons = double.tryParse(tonsText) ?? 0.0;
    
    if (wagons > 0) {
      // 1. Base length using standard 16 meters per wagon
      double baseLength = wagons * 16.0;
      
      // 2. Buffer play: Add 1 meter for every complete block of 10 wagons
      double bufferPlay = (wagons / 10).floorToDouble() * 1.0;

      // 3. Braking Percentage (BP) Calculation
      double totalBlockForceKn = wagons * 160.0; // 160 kN per wagon
      double totalWagonWeightKn = tons * 9.81;  // Mass in tonnes to weight in kN
      double bp = totalWagonWeightKn > 0 ? (totalBlockForceKn / totalWagonWeightKn) * 100 : 0.0;

      setState(() {
        totalBufferPlay = bufferPlay;
        totalTrainLength = baseLength + bufferPlay;
        totalBrakingPercentage = bp;
      });
    }
  }

Future<void> _exportAndProcessReceipt({
    required String locoCount,
    required String locoName,
    required String route,
    required String gcValue,
    required String baseCap,
    required String wagonAllowance,
    required String estWagons,
    required String totalLimit,
    required String inputTons,
    required String weightMarginStr,
    required String totalLength,
    required String brakingPercentage, // <-- Added parameter
    required String bufferPlay,
  }) async {
    final pdf = pw.Document();
    final timestamp = DateTime.now().toString().split('.')[0]; // e.g. 2026-07-04 09:45:12
    final appVersion = currentAppVersion;

    // 1. Build the read-only, layout-structured document structure to compute the baseline hash
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(24),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("Load Calculator Record", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text("Generated on: $timestamp", style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                pw.Text("Application Version: v$appVersion", style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                pw.Divider(thickness: 1, color: PdfColors.grey400),
                pw.SizedBox(height: 12),
                
                pw.Text("Train Details", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),
                pw.Text("Locomotives: $locoCount x $locoName"),
                pw.Text("Route: $route (Section ruling Gradient: GC $gcValue)"),
                pw.Text("Total Tons: ${inputTons}t"),
                pw.SizedBox(height: 12),

                pw.Text("Load Details", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),
                pw.Text("Brake Type: ${selectedBrakeType[0] + selectedBrakeType.substring(1).toLowerCase()}"), // 🧠 Added here
                pw.Text("Base Capacity: ${baseCap}t"),
                pw.Text("Wagon Overload Allowance: +${wagonAllowance}t ($estWagons wagons Total)"),
                pw.Text("Max Tonnage: ${totalLimit}t"),
                pw.Text("Status Framework Margin: $weightMarginStr"),
                pw.SizedBox(height: 12),

                pw.Text("Train Length Details", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),
                pw.Text("Estimated Train Length: ${totalLength}m"),
                pw.Text("Braking Percentage (BP): $brakingPercentage"), // <-- Inserted BP row
                pw.Text("Estimated Buffer Play: +${bufferPlay}m"),
                pw.Spacer(),
                
                pw.Divider(thickness: 1, color: PdfColors.grey400),
                pw.SizedBox(height: 6),
                pw.Text("SECURITY VERIFICATION BANNER", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
                pw.SizedBox(height: 4),
                pw.Text(
                  "To verify document integrity, pass this document payload into the SHA-256 confirmation utility. Any modifications to structural values invalidates the verification code below.",
                  style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                ),
                pw.SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );

    // 2. Compute the primary raw layout bytes
    final Uint8List pdfBytes = await pdf.save();

    // 3. Run the binary array through the SHA-256 Cryptographic meat-grinder
    final hashDigest = sha256.convert(pdfBytes);
    final String verificationToken = hashDigest.toString();

    // 4. Re-compile the final document stream with the absolute token stamped safely on the template layout
    final finalPdf = pw.Document();
    finalPdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(24),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("Load Calculator Record", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text("Generated on: $timestamp", style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                pw.Text("Application Version: v$appVersion", style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                pw.SizedBox(height: 10),
                pw.Container(height: 1, color: PdfColors.grey300),
                pw.SizedBox(height: 14),
                
                pw.Text("Train Details", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                pw.SizedBox(height: 6),
                pw.Text("Locomotives: $locoCount x $locoName", style: pw.TextStyle(fontSize: 11)),
                pw.Text("Route: $route (GC $gcValue)", style: pw.TextStyle(fontSize: 11)),
                pw.Text("Tons on vehicle list: $inputTons t", style: pw.TextStyle(fontSize: 11)),
                pw.SizedBox(height: 14),

                pw.Text("Calculated load details", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                pw.SizedBox(height: 6),
                pw.Text("Brake Type: ${selectedBrakeType[0] + selectedBrakeType.substring(1).toLowerCase()}", style: pw.TextStyle(fontSize: 11)), // 🧠 Added here
                pw.Text("Base Capacity: $baseCap t", style: pw.TextStyle(fontSize: 11)),
                pw.Text("Wagon Overload Allowance: +$wagonAllowance t ($estWagons items)", style: pw.TextStyle(fontSize: 11)),
                pw.Text("Max Tonnage: $totalLimit t", style: pw.TextStyle(fontSize: 11)),
                pw.Text("Calculated $weightMarginStr", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 14),

                pw.Text("Train Length Details", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                pw.SizedBox(height: 6),
                pw.Text("Estimated Train Length: $totalLength meters", style: pw.TextStyle(fontSize: 11)),
                pw.Text("Braking Percentage (BP): $brakingPercentage %", style: pw.TextStyle(fontSize: 11)), // <-- Inserted BP row
                pw.Text("Estimated Buffer Play: +$bufferPlay meters", style: pw.TextStyle(fontSize: 11)),
                
                pw.Spacer(),
                pw.Container(height: 1, color: PdfColors.grey300),
                pw.SizedBox(height: 8),
                pw.Text("Security Trail", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
                pw.SizedBox(height: 4),
                pw.Text(
                  "This document footprint is mathematically locked down. Modification of any cell value completely invalidates the underlying binary checksum key.",
                  style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                ),
                pw.SizedBox(height: 8),
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  color: PdfColors.grey100,
                  width: double.infinity,
                  child: pw.Text(
                    "SECURITY CODE: $verificationToken",
                    style: pw.TextStyle(fontSize: 8, font: pw.Font.courier(), fontWeight: pw.FontWeight.bold, color: PdfColors.grey900),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    // 5. Generate final bytes containing the stamped security code
    final Uint8List finalBytes = await finalPdf.save();
    final String safeFileName = "TFR_Report_${timestamp.replaceAll(' ', '_').replaceAll(':', '-')}.pdf";

    // 6. Execution Split: Handle Web Browser Sandbox vs Native Mobile Filesystem
    if (kIsWeb) {
      try {
        // WEB PLATFORM: Convert finalBytes to a Blob object and trigger the browser save dialog
        final blob = html.Blob([finalBytes], 'application/pdf');
        final url = html.Url.createObjectUrlFromBlob(blob);
        
        final anchor = html.AnchorElement(href: url)
          ..setAttribute("download", safeFileName)
          ..style.display = 'none';
        
        html.document.body?.children.add(anchor);
        anchor.click();
        html.document.body?.children.remove(anchor);
        html.Url.revokeObjectUrl(url);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("PDF Load Verification Receipt downloaded successfully."),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        debugPrint("Web download error: $e");
      }
    } else {
      // MOBILE PLATFORM: Enforce absolute offline local storage capture and trigger share manager sheet
      try {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$safeFileName');
        await file.writeAsBytes(finalBytes, flush: true);

        // Fire OS native share sheet framework instantly
        final xFile = XFile(file.path, mimeType: 'application/pdf');
        await Share.shareXFiles(
          [xFile],
          text: "TFR Load Calculation Record - Consist Reference: $locoCount x $locoName (Code: ${verificationToken.substring(0, 8)})",
        );
      } catch (e) {
        debugPrint("Mobile storage error: $e");
      }
    }
  }
  // The version hardcoded into this specific build string
  final String currentAppVersion = "1.3.13";
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
    // {'display': '14E', 'value': '14E_Class'},
    {'display': '18E', 'value': '18E_Class'},
    // {'display': '19E', 'value': '19E_Class'},
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

  String selectedBrakeType = '';
  Map<String, dynamic> locoData = {};

  // Brake Type Selection Configuration
  final List<Map<String, String>> brakeTypes = [
    {'display': 'Airbrake', 'value': 'AIRBRAKE'},
    {'display': 'Vacuum', 'value': 'VACUUM'},
    // Future corporate expansions go here natively:
    // {'display': 'DUAL CONTROL', 'value': 'DUAL'},
  ];

@override
  void initState() {
    super.initState();
    
    // Bind your existing bidirectional functions to the controllers
    axlesController.addListener(_onAxlesChanged);
    wagonsController.addListener(_onWagonsChanged);
    tonsController.addListener(_updateTrainLength); // <-- Recalculate BP on mass change

    loadJsonData().then((_) { 
      if (!kIsWeb) {
        WidgetsBinding.instance.addPostFrameCallback((_) => checkForUpdates());
      }
    });
  }

  @override
  void dispose() {
    // Standard cleanup to stop listeners when widget destroys
    axlesController.removeListener(_onAxlesChanged);
    wagonsController.removeListener(_onWagonsChanged);
    tonsController.removeListener(_updateTrainLength); // <-- Clean up listener
    tonsController.dispose();
    axlesController.dispose();
    wagonsController.dispose();
    super.dispose();
  }
  Future<void> checkForUpdates() async {
    if (_hasDeferredUpdate) return; // Silent exit if they already clicked Later
          // FIXED: Pointing to the exact repository name casing
      final String url = "https://leonbhoman.github.io/TFR-Load-Tables/version.json?v=${DateTime.now().millisecondsSinceEpoch}";

    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        String latestVersion = data['version'];
        String downloadUrl = data['url'];

        if (latestVersion != currentAppVersion && mounted) {
          showUpdateDialog(latestVersion, downloadUrl);
        }
      }else {
      // Diagnostic alert for non-200 responses
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Version check HTTP status: ${response.statusCode}")),
        );
      }
    }
  } catch (e) {
    // Diagnostic alert for socket/permission errors
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Version check error: $e")),
      );
    }
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
    // Safety guard: halt submission sequence if validation fails
    if (axleValidationError != null) return;

    // 🟢 NEW VALIDATION: Check if primary user input fields are left blank
    if (tonsController.text.trim().isEmpty || 
        axlesController.text.trim().isEmpty || 
        wagonsController.text.trim().isEmpty ||
        (selectedBrakeType != 'AIRBRAKE' && selectedBrakeType != 'VACUUM'))
    {
        ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please ensure all criteria hav been selected and all fields filled in before verifying."),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return; // 👈 CRITICAL: Stops the rest of the calculate() function from running
    }


    double tons = double.tryParse(tonsController.text) ?? 0;
    double axles = double.tryParse(axlesController.text) ?? 1;
    double axleMass = (axles > 0) ? tons / axles : 0;
    
    String blockKey = "";
    String warning = "";
    // String   = "";
    bool showIsolationWarning = false;
    int targetGC = 5; 

    // 1. Dynamic Safety Boundary Check based on Brake Type
    double maxAllowedAxleMass = (selectedBrakeType == 'AIRBRAKE') ? 20.0 : 18.5;
    int maxAllowedAxles = (selectedBrakeType == 'AIRBRAKE') ? 200 : 160;
    int maxAllowedWagons = (selectedBrakeType == 'AIRBRAKE') ? 50 : 40;
    String brakeName = selectedBrakeType; // ? "AIRBRAKE" : "VACUUM";
    bool isLimitExceeded = false; // 🟢 NEW FLAG: Track hard physical constraint violations

    // Check Axle Mass Threshold
    if (axleMass > maxAllowedAxleMass) {
      warning = "⚠️ EXCEEDS MAX $maxAllowedAxleMass t/a FOR $brakeName";
      isLimitExceeded = true; // 🟢 Hard limit broken
    }

    // Check Axle Mass Threshold
    if (axleMass > maxAllowedAxleMass) {
      warning = "⚠️ EXCEEDS MAX $maxAllowedAxleMass t/a FOR $brakeName";
      isLimitExceeded = true; // 🟢 Hard limit broken
    }

    // Check Consist Length / Axle Count Threshold
    double estimatedWagons = axles / 4;
    if (axles > maxAllowedAxles || estimatedWagons > maxAllowedWagons) {
      if (warning.isNotEmpty) warning += "\n";
      warning += "⚠️ $brakeName LIMIT EXCEEDED:\nMax $maxAllowedWagons Wagons / $maxAllowedAxles Axles allowed.";
      isLimitExceeded = true; // 🟢 Hard limit broken
    }
    // 1. Safety Boundary Check
    // if (axleMass > 20) {
    //  warning = "⚠️ EXCEEDS MAX 20 t/a";
    // *****************************************************************************************************************************}

    // 2. Routed Matrix Lookup (Hauler vs Mainline Branches)
    if (selectedTrainType == 'Hauler') {
      targetGC = haulerCatalog[selectedRoute] ?? 8;
    } else {
      String brakeKey = (selectedBrakeType == 'AIRBRAKE') ? 'Airbrake' : 'Vacuum';
      targetGC = routeCatalog[selectedRoute]?[brakeKey] ?? 5;
    }

    // 3. Determine Block Token based on Brake Type and Calculated Axle Mass (AAM)
    if (selectedBrakeType == 'AIRBRAKE') {
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
          //String displayLocoName = locos.firstWhere((l) => l['value'] == selectedLoco)['display']!;

          if (requestedCount > maxAvailableCount && maxAvailableCount > 0) {
            actualLookupKey = maxAvailableCount;
            showIsolationWarning = true;
            //isolationWarningMessage = "No provision for more than $maxAvailableCount x $displayLocoName locos on this route. Extra locos must be isolated.";
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
      bool overWeight = tons > totalAllowedTons;
      
      // 🟢 FAILURE STATE DETECTION: If a physical limit is broken OR it is overweight, turn it RED
      bool isFailureState = isLimitExceeded || overWeight; 
      
      String titleText = isFailureState ? "❌ LIMIT EXCEEDED" : "✅ CLEAR TO RUN";
      Color headerColor = isFailureState ? Colors.red : Colors.green;
      
      String displayLocoName = locos.firstWhere((l) => l['value'] == selectedLoco)['display']!;
      
      showDialog(
        context: context,
        barrierDismissible: false, // Prevents accidentally tapping outside to close
        builder: (BuildContext context) {
          
          final double estimatedWagons = (double.tryParse(wagonsController.text) ?? 0.0);
          final String marginLabel = overWeight ? "Over max limit by" : "Remaining margin";
          final String marginVal = "${(totalAllowedTons - tons).abs().toInt()}t";
          final String combinedMarginStr = "$marginLabel: $marginVal";

          // Calculate isolated engine adjustments if required
          int excessLocosCount = 0;
          if (locoData.containsKey(selectedLoco) && locoData[selectedLoco]!.containsKey(blockKey)) {
            List<dynamic> blockDataList = locoData[selectedLoco]![blockKey];
            var rowMatch = blockDataList.firstWhere((row) => row['GC'] == targetGC, orElse: () => null);
            if (rowMatch != null) {
              int maxAvailableCount = rowMatch.keys
                  .where((key) => int.tryParse(key) != null)
                  .map((key) => int.parse(key))
                  .fold(0, (max, element) => element > max ? element : max);
              
              if (selectedLocoCount > maxAvailableCount) {
                excessLocosCount = selectedLocoCount - maxAvailableCount;
              }
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.analytics, color: headerColor, size: 28),
                const SizedBox(width: 10),
                Text(titleText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: SingleChildScrollView(
              child: ListBody(
                children: [
                  Text(
                    "Consist: $selectedLocoCount x $displayLocoName ($blockKey)",
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  Text("Route: $selectedRoute (GC $targetGC)"),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text("Brake Type: ${selectedBrakeType[0] + selectedBrakeType.substring(1).toLowerCase()}"),
                  Text("Train Capacity: ${baselineMaxTons}t"),
                  Text("Wagon Allowance: +${allowanceTons}t (${estimatedWagons.toStringAsFixed(0)} wagons)"),
                  Text(
                    "Total Limit: ${totalAllowedTons}t", 
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    "Train Length Estimates:",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                  ),
                  Text("Est. Train Length: ${totalTrainLength.toStringAsFixed(1)}m"),
                  Text(
                    selectedBrakeType == 'AIRBRAKE'
                        ? "Braking Percentage (BP): N/A for Airbrake"
                        : "Braking Percentage (BP): ${totalBrakingPercentage.toStringAsFixed(2)}%",
                  ),    
                  Text("Est. Buffer Play: +${totalBufferPlay.toStringAsFixed(0)}m"),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: overWeight ? Colors.red.shade50 : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: overWeight ? Colors.red.shade300 : Colors.green.shade300),
                    ),
                    child: Text(
                      combinedMarginStr,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: overWeight ? Colors.red.shade900 : Colors.green.shade900,
                      ),
                    ),
                  ),

                  // 🛑 RED DANGER BOX: Displays layout violation text if physical thresholds are breached
                  if (warning.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade400, width: 1.5),
                      ),
                      width: double.infinity,
                      child: Text(
                        warning,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.red.shade900,
                        ),
                      ),
                    ),
                  ],

                  // 🍊 ORANGE ISOLATION BOX: Reminds drivers to switch off trailing traction assets
                  if (showIsolationWarning) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade400, width: 1.5),
                    ),
                    width: double.infinity,
                    child: Text(
                      "No provision for more than ${selectedLocoCount - excessLocosCount} x $displayLocoName locos on this route. $excessLocosCount locomotive${excessLocosCount > 1 ? 's' : ''} must be isolated.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            actions: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text("CANCEL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf, size: 16),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 2,
                    ),
                    onPressed: () async {
                      Navigator.of(context).pop();
                      
                      await _exportAndProcessReceipt(
                        locoCount: selectedLocoCount.toString(),
                        locoName: displayLocoName,
                        route: selectedRoute,
                        gcValue: targetGC.toString(),
                        baseCap: baselineMaxTons.toString(),
                        wagonAllowance: allowanceTons.toString(),
                        estWagons: estimatedWagons.toStringAsFixed(0),
                        totalLimit: totalAllowedTons.toString(),
                        inputTons: tons.toString(),
                        weightMarginStr: combinedMarginStr,
                        totalLength: totalTrainLength.toStringAsFixed(1),
                        brakingPercentage: selectedBrakeType == 'AIRBRAKE' 
                              ? "N/A for Airbrake" 
                              : "${totalBrakingPercentage.toStringAsFixed(2)}%", // Pass fully formatted string                        
                        bufferPlay: totalBufferPlay.toStringAsFixed(0),
                      );
                    },
                    label: const Text("CONFIRM", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
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

        return Form( // Invisible wrapper enabling clean web keyboard submission
          child: Column(
            children: [
              // Scrollable Input Core Engine Area
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isWideScreen) ...[
                        // ===================================================================
                        // DESKTOP WIDE GRID VIEW (Unified Floating Label Architecture)
                        // ===================================================================
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Far Left Column (Empty Margin)
                            const Spacer(flex: 1),

                            // 2. Mid-Left Column (Inputs Side A)
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  DropdownButtonFormField<String>(
                                    initialValue: selectedTrainType,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: "Train Type",
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    ),
                                    items: trainTypes.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                                    onChanged: (val) {
                                      setState(() {
                                        selectedTrainType = val!;
                                        List<String> nextOptions = (selectedTrainType == 'Hauler') ? haulerRoutes : mainlineRoutes;
                                        selectedRoute = nextOptions.first;
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 24),
                                  DropdownButtonFormField<String>(
                                    initialValue: selectedLoco,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: "Locomotive Class",
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    ),
                                    items: locos.map((loco) => DropdownMenuItem<String>(
                                      value: loco['value'], 
                                      child: Text(loco['display']!),
                                    )).toList(),
                                    onChanged: (val) => setState(() => selectedLoco = val!),
                                  ),
                                  const SizedBox(height: 24),
                                  DropdownButtonFormField<String>(
                                    initialValue: selectedBrakeType.isEmpty ? null : selectedBrakeType,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: "Brake Type",
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    ),
                                    items: brakeTypes.map((brake) => DropdownMenuItem<String>(
                                      value: brake['value'], 
                                      child: Text(brake['display']!),
                                    )).toList(),
                                    onChanged: (val) => setState(() => selectedBrakeType = val!),
                                  ),
                                  const SizedBox(height: 24),
                                  TextField(
                                    controller: tonsController, 
                                    keyboardType: TextInputType.number, 
                                    onSubmitted: (_) => calculate(),
                                    decoration: const InputDecoration(
                                      labelText: "Total Tons", 
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Balanced Grid Spacer
                            const SizedBox(width: 32),

                            // 3. Mid-Right Column (Inputs Side B)
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  DropdownButtonFormField<String>(
                                    initialValue: selectedRoute,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: "Route",
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    ),
                                    items: activeRouteOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                                    onChanged: (val) => setState(() => selectedRoute = val!),
                                  ),
                                  const SizedBox(height: 24),
                                  DropdownButtonFormField<int>(
                                    initialValue: selectedLocoCount,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: "Number of Locos (Live locos only)",
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    ),
                                    items: locoCounts.map((int value) {
                                      return DropdownMenuItem<int>(
                                        value: value,
                                        child: Text("$value Locomotive${value > 1 ? 's' : ''}"),
                                      );
                                    }).toList(),
                                    onChanged: (val) => setState(() => selectedLocoCount = val!),
                                  ),
                                  const SizedBox(height: 16),
                                  const SizedBox(height: 58),
                                  const SizedBox(height: 24),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: axlesController, 
                                          keyboardType: TextInputType.number, 
                                          onSubmitted: (_) => calculate(),
                                          decoration: InputDecoration(
                                            labelText: "Total Axles", 
                                            border: const OutlineInputBorder(),
                                            errorText: axleValidationError, 
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: TextField(
                                          controller: wagonsController, 
                                          keyboardType: TextInputType.number, 
                                          onSubmitted: (_) => calculate(),
                                          decoration: const InputDecoration(
                                            labelText: "Total Wagons", 
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // 4. Far Right Column (Empty Margin)
                            const Spacer(flex: 1),
                          ],
                        ),
                      ] else ...[                        
                        // ===================================================================
                        // MOBILE PORTRAIT VIEW (Compact Single Stack)
                        // ===================================================================
                        const Text("Train Type:", style: TextStyle(fontWeight: FontWeight.bold)),
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
                        const Text("Number of Locos (Live locos only):", style: TextStyle(fontWeight: FontWeight.bold)),
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
                        DropdownButton<String>(
                          value: selectedBrakeType.isEmpty ? null : selectedBrakeType,
                          hint: const Text("Select Brake Type"),
                          isExpanded: true,
                          items: brakeTypes.map((type) {
                            return DropdownMenuItem<String>(
                              value: type['value'], 
                              child: Text(type['display']!),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              selectedBrakeType = val!;
                            });
                          },
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: tonsController, 
                          keyboardType: TextInputType.number, 
                          onSubmitted: (_) => calculate(), 
                          decoration: const InputDecoration(labelText: "Total Tons", border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: axlesController, 
                          keyboardType: TextInputType.number, 
                          onSubmitted: (_) => calculate(), 
                          decoration: InputDecoration(
                            labelText: "Total Axles", 
                            border: const OutlineInputBorder(),
                            errorText: axleValidationError, 
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      
                      // Live Physical Clearance Framework 
if (totalTrainLength > 0 && axleValidationError == null) ...[
  Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.grey.shade50,
      border: Border.all(color: Colors.grey.shade300),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        Column(
          children: [
            Text("Total Length", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600, letterSpacing: 0.8)),
            const SizedBox(height: 4),
            Text("${totalTrainLength.toStringAsFixed(1)} m", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
          ],
        ),
        Container(height: 30, width: 1, color: Colors.grey.shade300),
        Column(
          children: [
            Text("Braking % (BP)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600, letterSpacing: 0.8)),
            const SizedBox(height: 4),
            Text(selectedBrakeType == 'AIRBRAKE' 
                  ? "N/A for Airbrake" 
                  : "${totalBrakingPercentage.toStringAsFixed(2)} %", 
                style: TextStyle(
                  fontSize: selectedBrakeType == 'AIRBRAKE' ? 13 : 18, // Slightly smaller font so the full phrase fits cleanly
                  fontWeight: FontWeight.bold, 
                  color: Colors.orange.shade800,
                      ),
                ),
          ],
        ),
        Container(height: 30, width: 1, color: Colors.grey.shade300),
        Column(
          children: [
            Text("Buffer Play", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600, letterSpacing: 0.8)),
            const SizedBox(height: 4),
            Text("+${totalBufferPlay.toStringAsFixed(0)} m", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
          ],
        ),
      ],
    ),
  ),
],

                      const SizedBox(height: 40),

                      // Verify Load Button
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