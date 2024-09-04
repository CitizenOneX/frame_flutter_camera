import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import 'jpeg_helper.dart';

final _log = Logger("ImageDR");

// Frame to Phone flags
const imageChunkFlag = 0x07;

Stream<Uint8List> imageDataResponse(Stream<List<int>> dataResponse) {
  late StreamController<Uint8List> controller;
  Uint8List? buffer;
  int? totalLength;
  int rawLength = 0;
  int rawOffset = 0;
  int dataOffset = 0;

  controller = StreamController<Uint8List>(
    onListen: () {
      dataResponse.where((data) => data[0] == imageChunkFlag).listen((data) {
        if (buffer == null && data.length >= 3) {
          // Extract the image length from the first two bytes
          rawLength = (data[1] << 8) + data[2];
          _log.fine('rawLength set to: $rawLength');

          // FIXME needs to get correct quality level for this imageDataResponse
          Uint8List? jpegHeader = jpegHeaderMap[50];
          totalLength = rawLength + jpegHeader!.length + jpegFooter.length;

          buffer = Uint8List(totalLength!);
          buffer!.setAll(0, jpegHeader);
          dataOffset += jpegHeader.length;

          buffer!.setAll(dataOffset, data.skip(3));
          dataOffset += data.length - 3;
          rawOffset += data.length - 3;

        } else {
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
      }, onDone: controller.close, onError: controller.addError);
    },
    //onCancel: controller.close,
  );

  return controller.stream;
}