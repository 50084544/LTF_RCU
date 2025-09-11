import 'package:equatable/equatable.dart';

abstract class SessionState extends Equatable {
  const SessionState();

  @override
  List<Object?> get props => [];
}

class SessionInitial extends SessionState {}

class SessionLoading extends SessionState {}

class SessionAuthenticated extends SessionState {
  final Map<String, dynamic> user;
  final String token;

  const SessionAuthenticated({required this.user, required this.token});

  @override
  List<Object?> get props => [user, token];
}

class SessionUnauthenticated extends SessionState {
  final String? message;

  const SessionUnauthenticated({this.message});

  @override
  List<Object?> get props => [message];
}

class SessionError extends SessionState {
  final String message;

  const SessionError(this.message);

  @override
  List<Object?> get props => [message];
}
