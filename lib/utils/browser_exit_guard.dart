import 'browser_exit_guard_stub.dart'
    if (dart.library.html) 'browser_exit_guard_web.dart'
    as impl;

typedef BrowserExitGuardDisposer = void Function();

BrowserExitGuardDisposer registerBrowserExitGuard() {
  return impl.registerBrowserExitGuard();
}
