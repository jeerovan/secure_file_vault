import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/utils/common.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'native_test_identity.dart';

enum NativeTestCheckpoint {
  setup,
  signIn,
  keys,
  registration,
  settings,
  sliderMax,
  sliderMin,
  notificationProgress,
  notificationLocale,
  complete
}

NativeTestCheckpoint? _checkpoint;
void markNativeCheckpoint(NativeTestCheckpoint checkpoint) =>
    _checkpoint = checkpoint;

/// Report nonsecret outcomes through the isolated app's container when Xcode
/// cannot attach. The ordinary integration driver remains supported.
void recordIphoneResults(
    IntegrationTestWidgetsFlutterBinding binding, String suite) {
  const runId = String.fromEnvironment('FIFE_NATIVE_RUN_ID');
  if (!Platform.isIOS || runId.isEmpty) return;
  unawaited(binding.allTestsPassed.future.then((passed) async {
    final bundle = (await PackageInfo.fromPlatform()).packageName;
    if (!isIsolatedNativeTestBundle(bundle)) {
      throw StateError('Native reporting requires an isolated test app');
    }
    final documents = await getApplicationDocumentsDirectory();
    final result = File('${documents.path}/fife-native-result.json');
    final endpoint = Uri.parse(AppEnv.effectiveApiBaseUrl);
    final interfaces =
        await NetworkInterface.list(type: InternetAddressType.IPv4);
    final wifi = interfaces
        .where((interface) => interface.name == 'en0')
        .expand((interface) => interface.addresses)
        .map((address) => address.address)
        .toList();
    final prefix = endpoint.host.split('.').take(3).join('.');
    var reachable = false;
    int? socketErrno;
    try {
      final socket = await Socket.connect(endpoint.host, endpoint.port,
          timeout: const Duration(seconds: 3));
      socket.destroy();
      reachable = true;
    } on SocketException catch (error) {
      socketErrno = error.osError?.errorCode;
    } on TimeoutException {
      // A timeout is an outcome, never authority to clear a local account.
    }
    final temporary = File('${result.path}.partial');
    await temporary.writeAsString(
        jsonEncode({
          'runId': runId,
          'suite': suite,
          'passed': passed,
          'testNames': binding.results.keys.toList(),
          'failureCount': binding.failureMethodsDetails.length,
          'checkpoint': _checkpoint?.name,
          // Keep raw failures private: assertions can contain encrypted keys,
          // signed URLs or credentials. Locations and primitive expectations
          // are enough to locate a failed assertion without copying its data.
          'failureSummary': binding.failureMethodsDetails.map((failure) {
            final details = failure.details ?? '';
            return {
              'locations': RegExp(
                      r'(?:integration_test|lib)/[a-zA-Z0-9_./-]+\.dart:[0-9]+(?::[0-9]+)?')
                  .allMatches(details)
                  .map((match) => match.group(0))
                  .toSet()
                  .toList(),
              'primitiveExpectations': RegExp(
                      r'^\s*(?:Expected|Actual):\s*<?(?:true|false|null|-?[0-9]+)>?\s*$',
                      multiLine: true)
                  .allMatches(details)
                  .map((match) => match.group(0)!.trim())
                  .toList(),
              'timeout': details.contains('TimeoutException'),
            };
          }).toList(),
          'network': {
            'wifiIPv4Present': wifi.isNotEmpty,
            'sameIPv4PrefixAsBackend':
                wifi.any((address) => address.startsWith('$prefix.')),
            'backendTCPReachable': reachable,
            'socketErrno': socketErrno,
          }
        }),
        flush: true);
    await temporary.rename(result.path);
  }));
}
