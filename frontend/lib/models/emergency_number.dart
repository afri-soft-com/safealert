class EmergencyNumber {
  final String id;
  final String serviceName;
  final String serviceType;
  final String phoneNumber;
  final String icon;

  EmergencyNumber({
    required this.id,
    required this.serviceName,
    required this.serviceType,
    required this.phoneNumber,
    this.icon = '📞',
  });

  factory EmergencyNumber.fromJson(Map<String, dynamic> json) {
    return EmergencyNumber(
      id: json['id'] as String,
      serviceName: json['service_name'] as String,
      serviceType: json['service_type'] as String,
      phoneNumber: json['phone_number'] as String,
      icon: json['icon'] as String? ?? '📞',
    );
  }
}
