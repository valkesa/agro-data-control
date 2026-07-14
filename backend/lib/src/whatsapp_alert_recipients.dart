enum AlertRecipientScope { global, tenantSite }

class AlertRecipient {
  const AlertRecipient({
    required this.scope,
    required this.contactName,
    required this.phone,
    this.tenantId,
    this.siteId,
    this.clientName,
    this.siteName,
  });

  final AlertRecipientScope scope;
  final String? tenantId;
  final String? siteId;
  final String? clientName;
  final String? siteName;
  final String contactName;
  final String phone;

  bool get isConfigured {
    if (!_isConfiguredValue(contactName) ||
        !_isConfiguredValue(phone) ||
        normalizedPhone.length < 8) {
      return false;
    }
    return switch (scope) {
      AlertRecipientScope.global => true,
      AlertRecipientScope.tenantSite =>
        _isConfiguredValue(tenantId) &&
            _isConfiguredValue(siteId) &&
            _isConfiguredValue(clientName) &&
            _isConfiguredValue(siteName),
    };
  }

  String get normalizedPhone => normalizeWhatsAppPhone(phone);

  String get displayClientName {
    if (scope == AlertRecipientScope.global) {
      return 'Valke';
    }
    return clientName?.trim().isNotEmpty == true ? clientName!.trim() : '';
  }

  String get displaySiteName {
    if (scope == AlertRecipientScope.global) {
      return 'Todos los sitios';
    }
    return siteName?.trim().isNotEmpty == true ? siteName!.trim() : '';
  }
}

class WhatsAppAlertRecipientsConfig {
  const WhatsAppAlertRecipientsConfig();

  static const List<AlertRecipient> _recipients = <AlertRecipient>[
    // ===== Destinatarios globales =====
    AlertRecipient(
      scope: AlertRecipientScope.global,
      contactName: 'Gerardo',
      phone: '5491138267368',
    ),
    AlertRecipient(
      scope: AlertRecipientScope.global,
      contactName: 'Demián',
      phone: '5491130740079',
    ),

    // ===== Cliente especifico =====
    AlertRecipient(
      scope: AlertRecipientScope.tenantSite,
      tenantId: 'the_good_pig',
      siteId: 'main_site',
      clientName: 'The Good Pig',
      siteName: 'Sitio principal',
      contactName: 'Gerardo',
      phone: '5491138267368',
    ),
    AlertRecipient(
      scope: AlertRecipientScope.tenantSite,
      tenantId: 'the_good_pig',
      siteId: 'main_site',
      clientName: 'The Good Pig',
      siteName: 'Sitio principal',
      contactName: 'Cliente',
      phone: '54911YYYYYYYY',
    ),
    AlertRecipient(
      scope: AlertRecipientScope.tenantSite,
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
    return deduplicateAlertRecipients(<AlertRecipient>[
      ...globalRecipients(),
      ...siteRecipientsFor(tenantId: tenantId, siteId: siteId),
    ]);
  }

  List<AlertRecipient> globalRecipients() {
    return List<AlertRecipient>.unmodifiable(
      _recipients.where(
        (AlertRecipient recipient) =>
            recipient.scope == AlertRecipientScope.global &&
            recipient.isConfigured,
      ),
    );
  }

  List<AlertRecipient> siteRecipientsFor({
    required String tenantId,
    required String siteId,
  }) {
    final String normalizedTenantId = tenantId.trim();
    final String normalizedSiteId = siteId.trim();
    if (normalizedTenantId.isEmpty || normalizedSiteId.isEmpty) {
      return const <AlertRecipient>[];
    }
    return List<AlertRecipient>.unmodifiable(
      _recipients.where(
        (AlertRecipient recipient) =>
            recipient.isConfigured &&
            recipient.scope == AlertRecipientScope.tenantSite &&
            recipient.tenantId == normalizedTenantId &&
            recipient.siteId == normalizedSiteId,
      ),
    );
  }
}

Map<String, Object?> buildWhatsAppAlertRecipientsResponse({
  required WhatsAppAlertRecipientsConfig recipientsConfig,
  required Map<String, Object?> runtimeControl,
  required String? role,
  required String? userTenantId,
  required String? queryTenantId,
  required String? querySiteId,
}) {
  final String normalizedRole = role?.trim() ?? '';
  final bool isOwner = normalizedRole == 'owner';
  final String tenantId = isOwner
      ? _firstConfiguredValue(<String?>[queryTenantId, userTenantId])
      : _firstConfiguredValue(<String?>[userTenantId]);
  final String siteId = querySiteId?.trim() ?? '';
  final List<AlertRecipient> globalRecipients = recipientsConfig
      .globalRecipients();
  final List<AlertRecipient> siteRecipients =
      tenantId.isNotEmpty && siteId.isNotEmpty
      ? recipientsConfig.siteRecipientsFor(tenantId: tenantId, siteId: siteId)
      : const <AlertRecipient>[];
  final List<AlertRecipient> recipients = deduplicateAlertRecipients(
    <AlertRecipient>[...globalRecipients, ...siteRecipients],
  );

  return <String, Object?>{
    'ok': true,
    'enabled': recipients.isNotEmpty,
    'recipientCount': recipients.length,
    'runtimeControl': runtimeControl,
    'globalRecipients': globalRecipients
        .map(alertRecipientToPublicJson)
        .toList(growable: false),
    'siteRecipients': siteRecipients
        .map(alertRecipientToPublicJson)
        .toList(growable: false),
    'recipients': recipients
        .map(alertRecipientToPublicJson)
        .toList(growable: false),
  };
}

Map<String, Object?> alertRecipientToPublicJson(AlertRecipient recipient) {
  return <String, Object?>{
    'clientName': recipient.displayClientName,
    'siteName': recipient.displaySiteName,
    'contactName': recipient.contactName,
    'phoneMasked': maskWhatsAppPhone(recipient.phone),
  };
}

List<AlertRecipient> deduplicateAlertRecipients(
  Iterable<AlertRecipient> recipients,
) {
  final Set<String> seenPhones = <String>{};
  final List<AlertRecipient> deduplicated = <AlertRecipient>[];
  for (final AlertRecipient recipient in recipients) {
    final String normalizedPhone = recipient.normalizedPhone;
    if (normalizedPhone.isEmpty || !seenPhones.add(normalizedPhone)) {
      continue;
    }
    deduplicated.add(recipient);
  }
  return List<AlertRecipient>.unmodifiable(deduplicated);
}

String normalizeWhatsAppPhone(String phone) {
  return phone.replaceAll(RegExp(r'\D'), '');
}

String maskWhatsAppPhone(String phone) {
  final String digits = normalizeWhatsAppPhone(phone);
  if (digits.length == 13 &&
      digits.startsWith('549') &&
      digits.substring(3, 5) == '11') {
    return '+54 9 11 **** ${digits.substring(digits.length - 4)}';
  }
  if (digits.length < 4) {
    return '********';
  }
  if (digits.length <= 8) {
    return '********${digits.substring(digits.length - 4)}';
  }
  return '********${digits.substring(digits.length - 4)}';
}

bool _isConfiguredValue(String? value) {
  final String normalized = value?.trim().toUpperCase() ?? '';
  if (normalized.isEmpty) {
    return false;
  }
  return !normalized.contains('PENDING') &&
      !normalized.contains('SIN_CONFIGURAR') &&
      !normalized.contains('TODO') &&
      !normalized.contains('PLACEHOLDER');
}

String _firstConfiguredValue(Iterable<String?> values) {
  for (final String? value in values) {
    final String normalized = value?.trim() ?? '';
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }
  return '';
}
