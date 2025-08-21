import 'package:equatable/equatable.dart';

abstract class SessionEvent extends Equatable {
  const SessionEvent();

  @override
  List<Object?> get props => [];
}

class LoginRequested extends SessionEvent {
  final String username;
  final String password;

  const LoginRequested({required this.username, required this.password});

  @override
  List<Object?> get props => [username, password];
}

class LogoutRequested extends SessionEvent {
  const LogoutRequested();

  @override
  List<Object?> get props => [];
}

class CheckSession extends SessionEvent {}

class ClearSessionError extends SessionEvent {}
