import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../api/messages_api.dart';
import '../../../api/admin_profile_api.dart';

// ─── Send Mode ────────────────────────────────────────────────────────────────

enum SendToMode { specific, all }

// ─── Admin Profile ────────────────────────────────────────────────────────────

class AdminProfile {
  const AdminProfile({
    required this.fullName,
    required this.email,
    required this.phone,
  });

  final String  fullName;
  final String  email;
  final String  phone;

  factory AdminProfile.fromProfileModel(ProfileModel m) => AdminProfile(
        fullName: m.fullName,
        email:    m.email,
        phone:    m.phone,
      );

  /// Shown while the real profile is still loading.
  static const placeholder = AdminProfile(
    fullName: '—',
    email:    '—',
    phone:    '—',
  );
}

// ─── Draft ────────────────────────────────────────────────────────────────────

class ComposeMessageDraft {
  ComposeMessageDraft({
    this.sendToMode = SendToMode.specific,
    this.selectedBusinesses = const [],
    this.messageType,
    this.subject = '',
    this.messageContent = '',
  });

  SendToMode            sendToMode;
  List<BusinessSummary> selectedBusinesses;
  MessageType?          messageType;
  String                subject;
  String                messageContent;

  bool get isValid {
    final hasRecipient =
        sendToMode == SendToMode.all || selectedBusinesses.isNotEmpty;
    return hasRecipient &&
        messageType != null &&
        subject.trim().isNotEmpty &&
        messageContent.trim().isNotEmpty;
  }

  ComposeMessageDraft copyWith({
    SendToMode?            sendToMode,
    List<BusinessSummary>? selectedBusinesses,
    MessageType?           messageType,
    String?                subject,
    String?                messageContent,
  }) {
    return ComposeMessageDraft(
      sendToMode:         sendToMode         ?? this.sendToMode,
      selectedBusinesses: selectedBusinesses ?? this.selectedBusinesses,
      messageType:        messageType        ?? this.messageType,
      subject:            subject            ?? this.subject,
      messageContent:     messageContent     ?? this.messageContent,
    );
  }
}

// ─── Show Helper ──────────────────────────────────────────────────────────────

Future<bool?> showComposeMessageDialog(
  BuildContext context, {
  required MessagesApi api,
  required String      senderId,
}) {
  return showDialog<bool>(
    context: context,
    // ignore: deprecated_member_use
    barrierColor:       Colors.black.withOpacity(0.65),
    barrierDismissible: true,
    builder: (_) => ComposeMessageDialog(api: api, senderId: senderId),
  );
}

// ─── Letter Builder ───────────────────────────────────────────────────────────
//
// [admin] is fetched once from public.profiles where id = senderId.
// All three fields are baked into the string at call time — changing the
// admin's profile later has zero effect on already-sent letters.

String _buildLetter(ComposeMessageDraft d, AdminProfile admin) {
  final String recipient;
  if (d.sendToMode == SendToMode.all) {
    recipient = 'All Registered Accommodations';
  } else if (d.selectedBusinesses.length == 1) {
    recipient = d.selectedBusinesses.first.name;
  } else if (d.selectedBusinesses.isEmpty) {
    recipient = '—';
  } else {
    recipient = d.selectedBusinesses.map((b) => b.name).join(', ');
  }
  return buildOfficialMessageLetter(
    recipient: recipient,
    subject: d.subject,
    messageContent: d.messageContent,
    senderFullName: admin.fullName,
    senderEmail: admin.email,
    senderPhone: admin.phone,
    messageType: d.messageType ?? MessageType.general,
  );
}

// ─── Main Dialog ──────────────────────────────────────────────────────────────

class ComposeMessageDialog extends StatefulWidget {
  const ComposeMessageDialog({
    super.key,
    required this.api,
    required this.senderId,
  });

  final MessagesApi api;
  final String      senderId;

  @override
  State<ComposeMessageDialog> createState() => _ComposeMessageDialogState();
}

class _ComposeMessageDialogState extends State<ComposeMessageDialog>
    with SingleTickerProviderStateMixin {
  // ── Animation ──────────────────────────────────────────────────────────────
  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;
  late Animation<Offset>   _slideAnim;

  // ── State ──────────────────────────────────────────────────────────────────
  late ComposeMessageDraft _draft;
  bool _previewMode = false;
  bool _sending     = false;
  final Set<String> _touched = {};

  // ── Admin profile ──────────────────────────────────────────────────────────
  AdminProfile _adminProfile    = AdminProfile.placeholder;
  bool         _loadingAdmin    = true;
  String?      _adminLoadError;

  // ── Businesses ─────────────────────────────────────────────────────────────
  List<BusinessSummary> _businesses   = [];
  bool                  _loadingBiz   = true;
  String?               _bizLoadError;

  // ── Text Controllers ───────────────────────────────────────────────────────
  late final TextEditingController _subjectCtrl;
  late final TextEditingController _contentCtrl;

  @override
  void initState() {
    super.initState();

    _animCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 260),
    );
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();

    _draft       = ComposeMessageDraft(messageType: MessageType.general);
    _subjectCtrl = TextEditingController();
    _contentCtrl = TextEditingController();

    _loadAdminProfile();
    _loadBusinesses();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _subjectCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  // ── Loaders ────────────────────────────────────────────────────────────────

  Future<void> _loadAdminProfile() async {
    setState(() { _loadingAdmin = true; _adminLoadError = null; });
    try {
      final model = await AdminProfileApi().fetchProfile();
      if (mounted) {
        setState(() => _adminProfile = AdminProfile.fromProfileModel(model));
      }
    } catch (_) {
      if (mounted) setState(() => _adminLoadError = 'Failed to load profile.');
    } finally {
      if (mounted) setState(() => _loadingAdmin = false);
    }
  }

  Future<void> _loadBusinesses() async {
    setState(() { _loadingBiz = true; _bizLoadError = null; });
    try {
      final list = await widget.api.fetchEligibleBusinesses();
      if (mounted) setState(() => _businesses = list);
    } catch (_) {
      if (mounted) setState(() => _bizLoadError = 'Failed to load businesses.');
    } finally {
      if (mounted) setState(() => _loadingBiz = false);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _syncText() {
    _draft.subject        = _subjectCtrl.text;
    _draft.messageContent = _contentCtrl.text;
  }

  void _touch(String field) {
    if (!_touched.contains(field)) setState(() => _touched.add(field));
  }

  String? _err(String field, bool invalid, String msg) =>
      (_touched.contains(field) && invalid) ? msg : null;

  void _togglePreview() {
    _syncText();
    setState(() => _previewMode = !_previewMode);
  }

  // ── Send ───────────────────────────────────────────────────────────────────

  Future<void> _send() async {
    _syncText();
    setState(() =>
        _touched.addAll(['business', 'messageType', 'subject', 'content']));

    if (!_draft.isValid) return;
    setState(() => _sending = true);

    // Admin name/email/phone are frozen into the letter string right here.
    // Even if the admin updates their profile tomorrow, this letter is unchanged.
    final frozenLetter = _buildLetter(_draft, _adminProfile);

    try {
      if (_draft.sendToMode == SendToMode.all) {
        await widget.api.sendToAll(
          senderId:    widget.senderId,
          messageType: _draft.messageType!,
          subject:     _draft.subject,
          content:     frozenLetter,
        );
      } else {
        await widget.api.sendToSelected(
          senderId:    widget.senderId,
          businessIds: _draft.selectedBusinesses.map((b) => b.id).toList(),
          messageType: _draft.messageType!,
          subject:     _draft.subject,
          content:     frozenLetter,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text('Failed to send: $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _syncText();

    final businessErr = _err(
      'business',
      _draft.sendToMode == SendToMode.specific &&
          _draft.selectedBusinesses.isEmpty,
      'Please select at least one business',
    );
    final typeErr    = _err('messageType', _draft.messageType == null,
                            'Please select a message type');
    final subjectErr = _err('subject', _draft.subject.trim().isEmpty,
                            'Subject is required');
    final contentErr = _err('content', _draft.messageContent.trim().isEmpty,
                            'Message content is required');

    // Block sending until the admin profile is resolved — we must not send
    // a letter with placeholder values.
    final canSend = _draft.isValid && !_sending && !_loadingAdmin;

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding:    const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: GestureDetector(
          onTap: () {},
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Container(
                    decoration: BoxDecoration(
                      color:        AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(16),
                      border:       Border.all(color: AppColors.cardBorder),
                      boxShadow: [
                        BoxShadow(
                          // ignore: deprecated_member_use
                          color:      Colors.black.withOpacity(0.55),
                          blurRadius: 48,
                          offset:     const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Header(
                          previewMode: _previewMode,
                          // Disable preview toggle while admin profile loads
                          // so the letter never shows placeholder values.
                          onToggle: _loadingAdmin ? null : _togglePreview,
                          onClose:  () => Navigator.of(context).pop(),
                        ),
                        const Divider(color: AppColors.cardBorder, height: 1),
                        // ── Admin profile error banner ───────────────────────
                        if (_adminLoadError != null)
                          _AdminErrorBanner(
                            error:   _adminLoadError!,
                            onRetry: _loadAdminProfile,
                          ),
                        Flexible(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: _previewMode
                                ? _LetterPreview(
                                    key:  const ValueKey('preview'),
                                    text: _buildLetter(_draft, _adminProfile),
                                  )
                                : _Form(
                                    key:          const ValueKey('form'),
                                    draft:        _draft,
                                    subjectCtrl:  _subjectCtrl,
                                    contentCtrl:  _contentCtrl,
                                    businesses:   _businesses,
                                    loadingBiz:   _loadingBiz,
                                    bizLoadError: _bizLoadError,
                                    onRetryBiz:   _loadBusinesses,
                                    businessErr:  businessErr,
                                    typeErr:      typeErr,
                                    subjectErr:   subjectErr,
                                    contentErr:   contentErr,
                                    onChanged:    (d) => setState(() => _draft = d),
                                    onTouch:      _touch,
                                    onSyncText:   _syncText,
                                    // Show admin profile summary at the bottom
                                    // of the form so the sender can verify
                                    // whose details will appear in the letter.
                                    adminProfile: _adminProfile,
                                    loadingAdmin: _loadingAdmin,
                                  ),
                          ),
                        ),
                        const Divider(color: AppColors.cardBorder, height: 1),
                        _Footer(
                          canSend:  canSend,
                          sending:  _sending,
                          onCancel: () => Navigator.of(context).pop(),
                          onSend:   _send,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Admin Error Banner ───────────────────────────────────────────────────────

class _AdminErrorBanner extends StatelessWidget {
  const _AdminErrorBanner({required this.error, required this.onRetry});

  final String       error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color:   Colors.redAccent.withOpacity(0.1),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.redAccent, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(error,
                style: const TextStyle(
                    color: Colors.redAccent, fontSize: 12)),
          ),
          GestureDetector(
            onTap: onRetry,
            child: const Text('Retry',
                style: TextStyle(
                  color:      AppColors.textWhite,
                  fontSize:   12,
                  fontWeight: FontWeight.w600,
                )),
          ),
        ],
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.previewMode,
    required this.onToggle,    // null while admin profile is loading
    required this.onClose,
  });

  final bool          previewMode;
  final VoidCallback? onToggle;
  final VoidCallback  onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      child: Row(
        children: [
          const Text(
            'Compose Message',
            style: TextStyle(
              color:         AppColors.textWhite,
              fontSize:      16,
              fontWeight:    FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onToggle,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity:  onToggle != null ? 1.0 : 0.4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color:        AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(20),
                  border:       Border.all(color: AppColors.cardBorder),
                ),
                child: Text(
                  previewMode ? 'Edit' : 'Preview Letter',
                  style: const TextStyle(
                    color:      AppColors.textWhite,
                    fontSize:   12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onClose,
            child: Container(
              width:  28,
              height: 28,
              decoration: BoxDecoration(
                color:        AppColors.cardBackground,
                borderRadius: BorderRadius.circular(8),
                border:       Border.all(color: AppColors.cardBorder),
              ),
              child: const Icon(Icons.close_rounded,
                  color: AppColors.textGray, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Compose Form ─────────────────────────────────────────────────────────────

class _Form extends StatelessWidget {
  const _Form({
    super.key,
    required this.draft,
    required this.subjectCtrl,
    required this.contentCtrl,
    required this.businesses,
    required this.loadingBiz,
    required this.bizLoadError,
    required this.onRetryBiz,
    required this.businessErr,
    required this.typeErr,
    required this.subjectErr,
    required this.contentErr,
    required this.onChanged,
    required this.onTouch,
    required this.onSyncText,
    required this.adminProfile,
    required this.loadingAdmin,
  });

  final ComposeMessageDraft              draft;
  final TextEditingController            subjectCtrl;
  final TextEditingController            contentCtrl;
  final List<BusinessSummary>            businesses;
  final bool                             loadingBiz;
  final String?                          bizLoadError;
  final VoidCallback                     onRetryBiz;
  final String?                          businessErr;
  final String?                          typeErr;
  final String?                          subjectErr;
  final String?                          contentErr;
  final ValueChanged<ComposeMessageDraft> onChanged;
  final ValueChanged<String>             onTouch;
  final VoidCallback                     onSyncText;
  final AdminProfile                     adminProfile;
  final bool                             loadingAdmin;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Label('Send To'),
          const SizedBox(height: 10),
          _SendToToggle(
            mode: draft.sendToMode,
            onChanged: (m) {
              onTouch('business');
              onChanged(draft.copyWith(
                sendToMode:         m,
                selectedBusinesses: m == SendToMode.all
                    ? [] : draft.selectedBusinesses,
              ));
            },
          ),
          if (draft.sendToMode == SendToMode.specific) ...[
            const SizedBox(height: 18),
            const _Label('Select Business'),
            const SizedBox(height: 10),
            _BusinessPicker(
              selected:   draft.selectedBusinesses,
              businesses: businesses,
              loading:    loadingBiz,
              loadError:  bizLoadError,
              onRetry:    onRetryBiz,
              errorText:  businessErr,
              onChanged: (list) {
                onTouch('business');
                onChanged(draft.copyWith(selectedBusinesses: list));
              },
            ),
          ],
          if (draft.sendToMode == SendToMode.all) ...[
            const SizedBox(height: 12),
            _BroadcastNotice(),
          ],
          const SizedBox(height: 18),
          const _Label('Message Type'),
          const SizedBox(height: 10),
          _TypeSelector(
            selected:  draft.messageType,
            errorText: typeErr,
            onChanged: (t) {
              onTouch('messageType');
              onChanged(draft.copyWith(messageType: t));
            },
          ),
          const SizedBox(height: 18),
          const _Label('Subject'),
          const SizedBox(height: 10),
          _StyledTextField(
            controller: subjectCtrl,
            hint:       'Enter subject...',
            errorText:  subjectErr,
            onChanged: (v) {
              onTouch('subject');
              onSyncText();
              onChanged(draft.copyWith(subject: v));
            },
            onEditingComplete: () => onTouch('subject'),
          ),
          const SizedBox(height: 18),
          const _Label('Message Content'),
          const SizedBox(height: 10),
          _StyledTextField(
            controller: contentCtrl,
            hint:       'Write your message here...',
            maxLines:   6,
            errorText:  contentErr,
            onChanged: (v) {
              onTouch('content');
              onSyncText();
              onChanged(draft.copyWith(messageContent: v));
            },
            onEditingComplete: () => onTouch('content'),
          ),

          // ── Sender info card ───────────────────────────────────────────────
          // Shows what will be printed in the letter's signature block.
          const SizedBox(height: 24),
          const _Label('Sender Details (appears in letter)'),
          const SizedBox(height: 10),
          _SenderCard(profile: adminProfile, loading: loadingAdmin),
        ],
      ),
    );
  }
}

// ─── Sender Card ─────────────────────────────────────────────────────────────

class _SenderCard extends StatelessWidget {
  const _SenderCard({required this.profile, required this.loading});

  final AdminProfile profile;
  final bool         loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color:        AppColors.primaryBlue.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          // ignore: deprecated_member_use
          color: AppColors.primaryBlue.withOpacity(0.2),
        ),
      ),
      child: loading
          ? const Center(
              child: SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.textGray),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SenderRow(
                  icon:  Icons.person_outline_rounded,
                  label: 'Name',
                  value: profile.fullName,
                ),
                const SizedBox(height: 6),
                _SenderRow(
                  icon:  Icons.email_outlined,
                  label: 'Email',
                  value: profile.email.isEmpty ? '—' : profile.email,
                ),
                const SizedBox(height: 6),
                _SenderRow(
                  icon:  Icons.phone_outlined,
                  label: 'Phone',
                  value: profile.phone,
                ),
              ],
            ),
    );
  }
}

class _SenderRow extends StatelessWidget {
  const _SenderRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String   label;
  final String   value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textGray, size: 13),
        const SizedBox(width: 6),
        Text('$label: ',
            style: const TextStyle(
              color:      AppColors.textGray,
              fontSize:   12,
              fontWeight: FontWeight.w500,
            )),
        Expanded(
          child: Text(value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color:    AppColors.textWhite,
                fontSize: 12,
              )),
        ),
      ],
    );
  }
}

// ─── Send-To Toggle ───────────────────────────────────────────────────────────

class _SendToToggle extends StatelessWidget {
  const _SendToToggle({required this.mode, required this.onChanged});

  final SendToMode               mode;
  final ValueChanged<SendToMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Segment(
            label:        'Specific Business',
            active:       mode == SendToMode.specific,
            leftRounded:  true,
            rightRounded: false,
            onTap:        () => onChanged(SendToMode.specific),
          ),
        ),
        Expanded(
          child: _Segment(
            label:        'All Businesses',
            active:       mode == SendToMode.all,
            leftRounded:  false,
            rightRounded: true,
            onTap:        () => onChanged(SendToMode.all),
          ),
        ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.active,
    required this.leftRounded,
    required this.rightRounded,
    required this.onTap,
  });

  final String       label;
  final bool         active;
  final bool         leftRounded;
  final bool         rightRounded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding:  const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  colors: [AppColors.gradientStart, AppColors.gradientEnd])
              : null,
          color:        active ? null : AppColors.cardBackground,
          borderRadius: BorderRadius.horizontal(
            left:  leftRounded  ? const Radius.circular(10) : Radius.zero,
            right: rightRounded ? const Radius.circular(10) : Radius.zero,
          ),
          border: Border.all(
              color: active ? Colors.transparent : AppColors.cardBorder),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color:      active ? Colors.white : AppColors.textGray,
              fontSize:   13,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Broadcast Notice ─────────────────────────────────────────────────────────

class _BroadcastNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color:        const Color(0xFF9B8AFB).withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            // ignore: deprecated_member_use
            color: const Color(0xFF9B8AFB).withOpacity(0.3)),
      ),
      child: Row(
        children: const [
          Icon(Icons.info_outline_rounded, color: Color(0xFF9B8AFB), size: 14),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Will be sent to all businesses with Approved or Warning status at time of sending.',
              style: TextStyle(
                color:    Color(0xFF9B8AFB),
                fontSize: 12,
                height:   1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Business Picker ──────────────────────────────────────────────────────────

class _BusinessPicker extends StatelessWidget {
  const _BusinessPicker({
    required this.selected,
    required this.businesses,
    required this.loading,
    required this.loadError,
    required this.onRetry,
    required this.onChanged,
    this.errorText,
  });

  final List<BusinessSummary>               selected;
  final List<BusinessSummary>               businesses;
  final bool                                loading;
  final String?                             loadError;
  final VoidCallback                        onRetry;
  final ValueChanged<List<BusinessSummary>> onChanged;
  final String?                             errorText;

  void _toggle(BusinessSummary biz, List<BusinessSummary> current) {
    final updated = List<BusinessSummary>.from(current);
    final idx     = updated.indexWhere((b) => b.id == biz.id);
    if (idx >= 0) updated.removeAt(idx); else updated.add(biz);
    onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        height: 48,
        decoration: BoxDecoration(
          color:        AppColors.cardBackground,
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(color: AppColors.cardBorder),
        ),
        child: const Center(
          child: SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.textGray),
          ),
        ),
      );
    }

    if (loadError != null) {
      return Container(
        height: 48,
        decoration: BoxDecoration(
          color:        AppColors.cardBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              // ignore: deprecated_member_use
              color: Colors.redAccent.withOpacity(0.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.redAccent, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(loadError!,
                  style: const TextStyle(
                      color: Colors.redAccent, fontSize: 13)),
            ),
            GestureDetector(
              onTap: onRetry,
              child: const Text('Retry',
                  style: TextStyle(
                    color:      AppColors.textWhite,
                    fontSize:   12.5,
                    fontWeight: FontWeight.w600,
                  )),
            ),
          ],
        ),
      );
    }

    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selected.isNotEmpty) ...[
          Wrap(
            spacing: 6, runSpacing: 6,
            children: selected.map((b) {
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  // ignore: deprecated_member_use
                  color: AppColors.primaryBlue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      // ignore: deprecated_member_use
                      color: AppColors.primaryBlue.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(b.name,
                        style: const TextStyle(
                            color: AppColors.textWhite, fontSize: 12)),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _toggle(b, selected),
                      child: const Icon(Icons.close_rounded,
                          color: AppColors.textGray, size: 12),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ],
        Container(
          decoration: BoxDecoration(
            color:        AppColors.cardBackground,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: hasError ? Colors.redAccent : AppColors.cardBorder),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<BusinessSummary>(
              value:            null,
              hint:             const Text('Add business...',
                  style: TextStyle(
                      color: AppColors.textSubtle, fontSize: 13.5)),
              isExpanded:       true,
              dropdownColor:    AppColors.cardBackground,
              iconEnabledColor: AppColors.textGray,
              style: const TextStyle(
                  color: AppColors.textWhite, fontSize: 13.5),
              items: businesses.map((b) {
                final isSelected = selected.any((s) => s.id == b.id);
                return DropdownMenuItem<BusinessSummary>(
                  value: b,
                  child: Row(
                    children: [
                      if (isSelected)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(Icons.check_rounded,
                              color: AppColors.primaryBlue, size: 14),
                        ),
                      Expanded(child: Text(b.name)),
                      if (b.status == 'warning')
                        Container(
                          margin:  const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            // ignore: deprecated_member_use
                            color: Colors.orange.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                // ignore: deprecated_member_use
                                color: Colors.orange.withOpacity(0.4)),
                          ),
                          child: const Text('Warning',
                              style: TextStyle(
                                color:      Colors.orange,
                                fontSize:   10,
                                fontWeight: FontWeight.w600,
                              )),
                        ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (b) { if (b != null) _toggle(b, selected); },
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 13),
            const SizedBox(width: 4),
            Text(errorText!,
                style: const TextStyle(
                    color: Colors.redAccent, fontSize: 12)),
          ]),
        ],
      ],
    );
  }
}

// ─── Message Type Selector ────────────────────────────────────────────────────

class _TypeSelector extends StatelessWidget {
  const _TypeSelector({
    required this.selected,
    required this.onChanged,
    this.errorText,
  });

  final MessageType?              selected;
  final ValueChanged<MessageType> onChanged;
  final String?                   errorText;

  static const _opts = [
    (type: MessageType.compliance,   color: Color(0xFFFF4D6A)),
    (type: MessageType.announcement, color: Color(0xFF9B8AFB)),
    (type: MessageType.general,      color: Color(0xFF1A6FFF)),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(_opts.length, (i) {
            final opt      = _opts[i];
            final isActive = selected == opt.type;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < _opts.length - 1 ? 8 : 0),
                child: GestureDetector(
                  onTap: () => onChanged(opt.type),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 170),
                    padding:  const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isActive
                          // ignore: deprecated_member_use
                          ? opt.color.withOpacity(0.13)
                          : AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isActive
                            // ignore: deprecated_member_use
                            ? opt.color.withOpacity(0.5)
                            : (errorText != null
                                // ignore: deprecated_member_use
                                ? Colors.redAccent.withOpacity(0.5)
                                : AppColors.cardBorder),
                        width: isActive ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(opt.type.icon,
                            style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            opt.type.label,
                            overflow:   TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isActive ? opt.color : AppColors.textGray,
                              fontSize:   12.5,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 13),
            const SizedBox(width: 4),
            Text(errorText!,
                style: const TextStyle(
                    color: Colors.redAccent, fontSize: 12)),
          ]),
        ],
      ],
    );
  }
}

// ─── Styled Text Field ────────────────────────────────────────────────────────

class _StyledTextField extends StatelessWidget {
  const _StyledTextField({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.onChanged,
    this.onEditingComplete,
    this.errorText,
  });

  final TextEditingController controller;
  final String                hint;
  final int                   maxLines;
  final ValueChanged<String>? onChanged;
  final VoidCallback?         onEditingComplete;
  final String?               errorText;

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color:        AppColors.cardBackground,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: hasError ? Colors.redAccent : AppColors.cardBorder),
          ),
          child: TextField(
            controller:        controller,
            onChanged:         onChanged,
            onEditingComplete: onEditingComplete,
            maxLines:          maxLines,
            maxLength:         maxLines == 1 ? 255 : null,
            style: const TextStyle(
              color:    AppColors.textWhite,
              fontSize: 13.5,
              height:   1.55,
            ),
            decoration: InputDecoration(
              hintText:       hint,
              hintStyle: const TextStyle(
                  color: AppColors.textSubtle, fontSize: 13.5),
              border:         InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
            ),
            buildCounter: maxLines == 1
                ? (_, {required currentLength,
                        required isFocused,
                        maxLength}) =>
                    Text(
                      '$currentLength/${maxLength ?? 255}',
                      style: TextStyle(
                        color: currentLength > 240
                            ? Colors.orange
                            : AppColors.textSubtle,
                        fontSize: 10.5,
                      ),
                    )
                : null,
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 13),
            const SizedBox(width: 4),
            Text(errorText!,
                style: const TextStyle(
                    color: Colors.redAccent, fontSize: 12)),
          ]),
        ],
      ],
    );
  }
}

// ─── Letter Preview ───────────────────────────────────────────────────────────

class _LetterPreview extends StatelessWidget {
  const _LetterPreview({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Container(
        width:   double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color:        AppColors.cardBackground,
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(color: AppColors.cardBorder),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color:    AppColors.textWhite,
            fontSize: 13,
            height:   1.75,
          ),
        ),
      ),
    );
  }
}

// ─── Field Label ──────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color:      AppColors.textGray,
        fontSize:   12.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

// ─── Footer ───────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer({
    required this.canSend,
    required this.sending,
    required this.onCancel,
    required this.onSend,
  });

  final bool         canSend;
  final bool         sending;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          GestureDetector(
            onTap: onCancel,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color:        AppColors.cardBackground,
                borderRadius: BorderRadius.circular(10),
                border:       Border.all(color: AppColors.cardBorder),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color:      AppColors.textGray,
                  fontSize:   13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: canSend ? onSend : null,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity:  canSend ? 1.0 : 0.4,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.gradientStart, AppColors.gradientEnd],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: canSend
                        ? [
                            BoxShadow(
                              // ignore: deprecated_member_use
                              color:      AppColors.primaryBlue.withOpacity(0.35),
                              blurRadius: 16,
                              offset:     const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (sending)
                        const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      else
                        const Icon(Icons.send_rounded,
                            color: Colors.white, size: 15),
                      const SizedBox(width: 8),
                      Text(
                        sending ? 'Sending...' : 'Send Message',
                        style: const TextStyle(
                          color:      Colors.white,
                          fontSize:   13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}