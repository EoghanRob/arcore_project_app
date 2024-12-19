import 'dart:async';
import 'package:flutter/material.dart';
// AR Flutter Plugin
import 'package:ar_flutter_plugin_flutterflow/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_flutterflow/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_flutterflow/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_flutterflow/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_flutterflow/models/ar_anchor.dart';
import 'package:ar_flutter_plugin_flutterflow/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin_flutterflow/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_flutterflow/datatypes/node_types.dart';
import 'package:ar_flutter_plugin_flutterflow/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_flutterflow/models/ar_node.dart';
import 'package:ar_flutter_plugin_flutterflow/models/ar_hittest_result.dart';
import 'package:flutter/services.dart';
import 'package:native_device_orientation/native_device_orientation.dart';
import 'package:flutter_svg/flutter_svg.dart';


// Other imports
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:flutter/scheduler.dart'; // For Ticker

class ObjectGestures extends StatefulWidget {
  const ObjectGestures({super.key});

  @override
  State<ObjectGestures> createState() => _ObjectGesturesState();
}

class _ObjectGesturesState extends State<ObjectGestures>
    with SingleTickerProviderStateMixin {
  ARSessionManager? arSessionManager;
  ARObjectManager? arObjectManager;
  ARAnchorManager? arAnchorManager;

  ARNode? complexUINode; // Track the ComplexUI object
  ARNode? simpleUINode; // Track the ComplexUI object
  ARNode? objectNode;
  ARAnchor? objectAnchor;
  double scale = 1.0;
  double heightOffset = 0.0; // Was used to control HUD height, now controls HUD distance
  double rotationAngle = 0.0; // Default rotation around X-axis
  double heightOfUI = 0.3; //Actual height of HUD

  double complexAway = 20.0;
  double simpleAway = 0.0;

  bool isComplexMode = false;


  late Stream<NativeDeviceOrientation> _orientationStream;
  int _imageTurns = 0; // Cached orientation


  // FPS Counter Variables
  double _fps = 0.0;
  int _frameCount = 0;
  DateTime _lastTime = DateTime.now();
  Timer? _fpsTimer;

  late Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _startFPSThrottle();
    // Lock the visual layout to portrait mode
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    // Listen to orientation changes
    _orientationStream = NativeDeviceOrientationCommunicator().onOrientationChanged(useSensor: true);
    _orientationStream.listen((orientation) {
      // Update _imageTurns only when orientation changes
      setState(() {
        switch (orientation) {
          case NativeDeviceOrientation.portraitUp:
            _imageTurns = 0;
            break;
          case NativeDeviceOrientation.portraitDown:
            _imageTurns = 2;
            break;
          case NativeDeviceOrientation.landscapeLeft:
            _imageTurns = 1;
            break;
          case NativeDeviceOrientation.landscapeRight:
            _imageTurns = 3;
            break;
          default:
            _imageTurns = 0;
        }
      });
    });
  }



  @override
  void dispose() {
    // Restore all orientations when the widget is disposed
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _ticker.stop(); // Stop the ticker
    _ticker.dispose(); // Dispose the ticker
    _fpsTimer?.cancel(); // Cancel the timer

    super.dispose();
  }


  void _startFPSThrottle() {
    // Update FPS only every second
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _fps = _frameCount.toDouble();
        _frameCount = 0; // Reset frame count
      });
    });

    _ticker = createTicker((_) {
      _frameCount++;
    });
    _ticker.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56.0),
        child: SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: RotatedBox(
                quarterTurns: _imageTurns,
                child: Image.asset(
                  'assets/logo.png',
                  height: 40,
                ),
              ),
            ),
          ),
        ),
      ),


      body: Stack(
        children: [
          Positioned.fill(
            child: ARView(
              onARViewCreated: _onARViewCreated,
              planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
            ),
          ),
          // FPS Overlay at fixed top-left
          Positioned(
            top: 16.0,
            left: 16.0,
            child: Container(
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Text(
                "FPS: ${_fps.toStringAsFixed(1)}",
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
          // Bottom panel always at bottom center
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [


                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _switchComplexSimple();
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      elevation: 2,
                      padding: const EdgeInsets.all(8.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                    ),
                    child: SizedBox(
                      height: 40, // Adjust size of the button
                      width: 40,  // Ensure the button stays square
                      child: RotatedBox(
                        quarterTurns: _imageTurns, // Use cached orientation for rotation
                        child: Image.asset(
                          'assets/UI/switch-HUD.jpg',
                          height: 40, // Adjust height of the image
                          width: 40,  // Ensure consistent scaling
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // HUD Size Slider with Rotating Image
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Image to the left
                      SizedBox(
                        height: 40, // Adjust image size
                        width: 40,  // Ensure it doesn't shrink
                        child: RotatedBox(
                          quarterTurns: _imageTurns,
                          child: Image.asset(
                            'assets/UI/size.jpg',
                            height: 24, // Adjust the height of the image
                          ),
                        ),
                      ),
                      const SizedBox(width: 16), // Spacing between image and slider
                      // Slider to the right
                      Expanded( // Allow slider to take remaining space
                        child: Slider(
                          value: scale,
                          min: 0.5,
                          max: 1.5,
                          divisions: 10,
                          label: scale.toStringAsFixed(1),
                          activeColor: Colors.green[700],
                          inactiveColor: Colors.green[200],
                          onChanged: (newValue) {
                            setState(() {
                              scale = newValue;
                              _updateNodeAllTransforms();
                            });
                          },
                        ),
                      ),
                    ],
                  ),


                  // HUD Height Slider with Rotating Image
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Image to the left
                      SizedBox(
                        height: 40, // Adjust image size
                        width: 40,  // Ensure consistent size
                        child: RotatedBox(
                          quarterTurns: _imageTurns,
                          child: Image.asset(
                            'assets/UI/height.jpg',
                            height: 24, // Adjust the height of the image
                          ),
                        ),
                      ),
                      const SizedBox(width: 16), // Spacing between image and slider
                      // Slider to the right
                      Expanded( // Allow slider to take remaining space
                        child: Slider(
                          value: heightOffset,
                          min: 0.0,
                          max: 0.5,
                          divisions: 9,
                          label: heightOffset.toStringAsFixed(1),
                          activeColor: Colors.green[700],
                          inactiveColor: Colors.green[200],
                          onChanged: (newValue) {
                            setState(() {
                              heightOffset = newValue;
                              _updateNodeAllTransforms();
                            });
                          },
                        ),
                      ),
                    ],
                  ),


                  // HUD Tilt Slider with Rotating Image
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center, // Center vertically
                    children: [
                      // Image to the left
                      SizedBox(
                        height: 40, // Adjust image size
                        width: 40,  // Ensure consistent size
                        child: RotatedBox(
                          quarterTurns: _imageTurns, // Use cached value
                          child: Image.asset(
                            'assets/UI/tilt.jpg', // Replace with your image path
                            height: 24, // Adjust the height of the image
                          ),
                        ),
                      ),
                      const SizedBox(width: 16), // Spacing between image and slider
                      // Slider to the right
                      Expanded( // Allow slider to take remaining space
                        child: Slider(
                          value: rotationAngle,
                          min: 0.0,
                          max: 20,
                          divisions: 9,
                          label: rotationAngle.toStringAsFixed(0),
                          activeColor: Colors.green[700],
                          inactiveColor: Colors.green[200],
                          onChanged: (newValue) {
                            setState(() {
                              rotationAngle = newValue;
                              _updateNodeAllTransforms();
                            });
                          },
                        ),
                      ),
                    ],
                  ),

                ],
              ),
            ),
          ),

        ],
      ),
    );
  }



  void _onARViewCreated(
      ARSessionManager sessionManager,
      ARObjectManager objectManager,
      ARAnchorManager anchorManager,
      ARLocationManager locationManager,
      ) {
    arSessionManager = sessionManager;
    arObjectManager = objectManager;
    arAnchorManager = anchorManager;

    // Initialize AR session
    arSessionManager?.onInitialize(
      showPlanes: false, // Disable plane visualization
      handlePans: true, // Allow pan gestures
      handleRotation: true, // Allow rotation gestures
      //showFeaturePoints: false
    );

    // Event to handle taps on planes or points
    arSessionManager?.onPlaneOrPointTap = _onPlaneOrPointTapped;

    // Initialize object manager
    arObjectManager?.onInitialize();
  }

  Future<void> _onPlaneOrPointTapped(List<ARHitTestResult> hitTestResults) async {
    var hitTestResult = hitTestResults.firstWhere(
            (result) => result.type == ARHitTestResultType.plane,
        orElse: () => hitTestResults.first);

    if (hitTestResult != null) {
      _placeOrMoveObject(hitTestResult);
    }
  }

  Future<void> _placeOrMoveObject(ARHitTestResult hitTestResult) async {
    // Remove existing objects and anchors if any
    if (objectNode != null && objectAnchor != null) {
      await arObjectManager?.removeNode(objectNode!);
      await arObjectManager?.removeNode(complexUINode!);
      await arObjectManager?.removeNode(simpleUINode!);
      await arAnchorManager?.removeAnchor(objectAnchor!);
      objectNode = null;
      complexUINode = null;
      simpleUINode = null;
      objectAnchor = null;
    }

    // Create a new anchor at the tapped position
    var newAnchor = ARPlaneAnchor(transformation: hitTestResult.worldTransform);
    bool? didAddAnchor = await arAnchorManager?.addAnchor(newAnchor);

    if (didAddAnchor!) {
      objectAnchor = newAnchor;

      // Define rotation
      var quaternionY = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), vm.radians(180));
      var rotationVector = vm.Vector4(quaternionY.x, quaternionY.y, quaternionY.z, quaternionY.w);

      // First object
      var handlesNode = ARNode(
        type: NodeType.localGLTF2,
        uri: "assets/HandlesBike/BikeHandlesNew.gltf",
        scale: vm.Vector3(1, 1, 1),
        position: vm.Vector3(0.0, 0.0, 0.0),
        rotation: rotationVector,
      );

      // Second object
      var complexUINodeTemp = ARNode(
        type: NodeType.localGLTF2,
        uri: "assets/ComplexUI/ComplexUI.gltf",
        scale: vm.Vector3(scale, scale, scale),
        position: vm.Vector3(complexAway, heightOfUI, -heightOffset),
        rotation: rotationVector,
      );

      // Third object
      var simpleUINodeTemp = ARNode(
        type: NodeType.localGLTF2,
        uri: "assets/SimpleUI/SimpleUI.gltf",
        scale: vm.Vector3(scale, scale, scale),
        position: vm.Vector3(simpleAway, heightOfUI, -heightOffset),
        rotation: rotationVector,
      );

      bool? didAddHandles = await arObjectManager?.addNode(handlesNode, planeAnchor: newAnchor);
      bool? didAddComplexUI =
      await arObjectManager?.addNode(complexUINodeTemp, planeAnchor: newAnchor);
      bool? didAddSimpleUI =
      await arObjectManager?.addNode(simpleUINodeTemp, planeAnchor: newAnchor);

      if (didAddHandles == true && didAddComplexUI == true && didAddSimpleUI == true) {
        objectNode = handlesNode;
        complexUINode = complexUINodeTemp;
        simpleUINode = simpleUINodeTemp;
        print("Handles and ComplexUI objects placed successfully.");
      } else {
        print("Failed to add one or both objects.");
      }
    }
  }


  Future<void> _updateNodeAllTransforms() async {
    if (complexUINode != null) {
      final rotationX = vm.Quaternion.axisAngle(vm.Vector3(-1, 0, 0), vm.radians(rotationAngle));

      final newTransform = Matrix4.identity();
      newTransform.setFromTranslationRotationScale(
        vm.Vector3(complexAway, heightOfUI, -heightOffset),
        rotationX,
        vm.Vector3(scale, scale, scale),
      );

      complexUINode!.transform = newTransform;
      print("ComplexUI transforms updated");
    }
    if (simpleUINode != null) {
      final rotationX = vm.Quaternion.axisAngle(vm.Vector3(-1, 0, 0), vm.radians(rotationAngle));

      final newTransform = Matrix4.identity();
      newTransform.setFromTranslationRotationScale(
        vm.Vector3(simpleAway, heightOfUI, -heightOffset),
        rotationX,
        vm.Vector3(scale, scale, scale),
      );

      simpleUINode!.transform = newTransform;
      print("SimpleUI transforms updated");
    }
  }

  Future<void> _switchComplexSimple() async {
    if (isComplexMode) {
      complexAway = 20.0;
      simpleAway = 0.0;
      _updateNodeAllTransforms();
      isComplexMode = false;
    }
    else {
      complexAway = 0.0;
      simpleAway = 20.0;
      _updateNodeAllTransforms();
      isComplexMode = true;
    }
  }

  Future<void> _removeObject() async {
    if (objectNode != null && objectAnchor != null) {
      await arObjectManager?.removeNode(objectNode!);
      await arAnchorManager?.removeAnchor(objectAnchor!);
      setState(() {
        objectNode = null;
        objectAnchor = null;
      });
    }
  }
}
