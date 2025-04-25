class PeigonUserDetails {
  final String name;
  final String email;

  PeigonUserDetails({required this.name, required this.email});

  factory PeigonUserDetails.fromMap(Map<String, dynamic> map) {
    return PeigonUserDetails(
      name: map['name'] as String,
      email: map['email'] as String,
    );
  }
}
