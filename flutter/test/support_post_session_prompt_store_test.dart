import 'dart:io';

import 'package:flutter_hbb/models/support_secure_storage_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late SupportPostSessionPromptStore sessionWindow;
  late SupportPostSessionPromptStore mainWindow;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('support-prompt-test-');
    final file = File('${directory.path}${Platform.pathSeparator}prompts.json');
    final lockFile = File('${directory.path}${Platform.pathSeparator}prompts.lock');
    sessionWindow = SupportPostSessionPromptStore(file, lockFile);
    mainWindow = SupportPostSessionPromptStore(file, lockFile);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('a stale window cannot resurrect a declined prompt', () async {
    await sessionWindow.append({'id': 'old', 'rustdesk_id': '111'});
    expect((await mainWindow.read()).single['id'], 'old');

    await sessionWindow.remove('old');
    await mainWindow.append({'id': 'new', 'rustdesk_id': '222'});

    expect((await sessionWindow.read()).map((item) => item['id']).toList(),
        ['new']);
  });

  test('dismissal updates disk even without a local queue snapshot', () async {
    await sessionWindow.append({'id': 'old', 'rustdesk_id': '111'});
    await mainWindow.remove('old');

    expect(await sessionWindow.read(), isEmpty);
  });

  test('same session prompt is only stored once', () async {
    final prompt = {'id': 'session-1', 'rustdesk_id': '111'};
    await sessionWindow.append(prompt);
    await mainWindow.append(prompt);

    expect((await sessionWindow.read()).length, 1);
  });

  test('concurrent windows retain every distinct prompt', () async {
    await Future.wait([
      sessionWindow.append({'id': 'session-1', 'rustdesk_id': '111'}),
      mainWindow.append({'id': 'session-2', 'rustdesk_id': '222'}),
    ]);

    expect((await sessionWindow.read()).map((item) => item['id']).toSet(),
        {'session-1', 'session-2'});
  });
}
