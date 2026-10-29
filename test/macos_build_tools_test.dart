import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporary;
  late String universal;
  late String arm64;
  late Directory deploymentFixture;
  final wrapper = p.absolute('macos', 'Flutter', 'tools', 'lipo');
  final deploymentVerifier =
      p.absolute('macos', 'Flutter', 'tools', 'verify_deployment_target.py');

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

    // The failing slice is deliberately x86_64: checking only this host's
    // arm64 architecture would incorrectly accept this as macOS 12 compatible.
    deploymentFixture =
        Directory(p.join(temporary.path, 'Frameworks with spaces'));
    await deploymentFixture.create();
    final newerObject = p.join(temporary.path, 'newer x86_64.o');
    final newer = await run('/usr/bin/xcrun', [
      'clang',
      '-arch',
      'x86_64',
      '-mmacosx-version-min=13.0',
      '-c',
      source.path,
      '-o',
      newerObject,
    ]);
    expect(newer.exitCode, 0, reason: '${newer.stderr}');
    final mixed = await run('/usr/bin/lipo', [
      '-create',
      arm64,
      newerObject,
      '-output',
      p.join(deploymentFixture.path, 'mixed versions'),
    ]);
    expect(mixed.exitCode, 0, reason: '${mixed.stderr}');
    await File(p.join(deploymentFixture.path, 'resource.txt'))
        .writeAsString('A resource is not executable code.');
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

  test('deployment validation rejects a newer non-host architecture', () async {
    final result = await run('/usr/bin/python3', [
      deploymentVerifier,
      deploymentFixture.path,
      '12.0',
    ]);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('(x86_64) requires macOS 13.0'));
    expect(result.stderr, isNot(contains('(arm64) requires')));
  }, skip: !Platform.isMacOS);

  test('deployment validation accepts equal and older minimums', () async {
    final result = await run('/usr/bin/python3', [
      deploymentVerifier,
      deploymentFixture.path,
      '13.0',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, contains('Verified 1 bundled binaries'));
  }, skip: !Platform.isMacOS);

  test('deployment validation cannot pass with missing or empty code',
      () async {
    final empty = await Directory(p.join(temporary.path, 'empty')).create();
    for (final path in [empty.path, p.join(temporary.path, 'missing')]) {
      final result = await run('/usr/bin/python3', [
        deploymentVerifier,
        path,
        '13.0',
      ]);
      expect(result.exitCode, isNot(0));
    }
  }, skip: !Platform.isMacOS);
}
