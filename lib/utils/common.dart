import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image_lib;
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';
import '../utils/enums.dart';
import '../models/model_setting.dart';
import '../services/service_logger.dart';
import '../storage/storage_secure.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as path_lib;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

final String testEmailId = "fife@jeerovan.com";

bool canUseVideoPlayer =
    Platform.isAndroid || Platform.isIOS || Platform.isMacOS || kIsWeb;

bool isDebugEnabled = kDebugMode;

bool simulateTesting() {
  return ModelSetting.get(AppString.simulateTesting.string,
          defaultValue: "no") ==
      "yes";
}

bool revenueCatSupported =
    Platform.isIOS || Platform.isAndroid; // TODO || Platform.isMacOS

bool runningOnMobile = Platform.isAndroid || Platform.isIOS;

final List<Color> predefinedColors = [
  "#06b6d4",
  "#0ea5e9",
  "#3b82f6",
  "#6366f1",
  "#8b5cf6",
  "#ec4899",
  "#14b8a6",
  "#22c55e",
  "#84cc16",
  "#eab308",
  "#f97316",
  "#ef4444",
  "#ffffff",
  "#e5e7eb",
  "#9ca3af",
  "#4b5563",
  "#1f2937",
  "#000000"
].map((colorText) {
  return colorFromHex(colorText);
}).toList();

int getRandomInt(int range) {
  return Random().nextInt(range);
}

dynamic getValueFromMap(Map<String, dynamic> map, String key,
    {dynamic defaultValue}) {
  dynamic value;
  if (map.containsKey(key)) {
    if (map[key] == null) {
      value = defaultValue;
    } else {
      value = map[key];
    }
  } else {
    value = defaultValue;
  }
  return value;
}

/* input validations -- starts */
String? validateString(String? value) {
  if (value == null || value.isEmpty) {
    return 'Please enter data';
  }
  return null;
}

String? validateNumber(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  if (value.isNotEmpty && int.tryParse(value) == null) {
    return 'A number';
  }
  return null;
}

String? validateNonEmptyNumber(String? value) {
  if (value == null || value.isEmpty) {
    return 'Enter data';
  }
  if (value.isNotEmpty && int.tryParse(value) == null) {
    return 'A number';
  }
  return null;
}

String? validateDecimal(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  // Regular expression to match decimals and whole numbers
  RegExp regExp = RegExp(r'^\d*\.?\d+$');
  if (!regExp.hasMatch(value)) {
    return 'Please enter valid data';
  }
  return null;
}

String? validateSelection(String? value) {
  if (value == null || value.isEmpty) {
    return 'Please select an option';
  }
  return null;
}
/* input validations -- ends */

String capitalize(String text) {
  if (text.isEmpty) return "";
  return text[0].toUpperCase() + text.substring(1).toLowerCase();
}

Future<void> openURL(String link) async {
  final logger = AppLogger(prefixes: ["common", "openURL"]);
  try {
    await launchUrlString(link);
  } catch (e, s) {
    logger.error("Exception", error: e, stackTrace: s);
  }
}

void openMedia(String filePath) async {
  final logger = AppLogger(prefixes: ["common", "openMedia"]);
  try {
    OpenFilex.open(filePath);
  } catch (e, s) {
    logger.error("Exeption", error: e, stackTrace: s);
  }
}

void showAlertMessage(BuildContext context, String title, String message) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            child: const Text('OK'),
            onPressed: () {
              Navigator.of(context).pop(); // Dismiss the dialog
            },
          ),
        ],
      );
    },
  );
}

void showProcessingDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
        child: const Padding(
          padding: EdgeInsets.all(24.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text("Processing...", style: TextStyle(fontSize: 18)),
            ],
          ),
        ),
      );
    },
  );
}

/* date/time conversions -- starts */
String nowUtcInISO() {
  DateTime nowUtc = DateTime.now().toUtc();
  String formattedTimestamp = nowUtc.toIso8601String();

  // Adjusting format to match "YYYY-MM-DD HH:MM:SS.ssssss+00"
  formattedTimestamp = formattedTimestamp
      .replaceFirst("T", " ") // Replace 'T' with space
      .replaceFirst("Z", "+00"); // Replace 'Z' with '+00'

  return formattedTimestamp;
}

String stringFromIntDate(int date) {
  String input = date.toString();
  DateTime dateTime = dateFromStringDate(input);
  // Format the DateTime object to "MMM YY"
  return DateFormat('dd MMM yy').format(dateTime);
}

DateTime dateFromStringDate(String date) {
  // Parse the string to DateTime object
  // Assume the input is always valid and in the format "YYYYMM"
  int year = int.parse(date.substring(0, 4));
  int month = int.parse(date.substring(4, 6));
  int day = int.parse(date.substring(6, 8));
  return DateTime(year, month, day);
}

String stringFromDateRange(DateTimeRange dateRange) {
  String start = DateFormat('dd MMM yy').format(dateRange.start);
  String end = DateFormat('dd MMM yy').format(dateRange.end);
  return '$start - $end';
}

int daysDifference(DateTime date1, DateTime date2) {
  DateTime bigDate = date1.isAfter(date2) ? date1 : date2;
  DateTime smallDate = bigDate == date1 ? date2 : date1;
  Duration difference = bigDate.difference(smallDate);
  return difference.inDays;
}

int dateFromDateTime(DateTime datetime) {
  return int.parse(DateFormat('yyyyMMdd').format(datetime));
}

String getTodayDate() {
  DateTime now = DateTime.now();
  int year = now.year;
  int month = now.month;
  int date = now.day;
  String monthFormatted = month < 10 ? '0$month' : month.toString();
  String dayFormatted = date < 10 ? '0$date' : date.toString();
  return '$year$monthFormatted$dayFormatted';
}

String getDateFromUtcMilliSeconds(int utcMilliSeconds) {
  final DateTime dateTime =
      DateTime.fromMillisecondsSinceEpoch(utcMilliSeconds, isUtc: true);
  int year = dateTime.year;
  int month = dateTime.month;
  int date = dateTime.day;
  String monthFormatted = month < 10 ? '0$month' : month.toString();
  String dayFormatted = date < 10 ? '0$date' : date.toString();
  return '$year$monthFormatted$dayFormatted';
}

String getReadableDate(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));

  if (date.isAfter(today)) {
    return "Today";
  } else if (date.isAfter(yesterday)) {
    return "Yesterday";
  } else if (now.difference(date).inDays < 7) {
    return DateFormat('EEEE')
        .format(date); // Day of the week for the last 7 days
  } else {
    return DateFormat('MMMM d, yyyy')
        .format(date); // Full date for older messages
  }
}

String getFormattedTime(int utcMilliSeconds) {
  final DateTime dateTime =
      DateTime.fromMillisecondsSinceEpoch(utcMilliSeconds, isUtc: true);
  final String formattedTime = DateFormat('hh:mm a')
      .format(dateTime.toLocal()); // Converts to local time and formats
  return formattedTime;
}

String getFormattedDateTime(int utcMilliSeconds) {
  final DateTime dateTime =
      DateTime.fromMillisecondsSinceEpoch(utcMilliSeconds, isUtc: true);
  final String formattedTime = DateFormat('dd MMM yy hh:mm a')
      .format(dateTime.toLocal()); // Converts to local time and formats
  return formattedTime;
}

DateTime getLocalDateFromUtcMilliSeconds(int utcMilliSeconds) {
  final DateTime dateTime =
      DateTime.fromMillisecondsSinceEpoch(utcMilliSeconds, isUtc: true);
  final localDateTime = dateTime.toLocal();
  return DateTime(localDateTime.year, localDateTime.month, localDateTime.day);
}

String mediaFileDurationFromSeconds(int seconds) {
  final int hours = seconds ~/ 3600;
  final int minutes = (seconds % 3600) ~/ 60;
  final int secs = seconds % 60;

  final String hoursStr = hours.toString().padLeft(2, '0');
  final String minutesStr = minutes.toString().padLeft(2, '0');
  final String secondsStr = secs.toString().padLeft(2, '0');

  return hours > 0
      ? "$hoursStr:$minutesStr:$secondsStr"
      : "$minutesStr:$secondsStr";
}

int mediaFileDurationFromString(String duration) {
  final parts = duration.split(':');

  // If the duration includes hours (e.g., hh:mm:ss)
  if (parts.length == 3) {
    final int hours = int.parse(parts[0]);
    final int minutes = int.parse(parts[1]);
    final int seconds = int.parse(parts[2]);
    return hours * 3600 + minutes * 60 + seconds;
  }

  // If the duration only includes minutes and seconds (e.g., mm:ss)
  if (parts.length == 2) {
    final int minutes = int.parse(parts[0]);
    final int seconds = int.parse(parts[1]);
    return minutes * 60 + seconds;
  }

  // Return 0 for invalid format
  return 0;
}

/* date/time conversion -- ends */

Uint8List? getImageThumbnail(Uint8List bytes) {
  int maxSize = 200;
  image_lib.Image? src = image_lib.decodeImage(bytes);
  if (src != null) {
    image_lib.Image resized = image_lib.copyResize(src, width: maxSize);
    return Uint8List.fromList(image_lib.encodePng(resized));
  }
  return null;
}

Map<String, int> getImageDimension(Uint8List bytes) {
  image_lib.Image? src = image_lib.decodeImage(bytes);
  if (src != null) {
    int srcWidth = src.width;
    int srcHeight = src.height;
    return {"width": srcWidth, "height": srcHeight};
  }
  return {"width": 0, "height": 0};
}

String readableFileSizeFromBytes(int bytes, [int decimals = 2]) {
  if (bytes <= 0) return "0 B";
  const suffixes = ["B", "KB", "MB", "GB", "TB"];
  final i = (log(bytes) / log(1024)).floor();
  final size = bytes / pow(1024, i);
  return "${size.toStringAsFixed(decimals)} ${suffixes[i]}";
}

Color getIndexedColor(int count) {
  int predefinedColorsLength = 12;
  int index = count % predefinedColorsLength;
  return predefinedColors[index];
}

Color colorFromHex(String hex) {
  final buffer = StringBuffer();
  if (hex.length == 6 || hex.length == 7) {
    buffer.write('FF'); // Add opacity if not provided
  }
  buffer.write(hex.replaceFirst('#', ''));
  return Color(int.parse(buffer.toString(), radix: 16));
}

String colorToHex(Color color) {
  final red =
      (color.r * 255).toInt().toRadixString(16).padLeft(2, '0').toUpperCase();
  final green =
      (color.g * 255).toInt().toRadixString(16).padLeft(2, '0').toUpperCase();
  final blue =
      (color.b * 255).toInt().toRadixString(16).padLeft(2, '0').toUpperCase();
  final alpha =
      (color.a * 255).toInt().toRadixString(16).padLeft(2, '0').toUpperCase();

  return '$alpha$red$green$blue';
}

Future<String> getDbStoragePath() async {
  String? dbDirPath;
  if (Platform.isMacOS || Platform.isIOS) {
    Directory libDir = await getLibraryDirectory();
    dbDirPath = libDir.path;
  } else if (Platform.isWindows) {
    dbDirPath = Platform.environment['APPDATA'];
  } else if (Platform.isLinux) {
    Directory supportDir = await getApplicationSupportDirectory();
    dbDirPath = supportDir.path;
  }
  if (dbDirPath == null) {
    Directory documentsPath = await getApplicationDocumentsDirectory();
    dbDirPath = documentsPath.path;
  }
  Directory dbDir = Directory(dbDirPath); // Ensure directory exists
  if (!dbDir.existsSync()) {
    await dbDir.create(recursive: true);
  }
  AppLogger(prefixes: ["DbStoragePath"]).info(dbDirPath);
  return dbDirPath;
}

Future<Directory> getAppTempDirectory() async {
  Directory directory = await getApplicationDocumentsDirectory();
  String appTempPath = path_lib.joinAll([directory.path, "FiFe", "Temp"]);
  Directory tempDir = Directory(appTempPath);
  if (!tempDir.existsSync()) {
    await tempDir.create(recursive: true);
  }
  return tempDir;
}

Future<bool> directoryExistAtPath(String path) async {
  Directory dir = Directory(path);
  return await dir.exists();
}

Future<bool> fileExistAtPath(String path) async {
  File file = File(path);
  return await file.exists();
}

void copyFile(Map<String, String> mediaData) {
  File systemFile = File(mediaData["oldPath"]!);
  String newPath = mediaData["newPath"]!;
  systemFile.copySync(newPath);
}

Future<void> checkAndCreateDirectory(String filePath) async {
  String dirPath = path_lib.dirname(filePath);
  final directory = Directory(dirPath);
  bool exists = await directory.exists();
  if (!exists) {
    await directory.create(recursive: true);
  }
}

Future<void> initializeDirectories() async {
  SecureStorage secureStorage = SecureStorage();
  final directory = await getApplicationDocumentsDirectory();
  AppLogger(prefixes: ["MediaDirPath"]).info(directory.path);
  String? mediaDir = await secureStorage.read(key: "media_dir");
  String mediaDirPath = path_lib.join(directory.path, mediaDir);
  final mediaDirectory = Directory(mediaDirPath);
  if (!mediaDirectory.existsSync()) {
    await mediaDirectory.create(recursive: true);
  }
  String? backupDir = await secureStorage.read(key: "backup_dir");
  String backupDirPath = path_lib.join(directory.path, backupDir);
  final backupDirectory = Directory(backupDirPath);
  if (!backupDirectory.existsSync()) {
    await backupDirectory.create(recursive: true);
  }
}

Future<void> moveFileSafely(String sourcePath, String destPath) async {
  final File sourceFile = File(sourcePath);
  final File destFile = File(destPath);

  // 1. Verify the source file actually exists before doing anything
  if (!await sourceFile.exists()) {
    throw FileSystemException(
      'Source file missing. It may have already been moved or deleted.',
      sourcePath,
      const OSError('No such file or directory', 2),
    );
  }

  // 2. Safely create the destination's parent directory
  final Directory parentDir = destFile.parent;
  if (!await parentDir.exists()) {
    await parentDir.create(recursive: true);
  }

  // 3. Optional: Check if a directory mistakenly exists at the destination path
  // (Fixing the ghost folder issue from your previous run)
  if (await Directory(destPath).exists()) {
    await Directory(destPath).delete(recursive: true);
  }

  // 4. Perform the rename (with EXDEV fallback)
  try {
    await sourceFile.rename(destPath);
  } on FileSystemException catch (e) {
    if (e.osError?.errorCode == 18) {
      // EXDEV: Cross-device link
      await sourceFile.copy(destPath);
      await sourceFile.delete();
    } else {
      rethrow;
    }
  }
}

Future<String> getHashOfString(String stringForHash) async {
  return sha256.convert(utf8.encode(stringForHash)).toString();
}

Future<String?> getFileMime(String filePath) async {
  File file = File(filePath);
  if (!file.existsSync()) {
    return null;
  }
  String mime = "application/unknown";
  String? fileMime = lookupMimeType(filePath);
  if (fileMime == null) {
    return null;
  } else {
    mime = fileMime;
  }
  return mime;
}

Map<String, String> getMapUrls(double lat, double lng) {
  return {
    "google": 'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    "apple": 'https://maps.apple.com/?q=$lat,$lng'
  };
}

class FontSizeController extends ChangeNotifier {
  double _scaleFactor =
      double.parse(ModelSetting.get("fontScale", defaultValue: "1.0"));

  double get scaleFactor => _scaleFactor;

  TextScaler get textScaler => TextScaler.linear(_scaleFactor);

  // Get the scaled size based on base font size
  double getScaledSize(double fontSize) => fontSize * _scaleFactor;

  // Increase font size by 10%
  void increaseFontSize() {
    if (_scaleFactor < 1.8) {
      _scaleFactor += 0.1;
      ModelSetting.set("fontScale", _scaleFactor.toString());
      notifyListeners();
    }
  }

  // Decrease font size by 10%
  void decreaseFontSize() {
    if (_scaleFactor > 0.7) {
      // Prevent text from becoming too small
      _scaleFactor -= 0.1;
      ModelSetting.set("fontScale", _scaleFactor.toString());
      notifyListeners();
    }
  }

  // Reset to default size
  void resetFontSize() {
    _scaleFactor = 1.2;
    ModelSetting.set("fontScale", _scaleFactor.toString());
    notifyListeners();
  }
}

class ExecutionResult<T> {
  // Status of the execution using enum
  final ExecutionStatus status;

  // Holds the success result as a Map
  final Map<String, dynamic>? successResult;

  // Holds the failure reason if execution failed
  final String? failureReason;

  // Optional failure key for categorizing different types of failures
  final String? failureKey;

  ExecutionResult._({
    required this.status,
    this.successResult,
    this.failureReason,
    this.failureKey,
  });

  // Factory constructor for successful execution
  factory ExecutionResult.success(Map<String, dynamic> result) {
    return ExecutionResult._(
      status: ExecutionStatus.success,
      successResult: result,
      failureReason: null,
      failureKey: null,
    );
  }

  // Factory constructor for failed execution
  factory ExecutionResult.failure({
    required String reason,
    String? key,
  }) {
    return ExecutionResult._(
      status: ExecutionStatus.failure,
      successResult: null,
      failureReason: reason,
      failureKey: key,
    );
  }

  // Helper method to check if execution was successful
  bool get isSuccess => status == ExecutionStatus.success;

  // Helper method to check if execution failed
  bool get isFailure => status == ExecutionStatus.failure;

  // Helper method to safely get success result
  Map<String, dynamic>? getResult() {
    return isSuccess ? successResult : null;
  }

  // Helper method to safely get failure information
  Map<String, dynamic>? getFailureInfo() {
    if (!isFailure) return null;

    return {
      'reason': failureReason,
      if (failureKey != null) 'key': failureKey,
    };
  }

  @override
  String toString() {
    if (isSuccess) {
      return 'ExecutionResult(${status.name}): $successResult';
    } else {
      return 'ExecutionResult(${status.name}): ${failureReason ?? "No reason provided"}${failureKey != null ? " (Key: $failureKey)" : ""}';
    }
  }
}

class PageParams {
  String? id;
  bool? isAuthenticated;
  int? mediaIndexInGroup;
  int? mediaCountInGroup;
  AppTask? appTask;
  Map<String, dynamic>? cipherData;
  bool? recreatePassword;

  PageParams({
    this.id,
    this.isAuthenticated,
    this.mediaCountInGroup,
    this.mediaIndexInGroup,
    this.appTask,
    this.cipherData,
    this.recreatePassword,
  });
}

/* hexadecimal from/to conversions */
/// Converts a list of bytes to a hex string
String bytesToHex(List<int> bytes) {
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

/// Converts a hex string to a list of bytes
Uint8List hexToBytes(String hex) {
  final length = hex.length;
  if (length % 2 != 0) {
    throw FormatException('Hex string must have an even length');
  }

  return Uint8List.fromList(
    List.generate(length ~/ 2, (i) {
      final byte = hex.substring(i * 2, i * 2 + 2);
      return int.parse(byte, radix: 16);
    }),
  );
}

Future<String> getDeviceName() async {
  final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  if (Platform.isAndroid) {
    AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
    return '${androidInfo.brand} ${androidInfo.model}';
  } else if (Platform.isIOS) {
    IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
    return '${iosInfo.utsname.machine} (${iosInfo.model})';
  } else if (Platform.isMacOS) {
    MacOsDeviceInfo macInfo = await deviceInfo.macOsInfo;
    return macInfo.computerName;
  } else if (Platform.isWindows) {
    WindowsDeviceInfo winInfo = await deviceInfo.windowsInfo;
    return '${winInfo.productName} ${winInfo.computerName}';
  } else if (Platform.isLinux) {
    LinuxDeviceInfo linuxInfo = await deviceInfo.linuxInfo;
    return linuxInfo.name;
  } else {
    return 'Unknown';
  }
}

Future<int> getDeviceType() async {
  if (Platform.isAndroid) {
    return 1;
  } else if (Platform.isIOS) {
    return 2;
  } else if (Platform.isMacOS) {
    return 3;
  } else if (Platform.isWindows) {
    return 4;
  } else if (Platform.isLinux) {
    return 5;
  } else {
    return 0;
  }
}

Future<String> getDeviceHash() async {
  String savedHash = ModelSetting.get(AppString.deviceHash.string);
  if (savedHash.isNotEmpty) {
    return savedHash;
  } else {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    String stringForHash = "Unknown";
    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      stringForHash =
          '${androidInfo.manufacturer}${androidInfo.model}${androidInfo.device}${androidInfo.hardware}';
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      stringForHash =
          '${iosInfo.identifierForVendor}${iosInfo.utsname.machine}${iosInfo.model}';
    } else if (Platform.isMacOS) {
      MacOsDeviceInfo macInfo = await deviceInfo.macOsInfo;
      stringForHash = '${macInfo.systemGUID}';
    } else if (Platform.isWindows) {
      WindowsDeviceInfo winInfo = await deviceInfo.windowsInfo;
      stringForHash = '${winInfo.productId}${winInfo.deviceId}';
    } else if (Platform.isLinux) {
      LinuxDeviceInfo linuxInfo = await deviceInfo.linuxInfo;
      stringForHash = '${linuxInfo.machineId}';
    }
    String deviceHash = await getHashOfString(stringForHash);
    await ModelSetting.set(AppString.deviceHash.string, deviceHash);
    return deviceHash;
  }
}

Future<String> getDeviceId() async {
  return ModelSetting.get(AppString.deviceId.string);
}

// storage permission
Future<PermissionStatus> getStoragePermissionStatus() async {
  if (Platform.isAndroid) {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    // Android 11 (API 30): MANAGE_EXTERNAL_STORAGE permission
    if (androidInfo.version.sdkInt >= 30) {
      return await Permission.manageExternalStorage.status;
    } else {
      return await Permission.storage.status;
    }
  } else if (Platform.isIOS) {
    // iOS does not have a direct 'storage' permission, only photo library access
    return await Permission.photos.status;
  } else if (Platform.isMacOS) {
    // macOS distinguishes photo and file system access
    return await Permission.photos.status; // For Photos
    // For file access, you must use file dialogs as explicit permission model does not exist
  } else if (Platform.isWindows) {
    // No explicit storage permission, always granted
    return PermissionStatus.granted;
  } else if (Platform.isLinux) {
    // No explicit storage permission, always granted
    return PermissionStatus.granted;
  } else if (kIsWeb) {
    // Web: storage access is managed by the browser, always granted
    return PermissionStatus.granted;
  } else {
    // Default fallback
    return PermissionStatus.granted;
  }
}

SupabaseClient? getSupabaseClient() {
  try {
    return Supabase.instance.client;
  } catch (e, s) {
    AppLogger(prefixes: ["Common"])
        .error("Supaclient", error: e, stackTrace: s);
    return null;
  }
}

Future<void> initializeDependencies(
    {ExecutionMode mode = ExecutionMode.appForeground}) async {
  // initialize in parallel
  await Future.wait(([
    initializeDirectories(),
    initializeSupabase(mode: mode),
    initializePackages(mode: mode),
  ]));
  AppLogger(prefixes: [mode.string]).info("Initialized Dependencies");
}

Future<void> initializePackages(
    {ExecutionMode mode = ExecutionMode.appForeground}) async {
  //CryptoUtils.init();
}

Future<void> initializeSupabase(
    {ExecutionMode mode = ExecutionMode.appForeground}) async {
  // load certificate
  ByteData certData = await PlatformAssetBundle().load('assets/cacert.pem');
  SecurityContext.defaultContext
      .setTrustedCertificatesBytes(certData.buffer.asUint8List());
  await ModelSetting.set(AppString.supabaseInitialized.string, "no");
  final String supaUrl = const String.fromEnvironment("SUPABASE_URL");
  final String supaKey = const String.fromEnvironment("SUPABASE_KEY");
  if (supaUrl.isNotEmpty && supaKey.isNotEmpty) {
    Supabase _ = await Supabase.initialize(url: supaUrl, anonKey: supaKey);
    await ModelSetting.set(AppString.supabaseInitialized.string, "yes");
    AppLogger(prefixes: [mode.string]).info("Initialized Supabase");
  }
}

String? getSignedInUserId() {
  if (simulateTesting()) {
    if (ModelSetting.get(AppString.signedIn.string, defaultValue: "no") ==
        "yes") {
      return "fife";
    } else {
      return null;
    }
  }
  bool supabaseInitialized = ModelSetting.get(
          AppString.supabaseInitialized.string,
          defaultValue: "no") ==
      "yes";
  if (!supabaseInitialized) {
    AppLogger(prefixes: ["Common"]).error("Supabase not initialized");
    return null;
  }
  SupabaseClient supabaseClient = Supabase.instance.client;
  User? currentUser = supabaseClient.auth.currentUser;
  if (currentUser != null) {
    return currentUser.id;
  } else {
    return null;
  }
}

String? getSignedInEmailId() {
  if (simulateTesting()) {
    return testEmailId;
  }
  bool supabaseInitialized = ModelSetting.get(
          AppString.supabaseInitialized.string,
          defaultValue: "no") ==
      "yes";
  if (!supabaseInitialized) return null;
  SupabaseClient supabaseClient = Supabase.instance.client;
  User? currentUser = supabaseClient.auth.currentUser;
  if (currentUser != null) {
    return currentUser.email;
  } else {
    return null;
  }
}

Future<String?> getMasterKey() async {
  SecureStorage storage = SecureStorage();
  String? masterKeyBase64 = await storage.read(key: AppString.masterKey.string);
  return masterKeyBase64;
}

void safeParseJson(
    String responseBody, Map<String, dynamic> data, AppLogger logger) {
  if (responseBody.isEmpty) return;

  try {
    final decoded = jsonDecode(responseBody);
    if (decoded is Map<String, dynamic>) {
      data.addAll(decoded);
    } else {
      logger.error(
          "Upload warning: Expected JSON Map but got ${decoded.runtimeType}");
      data["error"] =
          data["error"] == "" ? "Invalid response format" : data["error"];
    }
  } catch (e, s) {
    // Server returned a non-JSON body (e.g. Cloudflare HTML block page, Nginx 413 page)
    logger.error(
        "JSON Decode Failed. Body snippet: ${responseBody.length > 50 ? responseBody.substring(0, 50) : responseBody}",
        error: e,
        stackTrace: s);
    data["error"] =
        data["error"] == "" ? "Failed to parse server response" : data["error"];
  }
}
