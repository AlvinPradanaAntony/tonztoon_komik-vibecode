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

  static const dialogAccountSetup =
      'lib/src/assets/icon_dialog/account_setup.png';
  static const dialogAuthError = 'lib/src/assets/icon_dialog/auth_error.png';
  static const dialogCloseApp = 'lib/src/assets/icon_dialog/close_app.png';
  static const dialogCloudSync = 'lib/src/assets/icon_dialog/cloudsync.png';
  static const dialogEditHeaderProfile =
      'lib/src/assets/icon_dialog/edit_header_profile.png';
  static const dialogFolder = 'lib/src/assets/icon_dialog/folder.png';
  static const dialogLogoutAccount =
      'lib/src/assets/icon_dialog/logout_account.png';
  static const dialogLogoutDeviceSession =
      'lib/src/assets/icon_dialog/logout_device_session.png';
  static const dialogPasswordSetup =
      'lib/src/assets/icon_dialog/password_setup.png';
  static const dialogSendToEmail =
      'lib/src/assets/icon_dialog/send_to_email.png';
  static const dialogTrash = 'lib/src/assets/icon_dialog/trash.png';
}
