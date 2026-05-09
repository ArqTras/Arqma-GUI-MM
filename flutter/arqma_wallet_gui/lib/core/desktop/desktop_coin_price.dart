import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Parity with `wallet_relay_ops::get_coin_and_conversion` (Coinpaprika + TradeOgre + BTC/USD).
Future<void> fetchCoinPriceAndConversion(void Function(Map<String, dynamic> payload) emit) async {
  double coin = 0;
  try {
    final HttpClient c = HttpClient();
    try {
      final HttpClientRequest req =
          await c.getUrl(Uri.parse('https://api.coinpaprika.com/v1/tickers/arq-arqma'));
      final HttpClientResponse resp = await req.close();
      if (resp.statusCode == 200) {
        final Object? v = jsonDecode(await utf8.decoder.bind(resp).join());
        if (v is Map) {
          final Object? p = v['quotes'];
          if (p is Map && p['USD'] is Map) {
            final Object? price = (p['USD'] as Map)['price'];
            if (price is num) {
              coin = price.toDouble();
            }
          }
        }
      }
    } finally {
      c.close(force: true);
    }
  } catch (e) {
    debugPrint('[coin_price] coinpaprika: $e');
  }

  double sats = 0;
  double usd15m = 0;
  try {
    final HttpClient c = HttpClient();
    try {
      final HttpClientRequest req =
          await c.getUrl(Uri.parse('https://tradeogre.com/api/v1/ticker/BTC-ARQ'));
      final HttpClientResponse resp = await req.close();
      if (resp.statusCode == 200) {
        final Object? v = jsonDecode(await utf8.decoder.bind(resp).join());
        if (v is Map && v['price'] != null) {
          sats = double.tryParse('${v['price']}') ?? 0;
        }
      }
    } finally {
      c.close(force: true);
    }
  } catch (e) {
    debugPrint('[coin_price] tradeogre: $e');
  }

  try {
    final HttpClient c = HttpClient();
    try {
      final HttpClientRequest req = await c.getUrl(Uri.parse('https://blockchain.info/ticker'));
      final HttpClientResponse resp = await req.close();
      if (resp.statusCode == 200) {
        final Object? v = jsonDecode(await utf8.decoder.bind(resp).join());
        if (v is Map && v['USD'] is Map) {
          final Object? u = (v['USD'] as Map)['15m'];
          if (u is num) {
            usd15m = u.toDouble();
          }
        }
      }
    } finally {
      c.close(force: true);
    }
  } catch (e) {
    debugPrint('[coin_price] blockchain: $e');
  }

  emit(<String, dynamic>{'event': 'set_coin_price', 'data': coin});
  emit(<String, dynamic>{
    'event': 'set_conversion_data',
    'data': <String, dynamic>{'sats': sats, 'currentPrice': usd15m},
  });
}
