/// Where the API lives. Override with `--dart-define=API_URL=...`; the
/// Android emulator reaches the host machine at 10.0.2.2, not localhost.
const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000');
