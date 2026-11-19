import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

Future<XFile> writeTempXFileImpl(
  Uint8List bytes,
  String fileName, {
  String mimeType = 'application/octet-stream',
}) async {
  return XFile.fromData(bytes, name: fileName, mimeType: mimeType);
}

Future<Uint8List?> readFileBytesByPathImpl(String? path) async => null;

Future<String> saveAttachmentBytesImpl(
  String dirPath,
  String fileName,
  Uint8List bytes,
) async =>
    fileName;
