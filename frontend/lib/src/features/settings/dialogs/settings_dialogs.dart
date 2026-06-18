part of '../settings_screen.dart';

Future<String?> _showProfileTextDialog(
  BuildContext context, {
  required String title,
  required String label,
  required String initialValue,
  required Future<void> Function(String value) onSubmit,
  String? helperText,
  TextInputType? keyboardType,
  int? maxLength,
  bool allowEmpty = false,
  String emptyError = 'Field ini wajib diisi.',
  String cancelLabel = 'Batal',
  String submitLabel = 'Simpan',
  String? Function(String? value)? validator,
}) {
  return showTonztoonModal<String>(
    context: context,
    builder: (context) => _ProfileTextDialog(
      title: title,
      label: label,
      initialValue: initialValue,
      onSubmit: onSubmit,
      helperText: helperText,
      keyboardType: keyboardType,
      maxLength: maxLength,
      allowEmpty: allowEmpty,
      emptyError: emptyError,
      cancelLabel: cancelLabel,
      submitLabel: submitLabel,
      validator: validator,
    ),
  );
}

class _ProfileTextDialog extends StatefulWidget {
  const _ProfileTextDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    required this.onSubmit,
    required this.allowEmpty,
    required this.emptyError,
    required this.cancelLabel,
    required this.submitLabel,
    this.helperText,
    this.keyboardType,
    this.maxLength,
    this.validator,
  });

  final String title;
  final String label;
  final String initialValue;
  final Future<void> Function(String value) onSubmit;
  final String? helperText;
  final TextInputType? keyboardType;
  final int? maxLength;
  final bool allowEmpty;
  final String emptyError;
  final String cancelLabel;
  final String submitLabel;
  final String? Function(String? value)? validator;

  @override
  State<_ProfileTextDialog> createState() => _ProfileTextDialogState();
}

class _ProfileTextDialogState extends State<_ProfileTextDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;
  bool _saving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: TonztoonModalDialog(
        title: widget.title,
        message:
            widget.helperText ?? 'Perbarui data profil akun TonzToon kamu.',
        art: TonztoonModalArt.editHeaderProfile,
        showCloseButton: !_saving,
        content: Form(
          key: _formKey,
          child: TextFormField(
            controller: _controller,
            autofocus: true,
            enabled: !_saving,
            keyboardType: widget.keyboardType,
            maxLength: widget.maxLength,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: widget.label,
              errorText: _errorText,
            ),
            validator: (value) {
              final customError = widget.validator?.call(value);
              if (customError != null) return customError;
              final text = value?.trim() ?? '';
              if (!widget.allowEmpty && text.isEmpty) return widget.emptyError;
              return null;
            },
            onFieldSubmitted: (_) => _submit(),
          ),
        ),
        secondaryLabel: widget.cancelLabel,
        onSecondaryPressed: _saving ? null : () => Navigator.of(context).pop(),
        primaryLabel: _saving ? 'Menyimpan...' : widget.submitLabel,
        primaryLoading: _saving,
        onPrimaryPressed: _saving ? null : _submit,
      ),
    );
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (_formKey.currentState?.validate() != true) return;
    setState(() {
      _saving = true;
      _errorText = null;
    });
    final value = _controller.text.trim();
    try {
      await widget.onSubmit(value);
      if (!mounted) return;
      Navigator.of(context).pop(value);
    } catch (error, stackTrace) {
      if (!mounted) return;
      final message = friendlyErrorMessage(
        error,
        fallbackMessage: 'Perubahan profil belum dapat disimpan.',
      );
      logAppError(error, stackTrace, context: 'Save profile field failed');
      setState(() {
        _saving = false;
        _errorText = message;
      });
      showAppSnackBar(context, message: message, type: AppSnackBarType.failure);
    }
  }
}

class _AvatarUploadDialog extends StatelessWidget {
  const _AvatarUploadDialog();

  @override
  Widget build(BuildContext context) {
    return const TonztoonModalDialog(
      title: 'Mengunggah foto',
      message:
          'Foto profil sedang diproses dan disimpan. Tunggu sebentar sampai unggahan selesai.',
      art: TonztoonModalArt.editHeaderProfile,
      showActions: false,
      showCloseButton: false,
      content: SizedBox.square(
        dimension: 28,
        child: CircularProgressIndicator(strokeWidth: 2.8),
      ),
    );
  }
}

class _ProfileSetupDialog extends StatefulWidget {
  const _ProfileSetupDialog({
    required this.requireUsername,
    required this.requirePassword,
    required this.title,
    required this.description,
    required this.cancelLabel,
    required this.submitLabel,
    required this.savingLabel,
    required this.onSubmit,
  });

  final bool requireUsername;
  final bool requirePassword;
  final String title;
  final String description;
  final String cancelLabel;
  final String submitLabel;
  final String savingLabel;
  final Future<void> Function({String? username, String? password}) onSubmit;

  @override
  State<_ProfileSetupDialog> createState() => _ProfileSetupDialogState();
}

class _ProfileSetupDialogState extends State<_ProfileSetupDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _saving = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _errorText;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_saving,
      child: TonztoonModalDialog(
        title: widget.title,
        message: widget.description,
        art: widget.requireUsername && widget.requirePassword
            ? TonztoonModalArt.accountSetup
            : widget.requirePassword
            ? TonztoonModalArt.passwordSetup
            : TonztoonModalArt.accountSetup,
        showCloseButton: !_saving,
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_errorText != null) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _errorText!,
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.requireUsername) ...[
                  TextFormField(
                    controller: _usernameController,
                    enabled: !_saving,
                    autofocus: true,
                    maxLength: 50,
                    textInputAction: widget.requirePassword
                        ? TextInputAction.next
                        : TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      helperText: 'Tidak dapat diubah kembali setelah dibuat.',
                    ),
                    validator: _validateUsernameValue,
                    onFieldSubmitted: (_) {
                      if (!widget.requirePassword) _submit();
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.requirePassword) ...[
                  TextFormField(
                    controller: _passwordController,
                    enabled: !_saving,
                    autofocus: !widget.requireUsername,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Password baru',
                      helperText: 'Minimal 8 karakter.',
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword
                            ? 'Tampilkan password'
                            : 'Sembunyikan password',
                        onPressed: _saving
                            ? null
                            : () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                        icon: Icon(
                          _obscurePassword
                              ? TonztoonIcons.eye
                              : TonztoonIcons.eyeOff,
                        ),
                      ),
                    ),
                    validator: _validatePassword,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmController,
                    enabled: !_saving,
                    obscureText: _obscureConfirm,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'Konfirmasi password',
                      suffixIcon: IconButton(
                        tooltip: _obscureConfirm
                            ? 'Tampilkan password'
                            : 'Sembunyikan password',
                        onPressed: _saving
                            ? null
                            : () => setState(
                                () => _obscureConfirm = !_obscureConfirm,
                              ),
                        icon: Icon(
                          _obscureConfirm
                              ? TonztoonIcons.eye
                              : TonztoonIcons.eyeOff,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value != _passwordController.text) {
                        return 'Konfirmasi password tidak sama.';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _submit(),
                  ),
                ],
              ],
            ),
          ),
        ),
        secondaryLabel: widget.cancelLabel,
        onSecondaryPressed: _saving
            ? null
            : () => Navigator.of(context).pop(false),
        primaryLabel: _saving ? widget.savingLabel : widget.submitLabel,
        primaryLoading: _saving,
        onPrimaryPressed: _saving ? null : _submit,
      ),
    );
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.length < 8) return 'Password minimal 8 karakter.';
    if (password.length > 128) return 'Password maksimal 128 karakter.';
    return null;
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (_formKey.currentState?.validate() != true) return;

    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await widget.onSubmit(
        username: widget.requireUsername
            ? _usernameController.text.trim()
            : null,
        password: widget.requirePassword ? _passwordController.text : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      if (!mounted) return;
      final message = friendlyErrorMessage(
        error,
        fallbackMessage: 'Data akun belum dapat disimpan. Silakan coba lagi.',
      );
      logAppError(error, stackTrace, context: 'Save profile setup failed');
      setState(() {
        _saving = false;
        _errorText = message;
      });
      showAppSnackBar(context, message: message, type: AppSnackBarType.failure);
    }
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({
    required this.onSubmit,
    this.title = 'Change Password',
    this.description,
    this.submitLabel = 'Simpan',
    this.savingLabel = 'Simpan',
  });

  final Future<void> Function(String password) onSubmit;
  final String title;
  final String? description;
  final String submitLabel;
  final String savingLabel;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _saving = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _errorText;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: TonztoonModalDialog(
        title: widget.title,
        message:
            widget.description ??
            'Gunakan password baru yang kuat dan mudah kamu ingat.',
        helperText: 'Password minimal 8 karakter dan maksimal 128 karakter.',
        helperIcon: TonztoonIcons.keyRound,
        art: TonztoonModalArt.passwordSetup,
        showCloseButton: !_saving,
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _passwordController,
                enabled: !_saving,
                autofocus: true,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Password baru',
                  errorText: _errorText,
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? 'Tampilkan password'
                        : 'Sembunyikan password',
                    onPressed: _saving
                        ? null
                        : () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                    icon: Icon(
                      _obscurePassword
                          ? TonztoonIcons.eye
                          : TonztoonIcons.eyeOff,
                    ),
                  ),
                ),
                validator: (value) {
                  final password = value ?? '';
                  if (password.length < 8) {
                    return 'Password minimal 8 karakter.';
                  }
                  if (password.length > 128) {
                    return 'Password maksimal 128 karakter.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmController,
                enabled: !_saving,
                obscureText: _obscureConfirm,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Konfirmasi password',
                  suffixIcon: IconButton(
                    tooltip: _obscureConfirm
                        ? 'Tampilkan password'
                        : 'Sembunyikan password',
                    onPressed: _saving
                        ? null
                        : () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                    icon: Icon(
                      _obscureConfirm
                          ? TonztoonIcons.eye
                          : TonztoonIcons.eyeOff,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value != _passwordController.text) {
                    return 'Konfirmasi password tidak sama.';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        secondaryLabel: 'Batal',
        onSecondaryPressed: _saving
            ? null
            : () => Navigator.of(context).pop(false),
        primaryLabel: _saving ? widget.savingLabel : widget.submitLabel,
        primaryLoading: _saving,
        onPrimaryPressed: _saving ? null : _submit,
      ),
    );
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (_formKey.currentState?.validate() != true) return;

    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await widget.onSubmit(_passwordController.text);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      if (!mounted) return;
      final message = friendlyErrorMessage(
        error,
        fallbackMessage: 'Password gagal disimpan. Silakan coba lagi.',
      );
      logAppError(error, stackTrace, context: 'Save password failed');
      setState(() {
        _saving = false;
        _errorText = message;
      });
      showAppSnackBar(context, message: message, type: AppSnackBarType.failure);
    }
  }
}
