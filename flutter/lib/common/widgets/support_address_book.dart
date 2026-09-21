import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/peer_card.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/models/support_address_book_model.dart';

enum _SupportDeviceFilter { all, online, offline, servers, computers }

const _supportSessionSummaryPromptsEnabled = bool.fromEnvironment(
  'RDBK_SESSION_SUMMARY_PROMPTS',
  defaultValue: false,
);

const _newSupportCustomerValue = '__new_support_customer__';

class SupportAddressBook extends StatefulWidget {
  const SupportAddressBook({Key? key}) : super(key: key);

  @override
  State<SupportAddressBook> createState() => _SupportAddressBookState();
}

class _SupportAddressBookState extends State<SupportAddressBook> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _searchController = TextEditingController();
  Timer? _onlineTimer;
  Timer? _syncTimer;
  _SupportDeviceFilter _filter = _SupportDeviceFilter.all;
  String? _selectedCustomerId;

  @override
  void initState() {
    super.initState();
    supportAddressBookModel.addListener(_modelChanged);
    supportAddressBookModel.startOnlineTracking();
    _onlineTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => supportAddressBookModel.queryOnlineStates(),
    );
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (supportAddressBookModel.isAuthenticated &&
          !supportAddressBookModel.loading) {
        unawaited(_silentRefresh());
      }
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await supportAddressBookModel.ensureInitialized();
    if (supportAddressBookModel.isAuthenticated) await _silentRefresh();
  }

  @override
  void dispose() {
    _onlineTimer?.cancel();
    _syncTimer?.cancel();
    supportAddressBookModel.removeListener(_modelChanged);
    _usernameController.dispose();
    _passwordController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _modelChanged() {
    if (mounted) setState(() {});
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      _showError('Podaj login i hasło.');
      return;
    }
    try {
      await supportAddressBookModel.login(username, password);
      _passwordController.clear();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _refresh() async {
    try {
      await supportAddressBookModel.refresh();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _silentRefresh() async {
    try {
      await supportAddressBookModel.refresh();
    } catch (error) {
      debugPrint('Support address book synchronization failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!supportAddressBookModel.initialized) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!supportAddressBookModel.isAuthenticated) {
      return _buildLogin();
    }
    return _buildAddressBook();
  }

  Widget _buildLogin() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.corporate_fare, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Wspólna książka adresowa',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _usernameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Login technika',
                    prefixIcon: Icon(Icons.person),
                  ),
                  onSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Hasło',
                    prefixIcon: Icon(Icons.lock),
                  ),
                  onSubmitted: (_) => _login(),
                ),
                if (supportAddressBookModel.error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    supportAddressBookModel.error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed:
                      supportAddressBookModel.loading ? null : () => _login(),
                  icon: supportAddressBookModel.loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: const Text('Zaloguj'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddressBook() {
    final query = _searchController.text.trim().toLowerCase();
    final devices = supportAddressBookModel.devices
        .where((device) => _matchesDevice(device, query))
        .where(_matchesFilter)
        .toList()
      ..sort(_compareDevices);
    final customers = supportAddressBookModel.customers
        .where((customer) =>
            _matchesCustomer(customer, query) ||
            devices.any((device) => device.customerId == customer.id))
        .toList()
      ..sort((left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()));
    final selectedCustomerId =
        customers.any((customer) => customer.id == _selectedCustomerId)
            ? _selectedCustomerId
            : null;
    final visibleDevices = selectedCustomerId == null
        ? devices
        : devices
            .where((device) => device.customerId == selectedCustomerId)
            .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 900;
        return Column(
          children: [
            _buildToolbar(desktop, constraints.maxWidth),
            if (supportAddressBookModel.loading)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: desktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 280,
                          child: _buildCustomerNavigation(
                            customers,
                            devices,
                            selectedCustomerId,
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: _buildDevicePane(
                            visibleDevices,
                            customers,
                            selectedCustomerId,
                            query,
                          ),
                        ),
                      ],
                    )
                  : _buildCompactAddressBook(
                      visibleDevices,
                      customers,
                      devices,
                      selectedCustomerId,
                      query,
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildToolbar(bool desktop, double availableWidth) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Wrap(
        runSpacing: 8,
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: desktop ? 410 : availableWidth - 24,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Szukaj: klient, urządzenie, ID, host, użytkownik…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Wyczyść wyszukiwanie',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          _buildFilters(),
          FilledButton.icon(
            onPressed: () => showSupportDeviceDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('Dodaj urządzenie'),
          ),
          Tooltip(
            message: 'Odśwież',
            child: IconButton.filledTonal(
              onPressed: supportAddressBookModel.loading ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ),
          Tooltip(
            message: 'Wyloguj',
            child: IconButton(
              onPressed: () => unawaited(supportAddressBookModel.logout()),
              icon: const Icon(Icons.logout),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    const labels = {
      _SupportDeviceFilter.all: 'Wszystkie',
      _SupportDeviceFilter.online: 'Online',
      _SupportDeviceFilter.offline: 'Offline',
      _SupportDeviceFilter.servers: 'Serwery',
      _SupportDeviceFilter.computers: 'Komputery',
    };
    return Wrap(
      spacing: 4,
      children: _SupportDeviceFilter.values
          .map((filter) => ChoiceChip(
                label: Text(labels[filter]!),
                selected: _filter == filter,
                onSelected: (_) => setState(() => _filter = filter),
              ))
          .toList(),
    );
  }

  Widget _buildCustomerNavigation(
    List<SupportCustomer> customers,
    List<SupportDevice> devices,
    String? selectedCustomerId,
  ) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
            child:
                Text('Klienci', style: Theme.of(context).textTheme.titleMedium),
          ),
          ListTile(
            selected: selectedCustomerId == null,
            leading: const Icon(Icons.grid_view),
            title: const Text('Wszystkie urządzenia'),
            trailing: Text('${devices.length}'),
            onTap: () => setState(() => _selectedCustomerId = null),
          ),
          const Divider(height: 1),
          Expanded(
            child: customers.isEmpty
                ? const _SupportEmptyState(
                    icon: Icons.people_outline,
                    title: 'Brak klientów',
                    message:
                        'Zmień wyszukiwanie lub filtr, aby zobaczyć klientów.',
                  )
                : ListView.builder(
                    itemCount: customers.length,
                    itemBuilder: (_, index) {
                      final customer = customers[index];
                      final count = devices
                          .where((device) => device.customerId == customer.id)
                          .length;
                      return ListTile(
                        selected: selectedCustomerId == customer.id,
                        leading: const Icon(Icons.business_outlined),
                        title: Text(customer.name,
                            overflow: TextOverflow.ellipsis),
                        subtitle: customer.note.isEmpty
                            ? null
                            : Text(customer.note,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('$count'),
                            _customerMenu(customer),
                          ],
                        ),
                        onTap: () =>
                            setState(() => _selectedCustomerId = customer.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactAddressBook(
    List<SupportDevice> visibleDevices,
    List<SupportCustomer> customers,
    List<SupportDevice> devices,
    String? selectedCustomerId,
    String query,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: DropdownButtonFormField<String>(
            value: selectedCustomerId ?? '',
            decoration: const InputDecoration(
              labelText: 'Klient',
              prefixIcon: Icon(Icons.business_outlined),
            ),
            items: [
              DropdownMenuItem<String>(
                value: '',
                child: Text('Wszystkie urządzenia (${devices.length})'),
              ),
              ...customers.map((customer) => DropdownMenuItem<String>(
                    value: customer.id,
                    child: Text(customer.name),
                  )),
            ],
            onChanged: (value) => setState(
              () => _selectedCustomerId =
                  value == null || value.isEmpty ? null : value,
            ),
          ),
        ),
        Expanded(
          child: _buildDevicePane(
            visibleDevices,
            customers,
            selectedCustomerId,
            query,
          ),
        ),
      ],
    );
  }

  Widget _buildDevicePane(
    List<SupportDevice> devices,
    List<SupportCustomer> customers,
    String? selectedCustomerId,
    String query,
  ) {
    SupportCustomer? customer;
    for (final item in customers) {
      if (item.id == selectedCustomerId) {
        customer = item;
        break;
      }
    }
    if (devices.isEmpty) {
      final hasData = supportAddressBookModel.devices.isNotEmpty;
      return _SupportEmptyState(
        icon: hasData ? Icons.search_off : Icons.devices_other_outlined,
        title: hasData
            ? 'Brak pasujących urządzeń'
            : 'Książka adresowa jest pusta',
        message: hasData
            ? 'Zmień wyszukiwanie lub filtr, aby zobaczyć inne urządzenia.'
            : 'Dodaj pierwsze urządzenie, aby szybko łączyć się z pomocą.',
        action: hasData
            ? null
            : FilledButton.icon(
                onPressed: () => showSupportDeviceDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Dodaj urządzenie'),
              ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: devices.length + 1,
      itemBuilder: (_, index) {
        if (index == 0) {
          final title = customer?.name ?? 'Urządzenia';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$title • ${devices.length}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (query.isNotEmpty)
                  Text('wyniki wyszukiwania',
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          );
        }
        return _buildDevice(devices[index - 1]);
      },
    );
  }

  Widget _customerMenu(SupportCustomer customer) {
    return PopupMenuButton<String>(
      tooltip: 'Opcje klienta',
      onSelected: (action) async {
        if (action == 'add') {
          await showSupportDeviceDialog(context,
              initialCustomerId: customer.id);
        } else if (action == 'delete') {
          await _deleteCustomer(customer);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'add', child: Text('Dodaj urządzenie')),
        PopupMenuItem(value: 'delete', child: Text('Usuń klienta')),
      ],
    );
  }

  Widget _buildDevice(SupportDevice device) {
    final critical = device.isCritical || device.warning.isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: critical ? Theme.of(context).colorScheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 940;
            final identity = _buildDeviceIdentity(device, critical);
            final details = _buildDeviceDetails(device);
            return Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 36),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 5, child: identity),
                            const SizedBox(width: 16),
                            Expanded(flex: 7, child: details),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            identity,
                            const SizedBox(height: 12),
                            details,
                          ],
                        ),
                ),
                Positioned(top: 0, right: 0, child: _deviceMenu(device)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildDeviceIdentity(SupportDevice device, bool critical) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(device.deviceType == 'server'
                  ? Icons.dns_outlined
                  : Icons.computer_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.name,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text('${device.customerName} • ID ${device.rustdeskId}'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _deviceBadge(device.online ? 'Online' : 'Offline',
                  device.online ? Colors.green : Colors.grey),
              _deviceBadge(
                  device.deviceType == 'server' ? 'Serwer' : 'Komputer',
                  Theme.of(context).colorScheme.primary),
              if (device.isInstalled != null)
                _deviceBadge(
                  device.isInstalled! ? 'Zainstalowany' : 'Przenośny',
                  Theme.of(context).colorScheme.secondary,
                ),
              if (critical)
                _deviceBadge('Uwaga', Theme.of(context).colorScheme.error),
            ],
          ),
          if (device.hostname.isNotEmpty ||
              device.remoteUsername.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              [
                if (device.hostname.isNotEmpty) 'Host: ${device.hostname}',
                if (device.remoteUsername.isNotEmpty)
                  'Użytkownik: ${device.remoteUsername}',
              ].join(' • '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (device.note.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              device.note,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (critical && device.warning.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              device.warning,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => connectInPeerTab(
                  context, device.toPeer(), PeerTabIndex.supportBook),
              icon: const Icon(Icons.link),
              label: const Text('Połącz'),
            ),
          ),
        ],
      );

  Widget _buildDeviceDetails(SupportDevice device) => LayoutBuilder(
        builder: (context, constraints) {
          final twoColumns = constraints.maxWidth >= 520;
          final tileWidth = twoColumns
              ? (constraints.maxWidth - 8) / 2
              : constraints.maxWidth;
          final display =
              device.displayWidth != null && device.displayHeight != null
                  ? '${device.displayWidth} × ${device.displayHeight}'
                  : 'Brak rozdzielczości';
          final displays = device.displayCount == null
              ? 'Liczba ekranów nieznana'
              : '${device.displayCount} ${_displayCountLabel(device.displayCount!)}';
          final lastSession = device.lastConnectedAt == null
              ? 'Brak historii połączeń'
              : 'Sesja: ${_formatSupportDate(device.lastConnectedAt)}';
          final technician = device.lastConnectedByName.isEmpty
              ? ''
              : 'Technik: ${device.lastConnectedByName}';
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _deviceInfoTile(
                width: tileWidth,
                icon: Icons.computer_outlined,
                label: 'System',
                primary: device.platform.isEmpty
                    ? 'Brak danych o systemie'
                    : device.platform,
                secondary: device.hostname.isEmpty ? '' : device.hostname,
              ),
              _deviceInfoTile(
                width: tileWidth,
                icon: Icons.monitor_outlined,
                label: 'Ekrany i klient',
                primary: '$displays • $display',
                secondary: device.rustdeskVersion.isEmpty
                    ? 'Wersja RustDesk nieznana'
                    : 'RustDesk ${device.rustdeskVersion}',
              ),
              _deviceInfoTile(
                width: tileWidth,
                icon: Icons.history,
                label: 'Aktywność',
                primary: device.lastSeen == null
                    ? 'Brak danych o aktywności'
                    : 'Widziany: ${_formatSupportDate(device.lastSeen)}',
                secondary: [lastSession, technician]
                    .where((v) => v.isNotEmpty)
                    .join(' • '),
              ),
              _deviceInfoTile(
                width: tileWidth,
                icon: Icons.settings_applications_outlined,
                label: 'Uruchomienie',
                primary: device.isInstalled == null
                    ? 'Tryb uruchomienia nieznany'
                    : device.isInstalled!
                        ? 'Klient zainstalowany'
                        : 'Tryb przenośny',
                secondary: device.isHeadless == null
                    ? ''
                    : device.isHeadless!
                        ? 'Bez monitora'
                        : 'Monitor dostępny',
              ),
            ],
          );
        },
      );

  String _displayCountLabel(int count) {
    if (count == 1) return 'ekran';
    final lastTwoDigits = count % 100;
    final lastDigit = count % 10;
    if (lastTwoDigits < 12 || lastTwoDigits > 14) {
      if (lastDigit >= 2 && lastDigit <= 4) return 'ekrany';
    }
    return 'ekranów';
  }

  Widget _deviceInfoTile({
    required double width,
    required IconData icon,
    required String label,
    required String primary,
    required String secondary,
  }) =>
      Container(
        width: width,
        constraints: const BoxConstraints(minHeight: 88),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16),
                const SizedBox(width: 7),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              primary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (secondary.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                secondary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      );

  Widget _deviceBadge(String label, Color color) => Chip(
        avatar: Icon(Icons.circle, color: color, size: 10),
        label: Text(label),
        visualDensity: VisualDensity.compact,
      );

  Widget _deviceMenu(SupportDevice device) => PopupMenuButton<String>(
        tooltip: 'Opcje urządzenia',
        onSelected: (action) async {
          if (action == 'card') {
            await _showDeviceCard(device);
          } else if (action == 'edit') {
            await showSupportDeviceDialog(context, device: device);
          } else if (action == 'delete') {
            await _deleteDevice(device);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'card', child: Text('Karta urządzenia')),
          PopupMenuItem(value: 'edit', child: Text('Edytuj')),
          PopupMenuItem(value: 'delete', child: Text('Usuń')),
        ],
      );

  bool _matchesCustomer(SupportCustomer customer, String query) =>
      query.isEmpty ||
      customer.name.toLowerCase().contains(query) ||
      customer.note.toLowerCase().contains(query);

  bool _matchesDevice(SupportDevice device, String query) {
    if (query.isEmpty) return true;
    var customerNote = '';
    for (final customer in supportAddressBookModel.customers) {
      if (customer.id == device.customerId) {
        customerNote = customer.note;
        break;
      }
    }
    return [
      device.customerName,
      customerNote,
      device.name,
      device.rustdeskId,
      device.hostname,
      device.remoteUsername,
      device.note,
    ].any((value) => value.toLowerCase().contains(query));
  }

  bool _matchesFilter(SupportDevice device) {
    switch (_filter) {
      case _SupportDeviceFilter.all:
        return true;
      case _SupportDeviceFilter.online:
        return device.online;
      case _SupportDeviceFilter.offline:
        return !device.online;
      case _SupportDeviceFilter.servers:
        return device.deviceType == 'server';
      case _SupportDeviceFilter.computers:
        return device.deviceType != 'server';
    }
  }

  int _compareDevices(SupportDevice left, SupportDevice right) {
    if (left.online != right.online) return left.online ? -1 : 1;
    final recent =
        (right.lastConnectedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(
                left.lastConnectedAt ?? DateTime.fromMillisecondsSinceEpoch(0));
    if (recent != 0) return recent;
    final name = left.name.toLowerCase().compareTo(right.name.toLowerCase());
    return name != 0
        ? name
        : left.customerName
            .toLowerCase()
            .compareTo(right.customerName.toLowerCase());
  }

  Future<void> _showDeviceCard(SupportDevice device) async {
    try {
      final card = await supportAddressBookModel.deviceCard(device.id);
      card.device.online = device.online;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('${card.device.customerName}: ${card.device.name}'),
          content: SizedBox(
            width: 700,
            height: 520,
            child: ListView(
              children: [
                if (card.device.isCritical || card.device.warning.isNotEmpty)
                  Card(
                    color: Theme.of(dialogContext).colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber_rounded),
                      title: const Text('Ostrzeżenie krytyczne'),
                      subtitle: Text(card.device.warning.isEmpty
                          ? 'Urządzenie oznaczono jako krytyczne.'
                          : card.device.warning),
                    ),
                  ),
                _cardRow('ID RustDesk', card.device.rustdeskId),
                _cardRow('Status', card.device.online ? 'online' : 'offline'),
                _cardRow('Ostatnio widziany',
                    _formatSupportDate(card.device.lastSeen)),
                _cardRow('Hostname', card.device.hostname),
                _cardRow('Użytkownik', card.device.remoteUsername),
                _cardRow('System', card.device.platform),
                _cardRow('Wersja RustDesk', card.device.rustdeskVersion),
                _cardRow(
                    'Monitory', card.device.displayCount?.toString() ?? ''),
                _cardRow(
                  'Rozdzielczość',
                  card.device.displayWidth == null ||
                          card.device.displayHeight == null
                      ? ''
                      : '${card.device.displayWidth} × ${card.device.displayHeight}',
                ),
                _cardRow(
                  'Tryb bez monitora',
                  card.device.isHeadless == null
                      ? ''
                      : card.device.isHeadless!
                          ? 'tak'
                          : 'nie',
                ),
                _cardRow(
                  'Instalacja RustDesk',
                  card.device.isInstalled == null
                      ? ''
                      : card.device.isInstalled!
                          ? 'zainstalowany'
                          : 'niezainstalowany',
                ),
                _cardRow('Ostatni technik', card.device.lastConnectedByName),
                _cardRow('Ostatnia sesja',
                    _formatSupportDate(card.device.lastConnectedAt)),
                if (card.device.note.isNotEmpty)
                  _cardRow('Notatka', card.device.note),
                const Divider(height: 28),
                Text('Historia sesji',
                    style: Theme.of(dialogContext).textTheme.titleMedium),
                if (card.sessions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Brak zarejestrowanych sesji.'),
                  )
                else
                  ...card.sessions.map(
                    (session) => ListTile(
                      dense: true,
                      leading: Icon(session.active ? Icons.link : Icons.history,
                          color: session.active ? Colors.green : null),
                      title: Text(
                        session.technician?.displayName.isNotEmpty == true
                            ? session.technician!.displayName
                            : session.technician?.username ??
                                'Nieznany technik',
                      ),
                      subtitle: Text(
                        '${_formatSupportDate(session.startedAt)}'
                        '${session.endedAt == null ? ' • aktywna' : ' – ${_formatSupportDate(session.endedAt)}'}'
                        '${session.durationSeconds > 0 ? ' • ${_formatSessionDuration(Duration(seconds: session.durationSeconds))}' : ''}'
                        '${session.technicianDeviceName.isEmpty ? '' : '\n${session.technicianDeviceName}'}'
                        '${session.note.isEmpty ? '' : '\n${session.note}'}',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Zamknij'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                connectInPeerTab(
                    context, card.device.toPeer(), PeerTabIndex.supportBook);
              },
              icon: const Icon(Icons.link),
              label: const Text('Połącz'),
            ),
          ],
        ),
      );
    } catch (error) {
      _showError(error);
    }
  }

  Widget _cardRow(String label, String value) => value.isEmpty
      ? const SizedBox.shrink()
      : ListTile(dense: true, title: Text(label), subtitle: Text(value));

  Future<void> _deleteDevice(SupportDevice device) async {
    final confirmed = await _confirm(
      context,
      'Usunąć urządzenie?',
      '${device.customerName}: ${device.name} (${device.rustdeskId})',
    );
    if (!confirmed) return;
    try {
      await supportAddressBookModel.deleteDevice(device);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _deleteCustomer(SupportCustomer customer) async {
    final confirmed = await _confirm(
      context,
      'Usunąć klienta?',
      'Klient „${customer.name}” oraz wszystkie jego urządzenia trafią do kosza.',
    );
    if (!confirmed) return;
    try {
      await supportAddressBookModel.deleteCustomer(customer);
    } catch (error) {
      _showError(error);
    }
  }
}

class _SupportEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const _SupportEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 48, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      );
}

String _formatSupportDate(DateTime? value) {
  if (value == null) return '';
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String message,
) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Usuń'),
            ),
          ],
        ),
      ) ??
      false;
}

Future<void> showSupportDeviceDialog(
  BuildContext context, {
  SupportDevice? device,
  String? rustdeskId,
  String? initialCustomerId,
}) async {
  final idController =
      TextEditingController(text: device?.rustdeskId ?? rustdeskId ?? '');
  final nameController = TextEditingController(text: device?.name ?? '');
  final noteController = TextEditingController(text: device?.note ?? '');
  final newCustomerController = TextEditingController();
  String? customerId = device?.customerId ??
      initialCustomerId ??
      (supportAddressBookModel.customers.isEmpty
          ? null
          : supportAddressBookModel.customers.first.id);
  if (customerId != null &&
      !supportAddressBookModel.customers
          .any((customer) => customer.id == customerId)) {
    customerId = null;
  }
  var deviceType = device?.deviceType ?? 'computer';
  var saving = false;
  String? errorMessage;

  await showDialog<void>(
    context: context,
    barrierDismissible: !saving,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(device == null ? 'Dodaj urządzenie' : 'Edytuj urządzenie'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: customerId ?? _newSupportCustomerValue,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Klient'),
                  items: [
                    ...supportAddressBookModel.customers.map(
                      (customer) => DropdownMenuItem(
                        value: customer.id,
                        child: Text(customer.name),
                      ),
                    ),
                    const DropdownMenuItem(
                      value: _newSupportCustomerValue,
                      child: Text('+ Utwórz nowego klienta'),
                    ),
                  ],
                  onChanged: saving
                      ? null
                      : (value) => setDialogState(() {
                            customerId = value == _newSupportCustomerValue
                                ? null
                                : value;
                          }),
                ),
                if (customerId == null) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: newCustomerController,
                    enabled: !saving,
                    autofocus: supportAddressBookModel.customers.isEmpty,
                    decoration: const InputDecoration(
                      labelText: 'Nazwa nowego klienta',
                      helperText:
                          'Klient zostanie utworzony razem z urządzeniem.',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: idController,
                  enabled: !saving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'ID RustDesk'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  enabled: !saving,
                  decoration: const InputDecoration(labelText: 'Nazwa'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: deviceType,
                  decoration: const InputDecoration(labelText: 'Typ'),
                  items: const [
                    DropdownMenuItem(
                        value: 'computer', child: Text('Komputer')),
                    DropdownMenuItem(value: 'server', child: Text('Serwer')),
                  ],
                  onChanged: saving
                      ? null
                      : (value) => setDialogState(
                          () => deviceType = value ?? 'computer'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  enabled: !saving,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Notatka'),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      errorMessage!,
                      style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(dialogContext),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    final id = idController.text.trim();
                    final name = nameController.text.trim();
                    final newCustomer = customerId == null
                        ? newCustomerController.text.trim()
                        : '';
                    if (!RegExp(r'^\d+$').hasMatch(id)) {
                      setDialogState(
                          () => errorMessage = 'ID musi zawierać tylko cyfry.');
                      return;
                    }
                    if (name.isEmpty) {
                      setDialogState(
                          () => errorMessage = 'Podaj nazwę urządzenia.');
                      return;
                    }
                    if (customerId == null && newCustomer.isEmpty) {
                      setDialogState(
                          () => errorMessage = 'Wybierz lub utwórz klienta.');
                      return;
                    }
                    setDialogState(() {
                      saving = true;
                      errorMessage = null;
                    });
                    try {
                      var selectedCustomerId = customerId;
                      selectedCustomerId ??= (await supportAddressBookModel
                              .createCustomer(newCustomer))
                          .id;
                      if (device == null) {
                        await supportAddressBookModel.createDevice(
                          customerId: selectedCustomerId,
                          rustdeskId: id,
                          name: name,
                          note: noteController.text,
                          deviceType: deviceType,
                        );
                      } else {
                        await supportAddressBookModel.updateDevice(
                          device: device,
                          customerId: selectedCustomerId,
                          rustdeskId: id,
                          name: name,
                          note: noteController.text,
                          deviceType: deviceType,
                        );
                      }
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    } catch (error) {
                      if (dialogContext.mounted) {
                        setDialogState(() {
                          saving = false;
                          errorMessage = error.toString();
                        });
                      }
                    }
                  },
            child: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(device == null ? 'Dodaj' : 'Zapisz'),
          ),
        ],
      ),
    ),
  );

  idController.dispose();
  nameController.dispose();
  noteController.dispose();
  newCustomerController.dispose();
}

class _SupportSessionResult {
  final String outcome;
  final String note;
  final String ticketReference;

  const _SupportSessionResult({
    required this.outcome,
    required this.note,
    required this.ticketReference,
  });
}

Future<_SupportSessionResult?> _showSupportSessionResultDialog(
  BuildContext context,
  SupportPostSessionPrompt prompt,
) async {
  final noteController = TextEditingController();
  final ticketController = TextEditingController();
  var outcome = 'pending';
  try {
    return await showDialog<_SupportSessionResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Zakończenie sesji'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: supportAddressBookModel,
                  builder: (_, __) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule),
                    title: Text(
                        'Czas sesji: ${_formatSessionDuration(prompt.duration)}'),
                    subtitle: Text(_sessionSyncLabel(prompt.supportSessionId)),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Wynik, notatka i czas sesji trafią do RDBK oraz przeglądu pracy.',
                  ),
                ),
                DropdownButtonFormField<String>(
                  value: outcome,
                  decoration: const InputDecoration(labelText: 'Wynik'),
                  items: const [
                    DropdownMenuItem(
                      value: 'pending',
                      child: Text('Nieuzupełniony'),
                    ),
                    DropdownMenuItem(
                      value: 'resolved',
                      child: Text('Rozwiązano'),
                    ),
                    DropdownMenuItem(
                      value: 'follow_up',
                      child: Text('Wymaga dalszych prac'),
                    ),
                    DropdownMenuItem(
                      value: 'escalated',
                      child: Text('Przekazano dalej'),
                    ),
                  ],
                  onChanged: (value) => setDialogState(
                    () => outcome = value ?? 'pending',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  minLines: 3,
                  maxLength: 4000,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Notatka z sesji',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ticketController,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Numer zgłoszenia (opcjonalnie)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Bez podsumowania'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _SupportSessionResult(
                  outcome: outcome,
                  note: noteController.text,
                  ticketReference: ticketController.text,
                ),
              ),
              child: const Text('Zapisz wynik'),
            ),
          ],
        ),
      ),
    );
  } finally {
    noteController.dispose();
    ticketController.dispose();
  }
}

String _formatSessionDuration(Duration duration) {
  final seconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final hours = seconds ~/ Duration.secondsPerHour;
  final minutes =
      (seconds % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;
  final remainingSeconds = seconds % Duration.secondsPerMinute;
  if (hours > 0) return '$hours godz. $minutes min';
  if (minutes > 0) return '$minutes min $remainingSeconds s';
  return '$remainingSeconds s';
}

String _sessionSyncLabel(String? sessionId) {
  if (sessionId == null || sessionId.isEmpty) {
    return 'Synchronizacja: brak rekordu sesji';
  }
  switch (supportAddressBookModel.syncStatusForSession(sessionId)) {
    case SupportSessionSyncStatus.waiting:
      return 'Synchronizacja: oczekuje na połączenie z RDBK';
    case SupportSessionSyncStatus.syncing:
      return 'Synchronizacja: wysyłanie do RDBK';
    case SupportSessionSyncStatus.synced:
      return 'Synchronizacja: zapisano w RDBK';
    case SupportSessionSyncStatus.failed:
      return 'Synchronizacja: ${supportAddressBookModel.syncErrorForSession(sessionId) ?? 'błąd trwały'}';
    case SupportSessionSyncStatus.signedOut:
      return 'Synchronizacja: wymagane ponowne logowanie';
  }
}

bool _showingPostSessionPrompt = false;

Future<void> queueSupportAddressBookPrompt(
  String rustdeskId, {
  SupportSessionHandle? supportSession,
  Map<String, dynamic> telemetry = const {},
}) async {
  if (supportAddressBookApiUrl.trim().isEmpty ||
      !supportAddressBookModel.isAuthenticated) {
    return;
  }
  final endedAt = DateTime.now().toUtc();
  await supportAddressBookModel.enqueuePostSessionPrompt(
    SupportPostSessionPrompt(
      id: supportSession?.id ?? '$rustdeskId-${endedAt.microsecondsSinceEpoch}',
      rustdeskId: rustdeskId,
      supportSessionId: supportSession?.id,
      startedAt: supportSession?.startedAt ?? endedAt,
      endedAt: endedAt,
      telemetry: Map<String, dynamic>.from(telemetry),
    ),
  );
}

Future<void> showPendingSupportAddressBookPrompt() async {
  if (_showingPostSessionPrompt || supportAddressBookApiUrl.trim().isEmpty) {
    return;
  }
  await supportAddressBookModel.ensureInitialized();
  await supportAddressBookModel.reloadPostSessionState();
  if (!supportAddressBookModel.isAuthenticated ||
      supportAddressBookModel.postSessionPrompts.isEmpty) {
    return;
  }
  final navigator = globalKey.currentState;
  final context = navigator?.context;
  if (context == null || !context.mounted) return;
  final prompt = supportAddressBookModel.postSessionPrompts.first;
  _showingPostSessionPrompt = true;
  var completed = false;
  try {
    final existing = await supportAddressBookModel.lookup(prompt.rustdeskId);
    if (_supportSessionSummaryPromptsEnabled &&
        prompt.supportSessionId != null) {
      final result = await _showSupportSessionResultDialog(context, prompt);
      if (result != null) {
        await supportAddressBookModel.updateSupportSessionResult(
          prompt.supportSessionId!,
          outcome: result.outcome,
          note: result.note,
          ticketReference: result.ticketReference,
        );
      }
    }
    if (existing != null) {
      await supportAddressBookModel.completePostSessionPrompt(prompt.id);
      completed = true;
      return;
    }
    final currentContext = globalKey.currentState?.context;
    if (currentContext == null || !currentContext.mounted) return;
    final shouldEdit = await showDialog<bool>(
          context: currentContext,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Dodać do książki adresowej?'),
            content: Text(
              'Zakończono sesję z nieznanym urządzeniem ${prompt.rustdeskId}. '
              'Czy dodać je do wspólnej książki?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Nie'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Dodaj'),
              ),
            ],
          ),
        ) ??
        false;
    final editContext = globalKey.currentState?.context;
    if (shouldEdit && editContext != null && editContext.mounted) {
      await showSupportDeviceDialog(
        editContext,
        rustdeskId: prompt.rustdeskId,
      );
    }
    await supportAddressBookModel.completePostSessionPrompt(prompt.id);
    completed = true;
  } catch (error) {
    debugPrint('Support address book post-session prompt failed: $error');
  } finally {
    _showingPostSessionPrompt = false;
    if (!completed && supportAddressBookModel.isAuthenticated) {
      Timer(const Duration(seconds: 15),
          () => unawaited(showPendingSupportAddressBookPrompt()));
    } else if (supportAddressBookModel.postSessionPrompts.isNotEmpty) {
      unawaited(showPendingSupportAddressBookPrompt());
    }
  }
}
