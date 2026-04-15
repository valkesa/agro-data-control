import 'package:flutter/material.dart';

class DashboardHeader extends StatelessWidget {
  const DashboardHeader({
    super.key,
    required this.selectedTab,
    required this.onSignOut,
    required this.onOpenSettings,
    required this.onSelectComparison,
  });

  final String selectedTab;
  final VoidCallback onSignOut;
  final VoidCallback onOpenSettings;
  final VoidCallback onSelectComparison;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xCC0F172A),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _HeaderTitle(),
            ),
          ),
          const SizedBox(width: 20),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (selectedTab != 'comparativo')
                    _NavButton(
                      label: 'Home',
                      selected: false,
                      onPressed: onSelectComparison,
                    ),
                  _SettingsButton(onPressed: onOpenSettings),
                  _HeaderActionButton(
                    onPressed: onSignOut,
                    tooltip: 'Salir',
                    icon: Icons.logout,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
        padding: const EdgeInsets.all(14),
      ),
      tooltip: 'Configuracion',
      icon: const Icon(Icons.settings),
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
        padding: const EdgeInsets.all(14),
      ),
      tooltip: tooltip,
      icon: Icon(icon),
    );
  }
}

class _HeaderTitle extends StatelessWidget {
  const _HeaderTitle();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: const [
        _ValkeLogo(),
        SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'AgroDataControl',
              style: TextStyle(
                color: Color(0xFFE5E7EB),
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Sala Genetica',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }
}

class _ValkeLogo extends StatelessWidget {
  const _ValkeLogo();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'web/branding/Logo.png',
      width: 52,
      height: 52,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
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
