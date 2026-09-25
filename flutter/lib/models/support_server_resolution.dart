class SupportDisplayResolution {
  const SupportDisplayResolution(this.width, this.height);

  final int width;
  final int height;

  int get area => width * height;

  bool get isValid => width > 0 && height > 0;

  @override
  bool operator ==(Object other) =>
      other is SupportDisplayResolution &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

SupportDisplayResolution? highestSupportDisplayResolution(
  Iterable<SupportDisplayResolution> resolutions,
) {
  SupportDisplayResolution? highest;
  for (final resolution in resolutions) {
    if (!resolution.isValid) continue;
    if (highest == null ||
        resolution.area > highest.area ||
        (resolution.area == highest.area && resolution.width > highest.width)) {
      highest = resolution;
    }
  }
  return highest;
}

class SupportServerResolutionRetryPolicy {
  SupportServerResolutionRetryPolicy({
    this.requestInterval = const Duration(seconds: 3),
  });

  final Duration requestInterval;
  DateTime? _lastRequestAt;
  SupportDisplayResolution? _lastRequestedResolution;

  bool isApplied({
    required SupportDisplayResolution? current,
    required SupportDisplayResolution target,
  }) =>
      current == target;

  bool shouldRequest({
    required SupportDisplayResolution? current,
    required SupportDisplayResolution target,
    required DateTime now,
  }) {
    if (isApplied(current: current, target: target)) return false;

    final lastRequestAt = _lastRequestAt;
    if (_lastRequestedResolution == target &&
        lastRequestAt != null &&
        now.difference(lastRequestAt) < requestInterval) {
      return false;
    }

    _lastRequestedResolution = target;
    _lastRequestAt = now;
    return true;
  }
}
