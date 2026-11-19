import 'package:drift/drift.dart';
// ignore: deprecated_member_use
import 'package:drift/web.dart';

Future<dynamic> getDatabaseFileImpl() async => null;

Future<String> getAttachmentsDirectoryPathImpl() async => 'web_attachments';

QueryExecutor openDefaultConnectionImpl() {
  return WebDatabase.withStorage(
    // ignore: experimental_member_use
    DriftWebStorage.indexedDb('arus_finance_db'),
  );
}
