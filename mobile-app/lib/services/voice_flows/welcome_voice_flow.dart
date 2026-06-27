import 'package:flutter/material.dart';

import '../../app_navigator.dart';
import '../../login_page.dart';
import '../../manual_login_page.dart';
import '../../manual_register_page.dart';
import '../../pin_onboarding_page.dart';
import '../../register_page.dart';
import '../../voice_login_page.dart';
import '../../voice_register_page.dart';
import '../voice_assistant_coordinator.dart';
import '../../utils/voice_option_parser.dart';

enum WelcomeChoice { signIn, register, activatePin }

/// Spoken onboarding on the welcome screen: sign in, register, or PIN activation.
class WelcomeVoiceFlow {
  WelcomeVoiceFlow({
    required this.isCancelled,
  });

  final bool Function() isCancelled;
  final _assistant = VoiceAssistantCoordinator.instance;

  Future<void> run() async {
    if (isCancelled()) return;

    while (!isCancelled()) {
      final choice = await _askWelcomeChoice();
      if (choice == null || isCancelled()) return;

      switch (choice) {
        case WelcomeChoice.signIn:
          await _guideSignIn();
          return;
        case WelcomeChoice.register:
          await _guideRegister();
          return;
        case WelcomeChoice.activatePin:
          await _guidePinActivation();
          return;
      }
    }
  }

  Future<WelcomeChoice?> _askWelcomeChoice() async {
    String promptKey = 'welcomeVoiceMenuPrompt';
    while (!isCancelled()) {
      try {
        final answer = await _assistant.promptAndListen(promptKey);
        if (isCancelled()) return null;

        final parsed = _parseWelcomeChoice(answer);
        if (parsed != null) return parsed;

        promptKey = 'welcomeVoiceMenuRetry';
      } on VoiceFlowNavigationException {
        return null;
      } on VoiceFlowCancelledException {
        await _assistant.speakPrompt('welcomeVoiceCancelled');
        return null;
      }
    }
    return null;
  }

  Future<void> _guideSignIn() async {
    if (isCancelled()) return;
    await _assistant.speakPrompt('welcomeVoiceOpeningSignIn');
    _openPage(const LoginPage());
    if (isCancelled()) return;

    String promptKey = 'welcomeVoiceSignInMethodPrompt';
    while (!isCancelled()) {
      try {
        final answer =
            await _assistant.promptAndListen(promptKey);
        if (isCancelled()) return;

        if (_matchesVoiceLogin(answer)) {
          await _assistant.speakPrompt('welcomeVoiceOpeningVoiceLogin');
          _openPage(const VoiceLoginPage());
          return;
        }
        if (_matchesManualLogin(answer)) {
          await _assistant.speakPrompt('welcomeVoiceOpeningManualLogin');
          _openPage(const ManualLoginPage());
          return;
        }

        promptKey = 'welcomeVoiceSignInMethodRetry';
      } on VoiceFlowNavigationException {
        return;
      } on VoiceFlowCancelledException {
        await _assistant.speakPrompt('welcomeVoiceCancelled');
        return;
      }
    }
  }

  Future<void> _guideRegister() async {
    if (isCancelled()) return;
    await _assistant.speakPrompt('welcomeVoiceOpeningRegister');
    _openPage(const RegisterPage());
    if (isCancelled()) return;

    String promptKey = 'welcomeVoiceRegisterMethodPrompt';
    while (!isCancelled()) {
      try {
        final answer = await _assistant.promptAndListen(promptKey);
        if (isCancelled()) return;

        if (_matchesVoiceRegister(answer)) {
          await _assistant.speakPrompt('welcomeVoiceOpeningVoiceRegister');
          _openPage(const VoiceRegisterPage());
          return;
        }
        if (_matchesManualRegister(answer)) {
          await _assistant.speakPrompt('welcomeVoiceOpeningManualRegister');
          _openPage(const ManualRegisterPage());
          return;
        }

        promptKey = 'welcomeVoiceRegisterMethodRetry';
      } on VoiceFlowNavigationException {
        return;
      } on VoiceFlowCancelledException {
        await _assistant.speakPrompt('welcomeVoiceCancelled');
        return;
      }
    }
  }

  Future<void> _guidePinActivation() async {
    if (isCancelled()) return;
    await _assistant.speakPrompt('welcomeVoiceOpeningPin');
    _openPage(const PinOnboardingPage());
    if (isCancelled()) return;
    await _assistant.speakPrompt('welcomeVoicePinPrompt');
  }

  void _openPage(Widget page) {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;
    navigator.push<void>(
      MaterialPageRoute<void>(builder: (context) => page),
    );
  }

  WelcomeChoice? _parseWelcomeChoice(String? answer) {
    final normalized = VoiceAssistantCoordinator.normalizeSpeech(answer ?? '');
    if (normalized.isEmpty) return null;

    final option = VoiceOptionParser.extractOptionNumber(answer ?? '', 3);
    if (option != null) {
      return switch (option) {
        1 => WelcomeChoice.signIn,
        2 => WelcomeChoice.register,
        3 => WelcomeChoice.activatePin,
        _ => null,
      };
    }

    if (_matchesAny(normalized, const [
      'activate with pin',
      'activate pin',
      'pin activation',
      'activation pin',
      'activate account',
      'patient pin',
      'use pin',
      'with pin',
      'pin',
      'activate',
      '激活',
      '使用pin',
      'pin激活',
      'aktif',
      'aktifkan',
      'pin aktif',
    ])) {
      return WelcomeChoice.activatePin;
    }

    if (_matchesAny(normalized, const [
      'create account',
      'register',
      'sign up',
      'signup',
      'new account',
      'registration',
      '注册',
      '创建账户',
      '建立账户',
      'daftar',
      'pendaftaran',
      'cipta akaun',
    ])) {
      return WelcomeChoice.register;
    }

    if (_matchesAny(normalized, const [
      'sign in',
      'signin',
      'log in',
      'login',
      'sign me in',
      '登录',
      '登入',
      'log masuk',
      'daftar masuk',
    ])) {
      return WelcomeChoice.signIn;
    }

    return null;
  }

  bool _matchesVoiceLogin(String? answer) {
    final option = VoiceOptionParser.extractOptionNumber(answer ?? '', 2);
    if (option == 1) return true;

    final normalized = VoiceAssistantCoordinator.normalizeSpeech(answer ?? '');
    return _matchesAny(normalized, const [
      'voice login',
      'voice sign in',
      'voice signin',
      'use voice',
      'with voice',
      'voice',
      '语音登录',
      '语音登入',
      '语音',
      'suara',
      'log masuk suara',
    ]);
  }

  bool _matchesManualLogin(String? answer) {
    final option = VoiceOptionParser.extractOptionNumber(answer ?? '', 2);
    if (option == 2) return true;

    final normalized = VoiceAssistantCoordinator.normalizeSpeech(answer ?? '');
    return _matchesAny(normalized, const [
      'manual login',
      'manual sign in',
      'email',
      'password',
      'email and password',
      'manual',
      '手动登录',
      '手动登入',
      '邮箱',
      '密码',
      '手动',
      'manual',
      'emel',
      'kata laluan',
    ]);
  }

  bool _matchesVoiceRegister(String? answer) {
    final option = VoiceOptionParser.extractOptionNumber(answer ?? '', 2);
    if (option == 1) return true;

    final normalized = VoiceAssistantCoordinator.normalizeSpeech(answer ?? '');
    return _matchesAny(normalized, const [
      'voice register',
      'voice registration',
      'register with voice',
      'use voice',
      'with voice',
      'voice',
      '语音注册',
      '语音',
      'suara',
      'daftar suara',
    ]);
  }

  bool _matchesManualRegister(String? answer) {
    final option = VoiceOptionParser.extractOptionNumber(answer ?? '', 2);
    if (option == 2) return true;

    final normalized = VoiceAssistantCoordinator.normalizeSpeech(answer ?? '');
    return _matchesAny(normalized, const [
      'manual register',
      'manual registration',
      'email',
      'password',
      'email and password',
      'manual',
      '手动注册',
      '手动',
      '邮箱',
      '密码',
      'manual',
      'emel',
      'kata laluan',
    ]);
  }

  bool _matchesAny(String normalized, List<String> phrases) {
    return phrases.any(
      (phrase) => normalized == phrase || normalized.contains(phrase),
    );
  }
}
