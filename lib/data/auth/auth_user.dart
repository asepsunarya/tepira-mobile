import 'package:flutter/foundation.dart';

/// The signed-in tepira user, as returned by `POST /api/mobile/session`.
@immutable
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    this.name,
    this.image,
  });

  /// Parses the `user` object of the session response. Throws
  /// [FormatException] when `id` or `email` is missing.
  factory AuthUser.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final email = json['email'];
    if (id is! String || email is! String) {
      throw const FormatException('user.id and user.email are required');
    }
    final name = json['name'];
    final image = json['image'];
    return AuthUser(
      id: id,
      email: email,
      name: name is String ? name : null,
      image: image is String ? image : null,
    );
  }

  final String id;
  final String email;
  final String? name;
  final String? image;

  Map<String, Object?> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'image': image,
      };

  @override
  bool operator ==(Object other) =>
      other is AuthUser &&
      other.id == id &&
      other.email == email &&
      other.name == name &&
      other.image == image;

  @override
  int get hashCode => Object.hash(id, email, name, image);
}
