// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/privacy_policy_text.dart';

// =============================================================================
// PUBLIC HELPER
// =============================================================================

/// Shows the Terms of Use and Data Privacy consent dialog.
///
/// [accountType] is one of 'attraction', 'business', or 'admin'.
/// Returns `true` when the user ticks the checkbox and presses "I Agree",
/// otherwise `false` (Decline or dismissed — the dialog cannot be dismissed
/// by tapping outside or pressing the back button).
Future<bool> showPrivacyConsent(
  BuildContext context, {
  required String accountType,
}) async {
  final agreed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PrivacyConsentDialog(accountType: accountType),
  );
  return agreed ?? false;
}

// =============================================================================
// DIALOG WIDGET (private)
// =============================================================================

class _PrivacyConsentDialog extends StatefulWidget {
  const _PrivacyConsentDialog({required this.accountType});

  final String accountType;

  @override
  State<_PrivacyConsentDialog> createState() => _PrivacyConsentDialogState();
}

class _PrivacyConsentDialogState extends State<_PrivacyConsentDialog> {
  bool _agreed = false;

  List<PolicySection> get _sections => [
        ...kPolicySectionsCommon,
        if (widget.accountType == 'admin')
          kPolicySectionAdmin
        else
          kPolicySectionBusinessAttraction,
        kPolicySectionContact,
      ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Terms of Use and Data Privacy Notice',
                  style: TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Version $kPrivacyPolicyVersion. Please read carefully before registering.',
                  style: const TextStyle(
                    color: AppColors.textGray,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final section in _sections)
                          _buildSection(section),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(height: 1, color: AppColors.cardBorder),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _agreed,
                  onChanged: (value) =>
                      setState(() => _agreed = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  activeColor: AppColors.primaryBlue,
                  title: const Text(
                    'I have read and agree to the Terms of Use and Data Privacy Notice.',
                    style: TextStyle(
                      color: AppColors.textGray,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.cardBorder),
                          foregroundColor: AppColors.textGray,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                        ),
                        child: const Text(
                          'Decline',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed:
                            _agreed ? () => Navigator.pop(context, true) : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          disabledBackgroundColor:
                              AppColors.primaryBlue.withOpacity(0.30),
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                        ),
                        child: const Text(
                          'I Agree',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(PolicySection section) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.heading,
            style: const TextStyle(
              color: AppColors.textWhite,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            section.body,
            style: const TextStyle(
              color: AppColors.textGray,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          if (section.bullets.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final bullet in section.bullets)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '\u2022  ',
                      style: TextStyle(
                        color: AppColors.textGray,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        bullet,
                        style: const TextStyle(
                          color: AppColors.textGray,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
