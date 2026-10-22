import 'dart:convert';
import 'dart:io';

import 'logic.dart';

// Exchange rates, all free and keyless, tried in order (#v39):
//
//  1. Coinbase — LIVE rates that move minute to minute, so the 10-minute
//     refresh actually brings new numbers. (open.er-api.com, the only source
//     before, publishes once a day: polling it more often changes nothing.)
//  2. fawazahmed0/currency-api on jsDelivr, then its Cloudflare mirror —
//     daily rates, and the one source here with HISTORY by date, which is
//     what prices a back-dated entry at its own day's rate.
//  3. open.er-api.com — the old source, kept as the last fallback.
//
// Every source is parsed to per-USD rates over ISO currencies only (see
// Fx.iso); null on any failure so the caller keeps its cache.

Future<Object?> _getJson(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 8));
    final resp = await req.close().timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) return null;
    final body = await resp.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
    return jsonDecode(body);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Today's rates, live where possible. Null when every source failed.
Future<Map<String, double>?> fetchFxRates() async {
  final sources = <(String, Map<String, double>? Function(Object?))>[
    ('https://api.coinbase.com/v2/exchange-rates?currency=USD', Fx.parseCoinbase),
    ('https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json', Fx.parseCurrencyApi),
    ('https://latest.currency-api.pages.dev/v1/currencies/usd.min.json', Fx.parseCurrencyApi),
    ('https://open.er-api.com/v6/latest/USD', Fx.parseErApi),
  ];
  for (final (url, parse) in sources) {
    final rates = parse(await _getJson(url));
    if (rates != null) return rates;
  }
  return null;
}

/// The rates of one past [day] (UTC date of that calendar day), or null.
Future<Map<String, double>?> fetchFxRatesOn(DateTime day) async {
  final d = '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
  for (final url in [
    'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@$d/v1/currencies/usd.min.json',
    'https://$d.currency-api.pages.dev/v1/currencies/usd.min.json',
  ]) {
    final rates = Fx.parseCurrencyApi(await _getJson(url));
    if (rates != null) return rates;
  }
  return null;
}
