// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../api/messages_api.dart';

// ─── Message View Data ────────────────────────────────────────────────────────

class MessageViewData {
  const MessageViewData({
    required this.subject,
    required this.recipient,
    required this.date,
    required this.messageType,
    required this.messageContent,
    // Optional — used when viewing a targeted (non-broadcast) message
    // to lazy-load the per-business delivery report.
    this.messageId,
  });

  final String subject;
  final String recipient;
  final String date;

  /// e.g. 'COMPLIANCE NOTICE' | 'ANNOUNCEMENT' | 'GENERAL NOTICE'
  final String messageType;
  final String messageContent;

  /// `messages.id` — supply this to enable the delivery report tab.
  final String? messageId;
}

// ─── Show Helper ──────────────────────────────────────────────────────────────

Future<void> showMessageViewDialog(
  BuildContext context,
  MessagesApi api,
  MessageViewData data,
) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.65),
    barrierDismissible: true,
    builder: (_) => MessageViewDialog(api: api, data: data),
  );
}

// ─── Main Dialog Widget ───────────────────────────────────────────────────────

class MessageViewDialog extends StatefulWidget {
  const MessageViewDialog({super.key, required this.api, required this.data});

  final MessagesApi api;
  final MessageViewData data;

  @override
  State<MessageViewDialog> createState() => _MessageViewDialogState();
}

class _MessageViewDialogState extends State<MessageViewDialog>
    with SingleTickerProviderStateMixin {
  // ── Animation ──────────────────────────────────────────────────────────────
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  // ── Delivery report (loaded only when messageId is supplied) ───────────────
  List<DeliveryReceipt>? _deliveryReport;
  bool _loadingReport = false;
  String? _reportError;

  // ── Tab (letter | report) ──────────────────────────────────────────────────
  bool _showReport = false;

  bool get _hasReport => widget.data.messageId != null;

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

  // ── Delivery report loader ─────────────────────────────────────────────────

  Future<void> _loadDeliveryReport() async {
    if (widget.data.messageId == null) return;
    setState(() {
      _loadingReport = true;
      _reportError = null;
    });
    try {
      final report = await widget.api.fetchDeliveryReport(
        widget.data.messageId!,
      );
      if (mounted) setState(() => _deliveryReport = report);
    } catch (e) {
      if (mounted)
        setState(() => _reportError = 'Failed to load delivery report.');
    } finally {
      if (mounted) setState(() => _loadingReport = false);
    }
  }

  void _switchToReport() {
    setState(() => _showReport = true);
    if (_deliveryReport == null && !_loadingReport) {
      _loadDeliveryReport();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: GestureDetector(
          onTap: () {},
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 580),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.cardBorder),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.55),
                          blurRadius: 48,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Header ─────────────────────────────────────────
                        _Header(
                          data: widget.data,
                          hasReport: _hasReport,
                          showReport: _showReport,
                          onShowLetter: () =>
                              setState(() => _showReport = false),
                          onShowReport: _switchToReport,
                        ),
                        const Divider(color: AppColors.cardBorder, height: 1),

                        // ── Body ───────────────────────────────────────────
                        Flexible(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: _showReport
                                ? _DeliveryReportBody(
                                    key: const ValueKey('report'),
                                    receipts: _deliveryReport,
                                    loading: _loadingReport,
                                    error: _reportError,
                                    onRetry: _loadDeliveryReport,
                                  )
                                : _LetterBody(
                                    key: const ValueKey('letter'),
                                    text: widget.data.messageContent,
                                  ),
                          ),
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

// ─── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.data,
    required this.hasReport,
    required this.showReport,
    required this.onShowLetter,
    required this.onShowReport,
  });

  final MessageViewData data;
  final bool hasReport;
  final bool showReport;
  final VoidCallback onShowLetter;
  final VoidCallback onShowReport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title + meta ─────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.subject,
                  style: const TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'To: ${data.recipient} • ${data.date}',
                  style: const TextStyle(
                    color: AppColors.textGray,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // ── Tab toggle (only when a messageId is available) ───────────────
          if (hasReport) ...[
            _TabPill(label: 'Letter', active: !showReport, onTap: onShowLetter),
            const SizedBox(width: 6),
            _TabPill(
              label: 'Delivery',
              active: showReport,
              onTap: onShowReport,
            ),
            const SizedBox(width: 10),
          ],

          // ── Close button ─────────────────────────────────────────────────
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: const Icon(
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

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  colors: [AppColors.gradientStart, AppColors.gradientEnd],
                )
              : null,
          color: active ? null : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? Colors.transparent : AppColors.cardBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : AppColors.textGray,
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ─── Letter Body ──────────────────────────────────────────────────────────────

class _LetterBody extends StatelessWidget {
  const _LetterBody({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.textWhite,
            fontSize: 13,
            height: 1.75,
          ),
        ),
      ),
    );
  }
}

// ─── Delivery Report Body ─────────────────────────────────────────────────────

class _DeliveryReportBody extends StatelessWidget {
  const _DeliveryReportBody({
    super.key,
    required this.receipts,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final List<DeliveryReceipt>? receipts;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.textGray,
          ),
        ),
      );
    }

    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.redAccent,
              size: 24,
            ),
            const SizedBox(height: 10),
            Text(
              error!,
              style: const TextStyle(color: AppColors.textGray, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final list = receipts ?? [];

    if (list.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: Text(
            'No recipients found.',
            style: TextStyle(color: AppColors.textGray),
          ),
        ),
      );
    }

    // ── Summary row ────────────────────────────────────────────────────────
    final readCount = list.where((r) => r.isRead).length;
    final unreadCount = list.length - readCount;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Summary bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            children: [
              _SummaryChip(
                label: '$readCount Read',
                color: const Color(0xFF22C55E),
                icon: Icons.done_all_rounded,
              ),
              const SizedBox(width: 8),
              _SummaryChip(
                label: '$unreadCount Unread',
                color: AppColors.textGray,
                icon: Icons.mark_email_unread_outlined,
              ),
            ],
          ),
        ),
        const Divider(color: AppColors.cardBorder, height: 1),

        // Receipt list
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: list.length,
            separatorBuilder: (_, __) =>
                const Divider(color: AppColors.cardBorder, height: 1),
            itemBuilder: (_, i) => _ReceiptRow(receipt: list[i]),
          ),
        ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.receipt});

  final DeliveryReceipt receipt;

  String _fmtOpt(DateTime? dt) {
    if (dt == null) return '—';
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isRead = receipt.isRead;
    final color = isRead ? const Color(0xFF22C55E) : AppColors.textGray;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Status icon
          Icon(
            isRead ? Icons.done_all_rounded : Icons.radio_button_unchecked,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 10),

          // Business name + status badge
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  receipt.businessName,
                  style: const TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (receipt.businessStatus != 'approved') ...[
                  const SizedBox(height: 2),
                  Text(
                    receipt.businessStatus,
                    style: const TextStyle(color: Colors.orange, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),

          // Read-at timestamp
          Text(
            isRead ? 'Read ${_fmtOpt(receipt.readAt)}' : 'Unread',
            style: TextStyle(color: color, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
