class AlertRecipient {
  const AlertRecipient({
    required this.tenantId,
    required this.siteId,
    required this.clientName,
    required this.siteName,
    required this.contactName,
    required this.phone,
  });

  final String tenantId;
  final String siteId;
  final String clientName;
  final String siteName;
  final String contactName;
  final String phone;
}

class WhatsAppAlertRecipientsConfig {
  const WhatsAppAlertRecipientsConfig();

  static const List<AlertRecipient> _recipients = <AlertRecipient>[
    AlertRecipient(
      tenantId: 'the_good_pig',
      siteId: 'main_site',
      clientName: 'The Good Pig',
      siteName: 'Sitio principal',
      contactName: 'Gerardo',
      phone: '5491138267368',
    ),
    AlertRecipient(
      tenantId: 'PENDING_TENANT_ID',
      siteId: 'PENDING_SITE_ID',
      clientName: 'Pendiente',
      siteName: 'Pendiente',
      contactName: 'Pendiente',
      phone: 'PENDING_PHONE',
    ),
  ];

  List<AlertRecipient> recipientsFor({
    required String tenantId,
    required String siteId,
  }) {
    final String normalizedTenantId = tenantId.trim();
    final String normalizedSiteId = siteId.trim();
    if (normalizedTenantId.isEmpty || normalizedSiteId.isEmpty) {
      return const <AlertRecipient>[];
    }
    return _recipients
        .where(
          (AlertRecipient recipient) =>
              recipient.tenantId == normalizedTenantId &&
              recipient.siteId == normalizedSiteId,
        )
        .toList(growable: false);
  }
}

String maskWhatsAppPhone(String phone) {
  final String digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 4) {
    return '********';
  }
  return '********${digits.substring(digits.length - 4)}';
}
