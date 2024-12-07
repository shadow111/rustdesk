import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/utils/app_logger.dart';
import 'package:flutter_hbb/utils/license_service.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

class LicenseController extends GetxController {
  static LicenseController get to => Get.find();
  var isCheckingActivation = true.obs;
  RxBool isLicenseValid = false.obs;
  final storage = GetStorage();
  String? deviceId;
  String? storedLicenseKey;
  DateTime? activationDate;
  DateTime? expirationDate;

  var errorMessage = ''.obs;

  @override
  void onInit()  {
    super.onInit();
    AppLogger().log('LicenseController onInit');
    // _empty_storage();
    _initDeviceId();
  }


  Future<void> _initDeviceId() async {
    AppLogger().log('Initializing device ID');
    _getDeviceId().then((value) async {
      deviceId = value;
      AppLogger().log('Device ID obtained: $deviceId');
      await checkLicense();
    });
    
    
  }

  Future<String?> _getDeviceId() async {
    AppLogger().log('Start getting device Id');
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    String? id;
    if (GetPlatform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      id = androidInfo.id.hashCode.toString();
    } else if (GetPlatform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      id = iosInfo.identifierForVendor.hashCode.toString();
    } else if (GetPlatform.isLinux) {
      LinuxDeviceInfo linuxInfo = await deviceInfo.linuxInfo;

      id = linuxInfo.machineId ?? linuxInfo.id;
    } else if (GetPlatform.isWindows) {
      AppLogger().log('Platform isWindows');
      try {
        // request windows build number to fix overflow on win7
        windowsBuildNumber = getWindowsTargetBuildNumber();
        WindowsDeviceInfo winInfo = await deviceInfo.windowsInfo;
        id = winInfo.deviceId;
      } catch (e) {
        AppLogger().log('Error getting deviceId for Windows $e');
        id = "unknown";
      }
    } else if (GetPlatform.isMacOS) {
      MacOsDeviceInfo macOsInfo = await deviceInfo.macOsInfo;
      id = macOsInfo.systemGUID ?? '';
    }
    return id;
  }

  void _empty_storage() {
    AppLogger().log('Start Emtying local storage');
    storage.remove('licenseKey');
    storage.remove('activationDate');
    storage.remove('expirationDate');
    storage.remove('deviceId');
  }

  Future<void> checkLicense() async {
    AppLogger().log('Starting license check');
    isCheckingActivation.value = true;
    storedLicenseKey = storage.read('licenseKey');
    activationDate = storage.read('activationDate') != null
        ? DateTime.parse(storage.read('activationDate'))
        : null;
    expirationDate = storage.read('expirationDate') != null
        ? DateTime.parse(storage.read('expirationDate'))
        : null;
    if (storedLicenseKey == null ||
        activationDate == null ||
        expirationDate == null) {
      isLicenseValid.value = false;
    } else {
      try {
        // Attempt to validate license with the backend
        LicenseResponse response = await LicenseService.checkLicense(
          licenseKey: storedLicenseKey!,
          deviceId: deviceId!,
        );
        if (response.isValid) {
          // Update local cache with activation and expiration dates
          activationDate = response.activationDate;
          expirationDate = response.expirationDate;
          storage.write('activationDate', activationDate!.toIso8601String());
          storage.write('expirationDate', expirationDate!.toIso8601String());
          isLicenseValid.value = true;
          errorMessage.value = '';
        } else {
          isLicenseValid.value = false;
          errorMessage.value = 'Invalid license key.';
        }
        AppLogger().log('License is checked');
      } on NetworkException {
        // Network issue: perform local validation
        // AppLogger().log("Network issue detected, performing local validation.");
        AppLogger().log('Network issue detected, performing local validation');
        bool isValid = _validateLocally();
        isLicenseValid.value = isValid;
        if (!isValid) {
          errorMessage.value =
              'Cannot verify license online and local license is invalid.';
        } else {
          errorMessage.value = 'Running in offline mode with cached license.';
        }
      } catch (e) {
        AppLogger().log('Error during license check: $e');
        isLicenseValid.value = false;
        errorMessage.value = 'An unexpected error occurred.';
      }
    }
    isCheckingActivation.value = false;
    /*} catch (e) {
      isLicenseValid.value = false;
      errorMessage.value = 'An unexpected error occurred during license check.';
    } finally {
      isCheckingActivation.value = false;
    }*/
  }

  bool _validateLocally() {
    // AppLogger().log("LicenseController::_validateLocally called");
    if (activationDate == null || expirationDate == null) {
      // AppLogger().log("Local validation failed: Missing activation or expiration dates.");
      return false;
    }

    // Check if the device ID matches
    String? localDeviceId = storage.read('deviceId');
    // AppLogger().log("$localDeviceId , $deviceId");
    if (localDeviceId != deviceId) {
      // AppLogger().log("Local validation failed: Device ID does not match.");
      return false;
    }

    // Check if the current date is within the valid period
    DateTime now = DateTime.now();
    if (now.isAfter(expirationDate!)) {
      //AppLogger().log("Local validation failed: License has expired.");
      return false;
    }

    if (now.isBefore(activationDate!)) {
      //AppLogger().log("Local validation failed: License not yet active.");
      return false;
    }

    return true;
  }
}
