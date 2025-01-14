import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:share_plus/share_plus.dart';
import 'package:simple_frame_app/frame_vision_app.dart';
import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:simple_frame_app/tx/plain_text.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  MainAppState createState() => MainAppState();
}

class MainAppState extends State<MainApp> with SimpleFrameAppState, FrameVisionAppState {
  // main state of photo request/processing on/off
  bool _processing = false;

  // the list of images to show in the scolling list view
  final List<Image> _imageList = [];
  final List<ImageMetadata> _imageMeta = [];
  final List<Uint8List> _jpegBytes = [];

  MainAppState() {
    Logger.root.level = Level.FINE;
    Logger.root.onRecord.listen((record) {
      debugPrint('${record.level.name}: ${record.time}: ${record.message}');
    });
  }

  @override
  void initState() {
    super.initState();

    // if possible, connect right away and load files on Frame
    // note: camera app wouldn't necessarily run on start
    tryScanAndConnectAndStart(andRun: true);
  }

  @override
  Future<void> onRun() async {
    // initial message to display when running
    await frame!.sendMessage(
      TxPlainText(
        msgCode: 0x0a,
        text: '2-Tap: take photo'
      )
    );
  }

  @override
  Future<void> onCancel() async {
    // no app-specific cleanup required here
  }

  @override
  Future<void> onTap(int taps) async {
    switch (taps) {
      case 2:
        // check if there's processing in progress already and drop the request if so
        if (!_processing) {
          _processing = true;
          // synchronously call the capture and processing (just display) of the photo
          await capture().then(process);
        }
        break;
      default:
    }
  }

  /// The vision pipeline to run when a photo is captured
  /// Which in this case is just displaying
  FutureOr<void> process((Uint8List, ImageMetadata) photo) async {
    var imageData = photo.$1;
    var meta = photo.$2;

    // update the image reel
    setState(() {
      _imageList.insert(0, Image.memory(imageData, gaplessPlayback: true,));
      _imageMeta.insert(0, meta);
      _jpegBytes.insert(0, imageData);
    });

    _processing = false;
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
        drawer: getCameraDrawer(),
        onDrawerChanged: (isOpened) {
          if (!isOpened) {
            // if the user closes the camera settings, send the updated settings to Frame
            sendExposureSettings();
          }
        },
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
                        GestureDetector(
                          onTap: () => _shareImage(_imageList[index], _imageMeta[index], _jpegBytes[index]),
                          child: _imageList[index]
                        ),
                        ImageMetadataWidget(meta: _imageMeta[index]),
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

  void _shareImage(Image image, ImageMetadata metadata, Uint8List jpegBytes) async {
    await Share.shareXFiles(
      [XFile.fromData(Uint8List.fromList(jpegBytes), mimeType: 'image/jpeg', name: 'image.jpg')],
      text: 'Frame camera image:\n$metadata',
    );
  }
}