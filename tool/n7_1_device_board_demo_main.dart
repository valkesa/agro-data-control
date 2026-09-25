// N7.1 §21 Chrome manual walkthrough — dev-only entrypoint (never shipped
// to `lib/main.dart`) that renders the real [DeviceBoardConfigPage]/
// [BoardEditorPage] (device mode) against LOCAL Firestore+Auth emulators
// instead of production Firebase. Never touches real Firestore: this file
// is not imported by `lib/main.dart` and is not part of the production
// build. Same "separate dev-only main() under tool/" convention already
// used by `tool/board_preview_main.dart` (N6.x) for the same reason:
// exercising real pages/widgets in a real browser without touching
// production data or requiring the full app's real sign-in flow.
//
// Prerequisites (see no_git/informes_de_codigo/evidencia_n7_1/README or
// the informe's Chrome manual section for the exact commands): Firestore
// + Auth emulators running on 127.0.0.1:8180/127.0.0.1:9199 for project
// "demo-n7-1-walkthrough", seeded with a fixed owner user
// (owner@n7demo.test / n7demo123), `tenants/tenant-demo`,
// `tenants/tenant-demo/devices/device-1`/`device-2`,
// `capabilityProfiles/sala_a`, `boardPresets/preset_demo_sala_a`.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:agro_data_control/firebase_options.dart';
import 'package:agro_data_control/models/agro_device.dart';
import 'package:agro_data_control/pages/device_board_config_page.dart';

const String _tenantId = 'tenant-demo';

// Kept alive for the process lifetime: the handle is ref-counted and
// semantics production stops if it is ever disposed/collected.
// ignore: unused_field
SemanticsHandle? _semanticsHandle;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Force the semantics tree on immediately (normally requires a user click
  // on Flutter web's "enable accessibility" placeholder) so an automated
  // CDP driver can locate widgets by their accessible label for this
  // dev-only Chrome walkthrough tool.
  _semanticsHandle = SemanticsBinding.instance.ensureSemantics();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8180);
  await FirebaseAuth.instance.useAuthEmulator('127.0.0.1', 9199);
  await FirebaseAuth.instance.signInWithEmailAndPassword(
    email: 'owner@n7demo.test',
    password: 'n7demo123',
  );
  // Wait for the Auth SDK to actually settle on the signed-in user before
  // rendering anything that reads Firestore — otherwise the very first
  // read can race ahead of the SDK's internal auth-state propagation and
  // reach the Firestore emulator as unauthenticated, causing a spurious
  // permission-denied (verified independently via direct REST calls with
  // a real ID token that the rules/seed data themselves are correct).
  await FirebaseAuth.instance.authStateChanges().firstWhere((u) => u != null);
  runApp(const _DemoApp());
}

class _DemoApp extends StatelessWidget {
  const _DemoApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(theme: ThemeData.dark(), home: const _DeviceHub());
  }
}

class _DeviceHub extends StatelessWidget {
  const _DeviceHub();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('N7.1 — Device Board Demo Hub')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              key: const ValueKey('hub-open-device-1'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (context) => DeviceBoardConfigPage(
                    isOwner: true,
                    tenantId: _tenantId,
                    device: AgroDevice(
                      id: 'device-1',
                      tenantId: _tenantId,
                      siteId: 'site-demo',
                      name: 'Sala Demo 1',
                      type: 'other',
                      model: '',
                      description: '',
                      enabled: true,
                      createdAt: null,
                      updatedAt: null,
                    ),
                  ),
                ),
              ),
              child: const Text('Abrir Configuración de Board — Device 1'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              key: const ValueKey('hub-open-device-2'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (context) => DeviceBoardConfigPage(
                    isOwner: true,
                    tenantId: _tenantId,
                    device: AgroDevice(
                      id: 'device-2',
                      tenantId: _tenantId,
                      siteId: 'site-demo',
                      name: 'Sala Demo 2',
                      type: 'other',
                      model: '',
                      description: '',
                      enabled: true,
                      createdAt: null,
                      updatedAt: null,
                    ),
                  ),
                ),
              ),
              child: const Text('Abrir Configuración de Board — Device 2'),
            ),
          ],
        ),
      ),
    );
  }
}
