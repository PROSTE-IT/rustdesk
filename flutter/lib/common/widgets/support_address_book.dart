import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/peer_card.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/models/support_address_book_model.dart';

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
    final customers = supportAddressBookModel.customers.where((customer) {
      if (query.isEmpty ||
          customer.name.toLowerCase().contains(query) ||
          customer.note.toLowerCase().contains(query)) {
        return true;
      }
      return supportAddressBookModel.devicesFor(customer.id).any((device) =>
          device.name.toLowerCase().contains(query) ||
          device.rustdeskId.contains(query) ||
          device.note.toLowerCase().contains(query));
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 12, bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Szukaj klienta, urządzenia, ID lub notatki',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Dodaj urządzenie',
                child: IconButton.filledTonal(
                  onPressed: () => showSupportDeviceDialog(context),
                  icon: const Icon(Icons.add),
                ),
              ),
              Tooltip(
                message: 'Odśwież',
                child: IconButton(
                  onPressed:
                      supportAddressBookModel.loading ? null : () => _refresh(),
                  icon: const Icon(Icons.refresh),
                ),
              ),
              Tooltip(
                message: 'Wyloguj',
                child: IconButton(
                  onPressed: () =>
                      unawaited(supportAddressBookModel.logout()),
                  icon: const Icon(Icons.logout),
                ),
              ),
            ],
          ),
        ),
        if (supportAddressBookModel.loading)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: customers.isEmpty
              ? Center(
                  child: Text(query.isEmpty
                      ? 'Książka adresowa jest pusta.'
                      : 'Brak wyników wyszukiwania.'),
                )
              : ListView.builder(
                  itemCount: customers.length,
                  itemBuilder: (context, index) =>
                      _buildCustomer(customers[index], query),
                ),
        ),
      ],
    );
  }

  Widget _buildCustomer(SupportCustomer customer, String query) {
    final devices = supportAddressBookModel
        .devicesFor(customer.id)
        .where((device) =>
            query.isEmpty ||
            customer.name.toLowerCase().contains(query) ||
            device.name.toLowerCase().contains(query) ||
            device.rustdeskId.contains(query) ||
            device.note.toLowerCase().contains(query))
        .toList();
    return Card(
      margin: const EdgeInsets.only(right: 12, bottom: 8),
      child: ExpansionTile(
        initiallyExpanded: query.isNotEmpty,
        leading: const Icon(Icons.business),
        title: Text(customer.name),
        subtitle: Text(
          '${devices.length} ${devices.length == 1 ? 'urządzenie' : 'urządzeń'}'
          '${customer.note.isEmpty ? '' : ' • ${customer.note}'}',
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) async {
            if (action == 'add') {
              await showSupportDeviceDialog(
                context,
                initialCustomerId: customer.id,
              );
            } else if (action == 'delete') {
              await _deleteCustomer(customer);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'add', child: Text('Dodaj urządzenie')),
            PopupMenuItem(
              value: 'delete',
              child: Text('Usuń klienta'),
            ),
          ],
        ),
        children: devices.map(_buildDevice).toList(),
      ),
    );
  }

  Widget _buildDevice(SupportDevice device) {
    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(device.deviceType == 'server'
              ? Icons.dns_outlined
              : Icons.computer),
          Positioned(
            right: -2,
            bottom: -2,
            child: CircleAvatar(
              radius: 5,
              backgroundColor: device.online ? Colors.green : Colors.grey,
            ),
          ),
        ],
      ),
      title: Text(device.name),
      subtitle: Text(
        '${device.rustdeskId} • '
        '${device.deviceType == 'server' ? 'Serwer' : 'Komputer'} • '
        '${device.online ? 'online' : 'offline'}'
        '${device.lastSeen == null ? '' : ' • ostatnio ${_formatSupportDate(device.lastSeen)}'}'
        '${device.note.isEmpty ? '' : '\n${device.note}'}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => connectInPeerTab(
        context,
        device.toPeer(),
        PeerTabIndex.supportBook,
      ),
      trailing: PopupMenuButton<String>(
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
          PopupMenuItem(value: 'edit', child: Text('Edytuj')),
          PopupMenuItem(value: 'card', child: Text('Karta urządzenia')),
          PopupMenuItem(value: 'delete', child: Text('Usuń')),
        ],
      ),
    );
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
                _cardRow('Monitory', card.device.displayCount?.toString() ?? ''),
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
                            : session.technician?.username ?? 'Nieznany technik',
                      ),
                      subtitle: Text(
                        '${_formatSupportDate(session.startedAt)}'
                        '${session.endedAt == null ? ' • aktywna' : ' – ${_formatSupportDate(session.endedAt)}'}'
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
                connectInPeerTab(context, card.device.toPeer(),
                    PeerTabIndex.supportBook);
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
                  value: customerId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Klient'),
                  items: supportAddressBookModel.customers
                      .map((customer) => DropdownMenuItem(
                            value: customer.id,
                            child: Text(customer.name),
                          ))
                      .toList(),
                  onChanged: saving
                      ? null
                      : (value) => setDialogState(() => customerId = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newCustomerController,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    labelText: 'Lub utwórz nowego klienta',
                    helperText: 'Wpisana nazwa ma pierwszeństwo przed listą.',
                  ),
                ),
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
                    final newCustomer = newCustomerController.text.trim();
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
                      if (newCustomer.isNotEmpty) {
                        selectedCustomerId = (await supportAddressBookModel
                                .createCustomer(newCustomer))
                            .id;
                      }
                      if (device == null) {
                        await supportAddressBookModel.createDevice(
                          customerId: selectedCustomerId!,
                          rustdeskId: id,
                          name: name,
                          note: noteController.text,
                          deviceType: deviceType,
                        );
                      } else {
                        await supportAddressBookModel.updateDevice(
                          device: device,
                          customerId: selectedCustomerId!,
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
          title: const Text('Podsumowanie sesji'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
              child: const Text('Pomiń'),
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

final Set<String> _pendingSessionPrompts = {};

void queueSupportAddressBookPrompt(
  String rustdeskId, {
  String? supportSessionId,
  Map<String, dynamic> telemetry = const {},
}) {
  if (supportAddressBookApiUrl.trim().isEmpty ||
      !supportAddressBookModel.isAuthenticated ||
      !_pendingSessionPrompts.add(rustdeskId)) {
    return;
  }
  SupportDevice? previous;
  for (final device in supportAddressBookModel.devices) {
    if (device.rustdeskId == rustdeskId) {
      previous = device;
      break;
    }
  }
  final differences = <String>[];
  void compare(String label, String oldValue, Object? detected) {
    final newValue = detected?.toString() ?? '';
    if (newValue.isNotEmpty && newValue != oldValue) {
      differences.add(
          '$label: ${oldValue.isEmpty ? '(brak)' : oldValue} → $newValue');
    }
  }
  if (previous != null) {
    compare('Hostname', previous.hostname, telemetry['peer_hostname']);
    compare('Użytkownik', previous.remoteUsername, telemetry['peer_username']);
    compare('System', previous.platform, telemetry['peer_platform']);
    compare('Wersja RustDesk',
        previous.rustdeskVersion, telemetry['peer_version']);
    compare('Liczba monitorów', previous.displayCount?.toString() ?? '',
        telemetry['display_count']);
  }
  Future<void>.delayed(const Duration(milliseconds: 350), () async {
    try {
      var context = globalKey.currentContext;
      if (context == null || !context.mounted) return;
      if (supportSessionId != null) {
        final result = await _showSupportSessionResultDialog(context);
        if (result != null) {
          await supportAddressBookModel.updateSupportSessionResult(
            supportSessionId,
            outcome: result.outcome,
            note: result.note,
            ticketReference: result.ticketReference,
          );
        }
      }
      final existing = await supportAddressBookModel.lookup(rustdeskId);
      context = globalKey.currentContext;
      if (context == null || !context.mounted) return;
      final shouldEdit = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(existing == null
                  ? 'Dodać do książki adresowej?'
                  : 'Zaktualizować wpis w książce?'),
              content: Text(
                existing == null
                    ? 'Zakończono sesję z urządzeniem $rustdeskId. Czy dodać je do wspólnej książki?'
                    : 'Zakończono sesję z urządzeniem ${existing.customerName}: ${existing.name} ($rustdeskId).'
                        '${differences.isEmpty ? '' : '\n\nWykryte różnice:\n${differences.join('\n')}'}'
                        '\n\nCzy otworzyć formularz i zatwierdzić aktualizację wpisu?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Nie'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(existing == null ? 'Dodaj' : 'Edytuj'),
                ),
              ],
            ),
          ) ??
          false;
      final currentContext = globalKey.currentContext;
      if (shouldEdit && currentContext != null && currentContext.mounted) {
        await showSupportDeviceDialog(
          currentContext,
          device: existing,
          rustdeskId: existing == null ? rustdeskId : null,
        );
      }
    } catch (error) {
      debugPrint('Support address book post-session prompt failed: $error');
    } finally {
      _pendingSessionPrompts.remove(rustdeskId);
    }
  });
}
