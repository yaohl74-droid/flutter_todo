import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS Debug 在沙盒中声明钥匙串和出站网络权限', () {
    final entitlements = File(
      'macos/Runner/DebugProfile.entitlements',
    ).readAsStringSync();

    expect(entitlements, contains('com.apple.security.app-sandbox'));
    expect(entitlements, contains('com.apple.security.network.client'));
    expect(entitlements, contains('keychain-access-groups'));
    expect(
      entitlements,
      contains(r'$(AppIdentifierPrefix)$(CFBundleIdentifier)'),
    );
  });

  test('macOS Release 保留沙盒并声明钥匙串和出站网络权限', () {
    final entitlements = File(
      'macos/Runner/Release.entitlements',
    ).readAsStringSync();

    expect(entitlements, contains('com.apple.security.app-sandbox'));
    expect(entitlements, contains('com.apple.security.network.client'));
    expect(entitlements, contains('keychain-access-groups'));
    expect(
      entitlements,
      contains(r'$(AppIdentifierPrefix)$(CFBundleIdentifier)'),
    );
  });
}
