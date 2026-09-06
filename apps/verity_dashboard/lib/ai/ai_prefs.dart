import 'package:shared_preferences/shared_preferences.dart';

import 'session_brief.dart';

const kAiSelectedModel = 'openai_selected_model';
const kAiSelectedModelAccount = 'openai_selected_model_account';
const kAiContextDepth = 'openai_context_depth';

class AiPrefs {
  Future<String?> loadSelectedModel({String? accountId}) async {
    final prefs = await SharedPreferences.getInstance();
    final storedAccount = prefs.getString(kAiSelectedModelAccount);
    if (accountId != null &&
        storedAccount != null &&
        storedAccount.isNotEmpty &&
        storedAccount != accountId) {
      return null;
    }
    return prefs.getString(kAiSelectedModel);
  }

  Future<void> saveSelectedModel(String model, {String? accountId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kAiSelectedModel, model);
    if (accountId != null && accountId.isNotEmpty) {
      await prefs.setString(kAiSelectedModelAccount, accountId);
    }
  }

  Future<ContextDepth> loadDepth() async {
    final prefs = await SharedPreferences.getInstance();
    return ContextDepth.fromId(prefs.getString(kAiContextDepth));
  }

  Future<void> saveDepth(ContextDepth depth) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kAiContextDepth, depth.id);
  }

  Future<void> clearAccountModel() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kAiSelectedModel);
    await prefs.remove(kAiSelectedModelAccount);
  }
}
