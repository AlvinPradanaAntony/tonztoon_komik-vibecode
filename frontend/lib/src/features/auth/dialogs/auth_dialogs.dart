part of '../auth_screen.dart';

Future<void> _showAuthFailureDialog(
  BuildContext context, {
  required String title,
  required String message,
  VoidCallback? onForgotPassword,
}) {
  final lowerTitle = title.toLowerCase();
  final isLogin = lowerTitle.contains('login');
  final isGoogle = lowerTitle.contains('google');
  final helperText = isLogin
      ? isGoogle
            ? 'Pastikan akun Google aktif, izin login disetujui, dan koneksi internet stabil.'
            : 'Periksa koneksi internet dan pastikan email/username serta password sudah benar.'
      : 'Periksa kembali data yang dimasukkan. Jika masalah berlanjut, coba ulang beberapa saat lagi.';

  return showTonztoonNoticeDialog(
    context,
    title: title,
    emphasis: isLogin && !isGoogle
        ? 'Email/username atau password tidak valid.'
        : null,
    message: message,
    helperText: helperText,
    helperIcon: isLogin && !isGoogle
        ? TonztoonIcons.warning
        : TonztoonIcons.wifi,
    primaryLabel: 'Coba lagi',
    supportActions: [
      if (onForgotPassword != null)
        TonztoonModalSupportAction(
          label: 'Reset password',
          icon: TonztoonIcons.keyRound,
          fullWidth: true,
          onPressed: () {
            Navigator.of(context).pop();
            onForgotPassword();
          },
        ),
    ],
  );
}
