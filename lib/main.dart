import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'simple_frame_app.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  MainAppState createState() => MainAppState();
}

class MainAppState extends State<MainApp> with SimpleFrameAppState {
  // Phone to Frame flags
  static const takePhotoFlag = 0x0d;
  // Frame to Phone flags
  static const imageChunkFlag = 0x07;

  // the list of images to show in the scolling list view
  final List<Image> _imageList = [];
  final List<ImageMetadata> _imageMeta = [];
  final Stopwatch _stopwatch = Stopwatch();

  // camera settings
  int _qualityIndex = 2;
  final List<double> _qualityValues = [10, 25, 50, 100];
  double _exposure = 0.0; // -2.0 <= val <= 2.0
  int _meteringModeIndex = 0;
  final List<String> _meteringModeValues = ['SPOT', 'CENTER_WEIGHTED', 'AVERAGE'];
  int _autoExpGainTimes = 0; // val >= 0; number of times auto exposure and gain algorithm will be run every 100ms
  double _shutterKp = 0.1;  // val >= 0 (we offer 0.1 .. 0.5)
  int _shutterLimit = 6000; // 4 < val < 16383
  double _gainKp = 1.0;     // val >= 0 (we offer 1.0 .. 5.0)
  int _gainLimit = 248;     // 0 <= val <= 248

  MainAppState() {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint('${record.level.name}: ${record.time}: ${record.message}');
    });
  }

  /// Corresponding parser in frame_app.lua data_handler()
  List<int> makeTakePhotoPayload() {
    // exposure is a double in the range -2.0 to 2.0, so map that to an unsigned byte 0..255
    // by multiplying by 64, adding 128 and truncating
    int intExp;
    if (_exposure >= 2.0) {
      intExp = 255;
    }
    else if (_exposure <= -2.0) {
      intExp = 0;
    }
    else {
      intExp = ((_exposure * 64) + 128).floor();
    }

    int intShutKp = (_shutterKp * 10).toInt();
    int intShutLimMsb = _shutterLimit >> 8;
    int intShutLimLsb = _shutterLimit & 0xFF;
    int intGainKp = (_gainKp * 10).toInt();

    return [takePhotoFlag, _qualityIndex, _autoExpGainTimes, _meteringModeIndex,
            intExp, intShutKp, intShutLimMsb, intShutLimLsb, intGainKp, _gainLimit];
  }

  @override
  Future<void> run() async {
    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    // the image data as a list of bytes that accumulates with each packet
    ImageMetadata meta = ImageMetadata(_qualityValues[_qualityIndex].toInt(), _autoExpGainTimes, _meteringModeValues[_meteringModeIndex], _exposure, _shutterKp, _shutterLimit, _gainKp, _gainLimit);
    Uint8List? imageData;
    bool firstChunk = true;
    int totalLength = 0;
    int dataOffset = 0;

    // now send the lua command to request a photo from the Frame
    _stopwatch.reset();
    _stopwatch.start();
    await frame!.sendData(makeTakePhotoPayload());

    // read the response for the photo we just requested - a stream of packets of bytes
    await for (final data in frame!.dataResponse) {
      // allow the user to cancel before the image has returned
      if (currentState != ApplicationState.running) {
        break;
        // FIXME check if a subsequent photo works okay, or whether the dataResponse stream needs to be drained first
      }

      // image chunks have a first byte of 0x07
      if (data[0] == imageChunkFlag) {
        // first chunk has a 16-bit image length header, so pre-allocate the bytes
        if (firstChunk) {
          totalLength = data[1] << 8 | data[2];
          imageData = Uint8List(totalLength);
          imageData.setAll(dataOffset, data.skip(3));
          dataOffset += data.length - 3;
          firstChunk = false;
        }
        else {
          imageData!.setAll(dataOffset, data.skip(1));
          dataOffset += data.length - 1;
        }
        _log.fine('Chunk size: ${data.length}, dataOffset: $dataOffset');

        // if this chunk contained the final bytes of the image data
        if (dataOffset == totalLength) {
          _stopwatch.stop();

          try {
            Image im = Image.memory(imageData);
            _imageList.insert(0, im);

            // add the size and elapsed time to the image metadata widget
            meta.size = imageData.length;
            meta.elapsedTimeMs = _stopwatch.elapsedMilliseconds;
            _imageMeta.insert(0, meta);

            _log.info('Image file size in bytes: ${imageData.length}, elapsedMs: ${_stopwatch.elapsedMilliseconds}');

            // Success. Break out of the "await for" and stop listening to the stream
            break;

          } catch (e) {
            _log.severe('Error converting bytes to image: $e');

            break;
          }
        }
      }
      else if (data[0] == SimpleFrameAppState.batteryStatusFlag) {
        // ignore, handled by SimpleFrameApp
        // TODO remove when unexpected byte logging is removed
      }
      else {
        // TODO could remove
        _log.severe('Unexpected initial byte: ${data[0]}');
        break;
      }
    }

    currentState = ApplicationState.ready;
    if (mounted) setState(() {});
  }

  /// cancel the current photo
  @override
  Future<void> cancel() async {
    currentState = ApplicationState.ready;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frame Camera',
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
          title: const Text("Frame Camera"),
          actions: [getBatteryWidget()]
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
                  onChanged: (value) {
                    setState(() {
                      _qualityIndex = value.toInt();
                    });
                  },
                ),
              ),
              ListTile(
                title: const Text('Auto Exposure/Gain Runs'),
                subtitle: Slider(
                  value: _autoExpGainTimes.toDouble(),
                  min: 0,
                  max: 10,
                  divisions: 10,
                  label: _autoExpGainTimes.toInt().toString(),
                  onChanged: (value) {
                    setState(() {
                      _autoExpGainTimes = value.toInt();
                    });
                  },
                ),
              ),
              ListTile(
                title: const Text('Metering Mode'),
                subtitle: DropdownButton<int>(
                  value: _meteringModeIndex,
                  onChanged: (int? newValue) {
                    setState(() {
                      _meteringModeIndex = newValue!;
                    });
                  },
                  items: _meteringModeValues
                      .map<DropdownMenuItem<int>>((String value) {
                    return DropdownMenuItem<int>(
                      value: _meteringModeValues.indexOf(value),
                      child: Text(value),
                    );
                  }).toList(),
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
                  onChanged: (value) {
                    setState(() {
                      _exposure = value;
                    });
                  },
                ),
              ),
              ListTile(
                title: const Text('Shutter KP'),
                subtitle: Slider(
                  value: _shutterKp,
                  min: 0.1,
                  max: 0.5,
                  divisions: 4,
                  label: _shutterKp.toStringAsFixed(1),
                  onChanged: (value) {
                    setState(() {
                      _shutterKp = value;
                    });
                  },
                ),
              ),
              ListTile(
                title: const Text('Shutter Limit'),
                subtitle: Slider(
                  value: _shutterLimit.toDouble(),
                  min: 4,
                  max: 16383,
                  divisions: 10,
                  label: _shutterLimit.toStringAsFixed(0),
                  onChanged: (value) {
                    setState(() {
                      _shutterLimit = value.toInt();
                    });
                  },
                ),
              ),
              ListTile(
                title: const Text('Gain KP'),
                subtitle: Slider(
                  value: _gainKp,
                  min: 1.0,
                  max: 5.0,
                  divisions: 4,
                  label: _gainKp.toStringAsFixed(1),
                  onChanged: (value) {
                    setState(() {
                      _gainKp = value;
                    });
                  },
                ),
              ),
              ListTile(
                title: const Text('Gain Limit'),
                subtitle: Slider(
                  value: _gainLimit.toDouble(),
                  min: 0,
                  max: 248,
                  divisions: 8,
                  label: _gainLimit.toStringAsFixed(0),
                  onChanged: (value) {
                    setState(() {
                      _gainLimit = value.toInt();
                    });
                  },
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
                      child: Column(
                        children: [
                          _imageList[index],
                          _imageMeta[index],
                        ],
                      )
                    )
                  );
                },
                separatorBuilder: (context, index) => const Divider(height: 30),
                itemCount: _imageList.length,
              ),
            ),
          ]
        ),
        floatingActionButton: getFloatingActionButtonWidget(const Icon(Icons.camera_alt), const Icon(Icons.cancel)),
        persistentFooterButtons: getFooterButtonsWidget(),
      ),
    );
  }
}

class ImageMetadata extends StatelessWidget {
  final int quality;
  final int exposureRuns;
  final String meteringMode;
  final double exposure;
  final double shutterKp;
  final int shutterLimit;
  final double gainKp;
  final int gainLimit;

  ImageMetadata(this.quality, this.exposureRuns, this.meteringMode, this.exposure, this.shutterKp, this.shutterLimit, this.gainKp, this.gainLimit, {super.key});

  late int size;
  late int elapsedTimeMs;

  @override
  Widget build(BuildContext context) {
    return Text('$quality / $exposureRuns / $meteringMode / $exposure \n$shutterKp / $shutterLimit / $gainKp / $gainLimit \n${size/1024}kb / ${elapsedTimeMs}ms');
  }
}