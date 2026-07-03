class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    this.githubRepository = 'AlvinPradanaAntony/tonztoon_komik-vibecode',
    this.googleWebClientId,
    this.googleIosClientId,
  });

  factory AppConfig.fromEnvironment() {
    const configured = String.fromEnvironment('API_BASE_URL');
    const githubRepository = String.fromEnvironment(
      'GITHUB_REPOSITORY',
      defaultValue: 'AlvinPradanaAntony/tonztoon_komik-vibecode',
    );
    const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
    const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
    return const AppConfig(
      apiBaseUrl: configured == ''
          ? 'http://192.168.1.5:8000/api/v1'
          : configured,
      githubRepository: githubRepository,
      googleWebClientId: googleWebClientId == ''
          ? '141514991123-gs9a9hvbio055asv25bbrbeiaa98r65u.apps.googleusercontent.com'
          : googleWebClientId,
      googleIosClientId: googleIosClientId == ''
          ? '141514991123-but26c4bjmrsm9qssq377kl81su3kd7j.apps.googleusercontent.com'
          : googleIosClientId,
    );
  }

  final String apiBaseUrl;
  final String githubRepository;
  final String? googleWebClientId;
  final String? googleIosClientId;

  bool get hasGoogleAuthConfig => _hasValue(googleWebClientId);

  static bool _hasValue(String? value) =>
      value != null && value.trim().isNotEmpty;
}
