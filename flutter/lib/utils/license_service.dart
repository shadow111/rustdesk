/*class LicenseService {
  static Future<bool> checkLicense({
    required String licenseKey,
    required String deviceId,
  }) async {
    // Simulate network delay
    await Future.delayed(Duration(seconds: 2));
    // Implement your license checking logic here
    // For example, make a network request to validate the license
    // Return true if the license is valid, false otherwise
    if (licenseKey == 'VALID_LICENSE_KEY') {
      return true;
    } else {
      return false;
    }
  }

  static Future<bool> validateLicense({
    required String licenseKey,
    required String deviceId,
  }) async {
    // Simulate network delay
    await Future.delayed(Duration(seconds: 2));

    // Mock validation logic
    if (licenseKey == 'VALID_LICENSE_KEY') {
      return true;
    } else {
      return false;
    }
  }
}
*/

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io';

// Custom exception for network-related issues
class NetworkException implements Exception {
  final String message;
  NetworkException(this.message);
}

class LicenseResponse {
  final bool isValid;
  final DateTime? activationDate;
  final DateTime? expirationDate;
  final String? deviceId;

  LicenseResponse({
    required this.isValid,
    this.activationDate,
    this.expirationDate,
    this.deviceId,
  });

  factory LicenseResponse.fromJson(Map<String, dynamic> json) {
    return LicenseResponse(
      isValid: json['isValid'] == true,
      activationDate: json['activation_date'] != null
          ? DateTime.parse(json['activation_date'])
          : null,
      expirationDate: json['expiration_date'] != null
          ? DateTime.parse(json['expiration_date'])
          : null,
      deviceId: json['deviceId'],
    );
  }
}

class LicenseService {
  static const String apiUrl =
      'https://rustdesk-license-backend-cwfkahgjctbdexdr.canadacentral-01.azurewebsites.net';
  // 'https://rustdesk-license-backend-cwfkahgjctbdexdr.canadacentral-01.azurewebsites.net';

  static Future<LicenseResponse> validateLicense({
    required String licenseKey,
    required String deviceId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$apiUrl/validate_license'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'licenseKey': licenseKey,
          'deviceId': deviceId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // return data['isValid'] == true;
        return LicenseResponse.fromJson(data);
      } else {
        return LicenseResponse(isValid: false);
        // throw Exception('Failed to validate license');
      }
    } on SocketException {
      throw NetworkException('Network error occurred');
    } catch (e) {
      throw Exception('Failed to validate license');
    }
  }

  static Future<LicenseResponse> checkLicense({
    required String licenseKey,
    required String deviceId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$apiUrl/check_license'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'licenseKey': licenseKey,
          'deviceId': deviceId,
        }),
      );

      // print(response.statusCode);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // print("checkLicense:: $data");
        return LicenseResponse.fromJson(data);
      } else {
        return LicenseResponse(isValid: false);
      }
    } on SocketException {
      throw NetworkException('Network error occurred');
    } catch (e) {
      throw Exception('Failed to check license');
    }
  }

}

class LocalLicenseService {
  static Future<LicenseResponse> validateLicenseLocally({
    required String licenseKey,
    required String deviceId,
  }) async {
    if (licenseKey == "cd5b5a88-0dd5-4ab3-9107-03c72325b35e") {
      return LicenseResponse.fromJson({
      'isValid': true,
      'activation_date': '2024-11-03T20:06:13Z',
      'expiration_date': '2025-11-03T20:06:13Z',
      'deviceId': deviceId
    });
    } else {
      return LicenseResponse.fromJson({
      'isValid': false,
      //'activation_date': '2024-11-03T20:06:13Z',
      //'expiration_date': '2025-11-03T20:06:13Z',
      //'deviceId': deviceId
    });
    }
  }

  static Future<LicenseResponse> checkLicenseLocally({
    required String licenseKey,
    required String deviceId,
  }) async {
    return LicenseResponse.fromJson({
      'isValid': true,
      'activation_date': '2024-11-03T20:06:13Z',
      'expiration_date': '2025-11-03T20:06:13Z',
      'deviceId': deviceId
    });
  }
}
