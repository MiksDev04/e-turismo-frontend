// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

enum MessageTag { compliance, general, warning }

class ComplianceMessage {
  const ComplianceMessage({
    required this.title,
    required this.tag,
    required this.preview,
    required this.date,
  });

  final String title;
  final MessageTag tag;
  final String preview;
  final String date;
}

// ─── Sample message history ───────────────────────────────────────────────────

const _sampleMessages = [
  ComplianceMessage(
    title: 'Monthly Report Compliance Notice - March 2024',
    tag: MessageTag.compliance,
    preview:
        'This is to inform you that your monthly report for March 2024 is due. '
        'Please submit your report before the 5th of the following month to avoid penalties and late fees. The report should include all tourism statistics and visitor data for the month.',
    date: '2024-04-01',
  ),
  ComplianceMessage(
    title: 'System Update: New Report Features',
    tag: MessageTag.general,
    preview:
        'We have updated the tourism demographics system with new features '
        'including improved analytics, better report filtering, and enhanced data visualization tools. Check out the new dashboard for real-time insights.',
    date: '2024-04-20',
  ),
];

// ─── Compliance Message Dialog ────────────────────────────────────────────────

class ComplianceMessageDialog extends StatefulWidget {
  const ComplianceMessageDialog({
    super.key,
    required this.business,
    this.messages = _sampleMessages,
  });

  final String business;
  final List<ComplianceMessage> messages;

  @override
  State<ComplianceMessageDialog> createState() =>
      _ComplianceMessageDialogState();
}

class _ComplianceMessageDialogState extends State<ComplianceMessageDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.backgroundMid,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.55),
                    blurRadius: 40,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ─────────────────────────────────────────────────
                  _DialogHeader(
                    business: widget.business,
                    onClose: () => Navigator.of(context).pop(),
                  ),

                  // ── Message list ───────────────────────────────────────────
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      child: widget.messages.isEmpty
                          ? const _EmptyState()
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: widget.messages.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, i) =>
                                  _MessageCard(message: widget.messages[i]),
                            ),
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
}

// ─── Dialog Header ────────────────────────────────────────────────────────────

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.business, required this.onClose});

  final String business;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Message History',
                  style: TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  business,
                  style: TextStyle(
                    color: AppColors.textGray,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onClose,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.textSubtle.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                Icons.close_rounded,
                color: AppColors.textGray,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Message Card (with expand/collapse functionality) ──────────────────────

class _MessageCard extends StatefulWidget {
  const _MessageCard({required this.message});

  final ComplianceMessage message;

  @override
  State<_MessageCard> createState() => _MessageCardState();
}

class _MessageCardState extends State<_MessageCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isExpanded = !_isExpanded;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title + tag
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    widget.message.title,
                    style: TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _TagBadge(tag: widget.message.tag),
              ],
            ),

            const SizedBox(height: 8),

            // Preview/Full text with animation
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 250),
              crossFadeState: _isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: Text(
                widget.message.preview,
                style: TextStyle(
                  color: AppColors.textGray,
                  fontSize: 12.5,
                  height: 1.55,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              secondChild: Text(
                widget.message.preview,
                style: TextStyle(
                  color: AppColors.textGray,
                  fontSize: 12.5,
                  height: 1.55,
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Date and expand indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.message.date,
                  style: TextStyle(
                    color: AppColors.textSubtle,
                    fontSize: 12,
                  ),
                ),
                Icon(
                  _isExpanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: AppColors.textSubtle,
                  size: 18,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tag Badge ────────────────────────────────────────────────────────────────

class _TagBadge extends StatelessWidget {
  const _TagBadge({required this.tag});

  final MessageTag tag;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (tag) {
      MessageTag.compliance => ('compliance', AppColors.accentRed),
      MessageTag.general => ('general', AppColors.primaryBlue),
      MessageTag.warning => ('warning', AppColors.accentOrange),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.inbox_outlined,
              color: AppColors.textSubtle,
              size: 36,
            ),
            const SizedBox(height: 10),
            Text(
              'No messages sent yet.',
              style: TextStyle(
                color: AppColors.textSubtle,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}