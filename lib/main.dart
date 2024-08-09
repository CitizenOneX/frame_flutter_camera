import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:native_shutter_sound/native_shutter_sound.dart';
import 'simple_frame_app.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  MainAppState createState() => MainAppState();
}

class MainAppState extends State<MainApp> with SimpleFrameAppState {
  // stream subscription to pull data back from camera
  StreamSubscription<List<int>>? _dataResponseStream;

  // the list of images to show in the scolling list view
  final List<Image> _imageList = [];
  final Stopwatch _stopwatch = Stopwatch();

  // camera settings
  int _qualityIndex = 2;
  final List<double> _qualityValues = [10, 25, 50, 100];
  double _exposure = 0.0; // -2.0 to 2.0
  String _meteringMode = 'SPOT';
  final List<String> _meteringModeValues = ['SPOT', 'CENTER_WEIGHTED', 'AVERAGE'];

  MainAppState() {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint('${record.level.name}: ${record.time}: ${record.message}');
    });
  }

  /// Request a photo from the Frame and receive the data back, add the image to the listview
  @override
  Future<void> runApplication() async {
    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    try {
      _dataResponseStream?.cancel();
      String? response;

      // send a break in case anything is still running in the background - otherwise future lua calls will be ignored
      await connectedDevice!.sendBreakSignal();
      await Future.delayed(const Duration(milliseconds: 150));

      // print out the battery level while testing so we know when we're getting low
      response = await connectedDevice!.sendString('print(frame.battery_level())', awaitResponse: true);
      _log.info('print(frame.battery_level()) response: $response');
      await Future.delayed(const Duration(milliseconds: 150));

      // send a clear() so we do not burn-in the display, and there's no fram UI for this app
      await connectedDevice!.sendString('frame.display.text(" ", 50, 100)', awaitResponse: false);
      await Future.delayed(const Duration(milliseconds: 150));
      await connectedDevice!.sendString('frame.display.show()', awaitResponse: false);
      await Future.delayed(const Duration(milliseconds: 150));

      // clean up by deleting any prior camera script
      response = await connectedDevice!.sendString('frame.file.remove("library_functions.lua")', awaitResponse: false);
      await Future.delayed(const Duration(milliseconds: 150));

      // upload the camera script
      await connectedDevice!.uploadScript('library_functions.lua', 'assets/library_functions.lua');
      await Future.delayed(const Duration(milliseconds: 150));
      response = await connectedDevice!.sendString('require("library_functions")', awaitResponse: false);
      await Future.delayed(const Duration(milliseconds: 150));

      // the image data as a list of bytes that accumulates with each packet
      List<int> imageData = List.empty(growable: true);

      // set up the data response handler for the photo we're about to request
      _dataResponseStream = connectedDevice!.dataResponse.listen((data) {
        // non-final chunks have a first byte of 7
        if (data[0] == 7) {
          imageData += data.sublist(1);
        }
        // the last chunk has a first byte of 8 so stop after this
        else if (data[0] == 8) {
          _stopwatch.stop();
          imageData += data.sublist(1);
          _dataResponseStream!.cancel();

          try {
            Image im = Image.memory(Uint8List.fromList(imageData));
            _imageList.insert(0, im);

            currentState = ApplicationState.ready;
            if (mounted) setState(() {});
            _log.info('Image file size in bytes: ${imageData.length}, elapsedMs: ${_stopwatch.elapsedMilliseconds}');

          } catch (e) {
            _log.severe('Error converting bytes to image: $e');

            currentState = ApplicationState.ready;
            if (mounted) setState(() {});
          }
        }
        else {
          _log.severe('Unexpected initial byte: ${data[0]}');
          connectedDevice!.dataResponse.drain([8]);
        }
      });

      // now send the lua command to request a photo from the Frame
      NativeShutterSound.play();
      _stopwatch.reset();
      _stopwatch.start();
      response = await connectedDevice!.sendString('cameraCaptureAndSend(${_qualityValues[_qualityIndex].round().toString()},$_exposure,"$_meteringMode")', awaitResponse: false);

    } catch (e) {
      _log.fine('Error executing application logic: $e');
    }
  }

  @override
  Future<void> stopApplication() async {
    currentState = ApplicationState.stopping;
    if (mounted) setState(() {});
  }

  Future<void> sendBreak() async {
    await connectedDevice!.sendBreakSignal();
    currentState = ApplicationState.ready;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // work out the states of the footer buttons based on the app state
    List<Widget> pfb = [];

    switch (currentState) {
      case ApplicationState.disconnected:
        pfb.add(TextButton(onPressed: scanOrReconnectFrame, child: const Text('Connect Frame')));
        pfb.add(const TextButton(onPressed: null, child: Text('Take Photo')));
        pfb.add(const TextButton(onPressed: null, child: Text('Finish')));
        break;

      case ApplicationState.scanning:
      case ApplicationState.connecting:
      case ApplicationState.stopping:
      case ApplicationState.disconnecting:
        pfb.add(const TextButton(onPressed: null, child: Text('Connect Frame')));
        pfb.add(const TextButton(onPressed: null, child: Text('Take Photo')));
        pfb.add(const TextButton(onPressed: null, child: Text('Finish')));
        break;

      case ApplicationState.ready:
        pfb.add(const TextButton(onPressed: null, child: Text('Connect Frame')));
        pfb.add(TextButton(onPressed: runApplication, child: const Text('Take Photo')));
        pfb.add(TextButton(onPressed: disconnectFrame, child: const Text('Finish')));
        break;

      case ApplicationState.running:
        pfb.add(const TextButton(onPressed: null, child: Text('Connect Frame')));
        pfb.add(const TextButton(onPressed: null, child: Text('Take Photo')));
        pfb.add(TextButton(onPressed: sendBreak, child: const Text('Break')));
        pfb.add(const TextButton(onPressed: null, child: Text('Finish')));
        break;
    }

    return MaterialApp(
      title: 'Frame Camera',
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
          title: const Text("Frame Camera"),
        ),
        drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              const DrawerHeader(
                decoration: BoxDecoration(
                  color: Colors.blue,
                ),
                child: Text('Camera Settings',
                  style: TextStyle(color: Colors.white, fontSize: 24),
                  ),
              ),
              ListTile(
                title: const Text('Quality'),
                subtitle: Slider(
                  value: _qualityIndex.toDouble(),
                  min: 0,
                  max: _qualityValues.length - 1,
                  divisions: _qualityValues.length - 1,
                  label: _qualityValues[_qualityIndex].toString(),
                  onChanged: (double value) {
                    setState(() {
                      _qualityIndex = value.toInt();
                    });
                  },
                ),
              ),
              ListTile(
                title: const Text('Exposure'),
                subtitle: Slider(
                  value: _exposure,
                  min: -2,
                  max: 2,
                  divisions: 8,
                  label: _exposure.toString(),
                  onChanged: (double value) {
                    setState(() {
                      _exposure = value;
                    });
                  },
                ),
              ),
              ListTile(
                title: const Text('Metering Mode'),
                subtitle: DropdownButton<String>(
                  value: _meteringMode,
                  onChanged: (String? newValue) {
                    setState(() {
                      _meteringMode = newValue!;
                    });
                  },
                  items: _meteringModeValues
                      .map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        body: Flex(
          direction: Axis.vertical,
          children: [
            Expanded(
              // scrollable list view for multiple photos
              child: ListView.separated(
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.rotationZ(-pi*0.5),
                      child: _imageList[index]
                    )
                  );
                },
                separatorBuilder: (context, index) => const Divider(height: 30),
                itemCount: _imageList.length,
              ),
            ),
          ]
        ),
        persistentFooterButtons: pfb,
      ),
    );
  }
}
