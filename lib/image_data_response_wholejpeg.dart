import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';

final _log = Logger("ImageDR");

// Frame to Phone flags
const nonFinalChunkFlag = 0x07;
const finalChunkFlag = 0x08;

Stream<Uint8List> imageDataResponseWholeJpeg(Stream<List<int>> dataResponse) {
  // the image data as a list of bytes that accumulates with each packet
  List<int> imageData = List.empty(growable: true);
  int rawOffset = 0;

  // the subscription to the underlying data stream
  StreamSubscription<List<int>>? dataResponseSubs;

  // Our stream controller that transforms/accumulates the raw data into images (as bytes)
  StreamController<Uint8List> controller = StreamController();

  controller.onListen = () {
    dataResponseSubs = dataResponse
      .where((data) => data[0] == nonFinalChunkFlag || data[0] == finalChunkFlag)
      .listen((data) {
        if (data[0] == nonFinalChunkFlag) {
          imageData += data.sublist(1);
          rawOffset += data.length - 1;
        }
        // the last chunk has a first byte of 8 so stop after this
        else if (data[0] == finalChunkFlag) {
          imageData += data.sublist(1);
          rawOffset += data.length - 1;

          // When full image data is received, emit it and clear the buffer
          controller.add(Uint8List.fromList(imageData));
          imageData.clear();
          rawOffset = 0;
        }
        _log.fine('Chunk size: ${data.length-1}, rawOffset: $rawOffset');
      },
      onDone: controller.close,
      onError: controller.addError);
      _log.fine('Controller being listened to');
  };

  controller.onCancel = () {
    dataResponseSubs?.cancel();
    controller.close();
    _log.fine('Controller cancelled');
  };

  return controller.stream;
}