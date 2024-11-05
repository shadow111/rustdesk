import 'package:flutter_hbb/desktop/controller/license_controller.dart';
import 'package:flutter_hbb/utils/app_logger.dart';
import 'package:flutter_hbb/utils/license_service.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

class LicenseValidationController extends GetxController {
  // Observable variables
  var licenseKey = ''.obs;
  var isLoading = false.obs;
  var errorMessage = ''.obs;
  final storage = GetStorage();

  // Method to validate the license
  void validateLicense() async {
    SimpleLogger.log('Validating license key: ${licenseKey.value.trim()}');
    if (licenseKey.value.trim().isEmpty) {
      errorMessage.value = 'Please enter your license key.';
      return;
    }

    // Start loading
    isLoading.value = true;
    errorMessage.value = '';

    try {
      final licenseController = Get.find<LicenseController>();
      // Perform the license validation (replace with your actual implementation)
      LicenseResponse response = await LicenseService.validateLicense(
        licenseKey: licenseKey.value.trim(),
        deviceId: licenseController.deviceId!,
      );

      /*bool isValid = await LicenseService.validateLicense(
        licenseKey: licenseKey.value.trim(),
        deviceId: licenseController.deviceId!,
      );*/

      if (response.isValid) {
        //print("validateLicense ${licenseKey.value}");
        // Store the license key and dates locally
        storage.write('licenseKey', licenseKey.value.trim());
        storage.write(
            'activationDate', response.activationDate!.toIso8601String());
        storage.write(
            'expirationDate', response.expirationDate!.toIso8601String());
        storage.write('deviceId', licenseController.deviceId!);

        // Update the license state in the LicenseController
        licenseController.isLicenseValid.value = true;
        licenseController.storedLicenseKey = licenseKey.value.trim();
        licenseController.activationDate = response.activationDate;
        licenseController.expirationDate = response.expirationDate;
        licenseController.errorMessage.value = '';

        //licenseController.isLicenseValid.value = true;
        //licenseController.storedLicenseKey = licenseKey.value.trim();
        // Get.find<LicenseController>().isLicenseValid.value = true;
      } else {
        errorMessage.value = 'Invalid license key. Please try again.';
      }
      SimpleLogger.log('License key validated');
    } on NetworkException catch (e) {
      SimpleLogger.log('NetworkException during license validation: $e');
      errorMessage.value = e.message;
    } catch (e) {
      SimpleLogger.log('Error during license validation: $e');
      errorMessage.value = 'An error occurred during validation.';
    } finally {
      isLoading.value = false;
    }
  }
}
