// Platform-aware file saver. Uses a web implementation when running on web.
import 'file_saver_io.dart'
        if (dart.library.html) 'file_saver_web.dart' as impl;

Future<String> saveFileToDownloads(String fileName, List<int> bytes) {
    return impl.saveFileToDownloads(fileName, bytes);
}
