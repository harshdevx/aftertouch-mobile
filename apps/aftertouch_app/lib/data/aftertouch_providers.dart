import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soundtouch_client/soundtouch_client.dart';

const _kBaseUrlPref = 'aftertouch_base_url';

/// The configured AfterTouch base URL (`http://host:8000`), or null.
/// Persisted with `shared_preferences`.
final afterTouchBaseUrlProvider =
    NotifierProvider<AfterTouchBaseUrl, String?>(AfterTouchBaseUrl.new);

class AfterTouchBaseUrl extends Notifier<String?> {
  @override
  String? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kBaseUrlPref);
    if (v != null && v.trim().isNotEmpty) state = v.trim();
  }

  Future<void> set(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    final clean = url?.trim();
    if (clean == null || clean.isEmpty) {
      await prefs.remove(_kBaseUrlPref);
      state = null;
    } else {
      await prefs.setString(_kBaseUrlPref, clean);
      state = clean;
    }
  }
}

/// An [AfterTouchClient] when a base URL is configured, else null. The catalog
/// features hide themselves when this is null.
final afterTouchClientProvider = Provider<AfterTouchClient?>((ref) {
  final base = ref.watch(afterTouchBaseUrlProvider);
  if (base == null || base.isEmpty) return null;
  final client = AfterTouchClient(baseUrl: base);
  ref.onDispose(client.close);
  return client;
});
