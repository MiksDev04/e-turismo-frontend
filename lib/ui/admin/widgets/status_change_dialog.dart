// lib/ui/admin/widgets/status_change_dialog.dart

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// Shared modal for changing an accommodation/attraction status to Warning or
/// reverting it to Approved. A mandatory reason is collected and handed to
/// [onConfirm], which should notify the owner with an official message.
class StatusChangeDialog extends StatefulWidget {
  const StatusChangeDialog({
    super.key,
    this.title = 'Manage Business Status',
    required this.entityName,
    required this.currentStatusLabel,
    required this.currentStatusColor,
    this.currentStatusIcon,
    required this.canSetWarning,
    required this.canSetApproved,
    required this.onConfirm,
  });

  final String title;
  final String entityName;
  final String currentStatusLabel;
  final Color currentStatusColor;
  final IconData? currentStatusIcon;
  final bool canSetWarning;
  final bool canSetApproved;
  final Future<void> Function(String status, String reason) onConfirm;

  @override
  State<StatusChangeDialog> createState() => _StatusChangeDialogState();
}

class _StatusChangeDialogState extends State<StatusChangeDialog> {
  final _reasonCtrl = TextEditingController();
  final _reasonNode = FocusNode();

  bool _isSaving = false;
  String? _selected;

  bool get _canSetWarning => widget.canSetWarning;
  bool get _canSetApproved => widget.canSetApproved;
  bool get _hasAction => _canSetWarning || _canSetApproved;

  @override
  void initState() {
    super.initState();
    _reasonCtrl.addListener(() => setState(() {}));
    if (_canSetWarning) {
      _selected = 'warning';
    } else if (_canSetApproved) {
      _selected = 'approved';
    } else {
      _selected = null;
    }
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _reasonNode.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final reason = _reasonCtrl.text.trim();
    final selected = _selected;
    if (reason.isEmpty || selected == null) return;
    setState(() => _isSaving = true);
    await widget.onConfirm(selected, reason);
    if (mounted) Navigator.of(context).pop();
  }

  Widget _buildActionInfo({
    required String label,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppColors.textSubtle,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStatusChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: widget.currentStatusColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: widget.currentStatusColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.currentStatusIcon ?? Icons.badge_rounded,
            color: widget.currentStatusColor,
            size: 13,
          ),
          const SizedBox(width: 5),
          Text(
            widget.currentStatusLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: TextStyle(
              color: widget.currentStatusColor,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.cardBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryCyan.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.manage_accounts_rounded,
                      color: AppColors.primaryCyan,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: AppColors.textWhite,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.entityName,
                          style: const TextStyle(
                            color: AppColors.textGray,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: AppColors.textGray,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(color: AppColors.cardBorder, height: 1),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Text(
                    'Current Status',
                    style: TextStyle(color: AppColors.textGray, fontSize: 12),
                  ),
                  const Spacer(),
                  _buildCurrentStatusChip(),
                ],
              ),
              const SizedBox(height: 16),
              if (!_hasAction) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentOrange.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.accentOrange.withOpacity(0.25),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 14,
                        color: AppColors.accentOrange,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No status change is available. Warning can only be set '
                          'for accounts with no activity for 90+ days (Inactive or '
                          'No Activity) whose current status is Approved.',
                          style: TextStyle(
                            color: AppColors.accentOrange,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textGray,
                      side: BorderSide(color: AppColors.cardBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Close', style: TextStyle(fontSize: 13)),
                  ),
                ),
              ],
              if (_hasAction) ...[
                if (_canSetWarning)
                  _buildActionInfo(
                    label: 'Set to Warning',
                    description:
                        'Sets Warning after 90+ days of no activity (or none on record).',
                    icon: Icons.warning_amber_rounded,
                    color: AppColors.accentOrange,
                  ),
                if (_canSetApproved)
                  _buildActionInfo(
                    label: 'Revert to Approved',
                    description: 'Remove warning and restore good standing.',
                    icon: Icons.check_circle_outline_rounded,
                    color: AppColors.accentGreen,
                  ),
                const SizedBox(height: 16),
                Text(
                  'Reason for change *',
                  style: TextStyle(
                    color: AppColors.textGray,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _reasonCtrl,
                  focusNode: _reasonNode,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(color: AppColors.textWhite, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Explain why this status is being changed...',
                    hintStyle: const TextStyle(
                      color: AppColors.textSubtle, fontSize: 13,
                    ),
                    filled: true,
                    fillColor: AppColors.cardBackground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.cardBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.primaryCyan),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textGray,
                          side: BorderSide(color: AppColors.cardBorder),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: (_isSaving || _reasonCtrl.text.trim().isEmpty)
                            ? null
                            : _confirm,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryCyan,
                          foregroundColor: Colors.black,
                          disabledBackgroundColor: AppColors.primaryCyan.withOpacity(0.25),
                          disabledForegroundColor: Colors.black38,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black54,
                                ),
                              )
                            : const Text(
                                'Confirm',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
