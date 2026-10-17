import 'dart:async';

/// Keeps one subscription to [source] and gives every listener the latest
/// value (or error) straight away, then live updates.
///
/// The dashboard creates its Firestore streams once, so search keystrokes
/// don't resubscribe. But when the layout switches (resizing across a
/// breakpoint), new StreamBuilders start listening while the old ones are
/// still subscribed, and a plain Firestore stream only sends its current
/// snapshot to the first listener, so the new ones spun forever.
class LatestValueStream<T> {
  LatestValueStream(Stream<T> source) {
    _subscription = source.listen(
      (value) {
        _latest = value;
        _hasLatest = true;
        _latestError = null;
        for (final listener in _listeners.toList()) {
          listener.add(value);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _latestError = error;
        _latestStackTrace = stackTrace;
        for (final listener in _listeners.toList()) {
          listener.addError(error, stackTrace);
        }
      },
    );
  }

  late final StreamSubscription<T> _subscription;
  final Set<MultiStreamController<T>> _listeners = {};
  T? _latest;
  bool _hasLatest = false;
  Object? _latestError;
  StackTrace? _latestStackTrace;

  /// The same Stream object every time, so StreamBuilders keep their
  /// subscription across rebuilds.
  late final Stream<T> stream = Stream<T>.multi((controller) {
    if (_latestError != null) {
      controller.addError(_latestError!, _latestStackTrace);
    } else if (_hasLatest) {
      controller.add(_latest as T);
    }
    _listeners.add(controller);
    controller.onCancel = () => _listeners.remove(controller);
  });

  void dispose() {
    _subscription.cancel();
    for (final listener in _listeners.toList()) {
      listener.close();
    }
    _listeners.clear();
  }
}
