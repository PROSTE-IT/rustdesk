import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/models/support_session_activity_tracker.dart';

void main() {
  test('counts only focused time and resets interaction after hiding', () {
    final tracker = SupportSessionActivityTracker(
      interactionIdleWindow: const Duration(seconds: 60),
    );
    tracker.start();
    tracker.sample(windowActive: true, elapsed: Duration.zero);

    tracker.sample(
      windowActive: true,
      elapsed: const Duration(seconds: 10),
    );
    tracker.recordInteraction(
      windowActive: true,
      elapsed: const Duration(seconds: 10),
    );
    tracker.sample(
      windowActive: true,
      elapsed: const Duration(seconds: 30),
    );
    tracker.sample(
      windowActive: false,
      elapsed: const Duration(seconds: 40),
    );
    tracker.sample(
      windowActive: false,
      elapsed: const Duration(seconds: 50),
    );
    tracker.sample(
      windowActive: true,
      elapsed: const Duration(seconds: 50),
    );
    tracker.sample(
      windowActive: true,
      elapsed: const Duration(seconds: 60),
    );

    expect(tracker.activeWindowSeconds, 50);
    expect(tracker.interactionSeconds, 30);
  });

  test('interaction expires after idle window and never exceeds active time',
      () {
    final tracker = SupportSessionActivityTracker(
      interactionIdleWindow: const Duration(seconds: 60),
    );
    tracker.start();
    tracker.sample(windowActive: true, elapsed: Duration.zero);
    tracker.recordInteraction(windowActive: true);
    tracker.sample(
      windowActive: true,
      elapsed: const Duration(seconds: 90),
    );

    expect(tracker.activeWindowSeconds, 90);
    expect(tracker.interactionSeconds, 60);
  });

  test('ignored interaction while hidden requires a new event after restore',
      () {
    final tracker = SupportSessionActivityTracker();
    tracker.start();
    tracker.recordInteraction(
      windowActive: false,
      elapsed: const Duration(seconds: 5),
    );
    tracker.sample(
      windowActive: true,
      elapsed: const Duration(seconds: 20),
    );
    tracker.sample(
      windowActive: true,
      elapsed: const Duration(seconds: 35),
    );

    expect(tracker.activeWindowSeconds, 15);
    expect(tracker.interactionSeconds, 0);
  });
}
