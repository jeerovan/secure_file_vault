import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Native AX inspection/Save panels can enable the engine-owned semantics
/// handle after WidgetTester's baseline. Release that observation handle only
/// AFTER the journey assertions, before Flutter checks for leaked test handles.
/// This does not disable semantics during the journey or dispose any test-owned
/// handle. Restore the real platform value after test verification.
Future<void> withMacNativeAccessibility(
    IntegrationTestWidgetsFlutterBinding binding,
    Future<void> Function() body) async {
  try {
    await body();
  } finally {
    binding.platformDispatcher.semanticsEnabledTestValue = false;
    addTearDown(binding.platformDispatcher.clearSemanticsEnabledTestValue);
  }
}
