import 'dart:io';

class NetworkUtils {
  static Future<String> getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLinkLocal: false);
      for (var interface in interfaces) {
        // Typically, Wi-Fi interfaces start with wlan, en, or eth
        if (interface.name.startsWith('wlan') ||
            interface.name.startsWith('en') ||
            interface.name.startsWith('eth')) {
          for (var address in interface.addresses) {
            if (!address.isLoopback && address.type == InternetAddressType.IPv4) {
              return address.address;
            }
          }
        }
      }

      // Fallback: Return any non-loopback IPv4 address
      for (var interface in interfaces) {
        for (var address in interface.addresses) {
          if (!address.isLoopback && address.type == InternetAddressType.IPv4) {
            return address.address;
          }
        }
      }
    } catch (e) {
      print('Error getting local IP: $e');
    }
    return '127.0.0.1'; // Fallback to localhost if all else fails
  }
}
