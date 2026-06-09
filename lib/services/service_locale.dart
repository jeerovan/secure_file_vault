import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';

class LocaleProvider extends ChangeNotifier {
  Locale? _locale;

  Locale? get locale => _locale;

  LocaleProvider() {
    _loadSavedLocale();
  }

  void _loadSavedLocale() async {
    String savedLanguageCode =
        ModelSetting.get(AppString.locale.string, defaultValue: "");
    if (savedLanguageCode.isNotEmpty) {
      _locale = Locale(savedLanguageCode);
      notifyListeners();
    }
  }

  void setLocale(Locale locale) async {
    if (!L10n.all.contains(locale)) {
      return; // Prevent setting unsupported locales
    }

    _locale = locale;
    notifyListeners();

    await ModelSetting.set(AppString.locale.string, locale.languageCode);
  }

  void clearLocale() async {
    _locale = null;
    notifyListeners();

    await ModelSetting.set(AppString.locale.string, "");
  }
}

// Define your supported locales in a helper class
class L10n {
  static final all = [
    const Locale('en'),
    const Locale('hi'),
  ];
}
