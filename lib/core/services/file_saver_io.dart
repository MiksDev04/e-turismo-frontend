import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Saves [bytes] to disk and returns where it ended up.
///
/// Android / iOS: scoped storage blocks writing into the public Downloads
/// folder, and any folder we CAN write to is invisible to the user — so we
/// write to a temp dir and hand the file to the OS share/save sheet, where
/// the user picks Downloads, Drive, email, etc.
/// Windows / macOS / Linux: unchanged, writes into the real Downloads folder.
Future<String> saveFileToDownloads(String fileName, List<int> bytes) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/$fileName';
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(filePath, mimeType: '*/*')],
        fileNameOverrides: [fileName],
      ),
    );
    return filePath;
  }

  Directory? downloads;
  try {
    downloads = await getDownloadsDirectory();
  } catch (_) {}
  downloads ??= await getTemporaryDirectory();

  final filePath = '${downloads.path}/$fileName';
  final file = File(filePath);
  await file.create(recursive: true);
  await file.writeAsBytes(bytes);
  return filePath;
}