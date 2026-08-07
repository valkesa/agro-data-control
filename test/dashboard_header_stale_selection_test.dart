// Regression test for a real production incident: an owner's persisted
// activeTenantId/defaultSiteId pointed at a tenant/site that had since
// been disabled (a QA entity used for Etapa 5A's smoke test, disabled in
// Etapa 5B). DashboardHeader's tenant/site DropdownButtons hard-assert
// that `value` matches exactly one `item` — the stale id no longer
// appearing in `availableTenants`/`availableSites` (active-only lists)
// crashed the entire dashboard boot for that user, locking them out.
//
// Fixed in two layers: `_loadDashboardBootstrap` in main.dart now
// re-validates the resolved tenant/site against the just-fetched active
// lists and falls back to the first available one (not covered here,
// that logic lives inside a State class); and, as a defense-in-depth
// backstop tested directly here, DashboardHeader itself never passes a
// stale value straight into DropdownButton.
import 'package:agro_data_control/services/site_config_service.dart';
import 'package:agro_data_control/widgets/dashboard_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final List<TenantDocument> activeTenants = const [
    TenantDocument(tenantId: 'la-payana', name: 'La Payana', active: true),
    TenantDocument(
      tenantId: 'the-gene-pig',
      name: 'The Gene Pig',
      active: true,
    ),
  ];

  final List<SiteDocument> activeSites = const [
    SiteDocument(
      siteId: 'roque-perez',
      technicalId: 'roque-perez',
      name: 'Roque Pérez',
      backendUrl: 'https://example.com',
      active: true,
      enabled: true,
      provisioningStatus: 'ready',
    ),
    SiteDocument(
      siteId: 'otro-site',
      technicalId: 'otro-site',
      name: 'Otro Site',
      backendUrl: 'https://example.com',
      active: true,
      enabled: true,
      provisioningStatus: 'ready',
    ),
  ];

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets(
    'un activeTenantId que ya no esta en availableTenants (ej. tenant QA '
    'deshabilitado) no crashea el header — nunca antes del fix real',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          DashboardHeader(
            selectedTab: 'detalle',
            onSignOut: () {},
            onOpenSettings: () {},
            onSelectDetail: () {},
            onSelectTablero: () {},
            onSelectTabla: () {},
            onLogoTap: () {},
            activeTenantId: 'qa-structural-test', // ya no esta en la lista
            availableTenants: activeTenants,
            canSelectSite: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('un activeSiteId que ya no esta en availableSites (ej. site QA '
      'deshabilitado) no crashea el header', (WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(
        DashboardHeader(
          selectedTab: 'detalle',
          onSignOut: () {},
          onOpenSettings: () {},
          onSelectDetail: () {},
          onSelectTablero: () {},
          onSelectTabla: () {},
          onLogoTap: () {},
          activeTenantId: 'la-payana',
          availableTenants: activeTenants,
          activeSiteId: 'qa-site', // ya no esta en la lista
          availableSites: activeSites,
          canSelectSite: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'un activeTenantId/activeSiteId valido (caso normal) sigue funcionando '
    'igual que antes',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          DashboardHeader(
            selectedTab: 'detalle',
            onSignOut: () {},
            onOpenSettings: () {},
            onSelectDetail: () {},
            onSelectTablero: () {},
            onSelectTabla: () {},
            onLogoTap: () {},
            activeTenantId: 'the-gene-pig',
            availableTenants: activeTenants,
            activeSiteId: 'otro-site',
            availableSites: activeSites,
            canSelectSite: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('The Gene Pig'), findsOneWidget);
    },
  );
}
