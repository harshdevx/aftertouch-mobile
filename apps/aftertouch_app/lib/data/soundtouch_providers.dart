import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soundtouch_client/soundtouch_client.dart';

/// One [SoundTouchClient] per speaker host, reused across screens.
///
/// Keyed by `"host"` or `"host:port"`. The client owns an HTTP connection and
/// (lazily) the `gabbo` WebSocket; it is disposed when no longer watched.
final soundTouchClientProvider =
    Provider.family<SoundTouchClient, String>((ref, key) {
  final parts = key.split(':');
  final host = parts.first;
  final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 8090 : 8090;
  final client = SoundTouchClient(host: host, httpPort: port);
  ref.onDispose(client.dispose);
  return client;
});
