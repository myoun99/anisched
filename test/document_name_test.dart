import 'package:anisched/src/models/document.dart';
import 'package:anisched/src/services/document_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// The user types a name; the app adds `.anisched` (유저 2026-11-28).
void main() {
  test('the extension is added when left out, never doubled', () {
    expect(withDocumentExtension('/drive/일정'), '/drive/일정.anisched');
    expect(withDocumentExtension('/drive/일정.anisched'), '/drive/일정.anisched');
    expect(withDocumentExtension('일정.ANISCHED'), '일정.ANISCHED');
    expect(withDocumentExtension('v1.2'), 'v1.2.anisched');
    expect(documentFileName(' 일정 '), '일정.anisched');
    expect(documentFileName('일정.anisched'), '일정.anisched');
  });

  test('the display name drops the extension', () {
    expect(documentDisplayName('일정.anisched'), '일정');
    expect(documentDisplayName('일정.ANISCHED'), '일정');
    expect(documentDisplayName('v1.2'), 'v1.2');
    expect(documentDisplayName('일정'), '일정');
  });
}
