import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporary;
  late String universal;
  late String arm64;
  final wrapper = p.absolute('macos', 'Flutter', 'tools', 'lipo');

  Future<ProcessResult> run(String executable, List<String> arguments) =>
      Process.run(executable, arguments);

  setUpAll(() async {
    if (!Platform.isMacOS) return;
    temporary = await Directory.systemTemp.createTemp('fife lipo fixture ');
    final source = File(p.join(temporary.path, 'fixture.c'));
    await source.writeAsString('int fixture(void) { return 42; }\n');
    final objects = <String>[];
    for (final arch in ['arm64', 'x86_64']) {
      final object = p.join(temporary.path, '$arch.o');
      final compiled = await run('/usr/bin/xcrun', [
        'clang',
        '-arch',
        arch,
        '-mmacosx-version-min=12.0',
        '-c',
        source.path,
        '-o',
        object
      ]);
      expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
      objects.add(object);
    }
    arm64 = objects.first;
    universal = p.join(temporary.path, 'universal object.o');
    final combined = await run(
        '/usr/bin/lipo', ['-create', ...objects, '-output', universal]);
    expect(combined.exitCode, 0, reason: '${combined.stderr}');
  });

  tearDownAll(() async {
    if (Platform.isMacOS) await temporary.delete(recursive: true);
  });

  test('verifies every requested slice of a real universal Mach-O object',
      () async {
    final result =
        await run(wrapper, [universal, '-verify_arch', 'arm64', 'x86_64']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  }, skip: !Platform.isMacOS);

  test('a missing requested slice still fails architecture verification',
      () async {
    final result =
        await run(wrapper, [arm64, '-verify_arch', 'arm64', 'x86_64']);
    expect(result.exitCode, isNot(0));
  }, skip: !Platform.isMacOS);

  test('native info and extraction behavior are preserved', () async {
    final expected = await run('/usr/bin/lipo', ['-info', universal]);
    final info = await run(wrapper, ['-info', universal]);
    expect(info.exitCode, expected.exitCode);
    expect(info.stdout, expected.stdout);
    final output = p.join(temporary.path, 'extracted object.o');
    final extracted =
        await run(wrapper, [universal, '-thin', 'x86_64', '-output', output]);
    expect(extracted.exitCode, 0, reason: '${extracted.stderr}');
    expect(
        (await run('/usr/bin/lipo', [output, '-verify_arch', 'x86_64']))
            .exitCode,
        0);
    expect(
        (await run('/usr/bin/lipo', [output, '-verify_arch', 'arm64']))
            .exitCode,
        isNot(0));
  }, skip: !Platform.isMacOS);

  test('malformed requests retain native failure behavior', () async {
    final arguments = [universal, '-verify_arch'];
    final expected = await run('/usr/bin/lipo', arguments);
    final result = await run(wrapper, arguments);
    expect(expected.exitCode, isNot(0));
    expect(result.exitCode, expected.exitCode);
    expect(result.stderr, expected.stderr);
  }, skip: !Platform.isMacOS);
}
