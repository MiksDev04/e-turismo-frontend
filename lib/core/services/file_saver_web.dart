// Web implementation for saving files: triggers browser download via AnchorElement
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<String> saveFileToDownloads(String fileName, List<int> bytes) async {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.document.createElement('a') as html.AnchorElement;
  anchor.href = url;
  anchor.download = fileName;
  anchor.style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
  return fileName;
}
