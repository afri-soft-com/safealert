class TrustContact {
  final String id;
  final String contactName;
  final String contactPhone;
  final String? status;
  final String? pseudo;

  TrustContact({
    required this.id,
    required this.contactName,
    required this.contactPhone,
    this.status,
    this.pseudo,
  });

  factory TrustContact.fromJson(Map<String, dynamic> json) {
    return TrustContact(
      id: json['id'] as String,
      contactName: json['contact_name'] as String,
      contactPhone: json['contact_phone'] as String,
      status: json['status'] as String?,
      pseudo: json['pseudo'] as String?,
    );
  }
}
