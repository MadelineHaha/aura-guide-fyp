import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class MyProfilePage extends StatefulWidget {
  const MyProfilePage({super.key});

  @override
  State<MyProfilePage> createState() => _MyProfilePageState();
}

class _MyProfilePageState extends State<MyProfilePage> {
  bool _isEditing = false;
  bool _loading = true;
  String _patientId = '';
  String _loadedEmail = '';

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
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _addressController = TextEditingController();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }

    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data() ?? <String, dynamic>{};

      final birthDate = data['birthDate'];
      if (birthDate is Timestamp) {
        final dob = birthDate.toDate();
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

      _patientId = (data['userId'] as String?) ?? '';
      _nameController.text = (data['name'] as String?) ?? '';
      _emailController.text = (data['email'] as String?) ?? (user.email ?? '');
      _loadedEmail = _emailController.text.trim();
      _phoneController.text = (data['phoneNumber'] as String?) ?? '';
      _addressController.text = (data['address'] as String?) ?? '';
    } catch (_) {
      // Keep empty defaults if missing.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleEditSave() async {
    if (_isEditing) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final emailToSave = _emailController.text.trim();
        final emailChangeError = await _updateEmailIfNeeded(
          user: user,
          newEmail: emailToSave,
        );
        if (emailChangeError != null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(emailChangeError)),
          );
          return;
        }

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'name': _nameController.text.trim(),
          'email': emailToSave,
          'phoneNumber': _phoneController.text.trim(),
          'address': _addressController.text.trim(),
        }, SetOptions(merge: true));
        _loadedEmail = emailToSave;
      }
    }

    if (!mounted) return;
    setState(() => _isEditing = !_isEditing);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isEditing
              ? 'Editing mode enabled. Update fields then tap Save Profile.'
              : 'Profile changes saved.',
        ),
      ),
    );
  }

  Future<String?> _updateEmailIfNeeded({
    required User user,
    required String newEmail,
  }) async {
    final currentEmail = user.email?.trim() ?? '';
    if (newEmail.isEmpty) return 'Email cannot be empty.';
    if (newEmail == _loadedEmail || newEmail == currentEmail) return null;
    if (currentEmail.isEmpty) {
      return 'This account cannot change email because no current email is linked.';
    }

    final sameEmailUsers = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: newEmail)
        .limit(1)
        .get();
    if (sameEmailUsers.docs.isNotEmpty && sameEmailUsers.docs.first.id != user.uid) {
      return 'This email is already used by another account.';
    }

    final password = await _askForCurrentPassword();
    if (password == null || password.isEmpty) {
      return 'Password is required to change email.';
    }

    try {
      final cred = EmailAuthProvider.credential(
        email: currentEmail,
        password: password,
      );
      await user.reauthenticateWithCredential(cred);
      await user.verifyBeforeUpdateEmail(newEmail);
      return 'Verification link sent to $newEmail. Verify it, then save profile again.';
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Could not verify password or update email.';
    } catch (_) {
      return 'Failed to update email.';
    }
  }

  Future<String?> _askForCurrentPassword() async {
    String value = '';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        String? localError;
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text(
            'Confirm Password',
            style: TextStyle(color: Colors.white),
          ),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return TextField(
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                onChanged: (text) {
                  value = text;
                  if (localError != null) {
                    setDialogState(() => localError = null);
                  }
                },
                decoration: InputDecoration(
                  hintText: 'Enter current password',
                  hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                  errorText: localError,
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (value.trim().isEmpty) {
                  localError = 'Password is required';
                  (context as Element).markNeedsBuild();
                  return;
                }
                Navigator.of(context).pop();
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
    return value.trim().isEmpty ? null : value.trim();
  }

  @override
  void dispose() {
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
                      _nameController.text.trim(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _text,
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _patientId.isEmpty ? 'Patient ID:' : 'Patient ID: $_patientId',
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
                        child: const Text(
                          'Editing mode is ON. Update fields then tap Save Profile.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
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
          value: _emailController.text,
          accentBg: const Color(0xFF1B636A),
          isEditing: _isEditing,
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
        ),
        _ProfileTile(
          icon: Icons.person_outline,
          title: 'NAME',
          value: _nameController.text,
          accentBg: const Color(0xFF1B636A),
          trailingChevron: !_isEditing,
          isEditing: _isEditing,
          controller: _nameController,
        ),
        _ProfileTile(
          icon: Icons.phone_outlined,
          title: 'PHONE NUMBER',
          value: _phoneController.text,
          accentBg: const Color(0xFF1B636A),
          trailingChevron: !_isEditing,
          isEditing: _isEditing,
          controller: _phoneController,
          keyboardType: TextInputType.phone,
        ),
        _ProfileTile(
          icon: Icons.home_outlined,
          title: 'ADDRESS',
          value: _addressController.text,
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
                      if (value.trim().isEmpty)
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
                          value,
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
