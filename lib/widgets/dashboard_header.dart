import 'package:flutter/material.dart';

import '../services/site_config_service.dart';

class DashboardHeader extends StatelessWidget {
  const DashboardHeader({
    super.key,
    required this.selectedTab,
    required this.screenTitle,
    required this.onSignOut,
    required this.onOpenSettings,
    required this.onSelectComparison,
    required this.onLogoTap,
    this.userEmail,
    this.siteName,
    this.activeSiteId,
    this.availableSites = const <SiteDocument>[],
    this.onSiteChanged,
    this.activeUsersIndicator,
  });

  final String selectedTab;
  final String screenTitle;
  final VoidCallback onSignOut;
  final VoidCallback onOpenSettings;
  final VoidCallback onSelectComparison;
  final VoidCallback onLogoTap;
  final String? userEmail;
  final String? siteName;
  final String? activeSiteId;
  final List<SiteDocument> availableSites;
  final void Function(String siteId)? onSiteChanged;
  final Widget? activeUsersIndicator;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool narrow = constraints.maxWidth < 560;
        final bool veryNarrow = constraints.maxWidth < 360;
        final EdgeInsets padding = EdgeInsets.symmetric(
          horizontal: narrow ? 12 : 20,
          vertical: narrow ? 12 : 16,
        );
        final Widget title = _HeaderTitle(
          siteName: siteName,
          screenTitle: screenTitle,
          activeSiteId: activeSiteId,
          availableSites: availableSites,
          onSiteChanged: onSiteChanged,
          compact: narrow,
          veryCompact: veryNarrow,
          onLogoTap: onLogoTap,
        );
        final String? normalizedEmail = (userEmail ?? '').trim().isEmpty
            ? null
            : userEmail!.trim();
        final Widget actions = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: narrow ? 8 : 12,
              runSpacing: 8,
              children: [
                if (selectedTab != 'comparativo')
                  _NavButton(
                    label: 'Home',
                    selected: false,
                    onPressed: onSelectComparison,
                  ),
                ?activeUsersIndicator,
                _SettingsButton(onPressed: onOpenSettings),
                _HeaderActionButton(
                  onPressed: onSignOut,
                  tooltip: 'Salir',
                  icon: Icons.logout,
                ),
              ],
            ),
            if (normalizedEmail != null) ...[
              const SizedBox(height: 4),
              _UserEmailLabel(email: normalizedEmail, compact: narrow),
            ],
          ],
        );

        return Container(
          padding: padding,
          decoration: const BoxDecoration(
            color: Color(0xCC0F172A),
            border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
          ),
          child: narrow
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 10),
                    actions,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 20),
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: actions,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xFF111827),
        foregroundColor: const Color(0xFFE5E7EB),
        side: const BorderSide(color: Color(0xFF334155)),
        padding: const EdgeInsets.all(11),
        minimumSize: const Size.square(42),
      ),
      tooltip: 'Configuracion',
      icon: const Icon(Icons.settings, size: 21),
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton({
    required this.onPressed,
    required this.tooltip,
    required this.icon,
  });

  final VoidCallback onPressed;
  final String tooltip;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xFF111827),
        foregroundColor: const Color(0xFFE5E7EB),
        side: const BorderSide(color: Color(0xFF334155)),
        padding: const EdgeInsets.all(11),
        minimumSize: const Size.square(42),
      ),
      tooltip: tooltip,
      icon: Icon(icon, size: 21),
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
      constraints: BoxConstraints(maxWidth: compact ? 120 : 180),
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
    required this.siteName,
    required this.screenTitle,
    required this.activeSiteId,
    required this.availableSites,
    required this.onSiteChanged,
    required this.compact,
    required this.veryCompact,
    required this.onLogoTap,
  });

  final String? siteName;
  final String screenTitle;
  final String? activeSiteId;
  final List<SiteDocument> availableSites;
  final void Function(String siteId)? onSiteChanged;
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
                'AgroDataControl',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: const Color(0xFFE5E7EB),
                  fontSize: veryCompact ? 18 : (compact ? 21 : 24),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              if (availableSites.length > 1)
                _SiteDropdown(
                  availableSites: availableSites,
                  activeSiteId: activeSiteId,
                  onSiteChanged: onSiteChanged,
                )
              else
                Text(
                  siteName ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const SizedBox(height: 3),
              Text(
                screenTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
            ],
          ),
        ),
      ],
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
          fontSize: 14,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
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
                child: Text(site.name),
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

class _ValkeLogo extends StatelessWidget {
  const _ValkeLogo({required this.onTap, required this.compact});

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Ir al Dashboard',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(
          'web/branding/Logo.png',
          width: compact ? 44 : 52,
          height: compact ? 44 : 52,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: selected
            ? const Color(0xFF0EA5E9)
            : const Color(0xFF1E293B),
        foregroundColor: const Color(0xFFE5E7EB),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        side: BorderSide(
          color: selected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(label),
    );
  }
}
