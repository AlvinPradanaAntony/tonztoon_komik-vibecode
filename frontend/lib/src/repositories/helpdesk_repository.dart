import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/api_client.dart';
import '../models/helpdesk.dart';

class HelpdeskRepository {
  HelpdeskRepository(this._api);

  final TonztoonApi _api;

  Future<HelpdeskSubmissionReceipt> submit(
    HelpdeskSubmissionDraft draft,
  ) async {
    PackageInfo? packageInfo;
    try {
      packageInfo = await PackageInfo.fromPlatform();
    } catch (_) {
      packageInfo = null;
    }

    final response = await _api.post<Map<String, dynamic>>(
      '/helpdesk/submissions',
      data: {
        'category': draft.category.apiValue,
        'rating': draft.rating,
        'title': draft.title,
        'message': draft.message,
        'platform': _platformName(),
        'app_version': packageInfo?.version,
        'app_build': packageInfo?.buildNumber,
        'locale': PlatformDispatcher.instance.locale.toLanguageTag(),
        'client_context': {'source': 'home_helpdesk'},
      },
    );
    return HelpdeskSubmissionReceipt.fromJson(response.data ?? const {});
  }

  String _platformName() {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name;
  }
}
