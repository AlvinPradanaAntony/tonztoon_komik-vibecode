class AppConfig {
  const AppConfig({required this.apiBaseUrl});

  factory AppConfig.fromEnvironment() {
    const configured = String.fromEnvironment('API_BASE_URL');
    return const AppConfig(
      apiBaseUrl: configured == '' ? 'http://10.0.2.2:8000/api/v1' : configured,
    );
  }

  final String apiBaseUrl;
}
