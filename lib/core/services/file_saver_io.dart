import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Saves [bytes] to disk and returns where it ended up (or `null` if the user
/// cancelled).
///
/// Android / iOS: opens the native "Save to" dialog (Storage Access Framework
/// on Android) so the user picks the destination and the file is written
/// directly there. If that dialog is unavailable it falls back to writing a
/// temp file and handing it to the OS share/save sheet.
/// Windows / macOS / Linux: unchanged, writes into the real Downloads folder.
Future<String?> saveFileToDownloads(String fileName, List<int> bytes) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final extension =
        fileName.contains('.') ? fileName.split('.').last.toLowerCase() : null;

    // Preferred: native save dialog writes straight to the chosen location.
    try {
      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'Save file',
        fileName: fileName,
        bytes: Uint8List.fromList(bytes),
        type: extension != null ? FileType.custom : FileType.any,
        allowedExtensions: extension != null ? [extension] : null,
      );
      // null means the user cancelled — do not open the share sheet.
      return savedPath;
    } catch (_) {
      // No save provider available — fall through to the share-sheet fallback.
    }

    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/$fileName';
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(filePath)],
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
