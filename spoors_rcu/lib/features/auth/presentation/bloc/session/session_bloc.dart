import 'dart:async';
import 'package:BMS/features/auth/data/datasources/api_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive/hive.dart';
import 'session_event.dart';
import 'session_state.dart';

class SessionBloc extends Bloc<SessionEvent, SessionState> {
  final ApiService _apiService;

  SessionBloc({required ApiService apiService})
      : _apiService = apiService,
        super(SessionInitial()) {
    on<LoginRequested>(_onLoginRequested);
    on<LogoutRequested>(_onLogoutRequested);
    on<CheckSession>(_onCheckSession);
    on<ClearSessionError>(_onClearSessionError);
  }

  Future<void> _onLoginRequested(
    LoginRequested event,
    Emitter<SessionState> emit,
  ) async {
    emit(SessionLoading());
    try {
      final result = await _apiService.login(event.username, event.password);

      if (result['success']) {
        // Verify data exists
        if (result['data'] == null || result['data']['token'] == null) {
          emit(
              SessionError('Invalid response from server: missing token data'));
          return;
        }

        // Set auth token in API service (also updates Hive)
        await _apiService.setAuthToken(result['data']['token']);

        // Store username and additional data in Hive
        final box = await Hive.openBox('auth');
        await box.put('username', event.username);

        // Store access token if it exists in the response
        if (result['data']['access_token'] != null) {
          await box.put('access_token', result['data']['access_token']);
        }

        // Emit authenticated state
        emit(SessionAuthenticated(
          user: result['data']['user'] ?? {'username': event.username},
          token: result['data']['token'],
        ));
      } else {
        emit(SessionUnauthenticated(
            message: result['message'] ?? 'Unknown error occurred'));
      }
    } catch (e) {
      emit(SessionError('Login failed: ${e.toString()}'));
    }
  }

  Future<void> _onLogoutRequested(
    LogoutRequested event,
    Emitter<SessionState> emit,
  ) async {
    emit(SessionLoading());
    try {
      // Clear auth token in API service (also updates Hive)
      await _apiService.clearAuthToken();

      // Clear access token and other session data
      final box = await Hive.openBox('auth');
      await box.delete('access_token');
      await box.delete('username');
      // Don't delete the box itself to preserve settings

      emit(const SessionUnauthenticated());
    } catch (e) {
      emit(SessionError('Logout failed: ${e.toString()}'));
    }
  }

  Future<void> _onCheckSession(
    CheckSession event,
    Emitter<SessionState> emit,
  ) async {
    emit(SessionLoading());
    try {
      // Check if session is valid in API service
      final isValid = await _apiService.isSessionValid();

      if (isValid) {
        // Get current session information
        final sessionInfo = await _apiService.getCurrentSession();
        if (sessionInfo != null) {
          emit(SessionAuthenticated(
            user: sessionInfo['user'],
            token: sessionInfo['token'],
          ));
        } else {
          emit(const SessionUnauthenticated());
        }
      } else {
        emit(const SessionUnauthenticated());
      }
    } catch (e) {
      emit(SessionError('Session check failed: ${e.toString()}'));
    }
  }

  void _onClearSessionError(
    ClearSessionError event,
    Emitter<SessionState> emit,
  ) {
    if (state is SessionError) {
      emit(const SessionUnauthenticated());
    }
  }
}
