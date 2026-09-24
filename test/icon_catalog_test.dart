import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pixora/core/icons/icon_catalog.dart';
import 'package:pixora/document/model/layer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('online styles: queued, limited, deduplicated and cached', () async {
    final c = IconCatalog.instance;
    var running = 0, peak = 0, calls = 0;
    c.client = MockClient((req) async {
      calls++;
      running++;
      peak = running > peak ? running : peak;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      running--;
      return http.Response('<svg><path d="M0 0h10v10z"/></svg>', 200);
    });
    final names = ['home', 'star', 'mail', 'call', 'cake', 'flag', 'add'];
    final results = await Future.wait([
      for (final n in names)
        c.pathFor(n, style: IconStyle.rounded, filled: true),
      // Same icon twice at once: one download.
      c.pathFor('home', style: IconStyle.rounded, filled: true),
    ]);
    expect(results.every((d) => d == 'M0 0h10v10z'), isTrue);
    expect(calls, names.length);
    expect(peak, lessThanOrEqualTo(4));
    expect(
      c.cached('star', style: IconStyle.rounded, filled: true),
      'M0 0h10v10z',
    );
    // Previews scrolled away before their turn are skipped.
    final skipped = await c.pathFor(
      'pets',
      style: IconStyle.sharp,
      wanted: () => false,
    );
    expect(skipped, isNull);
    expect(calls, names.length);
    // Outlined regular comes from the app, no network.
    expect(await c.pathFor('home'), isNotNull);
    expect(calls, names.length);
  });
}
