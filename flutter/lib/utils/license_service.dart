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
import 'package:flutter_hbb/utils/app_logger.dart';
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
    AppLogger().log('Sending validateLicense request');
    try {
      final response = await http.post(
        Uri.parse('$apiUrl/validate_license'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'licenseKey': licenseKey,
          'deviceId': deviceId,
        }),
      );

      AppLogger().log('Received response: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // return data['isValid'] == true;
        return LicenseResponse.fromJson(data);
      } else {
        return LicenseResponse(isValid: false);
        // throw Exception('Failed to validate license');
      }
    } on SocketException {
      AppLogger().log('Network error occurred');
      throw NetworkException('Network error occurred');
    } catch (e) {
      AppLogger().log('Error in validateLicense: $e');
      throw Exception('Failed to validate license');
    }
  }

  static Future<LicenseResponse> checkLicense({
    required String licenseKey,
    required String deviceId,
  }) async {
    AppLogger().log('Sending checkLicense request');
    try {
      final response = await http.post(
        Uri.parse('$apiUrl/check_license'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'licenseKey': licenseKey,
          'deviceId': deviceId,
        }),
      );

      AppLogger().log('Received response: ${response.body}');

      // AppLogger().log(response.statusCode);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // AppLogger().log("checkLicense:: $data");
        return LicenseResponse.fromJson(data);
      } else {
        return LicenseResponse(isValid: false);
      }
    } on SocketException {
      AppLogger().log('Network error occurred');
      throw NetworkException('Network error occurred');
    } catch (e) {
      AppLogger().log('Error in checkLicense: $e');
      throw Exception('Failed to check license');
    }
  }
}
