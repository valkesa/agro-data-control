// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;

typedef BrowserExitGuardDisposer = void Function();

BrowserExitGuardDisposer registerBrowserExitGuard() {
  final StreamSubscription<html.Event> subscription = html.window.onBeforeUnload
      .listen((html.Event event) {
        final html.BeforeUnloadEvent beforeUnloadEvent =
            event as html.BeforeUnloadEvent;
        beforeUnloadEvent.returnValue = '';
      });
  return () {
    subscription.cancel();
  };
}
