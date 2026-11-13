import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api_failure.dart';
import '../data/auth_repository.dart';
import '../data/session.dart';

class AuthState extends Equatable {
  const AuthState({this.session, this.signingIn = false, this.failure});

  final Session? session;
  final bool signingIn;
  final ApiFailure? failure;

  @override
  List<Object?> get props => [session, signingIn, failure];
}

class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this._repository) : super(const AuthState());

  final AuthRepository _repository;

  Future<void> signIn(Role role, String name) async {
    emit(const AuthState(signingIn: true));
    try {
      final session = await _repository.signIn(role, name.trim());
      emit(AuthState(session: session));
    } on ApiFailure catch (failure) {
      emit(AuthState(failure: failure));
    }
  }

  void signOut() {
    _repository.signOut();
    emit(const AuthState());
  }
}
