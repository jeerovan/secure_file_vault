import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/ui/pages/page_explorer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Match the shipped app's glyph widths; Flutter's Ahem font uses square
    // glyphs and does not represent the available space in this toolbar.
    await (FontLoader('Inter')
          ..addFont(rootBundle.load('fonts/Inter-Regular.ttf')))
        .load();
  });
  for (final direction in TextDirection.values) {
    for (final scale in [1.0, 2.0]) {
      for (final depth in [2, 3]) {
        testWidgets(
            'FiFe stays visible and reachable in narrow $direction path at $scale text with $depth levels',
            (tester) async {
          final items = await Future.wait([
            ModelItem.fromMap({'id': 'fife', 'name': 'FiFe', 'is_folder': 1}),
            ModelItem.fromMap(
                {'id': 'device', 'name': 'Samsung SM-A305F', 'is_folder': 1}),
            ModelItem.fromMap({
              'id': 'folder',
              'name': 'A very long nested folder name',
              'is_folder': 1
            }),
          ]);
          String? selected;
          await tester.pumpWidget(MaterialApp(
              theme: ThemeData(
                  fontFamily: 'Inter',
                  brightness: depth == 2 ? Brightness.light : Brightness.dark),
              home: Scaffold(
                  body: MediaQuery(
                data: MediaQueryData(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true),
                child: Directionality(
                    textDirection: direction,
                    child: Center(
                        child: SizedBox(
                      width: 144,
                      child: BreadcrumbTrail(
                          parentChilds: items.take(depth).toList(),
                          onTap: (item) => selected = item.id),
                    ))),
              ))));
          await tester.pumpAndSettle();
          final viewport = tester.getRect(find.byType(BreadcrumbTrail));
          final root = tester.getRect(find.text('FiFe'));
          expect(root.left, greaterThanOrEqualTo(viewport.left));
          expect(root.right, lessThanOrEqualTo(viewport.right));
          await tester.tap(find.text('FiFe'));
          expect(selected, 'fife');
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
