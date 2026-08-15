import 'package:ntp/ntp.dart';

/// Anti-abuse time source: fetches the current time from an NTP server so
/// daily/weekly/monthly resets can't be gamed by changing the device clock.
/// Falls back to the device clock if the network/NTP lookup fails (offline,
/// timeout, DNS error, etc.) so callers always get a usable DateTime.
Future<DateTime> getNetworkTime() async {
  try {
    return await NTP.now();
  } catch (_) {
    return DateTime.now();
  }
}
