import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<String> saveFileToDownloads(String fileName, List<int> bytes) async {
  Directory? downloads;
  try {
    downloads = await getDownloadsDirectory();
  } catch (_) {}

  try {
    if (downloads == null) {
      if (Platform.isAndroid) {
        final androidDownloads = Directory('/storage/emulated/0/Download');
        if (await androidDownloads.exists()) {
          downloads = androidDownloads;
        } else {
          final ext = await getExternalStorageDirectory();
          if (ext != null) downloads = Directory('${ext.path}/Download');
        }
      } else {
        final ext = await getExternalStorageDirectory();
        if (ext != null) downloads = Directory('${ext.path}/Download');
      }
    }
  } catch (_) {}

  downloads ??= await getTemporaryDirectory();

  final filePath = '${downloads.path}/$fileName';
  final file = File(filePath);
  await file.create(recursive: true);
  await file.writeAsBytes(bytes);
  return filePath;
}
