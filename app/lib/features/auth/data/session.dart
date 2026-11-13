import 'package:equatable/equatable.dart';

/// The enum names are the values the API uses.
enum Role { customer, store, courier }

class User extends Equatable {
  const User({required this.id, required this.role, required this.name});

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    role: Role.values.byName(json['role'] as String),
    name: json['name'] as String,
  );

  final String id;
  final Role role;
  final String name;

  @override
  List<Object?> get props => [id, role, name];
}

class Session extends Equatable {
  const Session({required this.token, required this.user});

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    token: json['token'] as String,
    user: User.fromJson(json['user'] as Map<String, dynamic>),
  );

  final String token;
  final User user;

  @override
  List<Object?> get props => [token, user];
}
