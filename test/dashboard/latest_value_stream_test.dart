import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_appointment/view/dashboard/latest_value_stream.dart';

void main() {
  test('a listener that joins later gets the latest value immediately', () async {
    final source = StreamController<int>.broadcast();
    final latest = LatestValueStream(source.stream);

    final first = <int>[];
    final sub1 = latest.stream.listen(first.add);
    source.add(1);
    await pumpEventQueue();

    // Joins while the first listener is still subscribed (layout switch)
    final second = <int>[];
    final sub2 = latest.stream.listen(second.add);
    await pumpEventQueue();
    expect(second, [1]);

    source.add(2);
    await pumpEventQueue();
    expect(first, [1, 2]);
    expect(second, [1, 2]);

    await sub1.cancel();
    await sub2.cancel();
    latest.dispose();
    await source.close();
  });

  test('errors are replayed too', () async {
    final source = StreamController<int>();
    final latest = LatestValueStream(source.stream);
    source.addError(StateError('missing index'));
    await pumpEventQueue();

    final errors = <Object>[];
    final sub = latest.stream.listen((_) {}, onError: errors.add);
    await pumpEventQueue();
    expect(errors.single, isA<StateError>());

    await sub.cancel();
    latest.dispose();
  });
}
