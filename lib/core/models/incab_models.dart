class InCabOption {
  const InCabOption({required this.value, required this.label});
  factory InCabOption.fromJson(String value) {
    return InCabOption(value: value, label: value);
  }
  final String value;
  final String label;
}

class InCabQuestion {
  const InCabQuestion({
    required this.code,
    required this.text,
    required this.options,
  });

  factory InCabQuestion.fromJson(Map<String, dynamic> json) {
    final opts = (json['options'] as List<dynamic>? ?? const [])
        .map((e) => InCabOption.fromJson(e.toString()))
        .toList(growable: false);
    return InCabQuestion(
      code: json['code']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      options: opts,
    );
  }

  final String code;
  final String text;
  final List<InCabOption> options;
}

class InCabSection {
  const InCabSection({
    required this.key,
    required this.title,
    required this.items,
  });

  factory InCabSection.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? const [])
        .map((item) => InCabQuestion.fromJson(item as Map<String, dynamic>))
        .where((q) => q.code.isNotEmpty)
        .toList(growable: false);
    return InCabSection(
      key: json['key']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      items: items,
    );
  }

  final String key;
  final String title;
  final List<InCabQuestion> items;
}

class InCabAnswer {
  InCabAnswer({
    required this.sectionKey,
    required this.itemCode,
    required this.result,
    required this.questionText,
  });

  Map<String, dynamic> toJson() => {
        'section_key': sectionKey,
        'item_code': itemCode,
        'result': result,
        'question_text': questionText,
      };

  final String sectionKey;
  final String itemCode;
  final String result;
  final String questionText;
}

class InCabAssessmentRequest {
  InCabAssessmentRequest({
    required this.driverId,
    required this.vehicleId,
    this.plantId,
    this.assessorUserId,
    this.transporterName,
    this.weather,
    this.locationText,
    this.startTime,
    this.endTime,
    required this.assessmentDate,
    this.overallNotes,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
        'driver_id': driverId,
        'vehicle_id': vehicleId,
        if (plantId != null) 'plant_id': plantId,
        if (assessorUserId != null) 'assessor_user_id': assessorUserId,
        if (transporterName != null) 'transporter_name': transporterName,
        if (weather != null) 'weather': weather,
        if (locationText != null) 'location_text': locationText,
        if (startTime != null) 'start_time': startTime,
        if (endTime != null) 'end_time': endTime,
        'assessment_date': assessmentDate,
        if (overallNotes != null) 'overall_notes': overallNotes,
        'items': items.map((e) => e.toJson()).toList(),
      };

  final int driverId;
  final int vehicleId;
  final int? plantId;
  final int? assessorUserId;
  final String? transporterName;
  final String? weather;
  final String? locationText;
  final String? startTime;
  final String? endTime;
  final String assessmentDate;
  final String? overallNotes;
  final List<InCabAnswer> items;
}
