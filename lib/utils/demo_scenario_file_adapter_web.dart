// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;

Future<void> downloadDemoScenarioFile(String filename, String contents) async {
  final blob = html.Blob(<Object>[contents], 'application/json;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  try {
    html.AnchorElement(href: url)
      ..download = filename
      ..click();
  } finally {
    html.Url.revokeObjectUrl(url);
  }
}

Future<String?> pickDemoScenarioFile() async {
  final input = html.FileUploadInputElement()
    ..accept = '.json,application/json';
  final result = Completer<String?>();
  late StreamSubscription<html.Event> focusSubscription;
  late StreamSubscription<html.Event> changeSubscription;

  Future<void> finish(String? value) async {
    if (result.isCompleted) return;
    result.complete(value);
    await focusSubscription.cancel();
    await changeSubscription.cancel();
  }

  changeSubscription = input.onChange.listen((_) async {
    final file = input.files?.firstOrNull;
    if (file == null) return finish(null);
    if (file.size > 1024 * 1024) {
      return finish('__AGRO_DEMO_FILE_TOO_LARGE__');
    }
    final reader = html.FileReader();
    reader.onLoad.listen((_) => finish(reader.result as String?));
    reader.onError.listen((_) => finish('__AGRO_DEMO_FILE_READ_ERROR__'));
    reader.readAsText(file);
  });
  focusSubscription = html.window.onFocus.listen((_) {
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if ((input.files?.isEmpty ?? true)) finish(null);
    });
  });
  input.click();
  return result.future;
}
