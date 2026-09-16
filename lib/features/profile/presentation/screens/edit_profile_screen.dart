import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../shared/models/app_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../widgets/currency_picker.dart';

/// Edit name, avatar, currency and monthly budget.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final AppUser? _user = ref.read(currentUserProvider);
  late final TextEditingController _name = TextEditingController(text: _user?.name ?? '');
  late final TextEditingController _budget = TextEditingController(
    text: (_user?.monthlyBudget ?? 0) > 0 ? _user!.monthlyBudget.toStringAsFixed(2) : '',
  );

  late String _currency = _user?.currencyCode ?? 'USD';
  late String? _avatarPath = _user?.avatarUrl;
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _budget.dispose();
    super.dispose();
  }

  Future<void> _showAvatarOptions() async {
    final bool hasAvatar = _avatarPath != null && _avatarPath!.isNotEmpty;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Profile picture', style: sheetContext.text.titleMedium),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_rounded),
                  title: const Text('Take photo'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _pickImage(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded),
                  title: const Text('Choose from gallery'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _pickImage(ImageSource.gallery);
                  },
                ),
                if (hasAvatar)
                  ListTile(
                    leading: Icon(Icons.delete_outline_rounded, color: sheetContext.colors.error),
                    title: Text('Remove photo', style: TextStyle(color: sheetContext.colors.error)),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      setState(() => _avatarPath = null);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? file = await ImagePicker().pickImage(source: source, maxWidth: 512, maxHeight: 512, imageQuality: 85);
      if (file == null) return;

      final Directory appDir = await getApplicationDocumentsDirectory();
      final Directory avatarsDir = Directory('${appDir.path}/avatars');
      if (!avatarsDir.existsSync()) {
        await avatarsDir.create(recursive: true);
      }
      final String fileName = 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final String persistentPath = '${avatarsDir.path}/$fileName';
      await File(file.path).copy(persistentPath);

      if (mounted) {
        setState(() => _avatarPath = persistentPath);
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.warning(context, 'Could not select photo: $e');
      }
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_user == null) return;
    context.unfocus();

    setState(() => _submitting = true);

    final Failure? failure = await ref
        .read(authProvider.notifier)
        .updateProfile(
          _user.copyWith(name: _name.text.trim(), currencyCode: _currency, avatarUrl: _avatarPath, monthlyBudget: double.tryParse(_budget.text) ?? 0),
        );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (failure != null) {
      AppFeedback.error(context, failure);
    } else {
      AppFeedback.success(context, 'Profile updated');
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.page),
            children: <Widget>[
              Center(
                child: GestureDetector(
                  onTap: _showAvatarOptions,
                  child: Stack(
                    children: <Widget>[
                      UserAvatar(avatarUrl: _avatarPath, name: _name.text, radius: 48),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Material(
                          color: context.colors.primary,
                          shape: const CircleBorder(),
                          elevation: 2,
                          child: InkWell(
                            onTap: _showAvatarOptions,
                            customBorder: const CircleBorder(),
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              child: Icon(Icons.camera_alt_rounded, size: 18, color: context.colors.onPrimary),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AppSpacing.xxl.gapH,

              AppTextField(
                controller: _name,
                label: 'Full name',
                prefixIcon: Icons.person_outline_rounded,
                onChanged: (_) => setState(() {}),
                validator: (String? value) => (value ?? '').trim().length >= 2 ? null : 'Enter your name',
              ),
              AppSpacing.lg.gapH,

              // Email is the account identifier; changing it needs
              // re-verification, so it is read-only here by design.
              AppTextField(
                controller: TextEditingController(text: _user?.email ?? ''),
                label: 'Email',
                prefixIcon: Icons.mail_outline_rounded,
                enabled: false,
              ),
              AppSpacing.lg.gapH,

              Text('Currency', style: context.text.labelMedium),
              AppSpacing.sm.gapH,
              CurrencyPickerField(selected: _currency, onSelected: (String code) => setState(() => _currency = code)),
              AppSpacing.lg.gapH,

              AppTextField.amount(
                controller: _budget,
                label: 'Monthly budget (optional)',
                hint: 'Leave empty to hide the budget card',
                prefixText: _currency,
              ),
              AppSpacing.xxxl.gapH,

              AppButton(label: 'Save changes', icon: Icons.check_rounded, isLoading: _submitting, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
