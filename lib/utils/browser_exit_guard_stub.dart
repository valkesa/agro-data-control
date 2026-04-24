typedef BrowserExitGuardDisposer = void Function();

BrowserExitGuardDisposer registerBrowserExitGuard() {
  return () {};
}
