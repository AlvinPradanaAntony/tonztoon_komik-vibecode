part of '../auth_screen.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController = TextEditingController(
    text: widget.initialEmail,
  );
  bool _instructionSent = false;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _AuthPalette.fromTheme(theme);
    final overlayStyle = _authSystemOverlayStyle(theme);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          systemOverlayStyle: overlayStyle,
          leading: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: IconButton(
              tooltip: 'Kembali',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(TonztoonIcons.arrowBack),
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
                children: [
                  _ForgotPasswordHeader(
                    palette: palette,
                    instructionSent: _instructionSent,
                  ),
                  const SizedBox(height: 26),
                  _ForgotPasswordCard(
                    formKey: _formKey,
                    palette: palette,
                    emailController: _emailController,
                    instructionSent: _instructionSent,
                    submitting: _submitting,
                    errorMessage: _errorMessage,
                    onSubmit: _submit,
                    onEditEmail: () => setState(() {
                      _instructionSent = false;
                      _errorMessage = null;
                    }),
                  ),
                  const SizedBox(height: 18),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(TonztoonIcons.chevronLeft, size: 18),
                    label: const Text('Kembali ke login'),
                    style: TextButton.styleFrom(
                      foregroundColor: palette.accent,
                      textStyle: theme.textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (_formKey.currentState?.validate() != true) return;

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .requestPasswordReset(email: _emailController.text);
      if (!mounted) return;
      setState(() => _instructionSent = true);
    } catch (error, stackTrace) {
      logAppError(error, stackTrace, context: 'Password reset request failed');
      if (!mounted) return;
      final message = _authErrorMessage(
        error,
        fallbackMessage:
            'Permintaan reset password belum berhasil. Coba beberapa saat lagi.',
      );
      setState(() => _errorMessage = message);
      await _showAuthFailureDialog(
        context,
        title: 'Reset password gagal',
        message: message,
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}
