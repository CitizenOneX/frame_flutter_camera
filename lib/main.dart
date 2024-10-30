import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:simple_frame_app/rx/photo.dart';
import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:simple_frame_app/tx/camera_settings.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  MainAppState createState() => MainAppState();
}

class MainAppState extends State<MainApp> with SimpleFrameAppState {
  // stream subscription to pull application data back from camera
  StreamSubscription<Uint8List>? _photoStream;

  // the list of images to show in the scolling list view
  final List<Image> _imageList = [];
  final List<StatelessWidget> _imageMeta = [];
  final Stopwatch _stopwatch = Stopwatch();

  // camera settings
  int _qualityIndex = 0;
  final List<double> _qualityValues = [10, 25, 50, 100];
  bool _isAutoExposure = true;

  // autoexposure/gain parameters
  int _meteringIndex = 2;
  final List<String> _meteringValues = ['SPOT', 'CENTER_WEIGHTED', 'AVERAGE'];
  int _autoExpGainTimes = 1; // val >= 0; number of times auto exposure and gain algorithm will be run every _autoExpInterval ms
  int _autoExpInterval = 100; // 0<= val <= 255; sleep time between runs of the autoexposure algorithm
  double _exposure = 0.18; // 0.0 <= val <= 1.0
  double _exposureSpeed = 0.5;  // 0.0 <= val <= 1.0
  int _shutterLimit = 16383; // 4 < val < 16383
  int _analogGainLimit = 248;     // 0 <= val <= 248
  double _whiteBalanceSpeed = 0.5;  // 0.0 <= val <= 1.0

  // manual exposure/gain parameters
  int _manualShutter = 800; // 4 < val < 16383
  int _manualAnalogGain = 124;     // 0 <= val <= 248
  int _manualRedGain = 64; // 0 <= val <= 1023
  int _manualGreenGain = 64; // 0 <= val <= 1023
  int _manualBlueGain = 64; // 0 <= val <= 1023


  MainAppState() {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint('${record.level.name}: ${record.time}: ${record.message}');
    });
  }

  @override
  Future<void> run() async {
    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    try {
      // the image data as a list of bytes that accumulates with each packet
      StatelessWidget meta;

      if (_isAutoExposure) {
        meta = AutoExpImageMetadata(_qualityValues[_qualityIndex].toInt(), _autoExpGainTimes, _autoExpInterval, _meteringValues[_meteringIndex], _exposure, _exposureSpeed, _shutterLimit, _analogGainLimit, _whiteBalanceSpeed);
      }
      else {
        meta = ManualExpImageMetadata(_qualityValues[_qualityIndex].toInt(), _manualShutter, _manualAnalogGain, _manualRedGain, _manualGreenGain, _manualBlueGain);
      }

      try {
        // set up the data response handler for the photos
        _photoStream = RxPhoto(qualityLevel: _qualityValues[_qualityIndex].toInt()).attach(frame!.dataResponse).listen((imageData) {
          // received a whole-image Uint8List with jpeg header and footer included
          _stopwatch.stop();

          // unsubscribe from the image stream now (to also release the underlying data stream subscription)
          _photoStream?.cancel();

          try {
            Image im = Image.memory(imageData);

            // add the size and elapsed time to the image metadata widget
            if (meta is AutoExpImageMetadata) {
              meta.size = imageData.length;
              meta.elapsedTimeMs = _stopwatch.elapsedMilliseconds;
            }
            else if (meta is ManualExpImageMetadata) {
              meta.size = imageData.length;
              meta.elapsedTimeMs = _stopwatch.elapsedMilliseconds;
            }

            _log.fine('Image file size in bytes: ${imageData.length}, elapsedMs: ${_stopwatch.elapsedMilliseconds}');

            setState(() {
              _imageList.insert(0, im);
              _imageMeta.insert(0, meta);
            });

            currentState = ApplicationState.ready;
            if (mounted) setState(() {});

          } catch (e) {
            _log.severe('Error converting bytes to image: $e');
          }
        });
      } catch (e) {
        _log.severe('Error reading image data response: $e');
        // unsubscribe from the image stream now (to also release the underlying data stream subscription)
        _photoStream?.cancel();
      }

      // send the lua command to request a photo from the Frame
      _stopwatch.reset();
      _stopwatch.start();

      // Send the respective settings for autoexposure or manual
      if (_isAutoExposure) {
        await frame!.sendMessage(TxCameraSettings(
          msgCode: 0x0d,
          qualityIndex: _qualityIndex,
          autoExpGainTimes: _autoExpGainTimes,
          autoExpInterval: _autoExpInterval,
          meteringIndex: _meteringIndex,
          exposure: _exposure,
          exposureSpeed: _exposureSpeed,
          shutterLimit: _shutterLimit,
          analogGainLimit: _analogGainLimit,
          whiteBalanceSpeed: _whiteBalanceSpeed,
        ));
      }
      else {
        await frame!.sendMessage(TxCameraSettings(
          msgCode: 0x0d,
          qualityIndex: _qualityIndex,
          autoExpGainTimes: 0,
          manualShutter: _manualShutter,
          manualAnalogGain: _manualAnalogGain,
          manualRedGain: _manualRedGain,
          manualGreenGain: _manualGreenGain,
          manualBlueGain: _manualBlueGain,
        ));
      }
    }
    catch (e) {
      _log.severe('Error executing application: $e');
    }
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
              SwitchListTile(
                title: const Text('Auto Exposure/Gain'),
                value: _isAutoExposure,
                onChanged: (bool value) {
                  setState(() {
                    _isAutoExposure = value;
                  });
                },
                subtitle: Text(_isAutoExposure ? 'Auto' : 'Manual'),
              ),
              if (_isAutoExposure) ...[
                // Widgets visible in Auto mode
                ListTile(
                  title: const Text('Auto Exposure/Gain Runs'),
                  subtitle: Slider(
                    value: _autoExpGainTimes.toDouble(),
                    min: 1,
                    max: 30,
                    divisions: 29,
                    label: _autoExpGainTimes.toInt().toString(),
                    onChanged: (value) {
                      setState(() {
                        _autoExpGainTimes = value.toInt();
                      });
                    },
                  ),
                ),
                ListTile(
                  title: const Text('Auto Exposure Interval (ms)'),
                  subtitle: Slider(
                    value: _autoExpInterval.toDouble(),
                    min: 0,
                    max: 255,
                    divisions: 255,
                    label: _autoExpInterval.toInt().toString(),
                    onChanged: (value) {
                      setState(() {
                        _autoExpInterval = value.toInt();
                      });
                    },
                  ),
                ),
                ListTile(
                  title: const Text('Metering'),
                  subtitle: DropdownButton<int>(
                    value: _meteringIndex,
                    onChanged: (int? newValue) {
                      setState(() {
                        _meteringIndex = newValue!;
                      });
                    },
                    items: _meteringValues
                        .map<DropdownMenuItem<int>>((String value) {
                      return DropdownMenuItem<int>(
                        value: _meteringValues.indexOf(value),
                        child: Text(value),
                      );
                    }).toList(),
                  ),
                ),
                ListTile(
                  title: const Text('Exposure'),
                  subtitle: Slider(
                    value: _exposure,
                    min: 0,
                    max: 1,
                    divisions: 20,
                    label: _exposure.toString(),
                    onChanged: (value) {
                      setState(() {
                        _exposure = value;
                      });
                    },
                  ),
                ),
                ListTile(
                  title: const Text('Exposure Speed'),
                  subtitle: Slider(
                    value: _exposureSpeed,
                    min: 0,
                    max: 1,
                    divisions: 20,
                    label: _exposureSpeed.toString(),
                    onChanged: (value) {
                      setState(() {
                        _exposureSpeed = value;
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
                  title: const Text('Analog Gain Limit'),
                  subtitle: Slider(
                    value: _analogGainLimit.toDouble(),
                    min: 0,
                    max: 248,
                    divisions: 8,
                    label: _analogGainLimit.toStringAsFixed(0),
                    onChanged: (value) {
                      setState(() {
                        _analogGainLimit = value.toInt();
                      });
                    },
                  ),
                ),
                ListTile(
                  title: const Text('White Balance Speed'),
                  subtitle: Slider(
                    value: _whiteBalanceSpeed,
                    min: 0,
                    max: 1,
                    divisions: 20,
                    label: _whiteBalanceSpeed.toString(),
                    onChanged: (value) {
                      setState(() {
                        _whiteBalanceSpeed = value;
                      });
                    },
                  ),
                ),
              ] else ...[
                // Widgets visible in Manual mode
                ListTile(
                  title: const Text('Manual Shutter'),
                  subtitle: Slider(
                    value: _manualShutter.toDouble(),
                    min: 4,
                    max: 16383,
                    divisions: 100,
                    label: _manualShutter.toStringAsFixed(0),
                    onChanged: (value) {
                      setState(() {
                        _manualShutter = value.toInt();
                      });
                    },
                  ),
                ),
                ListTile(
                  title: const Text('Manual Analog Gain'),
                  subtitle: Slider(
                    value: _manualAnalogGain.toDouble(),
                    min: 0,
                    max: 248,
                    divisions: 50,
                    label: _manualAnalogGain.toStringAsFixed(0),
                    onChanged: (value) {
                      setState(() {
                        _manualAnalogGain = value.toInt();
                      });
                    },
                  ),
                ),
                ListTile(
                  title: const Text('Red Gain'),
                  subtitle: Slider(
                    value: _manualRedGain.toDouble(),
                    min: 0,
                    max: 1023,
                    divisions: 100,
                    label: _manualRedGain.toStringAsFixed(0),
                    onChanged: (value) {
                      setState(() {
                        _manualRedGain = value.toInt();
                      });
                    },
                  ),
                ),
                ListTile(
                  title: const Text('Green Gain'),
                  subtitle: Slider(
                    value: _manualGreenGain.toDouble(),
                    min: 0,
                    max: 1023,
                    divisions: 100,
                    label: _manualGreenGain.toStringAsFixed(0),
                    onChanged: (value) {
                      setState(() {
                        _manualGreenGain = value.toInt();
                      });
                    },
                  ),
                ),
                ListTile(
                  title: const Text('Blue Gain'),
                  subtitle: Slider(
                    value: _manualBlueGain.toDouble(),
                    min: 0,
                    max: 1023,
                    divisions: 100,
                    label: _manualBlueGain.toStringAsFixed(0),
                    onChanged: (value) {
                      setState(() {
                        _manualBlueGain = value.toInt();
                      });
                    },
                  ),
                ),
              ],
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
                    child: Column(
                      children: [
                        Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.rotationZ(-pi*0.5),
                          child: _imageList[index]
                        ),
                        _imageMeta[index],
                      ],
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

class AutoExpImageMetadata extends StatelessWidget {
  final int quality;
  final int exposureRuns;
  final int exposureInterval;
  final String metering;
  final double exposure;
  final double exposureSpeed;
  final int shutterLimit;
  final int analogGainLimit;
  final double whiteBalanceSpeed;

  AutoExpImageMetadata(this.quality, this.exposureRuns, this.exposureInterval, this.metering, this.exposure, this.exposureSpeed, this.shutterLimit, this.analogGainLimit, this.whiteBalanceSpeed, {super.key});

  late int size;
  late int elapsedTimeMs;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('Quality: $quality\nExposureRuns: $exposureRuns\nExpInterval: $exposureInterval\nMetering: $metering'),
        const Spacer(),
        Text('\nExposure: $exposure\nExposureSpeed: $exposureSpeed\nShutterLim: $shutterLimit\nAnalogGainLim: $analogGainLimit'),
        const Spacer(),
        Text('\nWBSpeed: $whiteBalanceSpeed\nSize: ${(size/1024).toStringAsFixed(1)} kb\nTime: $elapsedTimeMs ms'),
      ],
    );
  }
}

class ManualExpImageMetadata extends StatelessWidget {
  final int quality;
  final int shutter;
  final int analogGain;
  final int redGain;
  final int greenGain;
  final int blueGain;

  ManualExpImageMetadata(this.quality, this.shutter, this.analogGain, this.redGain, this.greenGain, this.blueGain, {super.key});

  late int size;
  late int elapsedTimeMs;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('Quality: $quality\nShutter: $shutter\nAnalogGain: $analogGain'),
        const Spacer(),
        Text('RedGain: $redGain\nGreenGain: $greenGain\nBlueGain: $blueGain'),
        const Spacer(),
        Text('Size: ${(size/1024).toStringAsFixed(1)} kb\nTime: $elapsedTimeMs ms'),
      ],
    );
  }
}