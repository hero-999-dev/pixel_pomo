import 'dart:convert';
import 'dart:io';

/// Fetches USD-based exchange rates from open.er-api.com (free, no API key,
/// 160+ currencies incl. TRY; upstream updates ~daily). Returns a currency→
/// per-USD-rate map, or null on any failure (offline, timeout, bad payload) so
/// the caller silently keeps its cache. Uses dart:io directly — no new dep.
Future<Map<String, double>?> fetchFxRates() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client
        .getUrl(Uri.parse('https://open.er-api.com/v6/latest/USD'))
        .timeout(const Duration(seconds: 8));
    final resp = await req.close().timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return null;
    final body = await resp
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 8));
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (json['result'] != 'success') return null;
    final raw = json['rates'] as Map<String, dynamic>;
    final out = <String, double>{};
    raw.forEach((k, v) {
      final d = (v is num) ? v.toDouble() : double.tryParse('$v');
      if (d != null && d > 0) out[k] = d;
    });
    return out.isEmpty ? null : out;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
