enum SupportDeviceFilter {
  attention,
  online,
  offline,
  servers,
  computers,
  shared,
}

bool matchesSupportDeviceFilters({
  required Set<SupportDeviceFilter> filters,
  required bool online,
  required bool isServer,
  required bool isShared,
  required bool needsAttention,
}) {
  if (filters.isEmpty) return true;

  if (filters.contains(SupportDeviceFilter.attention) && !needsAttention) {
    return false;
  }

  final includeOnline = filters.contains(SupportDeviceFilter.online);
  final includeOffline = filters.contains(SupportDeviceFilter.offline);
  if ((includeOnline || includeOffline) &&
      !((includeOnline && online) || (includeOffline && !online))) {
    return false;
  }

  final includeServers = filters.contains(SupportDeviceFilter.servers);
  final includeComputers = filters.contains(SupportDeviceFilter.computers);
  final includeShared = filters.contains(SupportDeviceFilter.shared);
  if ((includeServers || includeComputers || includeShared) &&
      !((includeServers && isServer) ||
          (includeComputers && !isServer) ||
          (includeShared && isShared))) {
    return false;
  }

  return true;
}
