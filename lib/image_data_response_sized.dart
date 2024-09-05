import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import 'jpeg_helper.dart';

final _log = Logger("ImageDR");

// Frame to Phone flags
const imageChunkFlag = 0x07;

// TODO for use if I switch from non-final, final message types to a single message type.
// Image size must be sent as first 2 bytes of first packet -
// we can then pre-allocate a correctly-sized Uint8List buffer.
// But if a packet is missed, it's hard to recover
Stream<Uint8List> imageDataResponseSized(Stream<List<int>> dataResponse, int qualityLevel) {
  // qualityLevel must be valid (10, 25, 50, 100)
  if (!jpegHeaderMap.containsKey(qualityLevel)) {
    throw Exception('Invalid quality level for jpeg: $qualityLevel - must be one of: ${jpegHeaderMap.keys}');
  }

  // the subscription to the underlying data stream
  StreamSubscription<List<int>>? dataResponseSubs;

  // Our stream controller that transforms/accumulates the raw data into images (as bytes)
  StreamController<Uint8List> controller = StreamController();

  Uint8List? buffer;
  int? totalLength;
  int rawLength = 0;
  int rawOffset = 0;
  int dataOffset = 0;

  controller.onListen = () {
    dataResponseSubs = dataResponse
      .where((data) => data[0] == imageChunkFlag)
      .listen((data) {
        if (buffer == null && data.length >= 3) {
          // Extract the image length from the first two bytes
          rawLength = (data[1] << 8) + data[2];
          _log.fine('rawLength set to: $rawLength');

          Uint8List? jpegHeader = jpegHeaderMap[qualityLevel];
          totalLength = rawLength + jpegHeader!.length + jpegFooter.length;

          buffer = Uint8List(totalLength!);
          buffer!.setAll(0, jpegHeader);
          dataOffset += jpegHeader.length;

          buffer!.setAll(dataOffset, data.skip(3));
          dataOffset += data.length - 3;
          rawOffset += data.length - 3;

        }
        else {
          // copy all the raw data from the packet
          try {
            buffer!.setAll(dataOffset, data.skip(1));
            dataOffset += data.length - 1;
            rawOffset += data.length - 1;
          } catch (e) {
            _log.severe('error copying body packet over: $e');
          }
        }
        _log.fine('Chunk size: ${data.length-1}, rawOffset: $rawOffset of $rawLength');

        // if this chunk contained the final bytes of the image data
        if (rawOffset >= rawLength) {
          // add the jpeg footer
          try {
            buffer!.setAll(dataOffset, jpegFooter);
            dataOffset += jpegFooter.length;
          } catch (e) {
            _log.severe('error copying footer packet over: $e');
          }

          // When full image data is received, emit it and clear the buffer
          controller.add(buffer!);
        }
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