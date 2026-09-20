import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';

class TestSettings extends SettingsService {
  // Tests exercise room collection operations without network/platform services.
  @override
  // Deliberately skip production scheduler/network initialization in this fixture.
  // ignore: must_call_super
  void onInit() {}
}

Future<TestSettings> createSettingsFixture() async {
  final directory = await Directory.systemTemp.createTemp('tv-settings-test-');
  Hive.init(directory.path);
  await HivePrefUtil.init();
  final settings = TestSettings();
  settings.autoRefreshFavorite.value = false;
  Get.put<SettingsService>(settings);
  addTearDown(() async {
    Get.reset();
    await Hive.close();
    await directory.delete(recursive: true);
  });
  return settings;
}
