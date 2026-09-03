import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/device_template_repository.dart';
import '../models/device_template.dart';
import '../models/device_template_record.dart';

/// Process-wide, in-memory cache of remote (Firestore) templates — the
/// "remote" half of Etapa 6A's `remote válido -> remote / remote
/// ausente|inválido -> local` resolution. `DeviceTemplateResolver.
/// templateForId` (`lib/ui_templates/catalog/device_template_resolver.dart`)
/// consults [resolve] first and falls back to the local catalog
/// (`getTemplateById`) when it returns `null` — including before [start] is
/// ever called, so the app behaves exactly as it does today until this
/// registry is explicitly warmed up and Firestore actually has data.
///
/// Exactly one `deviceTemplates` collection listener exists for the whole
/// app for the lifetime of [start]/[stop] — never one per template, never
/// one per card/row. `resolve` is a synchronous map lookup so every
/// existing call site (`main.dart`, `comparison_page.dart`, all synchronous,
/// called per card on every rebuild) stays unchanged.
class DeviceTemplateRegistry {
  DeviceTemplateRegistry._();

  static final DeviceTemplateRegistry instance = DeviceTemplateRegistry._();

  Map<String, DeviceTemplate> _remoteById = const <String, DeviceTemplate>{};
  StreamSubscription<List<DeviceTemplateRecord>>? _subscription;

  /// Idempotent: a repeated `start()` (e.g. logout -> login re-mounting the
  /// authenticated shell) cancels any previous subscription first rather
  /// than stacking listeners.
  void start({DeviceTemplateRepository? repository}) {
    _subscription?.cancel();
    _subscription = (repository ?? const DeviceTemplateRepository())
        .watchTemplates()
        .listen(_applySnapshot, onError: _handleStreamError);
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Test-only convenience: `stop()` plus clearing the cache, so tests in
  /// the same file never leak state into each other via the shared
  /// singleton.
  @visibleForTesting
  void reset() {
    stop();
    _remoteById = const <String, DeviceTemplate>{};
  }

  DeviceTemplate? resolve(String templateId) => _remoteById[templateId];

  void _applySnapshot(List<DeviceTemplateRecord> records) {
    final Map<String, DeviceTemplate> next = <String, DeviceTemplate>{
      for (final DeviceTemplateRecord record in records)
        if (record.enabled) record.template.id: record.template,
    };
    _logChanges(previous: _remoteById, next: next, records: records);
    _remoteById = next;
  }

  void _handleStreamError(Object error, StackTrace stackTrace) {
    debugPrint(
      '[TEMPLATE_REGISTRY] Firestore templates stream failed: $error '
      '-> keeping last valid remote cache (${_remoteById.length}) '
      'and using local fallback for missing ids',
    );
  }

  /// Logs only what actually changed relative to the previous cache state —
  /// not the whole map on every snapshot — per Etapa 6A §25 ("no hacer spam
  /// por frame").
  void _logChanges({
    required Map<String, DeviceTemplate> previous,
    required Map<String, DeviceTemplate> next,
    required List<DeviceTemplateRecord> records,
  }) {
    final Set<String> idsInSnapshot = <String>{};
    for (final DeviceTemplateRecord record in records) {
      final String id = record.template.id;
      idsInSnapshot.add(id);
      if (!record.enabled) {
        if (previous.containsKey(id)) {
          debugPrint(
            '[TEMPLATE_REGISTRY] disabled remote template $id -> local fallback',
          );
        }
        continue;
      }
      final bool isNewOrChanged =
          !previous.containsKey(id) ||
          previous[id]!.toMap().toString() !=
              record.template.toMap().toString();
      if (isNewOrChanged) {
        debugPrint(
          '[TEMPLATE_REGISTRY] loaded remote template $id '
          'v${record.templateVersion}',
        );
      }
    }
    // Only ids that dropped out of the snapshot entirely (deleted doc, or
    // it failed to parse and DeviceTemplateRepository already discarded it)
    // — not ids we already logged above as explicitly disabled.
    for (final String id in previous.keys) {
      if (!next.containsKey(id) && !idsInSnapshot.contains(id)) {
        debugPrint(
          '[TEMPLATE_REGISTRY] remote template $id no longer available -> local fallback',
        );
      }
    }
  }
}
