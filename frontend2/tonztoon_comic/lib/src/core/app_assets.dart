/// [AppAssets] adalah pusat pengelolaan gambar statis (assets).
/// Sama seperti ikon, memusatkan path aset di sini menghindari kesalahan pengetikan (typo)
/// saat memanggil gambar di dalam Widget.
class AppAssets {
  // Pastikan untuk menambahkan gambar ini ke dalam folder yang sesuai
  // dan mendaftarkannya di pubspec.yaml nantinya.
  static const logoApp = 'lib/src/assets/logo_app_250px.png';
  static const logoAppLarge = 'lib/src/assets/logo_app_lg_250px.png';
  static const logoAppSplash = 'lib/src/assets/logo_app_sm_500px.png';
  
  static const onboarding1 = 'assets/images/onboarding_1.png';
  static const onboarding2 = 'assets/images/onboarding_2.png';
  static const onboarding3 = 'assets/images/onboarding_3.png';
}
