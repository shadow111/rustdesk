import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_hbb/common.dart';
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
  void onInit() {
    super.onInit();
    // _empty_storage();
    // checkLicense();
    _initDeviceId();
  }

  void _initDeviceId() async {
    deviceId = await _getDeviceId();
    checkLicenseLocally();
  }

  Future<String?> _getDeviceId() async {
    /*DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    String? id;
    if (GetPlatform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      id = androidInfo.id.hashCode.toString();
    } else if (GetPlatform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      id = iosInfo.identifierForVendor.hashCode.toString();
    } else if (isLinux) {
      LinuxDeviceInfo linuxInfo = await deviceInfo.linuxInfo;

      id = linuxInfo.machineId ?? linuxInfo.id;
    } else if (isWindows) {
      try {
        // request windows build number to fix overflow on win7
        windowsBuildNumber = getWindowsTargetBuildNumber();
        WindowsDeviceInfo winInfo = await deviceInfo.windowsInfo;
        id = winInfo.deviceId;
      } catch (e) {
        id = "unknown";
      }
    } else if (isMacOS) {
      MacOsDeviceInfo macOsInfo = await deviceInfo.macOsInfo;
      id = macOsInfo.systemGUID ?? '';
    }*/
    return "temp_device_id";
  }

  void _empty_storage() {
    storage.remove('licenseKey');
    storage.remove('activationDate');
    storage.remove('expirationDate');
    storage.remove('deviceId');
  }

  void checkLicense() async {
    // print("LicenseController::checkLicense");
    //try {
    // Start checking
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
      // print("checkLicense can't find storedLicenseKey");
      isLicenseValid.value = false;
    } else {
      /*print("checkLicense find ${storedLicenseKey}");
        // Validate the license with the server
        bool isValid = await LicenseService.checkLicense(
          licenseKey: storedLicenseKey!,
          deviceId: deviceId!,
        );
        isLicenseValid.value = isValid;*/
      try {
        // Attempt to validate license with the backend
        LicenseResponse response = await LicenseService.checkLicense(
          licenseKey: storedLicenseKey!,
          deviceId: deviceId!,
        );
        // print("LicenseController::checkLicense");
        // print(response.isValid);
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
      } on NetworkException {
        // Network issue: perform local validation
        // print("Network issue detected, performing local validation.");
        bool isValid = _validateLocally();
        isLicenseValid.value = isValid;
        if (!isValid) {
          errorMessage.value =
              'Cannot verify license online and local license is invalid.';
        } else {
          errorMessage.value = 'Running in offline mode with cached license.';
        }
      } catch (e) {
        // print("LicenseController::checkLicense Exception");
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

  void checkLicenseLocally() async {
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
      // try {
      // Attempt to validate license with the backend
      LicenseResponse response = await LicenseService.checkLicenseLocally(
        licenseKey: storedLicenseKey!,
        deviceId: deviceId!,
      );
      // if (response.isValid) {
      // Update local cache with activation and expiration dates
      activationDate = response.activationDate;
      expirationDate = response.expirationDate;
      storage.write('activationDate', activationDate!.toIso8601String());
      storage.write('expirationDate', expirationDate!.toIso8601String());
      bool isValid = _validateLocally();
      isLicenseValid.value = isValid;
      if (!isValid) {
        errorMessage.value =
            'Cannot verify license online and local license is invalid.';
      } else {
        errorMessage.value = '';
      }
    }
    isCheckingActivation.value = false;
  }

  bool _validateLocally() {
    // print("LicenseController::_validateLocally called");
    if (activationDate == null || expirationDate == null) {
      // print("Local validation failed: Missing activation or expiration dates.");
      return false;
    }

    // Check if the device ID matches
    String? localDeviceId = storage.read('deviceId');
    // print("$localDeviceId , $deviceId");
    if (localDeviceId != deviceId) {
      // print("Local validation failed: Device ID does not match.");
      return false;
    }

    // Check if the current date is within the valid period
    DateTime now = DateTime.now();
    if (now.isAfter(expirationDate!)) {
      //print("Local validation failed: License has expired.");
      return false;
    }

    if (now.isBefore(activationDate!)) {
      //print("Local validation failed: License not yet active.");
      return false;
    }

    return true;
  }
}
