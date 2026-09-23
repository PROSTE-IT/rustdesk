class SupportSessionActivityTracker {
  SupportSessionActivityTracker({
    this.interactionIdleWindow = const Duration(seconds: 60),
  });

  final Duration interactionIdleWindow;
  final Stopwatch _clock = Stopwatch();

  Duration _lastSample = Duration.zero;
  Duration? _lastInteraction;
  Duration _activeWindow = Duration.zero;
  Duration _interaction = Duration.zero;
  bool _windowActive = false;
  bool _started = false;

  int get activeWindowSeconds => _activeWindow.inMilliseconds ~/ 1000;
  int get interactionSeconds => _interaction.inMilliseconds ~/ 1000;

  void start() {
    _clock
      ..reset()
      ..start();
    _lastSample = Duration.zero;
    _lastInteraction = null;
    _activeWindow = Duration.zero;
    _interaction = Duration.zero;
    _windowActive = false;
    _started = true;
  }

  void sample({
    required bool windowActive,
    Duration? elapsed,
  }) {
    if (!_started) return;
    final now = elapsed ?? _clock.elapsed;
    if (now < _lastSample) return;

    if (_windowActive) {
      _activeWindow += now - _lastSample;
      final lastInteraction = _lastInteraction;
      if (lastInteraction != null) {
        final interactionStart = _lastSample > lastInteraction
            ? _lastSample
            : lastInteraction;
        final idleAt = lastInteraction + interactionIdleWindow;
        final interactionEnd = now < idleAt ? now : idleAt;
        if (interactionEnd > interactionStart) {
          _interaction += interactionEnd - interactionStart;
        }
      }
    }
    _windowActive = windowActive;
    if (!windowActive) {
      // Restoring or reselecting a session must require a new input event.
      _lastInteraction = null;
    }
    _lastSample = now;
  }

  void recordInteraction({
    required bool windowActive,
    Duration? elapsed,
  }) {
    if (!_started) return;
    final now = elapsed ?? _clock.elapsed;
    if (!windowActive) {
      sample(windowActive: false, elapsed: now);
      return;
    }
    sample(windowActive: true, elapsed: now);
    _lastInteraction = now;
  }
}
