import 'package:flutter_hbb/models/support_server_resolution.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selects the largest valid resolution by area', () {
    final highest = highestSupportDisplayResolution(const [
      SupportDisplayResolution(1024, 768),
      SupportDisplayResolution(1600, 1200),
      SupportDisplayResolution(1920, 1080),
      SupportDisplayResolution(0, 2160),
    ]);

    expect(highest, const SupportDisplayResolution(1920, 1080));
  });

  test('uses width to break equal-area ties', () {
    final highest = highestSupportDisplayResolution(const [
      SupportDisplayResolution(1200, 800),
      SupportDisplayResolution(1600, 600),
    ]);

    expect(highest, const SupportDisplayResolution(1600, 600));
  });

  test('retries until the remote display confirms the target resolution', () {
    final policy = SupportServerResolutionRetryPolicy(
      requestInterval: const Duration(seconds: 3),
    );
    final startedAt = DateTime.utc(2026, 9, 25);
    const current = SupportDisplayResolution(1024, 768);
    const target = SupportDisplayResolution(1920, 1080);

    expect(
      policy.shouldRequest(
        current: current,
        target: target,
        now: startedAt,
      ),
      isTrue,
    );
    expect(policy.isApplied(current: current, target: target), isFalse);
    expect(
      policy.shouldRequest(
        current: current,
        target: target,
        now: startedAt.add(const Duration(seconds: 2)),
      ),
      isFalse,
    );
    expect(
      policy.shouldRequest(
        current: current,
        target: target,
        now: startedAt.add(const Duration(seconds: 3)),
      ),
      isTrue,
    );
    expect(policy.isApplied(current: target, target: target), isTrue);
    expect(
      policy.shouldRequest(
        current: target,
        target: target,
        now: startedAt.add(const Duration(seconds: 6)),
      ),
      isFalse,
    );
  });
}
