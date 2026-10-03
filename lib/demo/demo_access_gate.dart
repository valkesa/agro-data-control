/// Build-time gate. Normal builds are closed unless explicitly compiled with
/// `--dart-define=AGRO_DEMO_ENABLED=true`.
const bool agroDemoBuildEnabled = bool.fromEnvironment(
  'AGRO_DEMO_ENABLED',
  defaultValue: false,
);

/// Pure role/build decision. It deliberately accepts the role as a primitive
/// so lib/demo has no dependency on authentication or production services.
class DemoAccessGate {
  const DemoAccessGate._();

  static bool canAccess({
    required String? role,
    bool buildEnabled = agroDemoBuildEnabled,
  }) => buildEnabled && role == 'owner';
}
