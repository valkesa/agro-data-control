import 'package:flutter/material.dart';

import '../services/site_config_service.dart';

/// A pending site-configuration warning shown as a hover-tooltip icon next
/// to the header's email line, instead of a full banner in the page body —
/// kept out of the way of an owner's normal workflow.
class SiteAlert {
  const SiteAlert({required this.title, required this.subtitle, this.statusLabel});

  final String title;
  final String subtitle;
  final String? statusLabel;
}

/// Shared header for the three main views (Detalle, Tablero, Tabla) — same
/// layout, logo, tenant/site selector and action buttons everywhere. The
/// only thing that changes between views is which of the three "view"
/// buttons is highlighted (via [selectedTab]).
class DashboardHeader extends StatelessWidget {
  const DashboardHeader({
    super.key,
    required this.selectedTab,
    required this.onSignOut,
    required this.onOpenSettings,
    required this.onSelectDetail,
    required this.onSelectTablero,
    required this.onSelectTabla,
    required this.onLogoTap,
    this.userEmail,
    this.farmName,
    this.activeTenantId,
    this.availableTenants = const <TenantDocument>[],
    this.onTenantChanged,
    this.activeSiteId,
    this.availableSites = const <SiteDocument>[],
    this.onSiteChanged,
    this.canSelectSite = false,
    this.activeUsersIndicator,
    this.siteAlert,
  });

  final String selectedTab;
  final VoidCallback onSignOut;
  final VoidCallback onOpenSettings;

  /// "Detalle" — the main dashboard (ComparisonPage).
  final VoidCallback onSelectDetail;

  /// "Tablero" — EnvironmentOverviewPage (card grid).
  final VoidCallback onSelectTablero;

  /// "Tabla" — EnvironmentTablePage (unified table).
  final VoidCallback onSelectTabla;

  final VoidCallback onLogoTap;
  final String? userEmail;
  final String? farmName;
  final String? activeTenantId;
  final List<TenantDocument> availableTenants;
  final void Function(String tenantId)? onTenantChanged;
  final String? activeSiteId;
  final List<SiteDocument> availableSites;
  final void Function(String siteId)? onSiteChanged;
  final bool canSelectSite;

  /// The owner-only "eye" presence indicator, shown to the left of the
  /// three view buttons.
  final Widget? activeUsersIndicator;

  /// Owner-only pending-configuration warning; shown as a hover-tooltip
  /// icon to the left of the email line. Null hides the icon entirely —
  /// gating on ownership/role is the caller's responsibility.
  final SiteAlert? siteAlert;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool narrow = constraints.maxWidth < 560;
        final bool veryNarrow = constraints.maxWidth < 360;
        final EdgeInsets padding = EdgeInsets.symmetric(
          horizontal: narrow ? 12 : 20,
          vertical: narrow ? 10 : 12,
        );
        final Widget title = _HeaderTitle(
          farmName: farmName,
          activeTenantId: activeTenantId,
          availableTenants: availableTenants,
          onTenantChanged: onTenantChanged,
          activeSiteId: activeSiteId,
          availableSites: availableSites,
          onSiteChanged: onSiteChanged,
          canSelectSite: canSelectSite,
          compact: narrow,
          veryCompact: veryNarrow,
          onLogoTap: onLogoTap,
        );
        final String? normalizedEmail = (userEmail ?? '').trim().isEmpty
            ? null
            : userEmail!.trim();

        // Right side, left to right: eye (owner only), Tablero, Tabla,
        // Detalle, Configuración, Salir — i.e. right to left: Salir,
        // Configuración, then the three view buttons.
        final Widget actions = Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            ?activeUsersIndicator,
            _HeaderViewButton(
              tooltip: 'Tablero',
              icon: Icons.dashboard_rounded,
              selected: selectedTab == 'environmentOverview',
              onPressed: onSelectTablero,
            ),
            _HeaderViewButton(
              tooltip: 'Tabla',
              icon: Icons.table_chart_rounded,
              selected: selectedTab == 'tableView',
              onPressed: onSelectTabla,
            ),
            _HeaderViewButton(
              tooltip: 'Detalle',
              icon: Icons.article_outlined,
              selected: selectedTab == 'comparativo',
              onPressed: onSelectDetail,
            ),
            _HeaderIconButton(
              onPressed: onOpenSettings,
              tooltip: 'Configuracion',
              icon: Icons.settings_rounded,
            ),
            _HeaderIconButton(
              onPressed: onSignOut,
              tooltip: 'Salir',
              icon: Icons.logout,
            ),
          ],
        );

        return Container(
          padding: padding,
          decoration: const BoxDecoration(
            color: Color(0xCC0F172A),
            border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
          ),
          // The Valke logo sets the target header height — text/buttons
          // are sized to fit within roughly that height, with only the
          // email line allowed to add a little below it.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 12),
                  actions,
                ],
              ),
              if (normalizedEmail != null || siteAlert != null) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (siteAlert != null) ...[
                      _SiteAlertIcon(alert: siteAlert!),
                      const SizedBox(width: 6),
                    ],
                    if (normalizedEmail != null)
                      _UserEmailLabel(email: normalizedEmail, compact: narrow),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.onPressed,
    required this.tooltip,
    required this.icon,
  });

  final VoidCallback onPressed;
  final String tooltip;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          height: 28,
          width: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF162133),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: const Color(0xFF223046)),
          ),
          child: Icon(icon, size: 15, color: const Color(0xFFCBD5E1)),
        ),
      ),
    );
  }
}

/// Same shape/size as [_HeaderIconButton], but shows a highlighted state
/// for the currently active view, so the three view buttons make it clear
/// which one you're on.
class _HeaderViewButton extends StatelessWidget {
  const _HeaderViewButton({
    required this.onPressed,
    required this.tooltip,
    required this.icon,
    required this.selected,
  });

  final VoidCallback onPressed;
  final String tooltip;
  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          height: 28,
          width: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF0EA5E9)
                : const Color(0xFF162133),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: selected
                  ? const Color(0xFF38BDF8)
                  : const Color(0xFF223046),
            ),
          ),
          child: Icon(
            icon,
            size: 15,
            color: selected ? const Color(0xFFF8FAFC) : const Color(0xFFCBD5E1),
          ),
        ),
      ),
    );
  }
}

/// Hover-only warning icon replacing the old full-width banner for a site
/// pending backend configuration — keeps the header visually quiet while
/// still surfacing the alert to owners on hover.
class _SiteAlertIcon extends StatelessWidget {
  const _SiteAlertIcon({required this.alert});

  final SiteAlert alert;

  @override
  Widget build(BuildContext context) {
    final String message = alert.statusLabel == null
        ? '${alert.title}\n${alert.subtitle}'
        : '${alert.title} (${alert.statusLabel})\n${alert.subtitle}';
    return Tooltip(
      message: message,
      textAlign: TextAlign.left,
      child: const Icon(
        Icons.warning_amber_rounded,
        size: 16,
        color: Color(0xFFFBBF24),
      ),
    );
  }
}

class _UserEmailLabel extends StatelessWidget {
  const _UserEmailLabel({required this.email, this.compact = false});

  final String email;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 180 : 260),
      child: Text(
        email,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
        style: TextStyle(
          color: const Color(0xFF94A3B8),
          fontSize: compact ? 9 : 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _HeaderTitle extends StatelessWidget {
  const _HeaderTitle({
    required this.farmName,
    required this.activeTenantId,
    required this.availableTenants,
    required this.onTenantChanged,
    required this.activeSiteId,
    required this.availableSites,
    required this.onSiteChanged,
    required this.canSelectSite,
    required this.compact,
    required this.veryCompact,
    required this.onLogoTap,
  });

  final String? farmName;
  final String? activeTenantId;
  final List<TenantDocument> availableTenants;
  final void Function(String tenantId)? onTenantChanged;
  final String? activeSiteId;
  final List<SiteDocument> availableSites;
  final void Function(String siteId)? onSiteChanged;
  final bool canSelectSite;
  final bool compact;
  final bool veryCompact;
  final VoidCallback onLogoTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _ValkeLogo(onTap: onLogoTap, compact: veryCompact),
        SizedBox(width: veryCompact ? 8 : (compact ? 10 : 14)),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'AgroData Monitor | Valke S.A.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: const Color(0xFFCBD5E1),
                  fontSize: veryCompact ? 11 : (compact ? 12 : 13),
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 3),
              // Client name: a dropdown for owners who can switch between
              // several tenants, plain text for everyone else.
              if (canSelectSite && availableTenants.length > 1)
                _TenantDropdown(
                  availableTenants: availableTenants,
                  activeTenantId: activeTenantId,
                  onTenantChanged: onTenantChanged,
                )
              else
                Text(
                  farmName ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFE5E7EB),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              // Site selector: owners only, and only when there is more
              // than one site to choose from.
              if (canSelectSite && availableSites.length > 1) ...[
                const SizedBox(height: 3),
                _SiteDropdown(
                  availableSites: availableSites,
                  activeSiteId: activeSiteId,
                  onSiteChanged: onSiteChanged,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TenantDropdown extends StatelessWidget {
  const _TenantDropdown({
    required this.availableTenants,
    required this.activeTenantId,
    required this.onTenantChanged,
  });

  final List<TenantDocument> availableTenants;
  final String? activeTenantId;
  final void Function(String tenantId)? onTenantChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: activeTenantId ?? availableTenants.first.tenantId,
        isDense: true,
        dropdownColor: const Color(0xFF1E293B),
        style: const TextStyle(
          color: Color(0xFFE5E7EB),
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
        icon: const Icon(
          Icons.keyboard_arrow_down,
          color: Color(0xFF64748B),
          size: 16,
        ),
        items: availableTenants
            .map(
              (TenantDocument tenant) => DropdownMenuItem<String>(
                value: tenant.tenantId,
                child: Text(tenant.name),
              ),
            )
            .toList(),
        onChanged: (String? tenantId) {
          if (tenantId != null) {
            onTenantChanged?.call(tenantId);
          }
        },
      ),
    );
  }
}

class _SiteDropdown extends StatelessWidget {
  const _SiteDropdown({
    required this.availableSites,
    required this.activeSiteId,
    required this.onSiteChanged,
  });

  final List<SiteDocument> availableSites;
  final String? activeSiteId;
  final void Function(String siteId)? onSiteChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: activeSiteId ?? availableSites.first.siteId,
        isDense: true,
        dropdownColor: const Color(0xFF1E293B),
        style: const TextStyle(
          color: Color(0xFFCBD5E1),
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        icon: const Icon(
          Icons.keyboard_arrow_down,
          color: Color(0xFF64748B),
          size: 16,
        ),
        items: availableSites
            .map(
              (SiteDocument site) => DropdownMenuItem<String>(
                value: site.siteId,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: Text(site.name)),
                    const SizedBox(width: 8),
                    _SiteStatusChip(site: site),
                  ],
                ),
              ),
            )
            .toList(),
        onChanged: (String? siteId) {
          if (siteId != null) {
            onSiteChanged?.call(siteId);
          }
        },
      ),
    );
  }
}

class _SiteStatusChip extends StatelessWidget {
  const _SiteStatusChip({required this.site});

  final SiteDocument site;

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    if (!site.enabled) {
      background = const Color(0xFF374151);
      foreground = const Color(0xFFD1D5DB);
    } else if (site.provisioningStatus == 'error') {
      background = const Color(0xFF7F1D1D);
      foreground = const Color(0xFFFECACA);
    } else if (site.isOperational) {
      background = const Color(0xFF14532D);
      foreground = const Color(0xFFBBF7D0);
    } else {
      background = const Color(0xFF713F12);
      foreground = const Color(0xFFFDE68A);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        site.operationalStatusLabel,
        style: TextStyle(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ValkeLogo extends StatelessWidget {
  const _ValkeLogo({required this.onTap, required this.compact});

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final double size = compact ? 38 : 44;

    return Tooltip(
      message: 'Ir al Dashboard',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox.square(
          dimension: size,
          child: Image.asset(
            'web/branding/logo_valke_animated.gif',
            width: size,
            height: size,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.high,
            errorBuilder: (BuildContext context, Object error, _) {
              return Image.asset(
                'web/branding/logo_valke_192_0.png',
                width: size,
                height: size,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (BuildContext context, Object error, _) {
                  return const SizedBox.shrink();
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
