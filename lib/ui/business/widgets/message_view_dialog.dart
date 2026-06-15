// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../api/messages_api.dart';

// ─── Show Helper ──────────────────────────────────────────────────────────────

/// Opens the letter-view dialog for a business inbox message.
/// [msg] is an [InboxMessage] from `message_recipients` joined with `messages`.
Future<void> showMessageViewDialog(
  BuildContext context,
  InboxMessage msg,
) async {
  showDialog(
    context: context,
    barrierColor:       Colors.black.withOpacity(0.55),
    barrierDismissible: true,
    builder: (_) => _MessageViewDialog(
      letter:  msg.content,   // frozen letter exactly as stored in DB
      subject: msg.subject,
      type:    msg.messageType,
    ),
  );
}

// ─── Dialog ───────────────────────────────────────────────────────────────────

class _MessageViewDialog extends StatelessWidget {
  const _MessageViewDialog({
    required this.letter,
    required this.subject,
    required this.type,
  });

  final String      letter;
  final String      subject;
  final MessageType type;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding:    const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Container(
          decoration: BoxDecoration(
            color:        AppColors.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border:       Border.all(color: AppColors.cardBorder),
            boxShadow: [
              BoxShadow(
                color:     Colors.black.withOpacity(0.5),
                blurRadius: 40,
                offset:    const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ModalHeader(subject: subject, type: type),
              const Divider(color: AppColors.cardBorder, height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: SelectableText(
                    letter,
                    style: const TextStyle(
                      color:    AppColors.textGray,
                      fontSize: 13,
                      height:   1.55,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Modal Header ─────────────────────────────────────────────────────────────

class _ModalHeader extends StatelessWidget {
  const _ModalHeader({required this.subject, required this.type});

  final String      subject;
  final MessageType type;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Message Letter',
                  style: TextStyle(
                    color:         AppColors.textWhite,
                    fontSize:      16,
                    fontWeight:    FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subject,
                  style: const TextStyle(
                    color:    AppColors.textGray,
                    fontSize: 12.5,
                  ),
                  maxLines:  2,
                  overflow:  TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _TypeBadge(type: type),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width:  28,
              height: 28,
              decoration: BoxDecoration(
                color:        AppColors.cardBorder,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.close_rounded,
                color: AppColors.textGray,
                size:  16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Type Badge ───────────────────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});
  final MessageType type;

  @override
  Widget build(BuildContext context) {
    final (label, color, emoji) = switch (type) {
      MessageType.compliance   => ('Compliance',   AppColors.accentRed,    '⚠️'),
      MessageType.announcement => ('Announcement', AppColors.accentPurple, '📣'),
      MessageType.general      => ('General',      AppColors.primaryBlue,  '💬'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color:      color,
              fontSize:   11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
