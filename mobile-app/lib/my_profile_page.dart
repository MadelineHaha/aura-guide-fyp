import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'app_route_observer.dart';
import 'auth_session.dart';
import 'services/user_profile_service.dart';

class MyProfilePage extends StatefulWidget {
  const MyProfilePage({super.key});

  @override
  State<MyProfilePage> createState() => _MyProfilePageState();
}

class _MyProfilePageState extends State<MyProfilePage>
    with WidgetsBindingObserver, RouteAware {
  bool _isEditing = false;
  bool _loading = true;
  bool _routeSubscribed = false;
  bool _refreshInFlight = false;
  String _patientId = '';
  String _loadedEmail = '';
  String _emailVerificationTarget = '';
  /// Auth email before verify-before-update was requested.
  String _emailBeforeVerification = '';
  bool _awaitingEmailVerification = false;
  String? _loadError;
  String _authUid = '';
  Map<String, dynamic> _profileData = {};
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;
  Timer? _verificationPollTimer;
  final _profileService = UserProfileService();

  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  String _derivedAge = '';

  static const Color _bg = Color(0xFF000000);
  static const Color _text = Colors.white;
  static const Color _subtext = Color(0xFFB0B0B0);
  static const Color _tileFill = Color(0xFF0B181B);
  static const Color _tileBorder = Color(0xFF334146);
  static const Color _accent = Color(0xFF66C2BD);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _addressController = TextEditingController();
    _verificationPollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        if (_hasUnsavedEmailInForm()) return;
        unawaited(_syncVerifiedEmailIfNeeded(showSnack: false));
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeSubscribed) return;
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
      _routeSubscribed = true;
    }
  }

  @override
  void didPush() {
    unawaited(_refreshProfileOnOpen());
  }

  @override
  void didPopNext() {
    unawaited(_refreshProfileOnOpen());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshProfileOnOpen());
    }
  }

  /// User typed a new email in the form that Auth does not have yet.
  bool _hasUnsavedEmailInForm() {
    final auth = (AuthSession.resolveUser()?.email ?? '').trim().toLowerCase();
    final field = _emailController.text.trim().toLowerCase();
    if (field.isEmpty || auth.isEmpty) return false;
    return field != auth;
  }

  /// Only push Auth → Firestore when there is no pending/unsaved email change.
  bool _shouldPushAuthEmailToFirestore() {
    if (_awaitingEmailVerification) return false;
    if (_hasUnsavedEmailInForm()) return false;
    return true;
  }

  bool _hasPendingEmailChange() {
    return _awaitingEmailVerification || _hasUnsavedEmailInForm();
  }

  /// True when Firebase Auth already has the pending new email (verified).
  bool _isPendingEmailVerified(
    String authEmail, {
    String? baselineEmail,
  }) {
    final auth = authEmail.trim().toLowerCase();
    if (auth.isEmpty) return false;

    final target = _emailVerificationTarget.trim().toLowerCase();
    final field = _emailController.text.trim().toLowerCase();
    final firestore = _asString(_profileData['email']).trim().toLowerCase();

    if (target.isNotEmpty && auth == target) return true;
    if (field.isNotEmpty && auth == field) return true;
    if (firestore.isNotEmpty && auth == firestore) return true;

    // Verified via link: Auth email changed from the address we had before.
    if (_awaitingEmailVerification) {
      final baseline = (baselineEmail ?? _emailBeforeVerification)
          .trim()
          .toLowerCase();
      if (baseline.isNotEmpty && auth != baseline) return true;
    }
    return false;
  }

  void _clearEmailVerificationPending(String authEmail) {
    _awaitingEmailVerification = false;
    _emailVerificationTarget = '';
    _emailBeforeVerification = '';
    final trimmed = authEmail.trim();
    if (trimmed.isNotEmpty) {
      _loadedEmail = trimmed;
      _emailController.text = trimmed;
    }
  }

  void _reconcileEmailVerificationPending({String? baselineEmail}) {
    if (!_awaitingEmailVerification) return;
    final auth = (AuthSession.resolveUser()?.email ?? '').trim();
    if (_isPendingEmailVerified(auth, baselineEmail: baselineEmail)) {
      _clearEmailVerificationPending(auth);
    }
  }

  Future<void> _syncVerifiedEmailIfNeeded({required bool showSnack}) async {
    final user = await AuthSession.reloadAndResolve() ?? await _resolveCurrentUser();
    if (user == null) return;

    final refreshedEmail = (user.email ?? '').trim();
    if (refreshedEmail.isEmpty) return;

    final emailJustVerified =
        _awaitingEmailVerification && _isPendingEmailVerified(refreshedEmail);

    if (emailJustVerified) {
      await _profileService.syncEmailFromAuth(user.uid);
      if (!mounted) return;
      setState(() {
        _clearEmailVerificationPending(refreshedEmail);
        _isEditing = false;
      });
      unawaited(_refreshProfileOnOpen());
      if (showSnack) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email verification synced successfully.'),
          ),
        );
      }
      return;
    }

    // Never overwrite the form or Firestore with old Auth while email change is pending.
    if (_awaitingEmailVerification || _hasUnsavedEmailInForm()) {
      return;
    }

    final doc =
        await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final firestoreEmail = _asString(doc.data()?['email']).trim();

    final needsFirestoreSync = refreshedEmail != firestoreEmail;
    final needsUiSync = refreshedEmail != _loadedEmail ||
        refreshedEmail != _emailController.text.trim();

    if (!needsFirestoreSync && !needsUiSync) {
      return;
    }

    if (needsFirestoreSync && _shouldPushAuthEmailToFirestore()) {
      await _profileService.syncEmailFromAuth(user.uid);
    }

    if (!mounted) return;
    setState(() {
      if (needsUiSync) {
        _loadedEmail = refreshedEmail;
        if (!_isEditing) {
          _emailController.text = refreshedEmail;
        }
      }
    });
  }

  Future<User?> _resolveCurrentUser() async {
    var user = AuthSession.resolveUser();
    if (user != null) return user;

    // Auth can be null briefly right after email verification — wait and retry.
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      user = AuthSession.resolveUser();
      if (user != null) return user;
    }
    return null;
  }

  /// Runs every time the profile route opens, is re-shown, or the app resumes.
  Future<void> _refreshProfileOnOpen() async {
    if (_refreshInFlight || !mounted) return;

    // Never run a full reload while email verification is pending — it would
    // push the old Auth email to Firestore and reset the form.
    if (_isEditing || _hasPendingEmailChange()) {
      await _syncVerifiedEmailIfNeeded(showSnack: false);
      return;
    }

    _refreshInFlight = true;
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final user = await _resolveCurrentUser();
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _loadError =
              'Session is refreshing. Tap Retry in a moment — you are not logged out.';
        });
        unawaited(_retryRefreshWhenSessionRecovers());
        return;
      }

      final uid = user.uid;
      _authUid = uid;

      // Abort if user started a pending email change while this refresh ran.
      if (_hasPendingEmailChange()) {
        await _syncVerifiedEmailIfNeeded(showSnack: false);
        if (mounted) setState(() => _loading = false);
        return;
      }

      // 1. Sync Auth → Firestore only when there is no pending email change.
      if (_shouldPushAuthEmailToFirestore()) {
        await _profileService.syncEmailFromAuth(uid);
      }

      if (!mounted || _hasPendingEmailChange()) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      // 2. Reload profile from Firestore (with legacy email recovery if needed)
      final result = await _profileService.loadProfile(uid, syncAuthFirst: false);
      if (mounted && result.found && !_hasPendingEmailChange()) {
        final authEmail =
            (AuthSession.resolveUser()?.email ?? _loadedEmail).trim();
        setState(() {
          _profileData = result.data;
          _loadError = null;
          _applyProfileData(
            result.data,
            authEmail: authEmail,
            preserveEmail: false,
          );
          _reconcileEmailVerificationPending();
        });
      }

      // 3. Keep listening for live Firestore updates while page is open
      _profileSub?.cancel();
      _profileSub = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots()
          .listen(
        (snap) {
          if (!mounted) return;

          if (!snap.exists) {
            setState(() {
              _profileData = {};
              _loading = false;
              _loadError = 'No document at users/$uid';
            });
            return;
          }

          var data = Map<String, dynamic>.from(snap.data() ?? {});
          final authEmail =
              (AuthSession.resolveUser()?.email ?? _loadedEmail).trim();
          final preserveEmail = _isEditing || _hasPendingEmailChange();

          // Do not let Firestore snapshots revert the pending new email.
          if (preserveEmail) {
            final pendingEmail = _emailVerificationTarget.trim().isNotEmpty
                ? _emailVerificationTarget.trim()
                : _emailController.text.trim();
            if (pendingEmail.isNotEmpty) {
              data = Map<String, dynamic>.from(data)..['email'] = pendingEmail;
            }
          }

          setState(() {
            _profileData = data;
            _loading = false;
            _loadError = null;
            if (!_isEditing) {
              _applyProfileData(
                data,
                authEmail: authEmail,
                preserveEmail: preserveEmail,
              );
            }
            if (!preserveEmail) {
              _reconcileEmailVerificationPending();
            }
          });
        },
        onError: (Object e) {
          if (!mounted) return;
          if (_hasDisplayableProfileFromState()) {
            setState(() => _loading = false);
            return;
          }
          setState(() {
            _loading = false;
            _loadError =
                'Firestore read failed: $e\n'
                'Check Firestore rules allow read on users/$uid';
          });
        },
      );

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      if (!_hasDisplayableProfileFromState()) {
        setState(() {
          _loading = false;
          _loadError = 'Could not sync profile: $e';
        });
      } else {
        setState(() => _loading = false);
      }
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<void> _retryRefreshWhenSessionRecovers() async {
    for (var i = 0; i < 15; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      if (AuthSession.resolveUser() != null) {
        await _refreshProfileOnOpen();
        return;
      }
    }
  }

  bool _hasDisplayableProfileFromState() {
    return _asString(_profileData['name']).trim().isNotEmpty ||
        _asString(_profileData['userId']).trim().isNotEmpty ||
        _asString(_nameController.text).trim().isNotEmpty;
  }

  Future<void> _loadProfile() async {
    await _refreshProfileOnOpen();
  }

  void _applyProfileData(
    Map<String, dynamic> data, {
    required String authEmail,
    bool preserveEmail = false,
  }) {
    final dob = _parseBirthDate(data['birthDate']);
    if (dob != null) {
      final now = DateTime.now();
      var years = now.year - dob.year;
      if (now.month < dob.month ||
          (now.month == dob.month && now.day < dob.day)) {
        years--;
      }
      _derivedAge = years >= 0 ? years.toString() : '';
    } else {
      _derivedAge = '';
    }

    _patientId = _asString(data['userId']);
    _nameController.text = _asString(data['name']);
    if (!preserveEmail) {
      final firestoreEmail = _asString(data['email']).trim();
      // Auth is the source of truth for the verified email address.
      _loadedEmail =
          authEmail.isNotEmpty ? authEmail : firestoreEmail;
      _emailController.text = _loadedEmail;
    }
    _phoneController.text = _asString(data['phoneNumber']);
    _addressController.text = _asString(data['address']);
  }

  DateTime? _parseBirthDate(dynamic birthDate) {
    if (birthDate is Timestamp) return birthDate.toDate();
    if (birthDate is DateTime) return birthDate;
    return null;
  }

  String _viewField(String key) {
    if (_isEditing) return '';
    if (key == 'email') {
      final authEmail =
          (AuthSession.resolveUser()?.email ?? _loadedEmail).trim();
      if (authEmail.isNotEmpty) return authEmail;
    }
    return _asString(_profileData[key]).trim();
  }

  String _asString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    return value.toString();
  }

  void _showEmailNotVerifiedBlockMessage() {
    if (!mounted) return;
    final target = _emailVerificationTarget.trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          target.isNotEmpty
              ? 'Verify $target before saving your profile. '
                  'Open the verification link in your email, then tap Save Profile again.'
              : 'Verify your new email before saving your profile. '
                  'Open the verification link in your email, then tap Save Profile again.',
        ),
      ),
    );
  }

  Future<bool> _isEmailVerifiedForSave({
    required User refreshedUser,
    required String baselineBeforeSave,
  }) async {
    final authEmail = (refreshedUser.email ?? '').trim();
    if (_isPendingEmailVerified(authEmail, baselineEmail: baselineBeforeSave)) {
      return true;
    }

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(refreshedUser.uid)
        .get();
    final firestoreEmail = _asString(doc.data()?['email']).trim();
    return _isPendingEmailVerified(
      firestoreEmail,
      baselineEmail: baselineBeforeSave,
    );
  }

  /// Returns true only when profile fields were saved.
  Future<bool> _saveProfileWhileEditing(User user) async {
    final baselineBeforeSave = _emailBeforeVerification.isNotEmpty
        ? _emailBeforeVerification
        : _loadedEmail;

    final refreshedUser = await AuthSession.reloadAndResolve() ?? user;
    var refreshedAuthEmail = (refreshedUser.email ?? '').trim();

    // Block all profile saves until the pending email is verified in Auth.
    if (_awaitingEmailVerification) {
      final verified = await _isEmailVerifiedForSave(
        refreshedUser: refreshedUser,
        baselineBeforeSave: baselineBeforeSave,
      );
      if (!verified) {
        _showEmailNotVerifiedBlockMessage();
        return false;
      }
      _clearEmailVerificationPending(refreshedAuthEmail);
      await _profileService.syncEmailFromAuth(refreshedUser.uid);
      refreshedAuthEmail = (AuthSession.resolveUser()?.email ?? refreshedAuthEmail)
          .trim();
    } else if (refreshedAuthEmail.isNotEmpty &&
        refreshedAuthEmail != _loadedEmail &&
        !_hasUnsavedEmailInForm()) {
      _loadedEmail = refreshedAuthEmail;
    }

    final emailToSave = _emailController.text.trim();
    final isEmailChangeAttempt = emailToSave.isNotEmpty &&
        emailToSave.toLowerCase() != refreshedAuthEmail.toLowerCase();

    if (isEmailChangeAttempt) {
      // New email in the form is not verified in Auth yet — never save profile.
      if (_awaitingEmailVerification) {
        _showEmailNotVerifiedBlockMessage();
        return false;
      }

      final emailResult = await _updateEmailIfNeeded(
        user: refreshedUser,
        newEmail: emailToSave,
      );
      if (emailResult.error != null) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(emailResult.error!)),
        );
        return false;
      }
      if (emailResult.verificationPending) {
        final verificationTargetEmail =
            emailResult.sentToEmail ?? emailToSave;
        if (!mounted) return false;
        setState(() {
          _emailBeforeVerification = baselineBeforeSave.isNotEmpty
              ? baselineBeforeSave
              : refreshedAuthEmail;
          _awaitingEmailVerification = true;
          _emailVerificationTarget = verificationTargetEmail;
          _emailController.text = emailToSave;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Verification link sent to $verificationTargetEmail. '
              'Verify that email, then tap Save Profile again to save your profile.',
            ),
          ),
        );
        return false;
      }
    }

    // Safety: never write name/phone/address while email is still unverified.
    if (_awaitingEmailVerification || _hasUnsavedEmailInForm()) {
      _showEmailNotVerifiedBlockMessage();
      return false;
    }

    await _profileService.saveProfileFields(
      uid: refreshedUser.uid,
      name: _nameController.text,
      phoneNumber: _phoneController.text,
      address: _addressController.text,
    );

    if (_shouldPushAuthEmailToFirestore()) {
      await _profileService.syncEmailFromAuth(refreshedUser.uid);
    }
    await _syncAuthProfileCallable();

    final reload = await _profileService.loadProfile(
      refreshedUser.uid,
      syncAuthFirst: false,
    );
    if (reload.found && mounted) {
      _applyProfileData(
        reload.data,
        authEmail: (AuthSession.resolveUser()?.email ?? '').trim(),
      );
    }
    return true;
  }

  Future<void> _toggleEditSave() async {
    if (!_isEditing) {
      if (!mounted) return;
      setState(() => _isEditing = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Editing mode enabled. Update fields then tap Save Profile.',
          ),
        ),
      );
      return;
    }

    final user = AuthSession.resolveUser();
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Session is refreshing. Try Save Profile again in a moment.',
          ),
        ),
      );
      return;
    }

    final saved = await _saveProfileWhileEditing(user);
    if (!mounted || !saved) return;

    _reconcileEmailVerificationPending();
    setState(() => _isEditing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile changes saved.')),
    );
  }

  Future<void> _syncAuthProfileCallable() async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('syncMyAuthProfile');
      await callable.call();
    } catch (_) {
      // Non-blocking: local Firestore save already succeeded.
    }
  }

  Future<_EmailUpdateResult> _updateEmailIfNeeded({
    required User user,
    required String newEmail,
  }) async {
    final liveUser = await AuthSession.reloadAndResolve() ?? user;
    final currentEmail = (liveUser.email ?? '').trim();
    final normalizedNew = newEmail.trim().toLowerCase();
    if (newEmail.isEmpty) return const _EmailUpdateResult(error: 'Email cannot be empty.');
    if (normalizedNew == currentEmail.toLowerCase() ||
        normalizedNew == _loadedEmail.trim().toLowerCase()) {
      return const _EmailUpdateResult();
    }
    if (currentEmail.isEmpty) {
      return const _EmailUpdateResult(
        error: 'This account cannot change email because no current email is linked.',
      );
    }

    final sameEmailUsers = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: newEmail)
        .limit(1)
        .get();
    if (sameEmailUsers.docs.isNotEmpty &&
        sameEmailUsers.docs.first.id != liveUser.uid) {
      return const _EmailUpdateResult(
        error: 'This email is already used by another account.',
      );
    }

    final password = await _askForCurrentPassword();
    if (password == null || password.isEmpty) {
      return const _EmailUpdateResult(error: 'Password is required to change email.');
    }

    try {
      final cred = EmailAuthProvider.credential(
        email: currentEmail,
        password: password,
      );
      await liveUser.reauthenticateWithCredential(cred);
      await liveUser.verifyBeforeUpdateEmail(newEmail);
      return _EmailUpdateResult(
        verificationPending: true,
        sentToEmail: newEmail,
      );
    } on FirebaseAuthException catch (e) {
      return _EmailUpdateResult(
        error: _authErrorMessage(e),
      );
    } catch (_) {
      return const _EmailUpdateResult(error: 'Failed to update email.');
    }
  }

  Future<String?> _askForCurrentPassword() async {
    String value = '';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        String? localError;
        var obscure = true;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: const Color(0xFF0F1A1D),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF2E4D54), width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.lock_outline, color: _accent),
                        SizedBox(width: 8),
                        Text(
                          'Confirm Password',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'For security, enter your current password to update email.',
                      style: TextStyle(color: _subtext, fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      obscureText: obscure,
                      style: const TextStyle(color: Colors.white),
                      onChanged: (text) {
                        value = text;
                        if (localError != null) {
                          setDialogState(() => localError = null);
                        }
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF142328),
                        hintText: 'Enter current password',
                        hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                        errorText: localError,
                        suffixIcon: IconButton(
                          onPressed: () => setDialogState(() => obscure = !obscure),
                          icon: Icon(
                            obscure ? Icons.visibility_off : Icons.visibility,
                            color: const Color(0xFF9CA3AF),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF345059)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _accent),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () {
                            if (value.trim().isEmpty) {
                              setDialogState(() => localError = 'Password is required');
                              return;
                            }
                            Navigator.of(context).pop();
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.black,
                          ),
                          child: const Text('Confirm'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    return value.trim().isEmpty ? null : value.trim();
  }

  String get _displayPatientId {
    final id = _asString(_profileData['userId']).trim();
    if (id.isNotEmpty) return 'Patient ID: $id';
    if (_patientId.isNotEmpty) return 'Patient ID: $_patientId';
    return 'Patient ID: -';
  }

  String get _displayName {
    final name = _asString(_profileData['name']).trim();
    if (name.isNotEmpty) return name;
    final fromController = _nameController.text.trim();
    if (fromController.isNotEmpty) return fromController;
    final email = _loadedEmail.trim();
    if (email.contains('@')) return email.split('@').first;
    if (email.isNotEmpty) return email;
    return 'User';
  }

  @override
  void dispose() {
    if (_routeSubscribed) {
      appRouteObserver.unsubscribe(this);
    }
    _profileSub?.cancel();
    _verificationPollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
        title: const Text(
          'My Profile',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _accent))
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_loadError != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A1A1A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE57373)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _loadError!,
                              style: const TextStyle(color: Color(0xFFFFB4AB)),
                            ),
                            if (_authUid.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Signed-in uid: $_authUid',
                                style: const TextStyle(
                                  color: Color(0xFF9CA3AF),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _loadProfile,
                                child: const Text('Retry'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 4),
                    Center(
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: const Color(0xFF66C2CD),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'M',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 44,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _displayName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _text,
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _displayPatientId,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _subtext,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: FilledButton.icon(
                        onPressed: _toggleEditSave,
                        icon: Icon(
                          _isEditing ? Icons.save_outlined : Icons.edit_outlined,
                          size: 20,
                        ),
                        label: Text(_isEditing ? 'Save Profile' : 'Edit Profile'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _isEditing
                              ? const Color(0xFF2F8F46)
                              : const Color(0xFF1A7177),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                      ),
                    ),
                    if (_isEditing) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16331B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFF2F8F46),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          _awaitingEmailVerification ||
                                  _hasUnsavedEmailInForm()
                              ? 'Email not verified yet. Open the verification link, then tap Save Profile. '
                                  'Your profile will not be saved until then.'
                              : 'Editing mode is ON. Update fields then tap Save Profile.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF91E09F),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    const Divider(color: Color(0xFF2B2B2B), height: 1),
                    const SizedBox(height: 12),
                    const Text(
                      'PERSONAL DETAILS',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ..._profileCards(),
                  ],
                ),
              ),
      ),
    );
  }

  List<Widget> _profileCards() => [
        _ProfileTile(
          icon: Icons.mail_outline,
          title: 'EMAIL ADDRESS',
          value: _isEditing ? _emailController.text : _viewField('email'),
          accentBg: const Color(0xFF1B636A),
          isEditing: _isEditing,
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
        ),
        _ProfileTile(
          icon: Icons.person_outline,
          title: 'NAME',
          value: _isEditing ? _nameController.text : _viewField('name'),
          accentBg: const Color(0xFF1B636A),
          trailingChevron: !_isEditing,
          isEditing: _isEditing,
          controller: _nameController,
        ),
        _ProfileTile(
          icon: Icons.phone_outlined,
          title: 'PHONE NUMBER',
          value: _isEditing ? _phoneController.text : _viewField('phoneNumber'),
          accentBg: const Color(0xFF1B636A),
          trailingChevron: !_isEditing,
          isEditing: _isEditing,
          controller: _phoneController,
          keyboardType: TextInputType.phone,
        ),
        _ProfileTile(
          icon: Icons.home_outlined,
          title: 'ADDRESS',
          value: _isEditing ? _addressController.text : _viewField('address'),
          accentBg: const Color(0xFF1B636A),
          trailingChevron: !_isEditing,
          isEditing: _isEditing,
          controller: _addressController,
        ),
        _ProfileTile(
          icon: Icons.schedule,
          title: 'AGE',
          value: _derivedAge,
          accentBg: const Color(0xFF1B636A),
          trailingChevron: !_isEditing,
          isEditing: false,
        ),
      ];
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.accentBg,
    this.trailingChevron = false,
    this.isEditing = false,
    this.controller,
    this.keyboardType,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color accentBg;
  final bool trailingChevron;
  final bool isEditing;
  final TextEditingController? controller;
  final TextInputType? keyboardType;

  String get _displayValue {
    final fromController = controller?.text ?? '';
    if (fromController.trim().isNotEmpty) return fromController;
    return value;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isEditing ? const Color(0xFF102226) : _MyProfilePageState._tileFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isEditing ? _MyProfilePageState._accent : _MyProfilePageState._tileBorder,
          width: isEditing ? 1.2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: accentBg, shape: BoxShape.circle),
            child: Icon(icon, color: _MyProfilePageState._accent, size: 25),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: isEditing
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFFC7C7C7),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: controller,
                        keyboardType: keyboardType,
                        style: const TextStyle(color: Color(0xFFDADADA), fontSize: 15),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 4),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF4B5B60)),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: _MyProfilePageState._accent),
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFFC7C7C7),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (_displayValue.trim().isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF142328),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0xFF2A4A52),
                              width: 1,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 13,
                                color: Color(0xFF71C9D1),
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Not set yet',
                                style: TextStyle(
                                  color: Color(0xFF8BC0C7),
                                  fontSize: 13,
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Text(
                          _displayValue,
                          style: const TextStyle(
                            color: Color(0xFFDADADA),
                            fontSize: 15,
                          ),
                        ),
                    ],
                  ),
          ),
          if (trailingChevron)
            const Icon(Icons.chevron_right, color: Colors.white, size: 24),
        ],
      ),
    );
  }
}

String _authErrorMessage(FirebaseAuthException e) {
  switch (e.code) {
    case 'wrong-password':
      return 'Incorrect password. Email verification was not sent.';
    case 'invalid-email':
      return 'The new email address format is invalid.';
    case 'email-already-in-use':
      return 'This email is already linked to another Firebase account.';
    case 'requires-recent-login':
      return 'Please sign out, sign in again, then retry changing email.';
    case 'too-many-requests':
      return 'Too many attempts. Wait a few minutes, then try again.';
    default:
      return e.message ?? 'Could not send verification email (${e.code}).';
  }
}

class _EmailUpdateResult {
  const _EmailUpdateResult({
    this.error,
    this.verificationPending = false,
    this.sentToEmail,
  });

  final String? error;
  final bool verificationPending;
  final String? sentToEmail;
}
