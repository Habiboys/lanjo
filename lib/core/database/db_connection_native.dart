import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<File> getDatabaseFileImpl() async {
  final dir = await getApplicationDocumentsDirectory();
  return File(p.join(dir.path, 'arus_finance.sqlite'));
}

Future<String> getAttachmentsDirectoryPathImpl() async {
  final dir = await getApplicationDocumentsDirectory();
  final attDir = Directory(p.join(dir.path, 'attachments'));
  if (!await attDir.exists()) {
    await attDir.create(recursive: true);
  }
  return attDir.path;
}

QueryExecutor openDefaultConnectionImpl() {
  return LazyDatabase(() async {
    final file = await getDatabaseFileImpl();
    return NativeDatabase.createInBackground(file);
  });
}
