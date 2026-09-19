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
    if (supportAddressBookModel.isAuthenticated) {
      unawaited(_refresh());
    }
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
                  onPressed: supportAddressBookModel.logout,
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
        '${device.deviceType == 'server' ? 'Serwer' : 'Komputer'}'
        '${device.note.isEmpty ? '' : '\n${device.note}'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => connectInPeerTab(
        context,
        device.toPeer(),
        PeerTabIndex.supportBook,
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (action) async {
          if (action == 'edit') {
            await showSupportDeviceDialog(context, device: device);
          } else if (action == 'delete') {
            await _deleteDevice(device);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Edytuj')),
          PopupMenuItem(value: 'delete', child: Text('Usuń')),
        ],
      ),
    );
  }

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

final Set<String> _pendingSessionPrompts = {};

void queueSupportAddressBookPrompt(String rustdeskId) {
  if (supportAddressBookApiUrl.trim().isEmpty ||
      !supportAddressBookModel.isAuthenticated ||
      !_pendingSessionPrompts.add(rustdeskId)) {
    return;
  }
  Future<void>.delayed(const Duration(milliseconds: 350), () async {
    try {
      final existing = await supportAddressBookModel.lookup(rustdeskId);
      if (existing != null) return;
      final context = globalKey.currentContext;
      if (context == null || !context.mounted) return;
      final shouldAdd = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Dodać do książki adresowej?'),
              content: Text(
                  'Zakończono sesję z urządzeniem $rustdeskId. Czy dodać je do wspólnej książki?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Nie'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Tak'),
                ),
              ],
            ),
          ) ??
          false;
      final currentContext = globalKey.currentContext;
      if (shouldAdd && currentContext != null && currentContext.mounted) {
        await showSupportDeviceDialog(
          currentContext,
          rustdeskId: rustdeskId,
        );
      }
    } catch (error) {
      debugPrint('Support address book post-session prompt failed: $error');
    } finally {
      _pendingSessionPrompts.remove(rustdeskId);
    }
  });
}
