import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'firebase/firestore_paths.dart';
import 'models/dashboard_range_settings.dart';
import 'models/dashboard_snapshot.dart';
import 'models/magnifier_settings.dart';
import 'models/munters_model.dart';
import 'models/plc_unit_diagnostics.dart';
import 'models/unit_visibility_settings.dart';
import 'models/water_shortage_summary.dart';
import 'pages/comparison_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/munters_page.dart';
import 'pages/user_management_page.dart';
import 'pages/validation_page.dart';
import 'services/control_dashboard_config_service.dart';
import 'services/firebase_email_auth_service.dart';
import 'services/plc_dashboard_service.dart';
import 'services/site_config_service.dart';
import 'services/tenant_membership_service.dart';
import 'services/user_context_service.dart';
import 'services/user_management_service.dart';
import 'services/water_shortage_repository.dart';
import 'widgets/dashboard_header.dart';
import 'widgets/press_magnifier_region.dart';
import 'utils/browser_exit_guard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const AgroDataControlApp());
}

class AgroDataControlApp extends StatelessWidget {
  const AgroDataControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF0F172A);
    const surfaceColor = Color(0xFF1E293B);
    const textColor = Color(0xFFE5E7EB);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AgroDataControl',
      routes: <String, WidgetBuilder>{
        SnapshotValidationPage.routeName: (_) => const SnapshotValidationPage(),
      },
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: backgroundColor,
        fontFamily: 'monospace',
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF38BDF8),
          secondary: Color(0xFF22C55E),
          surface: surfaceColor,
          error: Color(0xFFEF4444),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: textColor),
          bodyLarge: TextStyle(color: textColor),
          titleLarge: TextStyle(
            color: textColor,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
          titleMedium: TextStyle(
            color: textColor,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        cardTheme: CardThemeData(
          color: surfaceColor,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF334155), width: 1),
          ),
          shadowColor: Colors.black54,
        ),
      ),
      home: const _AppEntry(),
    );
  }
}

class _AppEntry extends StatelessWidget {
  const _AppEntry();

  @override
  Widget build(BuildContext context) {
    final String path = Uri.base.path;

    if (path.contains('validation')) {
      return const SnapshotValidationPage();
    }

    return const _AppRoot();
  }
}

class _AppRoot extends StatelessWidget {
  const _AppRoot();

  static const FirebaseEmailAuthService _authService =
      FirebaseEmailAuthService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authService.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _CenteredStatusScaffold(
            title: 'Inicializando sesion',
            message: 'Esperando estado de autenticacion...',
            showProgress: true,
          );
        }

        if (snapshot.hasError) {
          return _CenteredStatusScaffold(
            title: 'Error de autenticacion',
            message: snapshot.error.toString(),
          );
        }

        final User? user = snapshot.data;
        if (user == null) {
          return const _LoginScreen(authService: _authService);
        }

        return AgroDataShell(user: user, authService: _authService);
      },
    );
  }
}

class AgroDataShell extends StatefulWidget {
  const AgroDataShell({
    super.key,
    required this.user,
    required this.authService,
  });

  final User user;
  final FirebaseEmailAuthService authService;

  @override
  State<AgroDataShell> createState() => _AgroDataShellState();
}

class _AgroDataShellState extends State<AgroDataShell> {
  static const Duration _liveRefreshInterval = Duration(seconds: 5);
  static const Duration _snapshotStaleThreshold = Duration(seconds: 20);
  static const Duration _snapshotPulseDuration = Duration(milliseconds: 400);

  final UserContextService _userContextService = const UserContextService();
  final TenantMembershipService _tenantMembershipService =
      const TenantMembershipService();
  final ControlDashboardConfigService _dashboardConfigService =
      const ControlDashboardConfigService();
  PlcDashboardService _service = const PlcDashboardService();
  String? _activeSiteId;
  String? _activeSiteName;
  List<SiteDocument> _availableSites = const <SiteDocument>[];
  final SiteConfigService _siteConfigService = const SiteConfigService();
  final PressMagnifierController _magnifierController =
      PressMagnifierController();
  String _selectedTab = 'comparativo';
  DashboardSnapshot _snapshot = DashboardSnapshot.placeholder();
  Timer? _refreshTimer;
  DashboardRangeSettings _rangeSettings =
      const DashboardRangeSettings.defaults();
  MagnifierSettings _magnifierSettings = const MagnifierSettings.defaults();
  UnitVisibilitySettings _unitVisibilitySettings =
      const UnitVisibilitySettings.defaults();
  List<String> _comparisonModuleOrder = ComparisonPage.defaultModuleOrder;
  late Future<_DashboardBootstrapResult> _dashboardBootstrapFuture;
  StreamSubscription<ControlDashboardConfigResult>? _configSubscription;
  bool _liveRequestInFlight = false;
  bool _showSnapshotPulse = false;
  bool _backendOnline = false;
  bool _snapshotStale = false;
  DateTime? _lastSuccessfulSnapshotAt;
  Timer? _snapshotPulseTimer;
  String? _historyTenantId;
  String? _historySiteId;
  String? _userRole;
  final WaterShortageRepository _waterShortageRepo =
      const WaterShortageRepository();
  final Map<String, bool?> _prevNivelAguaAlarma = {};
  Map<String, WaterShortageSummary> _waterShortageSummaries = {};
  late final BrowserExitGuardDisposer _disposeBrowserExitGuard;

  @override
  void initState() {
    super.initState();
    _disposeBrowserExitGuard = registerBrowserExitGuard();
    _dashboardBootstrapFuture = _createDashboardBootstrapFuture();
  }

  @override
  void dispose() {
    _disposeBrowserExitGuard();
    _refreshTimer?.cancel();
    _snapshotPulseTimer?.cancel();
    _configSubscription?.cancel();
    super.dispose();
  }

  void _startConfigStream({required String tenantId, required String siteId}) {
    _configSubscription?.cancel();
    _configSubscription = _dashboardConfigService
        .watchConfig(tenantId: tenantId, siteId: siteId)
        .listen((ControlDashboardConfigResult config) {
          if (!mounted) {
            return;
          }
          final ControlDashboardThresholds t = config.thresholds;
          if (t.tempInteriorMin != null &&
              t.tempInteriorMax != null &&
              t.humidityInteriorMin != null &&
              t.humidityInteriorMax != null &&
              t.filterPressureMax != null) {
            setState(() {
              _rangeSettings = DashboardRangeSettings(
                temperatureMin: t.tempInteriorMin!,
                temperatureMax: t.tempInteriorMax!,
                humidityMin: t.humidityInteriorMin!,
                humidityMax: t.humidityInteriorMax!,
                filterPressureMax: t.filterPressureMax!,
              );
            });
          }
        });
  }

  void _selectTab(String tab) {
    setState(() {
      _selectedTab = tab;
    });
  }

  Future<void> _updateComparisonModuleOrder(List<String> moduleOrder) async {
    final List<String> normalizedOrder = ComparisonPage.normalizeModuleOrder(
      moduleOrder,
    );
    setState(() {
      _comparisonModuleOrder = normalizedOrder;
    });

    try {
      await _userContextService.saveComparisonModuleOrder(
        uid: widget.user.uid,
        moduleOrder: normalizedOrder,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar el orden de modulos: $error'),
        ),
      );
    }
  }

  Future<bool> _confirmExit() async {
    final bool? shouldExit = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Salir de la app'),
          content: const Text('¿Querés cerrar Agro Data Control?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Salir'),
            ),
          ],
        );
      },
    );
    return shouldExit ?? false;
  }

  Future<bool> _confirmSignOut() async {
    final bool? shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Cerrar sesion'),
          content: const Text('¿Querés cerrar tu sesión?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Salir'),
            ),
          ],
        );
      },
    );
    return shouldSignOut ?? false;
  }

  @override
  void didUpdateWidget(covariant AgroDataShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid) {
      _dashboardBootstrapFuture = _createDashboardBootstrapFuture();
    }
  }

  Future<_DashboardBootstrapResult> _createDashboardBootstrapFuture() async {
    final _DashboardBootstrapResult result = await _loadDashboardBootstrap();
    if (!result.canReadConfig) {
      return result;
    }

    final DashboardRangeSettings? configuredRangeSettings =
        result.rangeSettingsOrNull;
    if (configuredRangeSettings != null) {
      debugPrint(
        '[Firebase settings] temperatureMin=${configuredRangeSettings.temperatureMin} temperatureMax=${configuredRangeSettings.temperatureMax} humidityMin=${configuredRangeSettings.humidityMin} humidityMax=${configuredRangeSettings.humidityMax} filterPressureMax=${configuredRangeSettings.filterPressureMax}',
      );
    }
    if (mounted && configuredRangeSettings != null) {
      setState(() {
        _rangeSettings = configuredRangeSettings;
      });
    }
    final MagnifierSettings? configuredMagnifierSettings =
        result.magnifierSettingsOrNull;
    if (mounted && configuredMagnifierSettings != null) {
      setState(() {
        _magnifierSettings = configuredMagnifierSettings;
      });
    }
    if (mounted) {
      setState(() {
        _unitVisibilitySettings = result.unitVisibilitySettings;
      });
    }
    final List<String>? configuredComparisonModuleOrder =
        result.comparisonModuleOrderOrNull;
    if (mounted && configuredComparisonModuleOrder != null) {
      setState(() {
        _comparisonModuleOrder = configuredComparisonModuleOrder;
      });
    }
    if (mounted) {
      setState(() {
        _historyTenantId = result.userContext.activeTenantId;
        _historySiteId = result.siteId;
        _userRole = result.userContext.role;
        _activeSiteId = result.siteId.isNotEmpty ? result.siteId : null;
        _activeSiteName = result.siteDocument?.name;
        _availableSites = result.availableSites;
        _service = PlcDashboardService(
          endpoint: result.siteDocument?.backendUrl,
        );
      });
      final String? tenantId = result.userContext.activeTenantId;
      if (tenantId != null) {
        _startConfigStream(tenantId: tenantId, siteId: result.siteId);
        unawaited(
          _loadWaterShortageSummaries(
            tenantId: tenantId,
            siteId: result.siteId,
          ),
        );
        unawaited(_refreshLiveSnapshot());
      }
    }
    return result;
  }

  Future<_DashboardBootstrapResult> _loadDashboardBootstrap() async {
    final UserContextResult userContext = await _userContextService
        .readUserContext(widget.user.uid, email: widget.user.email);

    final bool isOwner = userContext.role == UserAppRole.owner;
    final bool bypassesMembership =
        isOwner || userContext.role == UserAppRole.valkeTechnician;

    // Resolve effective siteId: prefer saved defaultSiteId, fall back to first
    // allowed site. No hardcoded fallback — null means no site assigned yet.
    final String? resolvedSiteId =
        (userContext.defaultSiteId?.isNotEmpty == true)
        ? userContext.defaultSiteId
        : (userContext.allowedSiteIds.isNotEmpty
              ? userContext.allowedSiteIds.first
              : null);

    // Global Valke roles bypass tenant membership checks. Owner is the only
    // role allowed through inactive/pending user state.
    if (userContext.hasError ||
        !userContext.exists ||
        (!isOwner && userContext.isPendingActivation) ||
        (!isOwner && !userContext.active) ||
        userContext.activeTenantId == null ||
        resolvedSiteId == null) {
      return _DashboardBootstrapResult(
        userContext: userContext,
        membership: const TenantMembershipLookupResult.notFound(),
        config: null,
        siteId: resolvedSiteId ?? '',
      );
    }

    final String tenantId = userContext.activeTenantId!;

    // Fetch site document and available sites list in parallel.
    final SiteDocument? siteDoc = await _siteConfigService.fetchSite(
      tenantId: tenantId,
      siteId: resolvedSiteId,
    );
    final List<SiteDocument> availableSites = await _siteConfigService
        .fetchActiveSitesForUser(
          tenantId: tenantId,
          allowedSiteIds: userContext.allowedSiteIds,
        );

    // Tenant users need a membership record. Global Valke roles do not.
    if (!bypassesMembership) {
      final TenantMembershipLookupResult membership =
          await _tenantMembershipService.readMembership(
            tenantId: tenantId,
            uid: widget.user.uid,
          );

      if (membership.hasError || !membership.exists || !membership.active) {
        return _DashboardBootstrapResult(
          userContext: userContext,
          membership: membership,
          config: null,
          siteId: resolvedSiteId,
          siteDocument: siteDoc,
          availableSites: availableSites,
        );
      }

      final ControlDashboardConfigResult config = await _dashboardConfigService
          .readConfig(tenantId: tenantId, siteId: resolvedSiteId);

      return _DashboardBootstrapResult(
        userContext: userContext,
        membership: membership,
        config: config,
        siteId: resolvedSiteId,
        siteDocument: siteDoc,
        availableSites: availableSites,
      );
    }

    // Global Valke role path: read config directly without membership.
    final ControlDashboardConfigResult config = await _dashboardConfigService
        .readConfig(tenantId: tenantId, siteId: resolvedSiteId);

    return _DashboardBootstrapResult(
      userContext: userContext,
      membership: const TenantMembershipLookupResult.notFound(),
      config: config,
      siteId: resolvedSiteId,
      siteDocument: siteDoc,
      availableSites: availableSites,
    );
  }

  Future<void> _openSettings() async {
    while (mounted) {
      final _DashboardBootstrapResult bootstrap =
          await _dashboardBootstrapFuture;
      if (!mounted) {
        return;
      }
      final _SettingsMenuAction? action = await showDialog<_SettingsMenuAction>(
        // ignore: use_build_context_synchronously
        context: context,
        builder: (context) => _SettingsMenuDialog(
          userEmail: widget.user.email ?? 'Sin email',
          selectedTab: _selectedTab,
          userRole: _userRole,
          canEditConfig: bootstrap.canEditConfig,
        ),
      );

      if (!mounted || action == null) {
        return;
      }

      switch (action) {
        case _SettingsMenuAction.changePassword:
          if (_userRole == UserAppRole.valkeTechnician) {
            continue;
          }
          await _openChangePassword();
          continue;
        case _SettingsMenuAction.rangeSettings:
          await _openRangeSettings();
          continue;
        case _SettingsMenuAction.filterSettings:
          await _openFilterSettings();
          continue;
        case _SettingsMenuAction.debugFilterIcons:
          await _openDebugFilterIcons();
          continue;
        case _SettingsMenuAction.magnifierSettings:
          await _openMagnifierSettings();
          continue;
        case _SettingsMenuAction.unitVisibilitySettings:
          await _openUnitVisibilitySettings();
          continue;
        case _SettingsMenuAction.manageUsers:
          await showDialog<void>(
            // ignore: use_build_context_synchronously
            context: context,
            builder: (context) => const UserManagementPage(),
          );
          continue;
        case _SettingsMenuAction.rolesHelp:
          await showDialog<void>(
            // ignore: use_build_context_synchronously
            context: context,
            builder: (context) => const _RolesHelpDialog(),
          );
          continue;
        case _SettingsMenuAction.legacyInterfaces:
          final _SettingsMenuAction? legacyAction =
              await showDialog<_SettingsMenuAction>(
                context: context,
                builder: (context) =>
                    _LegacyInterfacesDialog(selectedTab: _selectedTab),
              );
          if (!mounted || legacyAction == null) {
            continue;
          }
          switch (legacyAction) {
            case _SettingsMenuAction.legacyDashboard:
              _selectTab('dashboard');
              return;
            case _SettingsMenuAction.legacyMunters1:
              _selectTab('munters1');
              return;
            case _SettingsMenuAction.legacyMunters2:
              _selectTab('munters2');
              return;
            default:
              continue;
          }
        case _SettingsMenuAction.legacyDashboard:
          _selectTab('dashboard');
          return;
        case _SettingsMenuAction.legacyMunters1:
          _selectTab('munters1');
          return;
        case _SettingsMenuAction.legacyMunters2:
          _selectTab('munters2');
          return;
      }
    }
  }

  Future<void> _openRangeSettings() async {
    final _DashboardBootstrapResult bootstrap = await _dashboardBootstrapFuture;
    if (!mounted) {
      return;
    }
    final DashboardRangeSettings? updated =
        await showDialog<DashboardRangeSettings>(
          context: context,
          builder: (context) =>
              _DashboardSettingsDialog(initialSettings: _rangeSettings),
        );

    if (updated == null || !mounted) {
      return;
    }

    await _saveRangeSettings(bootstrap: bootstrap, updated: updated);
  }

  Future<void> _openFilterSettings() async {
    final _DashboardBootstrapResult bootstrap = await _dashboardBootstrapFuture;
    if (!mounted) {
      return;
    }

    final double? updated = await showDialog<double>(
      context: context,
      builder: (context) =>
          _FilterSettingsDialog(initialValue: _rangeSettings.filterPressureMax),
    );

    if (updated == null || !mounted) {
      return;
    }

    await _saveRangeSettings(
      bootstrap: bootstrap,
      updated: DashboardRangeSettings(
        temperatureMin: _rangeSettings.temperatureMin,
        temperatureMax: _rangeSettings.temperatureMax,
        humidityMin: _rangeSettings.humidityMin,
        humidityMax: _rangeSettings.humidityMax,
        filterPressureMax: updated,
      ),
    );
  }

  Future<void> _openDebugFilterIcons() async {
    await showDialog<void>(
      context: context,
      builder: (context) => const _FilterIconsDebugDialog(),
    );
  }

  Future<void> _saveRangeSettings({
    required _DashboardBootstrapResult bootstrap,
    required DashboardRangeSettings updated,
  }) async {
    final String? tenantId = bootstrap.userContext.activeTenantId;
    if (tenantId == null || !bootstrap.canEditConfig) {
      setState(() {
        _rangeSettings = updated;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar en Firebase.')),
      );
      return;
    }

    final ControlDashboardThresholds thresholds = ControlDashboardThresholds(
      tempInteriorMin: updated.temperatureMin,
      tempInteriorOpt: (updated.temperatureMin + updated.temperatureMax) / 2,
      tempInteriorMax: updated.temperatureMax,
      humidityInteriorMin: updated.humidityMin,
      humidityInteriorOpt: (updated.humidityMin + updated.humidityMax) / 2,
      humidityInteriorMax: updated.humidityMax,
      filterPressureMax: updated.filterPressureMax,
    );

    final ControlDashboardSaveResult saveResult = await _dashboardConfigService
        .saveThresholds(
          tenantId: tenantId,
          siteId: bootstrap.siteId,
          userUid: widget.user.uid,
          thresholds: thresholds,
        );

    if (!mounted) {
      return;
    }

    if (!saveResult.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo guardar en Firebase: ${saveResult.errorMessage}',
          ),
        ),
      );
      return;
    }

    final ControlDashboardConfigResult refreshedConfig =
        await _dashboardConfigService.readConfig(
          tenantId: tenantId,
          siteId: bootstrap.siteId,
        );

    if (!mounted) {
      return;
    }

    final DashboardRangeSettings effectiveSettings =
        refreshedConfig.thresholds.tempInteriorMin != null &&
            refreshedConfig.thresholds.tempInteriorMax != null &&
            refreshedConfig.thresholds.humidityInteriorMin != null &&
            refreshedConfig.thresholds.humidityInteriorMax != null &&
            refreshedConfig.thresholds.filterPressureMax != null
        ? DashboardRangeSettings(
            temperatureMin: refreshedConfig.thresholds.tempInteriorMin!,
            temperatureMax: refreshedConfig.thresholds.tempInteriorMax!,
            humidityMin: refreshedConfig.thresholds.humidityInteriorMin!,
            humidityMax: refreshedConfig.thresholds.humidityInteriorMax!,
            filterPressureMax: refreshedConfig.thresholds.filterPressureMax!,
          )
        : updated;

    debugPrint(
      '[Firebase settings] temperatureMin=${effectiveSettings.temperatureMin} temperatureMax=${effectiveSettings.temperatureMax} humidityMin=${effectiveSettings.humidityMin} humidityMax=${effectiveSettings.humidityMax} filterPressureMax=${effectiveSettings.filterPressureMax}',
    );

    setState(() {
      _rangeSettings = effectiveSettings;
      _dashboardBootstrapFuture = Future<_DashboardBootstrapResult>.value(
        _DashboardBootstrapResult(
          userContext: bootstrap.userContext,
          membership: bootstrap.membership,
          config: refreshedConfig,
          siteId: bootstrap.siteId,
          siteDocument: bootstrap.siteDocument,
          availableSites: bootstrap.availableSites,
        ),
      );
    });
  }

  Future<void> _openMagnifierSettings() async {
    final _DashboardBootstrapResult bootstrap = await _dashboardBootstrapFuture;
    if (!mounted) {
      return;
    }

    final MagnifierSettings? updated = await showDialog<MagnifierSettings>(
      context: context,
      builder: (context) =>
          _MagnifierSettingsDialog(initialSettings: _magnifierSettings),
    );

    if (updated == null || !mounted) {
      return;
    }

    final String? tenantId = bootstrap.userContext.activeTenantId;
    if (tenantId == null || !bootstrap.canEditConfig) {
      setState(() {
        _magnifierSettings = updated;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar en Firebase.')),
      );
      return;
    }

    final ControlDashboardSaveResult saveResult = await _dashboardConfigService
        .saveMagnifierSettings(
          tenantId: tenantId,
          siteId: bootstrap.siteId,
          userUid: widget.user.uid,
          zoom: updated.zoom,
          size: updated.size,
        );

    if (!mounted) {
      return;
    }

    setState(() {
      _magnifierSettings = updated;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saveResult.isSuccess
              ? 'Configuracion de lupa guardada.'
              : 'No se pudo guardar en Firebase.',
        ),
      ),
    );
  }

  Future<void> _openChangePassword() async {
    final String? newPassword = await showDialog<String>(
      context: context,
      builder: (context) => const _ChangePasswordDialog(),
    );

    if (newPassword == null || !mounted) {
      return;
    }

    try {
      await widget.authService.updatePassword(newPassword: newPassword);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password actualizada correctamente.')),
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message ?? error.code)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar password: $error')),
      );
    }
  }

  Future<void> _openUnitVisibilitySettings() async {
    final UnitVisibilitySettings? updated =
        await showDialog<UnitVisibilitySettings>(
          context: context,
          builder: (context) => _UnitVisibilitySettingsDialog(
            initialSettings: _unitVisibilitySettings,
          ),
        );

    if (updated == null || !mounted) {
      return;
    }

    try {
      await _userContextService.saveUnitVisibilitySettings(
        uid: widget.user.uid,
        showMunters1: updated.showMunters1,
        showMunters2: updated.showMunters2,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar en Firebase: $error')),
      );
      return;
    }

    setState(() {
      _unitVisibilitySettings = updated;
    });
  }

  Future<void> _switchSite(String siteId) async {
    final _DashboardBootstrapResult bootstrap = await _dashboardBootstrapFuture;
    final String? tenantId = bootstrap.userContext.activeTenantId;
    if (tenantId == null) return;

    final bool isOwner = bootstrap.userContext.role == UserAppRole.owner;
    if (!isOwner && !bootstrap.userContext.allowedSiteIds.contains(siteId)) {
      debugPrint(
        '[site-switch] siteId=$siteId not in allowedSiteIds — blocked',
      );
      return;
    }

    try {
      await _userContextService.setActiveSite(
        uid: widget.user.uid,
        siteId: siteId,
      );
    } catch (error) {
      debugPrint('[site-switch] persist error=$error');
    }

    final SiteDocument? siteDoc = await _siteConfigService.fetchSite(
      tenantId: tenantId,
      siteId: siteId,
    );

    if (!mounted) return;
    setState(() {
      _activeSiteId = siteId;
      _activeSiteName = siteDoc?.name;
      _historySiteId = siteId;
      _service = PlcDashboardService(endpoint: siteDoc?.backendUrl);
    });

    _startConfigStream(tenantId: tenantId, siteId: siteId);
    unawaited(_loadWaterShortageSummaries(tenantId: tenantId, siteId: siteId));
    unawaited(_refreshLiveSnapshot());
  }

  Future<void> _refreshLiveSnapshot() async {
    if (_liveRequestInFlight) {
      return;
    }

    _refreshTimer?.cancel();

    if (mounted) {
      setState(() {
        _liveRequestInFlight = true;
      });
    }

    final LiveSnapshotResult result = await _service.fetchLiveSnapshot();
    if (!mounted) {
      return;
    }

    setState(() {
      _liveRequestInFlight = false;

      if (result.isSuccess) {
        final DateTime successfulSnapshotAt =
            result.receivedAt ??
            result.snapshot!.lastUpdatedAt ??
            DateTime.now();
        final DashboardSnapshot nextSnapshot = _withUpdateDeltas(
          next: result.snapshot!,
          previous: _snapshot,
        );
        final bool snapshotStale = _isSnapshotStale(nextSnapshot);
        _snapshot = _applyBackendConnectivity(
          snapshot: _attachBackendMetadata(snapshot: nextSnapshot),
          backendOnline: true,
          snapshotStale: snapshotStale,
        );
        _backendOnline = true;
        _snapshotStale = snapshotStale;
        _lastSuccessfulSnapshotAt = successfulSnapshotAt;
        _showSnapshotPulse = true;
        debugPrint(
          '[frontend-fetch] snapshot fetch success backendOnline=$_backendOnline snapshotStale=$_snapshotStale lastSuccessfulSnapshotAt=${_lastSuccessfulSnapshotAt?.toIso8601String()}',
        );
      } else {
        _snapshot = _applyBackendConnectivity(
          snapshot: _snapshot,
          backendOnline: false,
          snapshotStale: true,
        );
        _backendOnline = false;
        _snapshotStale = true;
        debugPrint(
          '[frontend-fetch] snapshot fetch failed source=${result.source} backendOnline=$_backendOnline snapshotStale=$_snapshotStale lastSuccessfulSnapshotAt=${_lastSuccessfulSnapshotAt?.toIso8601String()} error=${result.message ?? result.statusLabel}',
        );
      }
    });

    if (result.isSuccess) {
      _detectWaterShortageTransitions(result.snapshot!.units);
      _snapshotPulseTimer?.cancel();
      _snapshotPulseTimer = Timer(_snapshotPulseDuration, () {
        if (!mounted) {
          return;
        }
        setState(() {
          _showSnapshotPulse = false;
        });
      });
    }

    if (mounted) {
      _refreshTimer = Timer(_liveRefreshInterval, () {
        unawaited(_refreshLiveSnapshot());
      });
    }
  }

  void _detectWaterShortageTransitions(List<MuntersModel> units) {
    final String? tenantId = _historyTenantId;
    final String? siteId = _historySiteId;
    if (tenantId == null || siteId == null) {
      return;
    }
    for (final MuntersModel unit in units) {
      final String key = unit.historyPlcId ?? unit.name;
      final bool? prev = _prevNivelAguaAlarma[key];
      final bool? curr = unit.nivelAguaAlarma;
      if (prev != true && curr == true) {
        final String? plcId = unit.historyPlcId;
        if (plcId != null) {
          unawaited(
            _recordWaterShortageEvent(
              tenantId: tenantId,
              siteId: siteId,
              plcId: plcId,
            ),
          );
        }
      }
      _prevNivelAguaAlarma[key] = curr;
    }
  }

  Future<void> _recordWaterShortageEvent({
    required String tenantId,
    required String siteId,
    required String plcId,
  }) async {
    try {
      await _waterShortageRepo.recordFaultEvent(
        tenantId: tenantId,
        siteId: siteId,
        plcId: plcId,
      );
      unawaited(
        _loadWaterShortageSummaries(tenantId: tenantId, siteId: siteId),
      );
    } catch (e) {
      debugPrint('[water-shortage] Error registrando evento de falla: $e');
    }
  }

  Future<void> _loadWaterShortageSummaries({
    required String tenantId,
    required String siteId,
  }) async {
    const List<String> plcIds = ['munters1', 'munters2'];
    final Map<String, WaterShortageSummary> summaries = {};
    await Future.wait(
      plcIds.map((plcId) async {
        try {
          summaries[plcId] = await _waterShortageRepo.fetchSummary(
            tenantId: tenantId,
            siteId: siteId,
            plcId: plcId,
          );
        } catch (e) {
          debugPrint('[water-shortage] Error cargando resumen para $plcId: $e');
        }
      }),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _waterShortageSummaries = summaries;
    });
  }

  DashboardSnapshot _withUpdateDeltas({
    required DashboardSnapshot next,
    required DashboardSnapshot previous,
  }) {
    final List<MuntersModel> mergedUnits = <MuntersModel>[];
    for (var index = 0; index < next.units.length; index++) {
      final MuntersModel current = next.units[index];
      final MuntersModel? prior = index < previous.units.length
          ? previous.units[index]
          : null;
      mergedUnits.add(
        _copyMuntersModel(
          source: current,
          previousLastUpdatedAt: prior?.lastUpdatedAt,
          updateDeltaSeconds: _calculateUpdateDeltaSeconds(
            current.lastUpdatedAt,
            prior?.lastUpdatedAt,
          ),
        ),
      );
    }

    return DashboardSnapshot(
      units: mergedUnits,
      doorEvents: next.doorEvents,
      backendOnline: next.backendOnline,
      startedAt: next.startedAt,
      lastUpdatedAt: next.lastUpdatedAt,
      clientName: next.clientName,
    );
  }

  int? _calculateUpdateDeltaSeconds(DateTime? current, DateTime? previous) {
    if (current == null || previous == null) {
      return null;
    }
    return previous.difference(current).inSeconds.abs();
  }

  DashboardSnapshot _applyBackendConnectivity({
    required DashboardSnapshot snapshot,
    required bool backendOnline,
    required bool snapshotStale,
  }) {
    return DashboardSnapshot(
      units: snapshot.units
          .map(
            (unit) => _copyMuntersModel(
              source: unit,
              backendOnline: backendOnline,
              diagnostics: _deriveFrontendDiagnostics(
                unit,
                backendOnline: backendOnline,
                snapshotStale: snapshotStale,
              ),
            ),
          )
          .toList(growable: false),
      doorEvents: snapshot.doorEvents,
      backendOnline: backendOnline,
      startedAt: snapshot.startedAt,
      lastUpdatedAt: snapshot.lastUpdatedAt,
      clientName: snapshot.clientName,
    );
  }

  DashboardSnapshot _attachBackendMetadata({
    required DashboardSnapshot snapshot,
  }) {
    return DashboardSnapshot(
      units: snapshot.units
          .map(
            (unit) => _copyMuntersModel(
              source: unit,
              backendStartedAt: snapshot.startedAt,
              lastUpdatedAt: unit.lastUpdatedAt,
              previousLastUpdatedAt: unit.previousLastUpdatedAt,
              updateDeltaSeconds: null,
            ),
          )
          .toList(growable: false),
      doorEvents: snapshot.doorEvents,
      backendOnline: snapshot.backendOnline,
      startedAt: snapshot.startedAt,
      lastUpdatedAt: snapshot.lastUpdatedAt,
      clientName: snapshot.clientName,
    );
  }

  bool _isSnapshotStale(DashboardSnapshot snapshot) {
    final DateTime? lastUpdatedAt = snapshot.lastUpdatedAt;
    if (lastUpdatedAt == null) {
      return true;
    }
    return DateTime.now().difference(lastUpdatedAt) > _snapshotStaleThreshold;
  }

  PlcUnitDiagnostics _deriveFrontendDiagnostics(
    MuntersModel unit, {
    required bool backendOnline,
    required bool snapshotStale,
  }) {
    final PlcUnitDiagnostics base =
        unit.diagnostics ??
        PlcUnitDiagnostics(
          backendAlive: backendOnline,
          plcConnectOk: unit.plcReachable ?? false,
          validKeySignals: null,
          invalidKeySignals: null,
          totalKeySignals: null,
          lastPollAt: unit.lastUpdatedAt,
          lastSuccessfulReadAt: unit.lastUpdatedAt,
          stateCode: PlcUnitDiagnostics.plcUnreachable,
          stateLabel: 'Sin diagnostico',
          stateReason: 'El backend no envio diagnostico explicito.',
        );

    if (!backendOnline) {
      return base.copyWith(
        backendAlive: false,
        stateCode: PlcUnitDiagnostics.backendDown,
        stateLabel: 'Backend no disponible',
        stateReason: 'No se pudo obtener /api/snapshot.',
      );
    }
    if (snapshotStale) {
      return base.copyWith(
        backendAlive: true,
        stateCode: PlcUnitDiagnostics.backendDown,
        stateLabel: 'Datos desactualizados',
        stateReason: 'El snapshot supera el umbral de frescura.',
      );
    }
    return base.copyWith(backendAlive: true);
  }

  MuntersModel _copyMuntersModel({
    required MuntersModel source,
    PlcUnitDiagnostics? diagnostics,
    bool? backendOnline,
    DateTime? backendStartedAt,
    DateTime? lastUpdatedAt,
    DateTime? previousLastUpdatedAt,
    int? updateDeltaSeconds,
  }) {
    return MuntersModel(
      name: source.name,
      historyClientId: source.historyClientId,
      historyPlcId: source.historyPlcId,
      diagnostics: diagnostics ?? source.diagnostics,
      backendOnline: backendOnline ?? source.backendOnline,
      configured: source.configured,
      plcReachable: source.plcReachable,
      plcRunning: source.plcRunning,
      dataFresh: source.dataFresh,
      plcOnline: source.plcOnline,
      plcLatencyMs: source.plcLatencyMs,
      routerLatencyMs: source.routerLatencyMs,
      backendStartedAt: backendStartedAt ?? source.backendStartedAt,
      lastUpdatedAt: lastUpdatedAt ?? source.lastUpdatedAt,
      previousLastUpdatedAt:
          previousLastUpdatedAt ?? source.previousLastUpdatedAt,
      updateDeltaSeconds: updateDeltaSeconds ?? source.updateDeltaSeconds,
      lastHeartbeatValue: source.lastHeartbeatValue,
      lastHeartbeatChangeAt: source.lastHeartbeatChangeAt,
      lastError: source.lastError,
      tempInterior: source.tempInterior,
      tempIngresoSala: source.tempIngresoSala,
      humInterior: source.humInterior,
      tempExterior: source.tempExterior,
      humExterior: source.humExterior,
      nh3: source.nh3,
      presionDiferencial: source.presionDiferencial,
      tensionSalidaVentiladores: source.tensionSalidaVentiladores,
      fanQ5: source.fanQ5,
      fanQ6: source.fanQ6,
      fanQ7: source.fanQ7,
      fanQ8: source.fanQ8,
      fanQ9: source.fanQ9,
      fanQ10: source.fanQ10,
      bombaHumidificador: source.bombaHumidificador,
      resistencia1: source.resistencia1,
      resistencia2: source.resistencia2,
      alarmaGeneral: source.alarmaGeneral,
      fallaRed: source.fallaRed,
      nivelAguaAlarma: source.nivelAguaAlarma,
      fallaTermicaBomba: source.fallaTermicaBomba,
      eventosSinAgua: source.eventosSinAgua,
      horasMunter: source.horasMunter,
      horasFiltroF9: source.horasFiltroF9,
      horasFiltroG4: source.horasFiltroG4,
      horasPolifosfato: source.horasPolifosfato,
      salaAbierta: source.salaAbierta,
      aperturasSala: source.aperturasSala,
      munterAbierto: source.munterAbierto,
      aperturasMunter: source.aperturasMunter,
      cantidadApagadas: source.cantidadApagadas,
      estadoEquipo: source.estadoEquipo,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DashboardBootstrapResult>(
      future: _dashboardBootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _CenteredStatusScaffold(
            title: 'Validando acceso',
            message: 'Estamos revisando la asignacion del usuario...',
            showProgress: true,
          );
        }

        if (snapshot.hasError) {
          return _AccessBlockedScaffold(
            title: 'No se pudo validar el acceso',
            message: snapshot.error.toString(),
            onSignOut: widget.authService.signOut,
          );
        }

        final _DashboardBootstrapResult? bootstrap = snapshot.data;
        if (bootstrap == null || !bootstrap.canReadConfig) {
          return _AccessBlockedScaffold(
            title: 'Acceso pendiente',
            userEmail: widget.user.email,
            message:
                bootstrap?.accessDeniedMessage(widget.user) ??
                'Tu usuario todavia no tiene rol, tenant y site asignados.',
            onSignOut: widget.authService.signOut,
          );
        }

        return _buildDashboard(context);
      },
    );
  }

  Widget _buildDashboard(BuildContext context) {
    final List<MuntersModel> units = _snapshot.units;
    final MuntersModel munters1 = units.first;
    final MuntersModel munters2 = units.length > 1
        ? units[1]
        : const MuntersModel.placeholder(name: 'Munters 2');
    final MuntersModel selectedUnit = _selectedTab == 'munters2'
        ? munters2
        : munters1;

    debugPrint(
      '[frontend-render] root.plcOnline=null status.plcOnline=null munters1.plcOnline=${munters1.plcOnline} munters2.plcOnline=${munters2.plcOnline}',
    );
    debugPrint(
      '[frontend-render] backendOnline=$_backendOnline snapshotStale=$_snapshotStale lastSuccessfulSnapshotAt=${_lastSuccessfulSnapshotAt?.toIso8601String()} munters1.configured=${munters1.configured} munters1.plcReachable=${munters1.plcReachable} munters1.dataFresh=${munters1.dataFresh} munters1.estadoEquipo=${munters1.estadoEquipo} munters2.configured=${munters2.configured} munters2.plcReachable=${munters2.plcReachable} munters2.dataFresh=${munters2.dataFresh} munters2.estadoEquipo=${munters2.estadoEquipo}',
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) {
          return;
        }
        final bool shouldExit = await _confirmExit();
        if (!shouldExit) {
          return;
        }
        await SystemNavigator.pop();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              DashboardHeader(
                selectedTab: _selectedTab,
                onSignOut: () async {
                  final bool shouldSignOut = await _confirmSignOut();
                  if (!shouldSignOut || !mounted) {
                    return;
                  }
                  await widget.authService.signOut();
                },
                onOpenSettings: _openSettings,
                onSelectComparison: () => _selectTab('comparativo'),
                siteName: _activeSiteName,
                activeSiteId: _activeSiteId,
                availableSites: _availableSites,
                onSiteChanged: _switchSite,
              ),
              if (_snapshotStale)
                _StaleSnapshotBanner(
                  lastSuccessfulSnapshotAt: _lastSuccessfulSnapshotAt,
                ),
              Expanded(
                child: PressMagnifierRegion(
                  controller: _magnifierController,
                  settings: _magnifierSettings,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (_selectedTab == 'comparativo') {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          child: ComparisonPage(
                            munters1: munters1,
                            munters2: munters2,
                            doorEvents: _snapshot.doorEvents,
                            tenantId: _historyTenantId,
                            siteId: _historySiteId,
                            showMunters1: _unitVisibilitySettings.showMunters1,
                            showMunters2: _unitVisibilitySettings.showMunters2,
                            snapshotStale: _snapshotStale,
                            showSnapshotPulse: _showSnapshotPulse,
                            rangeSettings: _rangeSettings,
                            magnifierSettings: _magnifierSettings,
                            moduleOrder: _comparisonModuleOrder,
                            onModuleOrderChanged: _updateComparisonModuleOrder,
                          ),
                        );
                      }

                      if (_selectedTab == 'munters1' ||
                          _selectedTab == 'munters2') {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          child: MuntersPage(
                            data: selectedUnit,
                            snapshotStale: _snapshotStale,
                            showSnapshotPulse: _showSnapshotPulse,
                            waterShortageSummary:
                                _waterShortageSummaries[selectedUnit
                                    .historyPlcId],
                          ),
                        );
                      }

                      final bool desktop = constraints.maxWidth >= 1200;

                      if (desktop) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 5,
                                child: DashboardPage(
                                  units: units,
                                  selectedUnitName: selectedUnit.name,
                                  waterShortageSummaries:
                                      _waterShortageSummaries,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 4,
                                child: MuntersPage(
                                  data: selectedUnit,
                                  snapshotStale: _snapshotStale,
                                  showSnapshotPulse: _showSnapshotPulse,
                                  waterShortageSummary:
                                      _waterShortageSummaries[selectedUnit
                                          .historyPlcId],
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DashboardPage(
                              units: units,
                              selectedUnitName: selectedUnit.name,
                              waterShortageSummaries: _waterShortageSummaries,
                            ),
                            const SizedBox(height: 12),
                            MuntersPage(
                              data: selectedUnit,
                              snapshotStale: _snapshotStale,
                              showSnapshotPulse: _showSnapshotPulse,
                              waterShortageSummary:
                                  _waterShortageSummaries[selectedUnit
                                      .historyPlcId],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen({required this.authService});

  final FirebaseEmailAuthService authService;

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final String email = _emailController.text.trim();
    final String password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Completa email y password.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.authService.signIn(email: email, password: password);
    } on FirebaseAuthException catch (error) {
      setState(() {
        _errorMessage = error.message ?? error.code;
      });
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.authService.signInWithGoogle();
    } on FirebaseAuthException catch (error) {
      setState(() {
        _errorMessage = error.message ?? error.code;
      });
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Ingresar',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Login real con Firebase Auth para resolver el tenant del usuario.',
                    style: TextStyle(color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _isLoading ? null : _signIn(),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFFFCA5A5),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _isLoading ? null : _signIn,
                    child: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Ingresar'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'o',
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: _isLoading ? null : _signInWithGoogle,
                    child: const Text('Continuar con Google'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CenteredStatusScaffold extends StatelessWidget {
  const _CenteredStatusScaffold({
    required this.title,
    required this.message,
    this.showProgress = false,
  });

  final String title;
  final String message;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showProgress) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
              ],
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccessBlockedScaffold extends StatelessWidget {
  const _AccessBlockedScaffold({
    required this.title,
    required this.message,
    required this.onSignOut,
    this.userEmail,
  });

  final String title;
  final String? userEmail;
  final String message;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (userEmail != null && userEmail!.isNotEmpty) ...[
                  Text(
                    userEmail!,
                    style: const TextStyle(color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 6),
                ],
                Text(message, style: const TextStyle(color: Color(0xFF94A3B8))),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: onSignOut,
                  child: const Text('Cerrar sesion'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardBootstrapResult {
  const _DashboardBootstrapResult({
    required this.userContext,
    required this.membership,
    required this.config,
    required this.siteId,
    this.siteDocument,
    this.availableSites = const <SiteDocument>[],
  });

  final UserContextResult userContext;
  final TenantMembershipLookupResult membership;
  final ControlDashboardConfigResult? config;
  final String siteId;
  final SiteDocument? siteDocument;
  final List<SiteDocument> availableSites;

  bool get bypassesMembership =>
      userContext.role == UserAppRole.owner ||
      userContext.role == UserAppRole.valkeTechnician;

  bool get canReadConfig =>
      userContext.exists &&
      userContext.active &&
      (bypassesMembership ||
          (membership.exists &&
              membership.active &&
              membership.tenantId != null));

  bool get canEditConfig =>
      userContext.role == UserAppRole.owner ||
      membership.role == UserAppRole.tenantAdmin;

  String accessDeniedMessage(User user) {
    final String identity = user.email ?? user.uid;
    if (userContext.hasError) {
      return 'No se pudo leer el perfil de $identity: ${userContext.errorMessage}';
    }
    if (!userContext.exists || userContext.isPendingActivation) {
      return 'Debe solicitar acceso a un administrador de Valke S.A.';
    }
    if (!userContext.active) {
      return 'El usuario $identity esta inactivo. Un owner debe activarlo antes de ingresar.';
    }
    if (userContext.role == null || userContext.role!.isEmpty) {
      return 'El usuario $identity no tiene rol asignado.';
    }
    if (userContext.activeTenantId == null ||
        userContext.activeTenantId!.isEmpty) {
      return 'El usuario $identity no tiene tenant asignado.';
    }
    if (siteId.isEmpty) {
      return 'El usuario $identity no tiene site asignado.';
    }
    if (membership.hasError) {
      return 'No se pudo validar la membresia del tenant: ${membership.errorMessage}';
    }
    if (!bypassesMembership && !membership.exists) {
      return 'El usuario $identity no tiene membresia activa en el tenant asignado.';
    }
    if (!bypassesMembership && !membership.active) {
      return 'La membresia del usuario $identity esta inactiva.';
    }
    return 'El usuario $identity no tiene permisos suficientes para acceder.';
  }

  DashboardRangeSettings? get rangeSettingsOrNull {
    final ControlDashboardThresholds? thresholds = config?.thresholds;
    if (thresholds == null ||
        thresholds.tempInteriorMin == null ||
        thresholds.tempInteriorMax == null ||
        thresholds.humidityInteriorMin == null ||
        thresholds.humidityInteriorMax == null ||
        thresholds.filterPressureMax == null) {
      return null;
    }

    return DashboardRangeSettings(
      temperatureMin: thresholds.tempInteriorMin!,
      temperatureMax: thresholds.tempInteriorMax!,
      humidityMin: thresholds.humidityInteriorMin!,
      humidityMax: thresholds.humidityInteriorMax!,
      filterPressureMax: thresholds.filterPressureMax!,
    );
  }

  MagnifierSettings? get magnifierSettingsOrNull {
    final double? zoom = config?.readMagnifierZoom();
    final double? size = config?.readMagnifierSize();
    if (zoom == null || size == null) {
      return null;
    }

    return MagnifierSettings(zoom: zoom, size: size);
  }

  UnitVisibilitySettings get unitVisibilitySettings {
    final bool? userShowMunters1 = userContext.readShowMunters1();
    final bool? userShowMunters2 = userContext.readShowMunters2();
    if (userShowMunters1 != null || userShowMunters2 != null) {
      return UnitVisibilitySettings(
        showMunters1: userShowMunters1 ?? true,
        showMunters2: userShowMunters2 ?? true,
      );
    }
    if (config == null || !config!.hasVisibleUnitsConfig) {
      return const UnitVisibilitySettings.defaults();
    }
    return UnitVisibilitySettings(
      showMunters1: config?.readShowMunters1() ?? true,
      showMunters2: config?.readShowMunters2() ?? true,
    );
  }

  List<String>? get comparisonModuleOrderOrNull {
    final List<String>? storedOrder = userContext.readComparisonModuleOrder();
    if (storedOrder == null) {
      return null;
    }
    return ComparisonPage.normalizeModuleOrder(storedOrder);
  }

  Color get statusColor {
    if (userContext.hasError ||
        membership.hasError ||
        config?.hasError == true) {
      return const Color(0xFFEF4444);
    }
    if (!userContext.exists ||
        !userContext.active ||
        (!bypassesMembership && !membership.exists) ||
        (!bypassesMembership && !membership.active) ||
        config?.exists == false) {
      return const Color(0xFFF59E0B);
    }
    if (config?.exists == true) {
      return const Color(0xFF22C55E);
    }
    return const Color(0xFF38BDF8);
  }

  String get statusLabel {
    if (userContext.hasError) {
      return 'Error leyendo users/{uid}';
    }
    if (!userContext.exists) {
      return 'Usuario autenticado sin contexto';
    }
    if (!userContext.active) {
      return 'Usuario inactivo';
    }
    if (bypassesMembership && config == null) {
      return 'Tenant resuelto, falta leer dashboard';
    }
    if (bypassesMembership && config?.hasError == true) {
      return 'Error leyendo controlDashboard';
    }
    if (bypassesMembership && config?.exists == false) {
      return 'Tenant resuelto, documento no existe';
    }
    if (bypassesMembership) {
      return 'Acceso Valke de solo lectura';
    }
    if (membership.hasError) {
      return 'Error resolviendo membresia';
    }
    if (!membership.exists) {
      return 'Sin membresia activa en el tenant';
    }
    if (!membership.active) {
      return 'Membresia inactiva';
    }
    if (config == null) {
      return 'Tenant resuelto, falta leer dashboard';
    }
    if (config!.hasError) {
      return 'Error leyendo controlDashboard';
    }
    if (!config!.exists) {
      return 'Tenant resuelto, documento no existe';
    }
    return 'Configuración compartida disponible';
  }

  String primaryLine(User user) {
    if (userContext.hasError) {
      return 'Usuario=${user.email ?? user.uid} error=${userContext.errorMessage}';
    }
    if (!userContext.exists) {
      return 'Falta users/${user.uid}';
    }
    if (!userContext.active) {
      return 'users/${user.uid} esta inactivo';
    }
    if (bypassesMembership) {
      if (config == null) {
        return 'Usuario=${user.email ?? user.uid} tenant=${userContext.activeTenantId}';
      }
      if (config!.hasError) {
        return 'tenant=${userContext.activeTenantId} site=$siteId error=${config!.errorMessage}';
      }
      if (!config!.exists) {
        return 'tenant=${userContext.activeTenantId} site=$siteId documento ausente';
      }
      return 'usuario=${user.email ?? user.uid} tenant=${userContext.activeTenantId} site=$siteId';
    }
    if (membership.hasError) {
      return 'Usuario=${user.email ?? user.uid} tenant=${userContext.activeTenantId} error=${membership.errorMessage}';
    }
    if (!membership.exists) {
      return 'Usuario=${user.email ?? user.uid} sin membresia activa en tenants/${userContext.activeTenantId}/members/${user.uid}';
    }
    if (!membership.active) {
      return 'Usuario=${user.email ?? user.uid} tenant=${userContext.activeTenantId} membresia inactiva';
    }
    if (config == null) {
      return 'Usuario=${user.email ?? user.uid} tenant=${userContext.activeTenantId}';
    }
    if (config!.hasError) {
      return 'tenant=${userContext.activeTenantId} site=$siteId error=${config!.errorMessage}';
    }
    if (!config!.exists) {
      return 'tenant=${userContext.activeTenantId} site=$siteId documento ausente';
    }
    return 'usuario=${user.email ?? user.uid} tenant=${userContext.activeTenantId} site=$siteId';
  }

  String secondaryLine() {
    if (bypassesMembership) {
      return 'role=${userContext.role ?? 'sin role'} path=${config?.path ?? FirestorePaths.controlDashboardSettings(userContext.activeTenantId!, siteId)}';
    }
    if (userContext.exists && userContext.active && !membership.exists) {
      return 'activeTenantId=${userContext.activeTenantId} defaultSiteId=${userContext.defaultSiteId}';
    }
    if (membership.exists && !membership.active) {
      return 'role=${membership.role ?? 'sin role'}';
    }
    if (config?.exists == true) {
      return 'active=${config!.active} updatedAt=${formatDateTime(config!.updatedAt)}';
    }
    if (config?.hasError == true) {
      return 'path=${config!.path}';
    }
    if (membership.exists && membership.active) {
      return 'role=${membership.role ?? 'sin role'} path=${config?.path ?? FirestorePaths.controlDashboardSettings(userContext.activeTenantId!, siteId)}';
    }
    return 'site=$siteId';
  }
}

String formatDateTime(DateTime? value) {
  if (value == null) {
    return 'N/D';
  }
  return value.toIso8601String();
}

String _formatStaleDateTime(DateTime value) {
  final DateTime local = value.toLocal();
  final String day = local.day.toString().padLeft(2, '0');
  final String month = local.month.toString().padLeft(2, '0');
  final String year = (local.year % 100).toString().padLeft(2, '0');
  return '$day/$month/$year ${_formatClockTime(local)}';
}

String _formatClockTime(DateTime value) {
  final DateTime local = value.toLocal();
  final String hh = local.hour.toString().padLeft(2, '0');
  final String mm = local.minute.toString().padLeft(2, '0');
  final String ss = local.second.toString().padLeft(2, '0');
  return '$hh:$mm:$ss';
}

class _StaleSnapshotBanner extends StatelessWidget {
  const _StaleSnapshotBanner({required this.lastSuccessfulSnapshotAt});

  final DateTime? lastSuccessfulSnapshotAt;

  @override
  Widget build(BuildContext context) {
    final String message = lastSuccessfulSnapshotAt == null
        ? 'ATENCION: Datos desactualizados: Sin datos del backend.'
        : 'ATENCION: Datos desactualizados: Ultimos datos: ${_formatStaleDateTime(lastSuccessfulSnapshotAt!)}';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF3B0D12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF7F1D1D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(
              color: Color(0xFFFCA5A5),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'DATOS VIEJOS: Los datos mostrados no representan la realidad',
            style: TextStyle(
              color: Color(0xFFFCA5A5),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

enum _SettingsMenuAction {
  changePassword,
  rangeSettings,
  filterSettings,
  debugFilterIcons,
  magnifierSettings,
  unitVisibilitySettings,
  manageUsers,
  rolesHelp,
  legacyInterfaces,
  legacyDashboard,
  legacyMunters1,
  legacyMunters2,
}

class _SettingsMenuDialog extends StatelessWidget {
  const _SettingsMenuDialog({
    required this.userEmail,
    required this.selectedTab,
    required this.canEditConfig,
    this.userRole,
  });

  final String userEmail;
  final String selectedTab;
  final bool canEditConfig;
  final String? userRole;

  @override
  Widget build(BuildContext context) {
    final bool canChangePassword = userRole != UserAppRole.valkeTechnician;

    return AlertDialog(
      backgroundColor: const Color(0xFF111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Configuracion',
        style: TextStyle(color: Color(0xFFE5E7EB)),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Usuario',
              style: TextStyle(
                color: Color(0xFFE5E7EB),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Email actual',
                              style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              userEmail,
                              style: const TextStyle(
                                color: Color(0xFFE5E7EB),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (canChangePassword) ...[
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'Cambiar password',
                          onPressed: () => Navigator.of(
                            context,
                          ).pop(_SettingsMenuAction.changePassword),
                          icon: const Icon(Icons.build_rounded, size: 18),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (canEditConfig) ...[
              const SizedBox(height: 18),
              const Text(
                'Seteos',
                style: TextStyle(
                  color: Color(0xFFE5E7EB),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.tonal(
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(_SettingsMenuAction.rangeSettings),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text('Rangos Temp. y Hum.'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(_SettingsMenuAction.filterSettings),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text('Limite Presion Diferencial'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(_SettingsMenuAction.magnifierSettings),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text('Lupa'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            const Text(
              'Vista',
              style: TextStyle(
                color: Color(0xFFE5E7EB),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: () => Navigator.of(
                  context,
                ).pop(_SettingsMenuAction.unitVisibilitySettings),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('PLC visibles'),
              ),
            ),
            if (userRole == UserAppRole.owner) ...[
              const SizedBox(height: 18),
              const Text(
                'Administración',
                style: TextStyle(
                  color: Color(0xFFE5E7EB),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.tonal(
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(_SettingsMenuAction.rolesHelp),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.security_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('Roles'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(_SettingsMenuAction.manageUsers),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.manage_accounts_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('Gestión de usuarios'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Interfaces viejas',
                style: TextStyle(
                  color: Color(0xFFE5E7EB),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(_SettingsMenuAction.legacyInterfaces),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.subdirectory_arrow_right_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Abrir interfaces'),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _RolesHelpDialog extends StatelessWidget {
  const _RolesHelpDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Roles', style: TextStyle(color: Color(0xFFE5E7EB))),
      content: const SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RoleHelpCard(
                role: 'owner',
                label: 'Owner',
                scope: 'Global',
                description:
                    'Acceso total al sistema. Puede ver todos los datos, editar configuraciones, gestionar usuarios, asignar tenants/sites y administrar roles.',
              ),
              SizedBox(height: 10),
              _RoleHelpCard(
                role: 'valke_technician',
                label: 'Tecnico Valke',
                scope: 'Global, solo lectura',
                description:
                    'Personal tecnico de Valke. Puede entrar a la app y ver el tenant/site asignado, settings y metricas. No puede modificar configuraciones ni gestionar usuarios.',
              ),
              SizedBox(height: 10),
              _RoleHelpCard(
                role: 'tenant_admin',
                label: 'Admin de tenant',
                scope: 'Por tenant',
                description:
                    'Administra su tenant. Puede ver datos, editar configuraciones del tenant/site y gestionar operadores dentro de su tenant. No puede crear owners ni otros admins.',
              ),
              SizedBox(height: 10),
              _RoleHelpCard(
                role: 'tenant_operator',
                label: 'Operador',
                scope: 'Por tenant',
                description:
                    'Usuario operativo del cliente. Puede ver la app y operar segun los permisos del tenant. No puede gestionar usuarios ni modificar configuraciones generales.',
              ),
              SizedBox(height: 10),
              _RoleHelpCard(
                role: 'pending',
                label: 'Pendiente',
                scope: 'Global',
                description:
                    'Usuario registrado sin acceso activo. Queda esperando que un owner le asigne rol, tenant y sites.',
              ),
              SizedBox(height: 10),
              _RoleHelpCard(
                role: 'null',
                label: 'Sin rol',
                scope: 'Estado administrativo',
                description:
                    'Usuario sin rol asignado. No deberia tener acceso funcional hasta que se configure su tenant, sites y estado activo.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _RoleHelpCard extends StatelessWidget {
  const _RoleHelpCard({
    required this.role,
    required this.label,
    required this.scope,
    required this.description,
  });

  final String role;
  final String label;
  final String scope;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFE5E7EB),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              _RoleCodePill(role),
              _RoleScopePill(scope),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleCodePill extends StatelessWidget {
  const _RoleCodePill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF93C5FD),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RoleScopePill extends StatelessWidget {
  const _RoleScopePill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF052E16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF166534)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFBBF7D0),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LegacyInterfacesDialog extends StatelessWidget {
  const _LegacyInterfacesDialog({required this.selectedTab});

  final String selectedTab;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Interfaces viejas',
        style: TextStyle(color: Color(0xFFE5E7EB)),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LegacyMenuButton(
              label: 'Dashboard',
              selected: selectedTab == 'dashboard',
              onPressed: () => Navigator.of(
                context,
              ).pop(_SettingsMenuAction.legacyDashboard),
            ),
            const SizedBox(height: 8),
            _LegacyMenuButton(
              label: 'Munters 1',
              selected: selectedTab == 'munters1',
              onPressed: () =>
                  Navigator.of(context).pop(_SettingsMenuAction.legacyMunters1),
            ),
            const SizedBox(height: 8),
            _LegacyMenuButton(
              label: 'Munters 2',
              selected: selectedTab == 'munters2',
              onPressed: () =>
                  Navigator.of(context).pop(_SettingsMenuAction.legacyMunters2),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Volver'),
        ),
      ],
    );
  }
}

class _LegacyMenuButton extends StatelessWidget {
  const _LegacyMenuButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          side: BorderSide(
            color: selected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
          ),
          foregroundColor: selected
              ? const Color(0xFF38BDF8)
              : const Color(0xFFE5E7EB),
        ),
        child: Row(
          children: [
            if (selected)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.check, size: 16),
              ),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _obscurePassword = true;
  String? _errorText;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final String password = _passwordController.text.trim();
    final String confirm = _confirmController.text.trim();

    if (password.length < 6) {
      setState(() {
        _errorText = 'La password debe tener al menos 6 caracteres.';
      });
      return;
    }

    if (password != confirm) {
      setState(() {
        _errorText = 'Las passwords no coinciden.';
      });
      return;
    }

    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Cambiar password',
        style: TextStyle(color: Color(0xFFE5E7EB)),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: const TextStyle(color: Color(0xFFE5E7EB)),
              decoration: InputDecoration(
                labelText: 'Nueva password',
                labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmController,
              obscureText: _obscurePassword,
              style: const TextStyle(color: Color(0xFFE5E7EB)),
              decoration: const InputDecoration(
                labelText: 'Repetir password',
                labelStyle: TextStyle(color: Color(0xFF94A3B8)),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: const TextStyle(
                  color: Color(0xFFFCA5A5),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }
}

class _DashboardSettingsDialog extends StatefulWidget {
  const _DashboardSettingsDialog({required this.initialSettings});

  final DashboardRangeSettings initialSettings;

  @override
  State<_DashboardSettingsDialog> createState() =>
      _DashboardSettingsDialogState();
}

class _DashboardSettingsDialogState extends State<_DashboardSettingsDialog> {
  late final TextEditingController _temperatureMinController;
  late final TextEditingController _temperatureMaxController;
  late final TextEditingController _humidityMinController;
  late final TextEditingController _humidityMaxController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _temperatureMinController = TextEditingController(
      text: widget.initialSettings.temperatureMin.toString(),
    );
    _temperatureMaxController = TextEditingController(
      text: widget.initialSettings.temperatureMax.toString(),
    );
    _humidityMinController = TextEditingController(
      text: widget.initialSettings.humidityMin.toString(),
    );
    _humidityMaxController = TextEditingController(
      text: widget.initialSettings.humidityMax.toString(),
    );
  }

  @override
  void dispose() {
    _temperatureMinController.dispose();
    _temperatureMaxController.dispose();
    _humidityMinController.dispose();
    _humidityMaxController.dispose();
    super.dispose();
  }

  void _submit() {
    final double? temperatureMin = _parseInput(_temperatureMinController.text);
    final double? temperatureMax = _parseInput(_temperatureMaxController.text);
    final double? humidityMin = _parseInput(_humidityMinController.text);
    final double? humidityMax = _parseInput(_humidityMaxController.text);

    if (temperatureMin == null ||
        temperatureMax == null ||
        humidityMin == null ||
        humidityMax == null) {
      setState(() {
        _errorText = 'Completa los cuatro valores con numeros validos.';
      });
      return;
    }

    if (temperatureMin >= temperatureMax || humidityMin >= humidityMax) {
      setState(() {
        _errorText = 'Cada minimo debe ser menor que su maximo.';
      });
      return;
    }

    Navigator.of(context).pop(
      DashboardRangeSettings(
        temperatureMin: temperatureMin,
        temperatureMax: temperatureMax,
        humidityMin: humidityMin,
        humidityMax: humidityMax,
        filterPressureMax: widget.initialSettings.filterPressureMax,
      ),
    );
  }

  double? _parseInput(String value) {
    return double.tryParse(value.trim().replaceAll(',', '.'));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Configuracion de rangos',
        style: TextStyle(color: Color(0xFFE5E7EB)),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Estos rangos aplican a todos los Munters en la UI.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
            const SizedBox(height: 16),
            _RangeField(
              controller: _temperatureMinController,
              label: 'Temp. interior minima',
              suffix: 'C',
            ),
            const SizedBox(height: 10),
            _RangeField(
              controller: _temperatureMaxController,
              label: 'Temp. interior maxima',
              suffix: 'C',
            ),
            const SizedBox(height: 14),
            _RangeField(
              controller: _humidityMinController,
              label: 'Humedad interior minima',
              suffix: '%',
            ),
            const SizedBox(height: 10),
            _RangeField(
              controller: _humidityMaxController,
              label: 'Humedad interior maxima',
              suffix: '%',
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: const TextStyle(
                  color: Color(0xFFFCA5A5),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }
}

class _FilterSettingsDialog extends StatefulWidget {
  const _FilterSettingsDialog({required this.initialValue});

  final double initialValue;

  @override
  State<_FilterSettingsDialog> createState() => _FilterSettingsDialogState();
}

class _FilterSettingsDialogState extends State<_FilterSettingsDialog> {
  late final TextEditingController _filterPressureMaxController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _filterPressureMaxController = TextEditingController(
      text: widget.initialValue.toString(),
    );
  }

  @override
  void dispose() {
    _filterPressureMaxController.dispose();
    super.dispose();
  }

  void _submit() {
    final double? filterPressureMax = double.tryParse(
      _filterPressureMaxController.text.trim().replaceAll(',', '.'),
    );
    if (filterPressureMax == null) {
      setState(() {
        _errorText = 'Completa el valor con un numero valido.';
      });
      return;
    }
    if (filterPressureMax < 0) {
      setState(() {
        _errorText =
            'La presion diferencial maxima debe ser mayor o igual a 0.';
      });
      return;
    }

    Navigator.of(context).pop(filterPressureMax);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Configuracion de filtros',
        style: TextStyle(color: Color(0xFFE5E7EB)),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Este valor define la alarma por presion diferencial en filtros.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
            const SizedBox(height: 16),
            _RangeField(
              controller: _filterPressureMaxController,
              label: 'Presion diferencial maxima',
              suffix: 'Pa',
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: const TextStyle(
                  color: Color(0xFFFCA5A5),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }
}

class _FilterIconsDebugDialog extends StatelessWidget {
  const _FilterIconsDebugDialog();

  static const Color _previewColor = Color(0xFF38BDF8);

  static const List<_DebugMaterialFilterIconOption>
  _materialIcons = <_DebugMaterialFilterIconOption>[
    _DebugMaterialFilterIconOption(
      'filter_alt_rounded',
      Icons.filter_alt_rounded,
    ),
    _DebugMaterialFilterIconOption('filter_alt', Icons.filter_alt),
    _DebugMaterialFilterIconOption(
      'filter_alt_outlined',
      Icons.filter_alt_outlined,
    ),
    _DebugMaterialFilterIconOption('filter_alt_sharp', Icons.filter_alt_sharp),
    _DebugMaterialFilterIconOption(
      'filter_alt_off_rounded',
      Icons.filter_alt_off_rounded,
    ),
    _DebugMaterialFilterIconOption('filter_alt_off', Icons.filter_alt_off),
    _DebugMaterialFilterIconOption(
      'filter_alt_off_outlined',
      Icons.filter_alt_off_outlined,
    ),
    _DebugMaterialFilterIconOption(
      'filter_list_rounded',
      Icons.filter_list_rounded,
    ),
    _DebugMaterialFilterIconOption('filter_list', Icons.filter_list),
    _DebugMaterialFilterIconOption(
      'filter_list_outlined',
      Icons.filter_list_outlined,
    ),
    _DebugMaterialFilterIconOption(
      'filter_list_sharp',
      Icons.filter_list_sharp,
    ),
    _DebugMaterialFilterIconOption('filter_list_alt', Icons.filter_list_alt),
    _DebugMaterialFilterIconOption(
      'filter_list_off_rounded',
      Icons.filter_list_off_rounded,
    ),
    _DebugMaterialFilterIconOption('filter_list_off', Icons.filter_list_off),
    _DebugMaterialFilterIconOption(
      'filter_list_off_outlined',
      Icons.filter_list_off_outlined,
    ),
    _DebugMaterialFilterIconOption(
      'filter_none_rounded',
      Icons.filter_none_rounded,
    ),
    _DebugMaterialFilterIconOption('filter_none', Icons.filter_none),
    _DebugMaterialFilterIconOption(
      'filter_none_outlined',
      Icons.filter_none_outlined,
    ),
    _DebugMaterialFilterIconOption(
      'filter_frames_rounded',
      Icons.filter_frames_rounded,
    ),
    _DebugMaterialFilterIconOption('filter_frames', Icons.filter_frames),
    _DebugMaterialFilterIconOption(
      'filter_frames_outlined',
      Icons.filter_frames_outlined,
    ),
    _DebugMaterialFilterIconOption('filter_rounded', Icons.filter_rounded),
    _DebugMaterialFilterIconOption('filter', Icons.filter),
    _DebugMaterialFilterIconOption('filter_outlined', Icons.filter_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Debug', style: TextStyle(color: Color(0xFFE5E7EB))),
      content: SizedBox(
        width: 920,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Opciones de iconos de filtros para elegir una variante.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(height: 16),
              const _DebugSectionLabel('Parecidos al actual'),
              const SizedBox(height: 10),
              const Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  _DebugFilterPreviewTile(
                    label: 'custom_square_dense',
                    preview: _DebugSquareAirFilterIcon(
                      color: _previewColor,
                      denseMesh: true,
                    ),
                  ),
                  _DebugFilterPreviewTile(
                    label: 'custom_square_light',
                    preview: _DebugSquareAirFilterIcon(color: _previewColor),
                  ),
                  _DebugFilterPreviewTile(
                    label: 'custom_square_double_border',
                    preview: _DebugSquareAirFilterIcon(
                      color: _previewColor,
                      denseMesh: true,
                      doubleBorder: true,
                    ),
                  ),
                  _DebugFilterPreviewTile(
                    label: 'custom_square_capsule',
                    preview: _DebugSquareAirFilterIcon(
                      color: _previewColor,
                      denseMesh: true,
                      capsuleBars: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const _DebugSectionLabel('Material Icons'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _materialIcons
                    .map(
                      (_DebugMaterialFilterIconOption option) =>
                          _DebugFilterPreviewTile(
                            label: option.label,
                            preview: Icon(
                              option.icon,
                              color: _previewColor,
                              size: 28,
                            ),
                          ),
                    )
                    .toList(growable: false),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _DebugSectionLabel extends StatelessWidget {
  const _DebugSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFFE5E7EB),
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _DebugFilterPreviewTile extends StatelessWidget {
  const _DebugFilterPreviewTile({required this.label, required this.preview});

  final String label;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 34, child: Center(child: preview)),
          const SizedBox(height: 10),
          SelectableText(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DebugMaterialFilterIconOption {
  const _DebugMaterialFilterIconOption(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _DebugSquareAirFilterIcon extends StatelessWidget {
  const _DebugSquareAirFilterIcon({
    required this.color,
    this.denseMesh = false,
    this.doubleBorder = false,
    this.capsuleBars = false,
  });

  final Color color;
  final bool denseMesh;
  final bool doubleBorder;
  final bool capsuleBars;

  @override
  Widget build(BuildContext context) {
    final List<double> guides = denseMesh
        ? const <double>[4, 7, 10]
        : const <double>[5.5, 8.5];

    return SizedBox(
      width: 26,
      height: 26,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: color, width: 1.6),
            ),
          ),
          if (doubleBorder)
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: color.withValues(alpha: 0.9)),
              ),
            ),
          for (final double x in guides)
            Positioned(
              left: x + 4,
              top: 4,
              bottom: 4,
              child: capsuleBars
                  ? Container(
                      width: 1.6,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    )
                  : Container(width: 1.2, color: color.withValues(alpha: 0.85)),
            ),
          for (final double y in guides)
            Positioned(
              left: 4,
              right: 4,
              top: y + 4,
              child: Container(
                height: 1.2,
                color: color.withValues(alpha: 0.85),
              ),
            ),
        ],
      ),
    );
  }
}

class _MagnifierSettingsDialog extends StatefulWidget {
  const _MagnifierSettingsDialog({required this.initialSettings});

  final MagnifierSettings initialSettings;

  @override
  State<_MagnifierSettingsDialog> createState() =>
      _MagnifierSettingsDialogState();
}

class _UnitVisibilitySettingsDialog extends StatefulWidget {
  const _UnitVisibilitySettingsDialog({required this.initialSettings});

  final UnitVisibilitySettings initialSettings;

  @override
  State<_UnitVisibilitySettingsDialog> createState() =>
      _UnitVisibilitySettingsDialogState();
}

class _UnitVisibilitySettingsDialogState
    extends State<_UnitVisibilitySettingsDialog> {
  late bool _showMunters1;
  late bool _showMunters2;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _showMunters1 = widget.initialSettings.showMunters1;
    _showMunters2 = widget.initialSettings.showMunters2;
  }

  void _submit() {
    if (!_showMunters1 && !_showMunters2) {
      setState(() {
        _errorText = 'Debe quedar visible al menos una unidad.';
      });
      return;
    }

    Navigator.of(context).pop(
      UnitVisibilitySettings(
        showMunters1: _showMunters1,
        showMunters2: _showMunters2,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Unidades visibles',
        style: TextStyle(color: Color(0xFFE5E7EB)),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Las unidades ocultas dejan de participar en la UI comparativa y en sus reglas visuales.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              value: _showMunters1,
              activeThumbColor: const Color(0xFF22C55E),
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Mostrar M1',
                style: TextStyle(color: Color(0xFFE5E7EB)),
              ),
              onChanged: (bool value) {
                setState(() {
                  _showMunters1 = value;
                  _errorText = null;
                });
              },
            ),
            SwitchListTile.adaptive(
              value: _showMunters2,
              activeThumbColor: const Color(0xFF22C55E),
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Mostrar M2',
                style: TextStyle(color: Color(0xFFE5E7EB)),
              ),
              onChanged: (bool value) {
                setState(() {
                  _showMunters2 = value;
                  _errorText = null;
                });
              },
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorText!,
                style: const TextStyle(
                  color: Color(0xFFFCA5A5),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }
}

class _MagnifierSettingsDialogState extends State<_MagnifierSettingsDialog> {
  static const List<double> _zoomOptions = <double>[1.5, 2.0, 2.5, 3.0];
  static const List<double> _sizeOptions = <double>[120, 140, 180, 220];

  late double _selectedZoom;
  late double _selectedSize;

  @override
  void initState() {
    super.initState();
    _selectedZoom = widget.initialSettings.zoom;
    _selectedSize = widget.initialSettings.size;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Configuracion de lupa',
        style: TextStyle(color: Color(0xFFE5E7EB)),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'La lupa aparece al mantener presionado sobre el contenido.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
            const SizedBox(height: 16),
            const Text(
              'Zoom',
              style: TextStyle(
                color: Color(0xFFE5E7EB),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<double>(
              initialValue: _selectedZoom,
              dropdownColor: const Color(0xFF0F172A),
              decoration: _settingsInputDecoration(),
              items: _zoomOptions
                  .map(
                    (value) => DropdownMenuItem<double>(
                      value: value,
                      child: Text('${value.toStringAsFixed(1)}x'),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _selectedZoom = value;
                });
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Tamano',
              style: TextStyle(
                color: Color(0xFFE5E7EB),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<double>(
              initialValue: _selectedSize,
              dropdownColor: const Color(0xFF0F172A),
              decoration: _settingsInputDecoration(),
              items: _sizeOptions
                  .map(
                    (value) => DropdownMenuItem<double>(
                      value: value,
                      child: Text('${value.toStringAsFixed(0)} px'),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _selectedSize = value;
                });
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(MagnifierSettings(zoom: _selectedZoom, size: _selectedSize)),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

InputDecoration _settingsInputDecoration() {
  return InputDecoration(
    filled: true,
    fillColor: const Color(0xFF0F172A),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF334155)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF334155)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF38BDF8)),
    ),
  );
}

class _RangeField extends StatelessWidget {
  const _RangeField({
    required this.controller,
    required this.label,
    required this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: Color(0xFFE5E7EB)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
        suffixText: suffix,
        suffixStyle: const TextStyle(color: Color(0xFF94A3B8)),
        filled: true,
        fillColor: const Color(0xFF0F172A),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF38BDF8)),
        ),
      ),
    );
  }
}
