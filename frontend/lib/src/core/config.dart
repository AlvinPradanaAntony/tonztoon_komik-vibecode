class AppConfig {
  const AppConfig({required this.apiBaseUrl});

  factory AppConfig.fromEnvironment() {
    const configured = String.fromEnvironment('API_BASE_URL');
    return const AppConfig(
      apiBaseUrl: configured == ''
          ? 'http://192.168.1.3:8000/api/v1'
          : configured,
    );
  }

  final String apiBaseUrl;
}
