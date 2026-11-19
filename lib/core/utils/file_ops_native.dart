import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<XFile> writeTempXFileImpl(
  Uint8List bytes,
  String fileName, {
  String mimeType = 'application/octet-stream',
}) async {
  Directory dir;
  try {
    dir = await getTemporaryDirectory();
  } catch (_) {
    dir = Directory.systemTemp;
  }
  final file = File(p.join(dir.path, fileName));
  await file.writeAsBytes(bytes, flush: true);
  return XFile(file.path, name: fileName, mimeType: mimeType);
}

Future<Uint8List?> readFileBytesByPathImpl(String? path) async {
  if (path == null || path.isEmpty) return null;
  final f = File(path);
  if (!await f.exists()) return null;
  return f.readAsBytes();
}

Future<String> saveAttachmentBytesImpl(
  String dirPath,
  String fileName,
  Uint8List bytes,
) async {
  final file = File(p.join(dirPath, fileName));
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
  return fileName;
}
