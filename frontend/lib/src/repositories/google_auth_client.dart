import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/app_error.dart';
import '../core/api_client.dart';
import '../core/config.dart';

class GoogleAuthTokens {
  const GoogleAuthTokens({required this.idToken, this.accessToken});

  final String idToken;
  final String? accessToken;
}

abstract class GoogleAuthClient {
  Future<GoogleAuthTokens> signIn();
  Future<void> signOut();
}

class NativeGoogleAuthClient implements GoogleAuthClient {
  NativeGoogleAuthClient(this._config, {GoogleSignIn? googleSignIn})
    : _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final AppConfig _config;
  final GoogleSignIn _googleSignIn;
  Future<void>? _initialization;

  @override
  Future<GoogleAuthTokens> signIn() async {
    _ensureConfigured();
    await _initializeGoogleSignIn();

    final GoogleSignInAccount googleAccount;
    try {
      googleAccount = await _googleSignIn.authenticate();
    } on GoogleSignInException catch (error, stackTrace) {
      logAppError(error, stackTrace, context: 'Native Google Sign-In failed');
      throw ApiException(_googleSignInErrorMessage(error));
    }

    final googleAuthentication = googleAccount.authentication;
    final idToken = googleAuthentication.idToken;

    if (idToken == null || idToken.isEmpty) {
      throw ApiException(
        'Google sign-in tidak mengembalikan ID token. Pastikan Web Client ID '
        'Google OAuth sudah benar.',
      );
    }

    return GoogleAuthTokens(idToken: idToken);
  }

  @override
  Future<void> signOut() async {
    await _signOutGoogle();
  }

  Future<void> _initializeGoogleSignIn() {
    return _initialization ??= _googleSignIn.initialize(
      clientId: _platformGoogleClientId(),
      serverClientId: _requiredValue(
        _config.googleWebClientId,
        'GOOGLE_WEB_CLIENT_ID',
      ),
    );
  }

  String? _platformGoogleClientId() {
    if (kIsWeb) return _config.googleWebClientId;

    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => _requiredValue(
        _config.googleIosClientId,
        'GOOGLE_IOS_CLIENT_ID',
      ),
      _ => null,
    };
  }

  void _ensureConfigured() {
    if (!_config.hasGoogleAuthConfig) {
      throw ApiException(
        'Konfigurasi Google Sign-In belum lengkap. Tambahkan '
        '--dart-define=GOOGLE_WEB_CLIENT_ID.',
      );
    }
  }

  String _requiredValue(String? value, String name) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      throw ApiException('Konfigurasi $name belum diisi.');
    }
    return trimmed;
  }

  String _googleSignInErrorMessage(GoogleSignInException error) {
    return switch (error.code) {
      GoogleSignInExceptionCode.canceled => 'Login Google dibatalkan.',
      GoogleSignInExceptionCode.clientConfigurationError =>
        'Konfigurasi OAuth Google belum benar. Periksa Web Client ID, '
            'iOS Client ID, package name, dan SHA certificate.',
      GoogleSignInExceptionCode.providerConfigurationError =>
        'Google Sign-In belum siap di perangkat ini atau konfigurasi provider '
            'belum lengkap.',
      GoogleSignInExceptionCode.uiUnavailable =>
        'UI Google Sign-In tidak dapat dibuka dari perangkat ini.',
      _ =>
        'Login Google gagal. Periksa konfigurasi Google Sign-In lalu coba lagi.',
    };
  }

  Future<void> _signOutGoogle() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Local logout should still complete even when Google Play Services or
      // browser state cannot be reached.
    }
  }
}
