enum HelpdeskCategory { review, report }

extension HelpdeskCategoryApi on HelpdeskCategory {
  String get apiValue => name;
}

class HelpdeskSubmissionDraft {
  const HelpdeskSubmissionDraft({
    required this.category,
    required this.message,
    this.rating,
    this.title,
    this.clientContext,
  });

  final HelpdeskCategory category;
  final int? rating;
  final String? title;
  final String message;
  final Map<String, dynamic>? clientContext;
}

class HelpdeskSubmissionReceipt {
  const HelpdeskSubmissionReceipt({
    required this.id,
    required this.referenceCode,
    required this.category,
    required this.status,
    required this.createdAt,
  });

  factory HelpdeskSubmissionReceipt.fromJson(Map<String, dynamic> json) {
    return HelpdeskSubmissionReceipt(
      id: json['id'] as String? ?? '',
      referenceCode: json['reference_code'] as String? ?? '',
      category: HelpdeskCategory.values.firstWhere(
        (value) => value.apiValue == json['category'],
        orElse: () => HelpdeskCategory.report,
      ),
      status: json['status'] as String? ?? 'open',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final String id;
  final String referenceCode;
  final HelpdeskCategory category;
  final String status;
  final DateTime createdAt;
}
