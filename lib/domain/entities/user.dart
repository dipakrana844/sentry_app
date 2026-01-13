class User {
  final String id;
  final String email;
  final String role;
  final String? token;

  const User({
    required this.id,
    required this.email,
    required this.role,
    this.token,
  });
}
