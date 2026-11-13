import '../../../core/api_client.dart';
import 'session.dart';

class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  Future<Session> signIn(Role role, String name) async {
    final json = await _api.post('/auth/demo-login', body: {'role': role.name, 'name': name});
    final session = Session.fromJson(json);
    _api.token = session.token;
    return session;
  }

  void signOut() => _api.token = null;
}
