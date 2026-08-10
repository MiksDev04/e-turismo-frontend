// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/document_service.dart';
import '../../../core/utils/datetime_utils.dart';
import '../../business/widgets/business_document_preview_modal.dart';
import '../models/attraction_models.dart';

// ─── Attraction Details Data Model ───────────────────────────────────────────

class AttractionDetails {
  const AttractionDetails({
    required this.attractionId,
    required this.name,
    required this.attractionTypes,
    required this.status,
    required this.owner,
    required this.registeredDate,
    required this.street,
    required this.barangay,
    required this.phone,
    required this.email,
    required this.validIdUrl,
  });

  final String attractionId;
  final String name;
  final String attractionTypes;
  final AttractionStatus status;
  final String owner;
  final String registeredDate;
  final String street;
  final String barangay;
  final String phone;
  final String email;
  final String validIdUrl;
}

// ─── Show Helper ──────────────────────────────────────────────────────────────

Future<void> showAttractionDetailsModal(
  BuildContext context,
  AttractionDetails details,
) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.6),
    barrierDismissible: true,
    builder: (_) => AttractionDetailsModal(details: details),
  );
}

// ─── Modal Widget ─────────────────────────────────────────────────────────────

class AttractionDetailsModal extends StatefulWidget {
  const AttractionDetailsModal({super.key, required this.details});
  final AttractionDetails details;

  @override
  State<AttractionDetailsModal> createState() => _AttractionDetailsModalState();
}

class _AttractionDetailsModalState extends State<AttractionDetailsModal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  static const _modalMaxWidth = 520.0;

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
    return Center(
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: GestureDetector(
            onTap: () {},
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _modalMaxWidth),
                    child: Container(
                      margin: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.cardBorder),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 40,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ModalHeader(
                            onClose: () => Navigator.of(context).pop(),
                          ),
                          const Divider(color: AppColors.cardBorder, height: 1),
                          Flexible(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(20),
                              child: _Content(details: widget.details),
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
      ),
    );
  }
}

// ─── Modal Header ─────────────────────────────────────────────────────────────

class _ModalHeader extends StatelessWidget {
  const _ModalHeader({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      child: Row(
        children: [
          const Text(
            'Attraction Details',
            style: TextStyle(
              color: AppColors.textWhite,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(),
          _HoverIconButton(icon: Icons.close_rounded, onTap: onClose),
        ],
      ),
    );
  }
}

// ─── Content ──────────────────────────────────────────────────────────────────

class _Content extends StatelessWidget {
  const _Content({required this.details});
  final AttractionDetails details;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AttractionIdentity(details: details),
        const SizedBox(height: 20),
        const Divider(color: AppColors.cardBorder, height: 1),
        const SizedBox(height: 20),
        _DetailRow(
          first: _DetailField(label: 'Attraction Type(s)', value: details.attractionTypes),
          second: _DetailField(
            label: 'Registered',
            value: _formatRegisteredDate(details.registeredDate),
          ),
        ),
        const SizedBox(height: 20),
        const Divider(color: AppColors.cardBorder, height: 1),
        const SizedBox(height: 20),
        _ContactInfo(details: details),
        const SizedBox(height: 20),
        const Divider(color: AppColors.cardBorder, height: 1),
        const SizedBox(height: 20),
        _DocumentsSection(validIdUrl: details.validIdUrl),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _AttractionIdentity extends StatelessWidget {
  const _AttractionIdentity({required this.details});
  final AttractionDetails details;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primaryCyan.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primaryCyan.withOpacity(0.25)),
          ),
          child: const Icon(
            Icons.attractions_rounded,
            color: AppColors.primaryCyan,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                details.name,
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Managed by ${details.owner}',
                style: const TextStyle(
                  color: AppColors.textGray,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 8),
              _StatusBadge(status: details.status),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: 24),
        Expanded(child: second),
      ],
    );
  }
}

String _formatRegisteredDate(String rawValue) {
  final value = rawValue.trim();
  if (value.isEmpty || value == '—') {
    return '—';
  }

  final parsed = tryParseDbDateTime(value);
  if (parsed == null) {
    return value;
  }

  const monthNames = <String>[
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  return '${monthNames[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
}

String _formatPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length == 11) {
    return '${digits.substring(0, 4)}-${digits.substring(4, 7)}-${digits.substring(7)}';
  }
  return raw;
}

class _DetailField extends StatelessWidget {
  const _DetailField({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSubtle,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textWhite,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ContactInfo extends StatelessWidget {
  const _ContactInfo({required this.details});
  final AttractionDetails details;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (details.street.isNotEmpty && details.street != '—') parts.add(details.street);
    if (details.barangay.isNotEmpty && details.barangay != '—') parts.add(details.barangay);
    parts.add('San Pablo City');
    parts.add('Laguna');
    final addressText = parts.join(', ');

    return Column(
      children: [
        _ContactRow(icon: Icons.location_on_outlined, text: addressText),
        const SizedBox(height: 10),
        _ContactRow(icon: Icons.phone_outlined, text: _formatPhone(details.phone)),
        const SizedBox(height: 10),
        _ContactRow(icon: Icons.email_outlined, text: details.email),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.textSubtle, size: 15),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: AppColors.textGray, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _DocumentsSection extends StatelessWidget {
  const _DocumentsSection({required this.validIdUrl});

  final String validIdUrl;

  void _previewDocument(BuildContext context, String title, String url) {
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document URL not available.')),
      );
      return;
    }
    DocumentService.instance.prefetch(url);
    showDocumentPreviewModal(context, title, url);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Registration Documents',
          style: TextStyle(
            color: AppColors.textSubtle,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
        _DocumentChip(
          label: 'Valid ID',
          onTap: () => _previewDocument(context, 'Valid ID', validIdUrl),
        ),
      ],
    );
  }
}

class _DocumentChip extends StatefulWidget {
  const _DocumentChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_DocumentChip> createState() => _DocumentChipState();
}

class _DocumentChipState extends State<_DocumentChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.primaryCyan.withOpacity(0.1)
                : AppColors.cardBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hovered
                  ? AppColors.primaryCyan.withOpacity(0.5)
                  : AppColors.cardBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.insert_drive_file_outlined,
                color: _hovered ? AppColors.primaryCyan : AppColors.textGray,
                size: 13,
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  color: _hovered ? AppColors.primaryCyan : AppColors.textGray,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.visibility_outlined,
                color: _hovered ? AppColors.primaryCyan : AppColors.textSubtle,
                size: 11,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HoverIconButton extends StatefulWidget {
  const _HoverIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_HoverIconButton> createState() => _HoverIconButtonState();
}

class _HoverIconButtonState extends State<_HoverIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.cardBorder.withOpacity(0.8)
                : AppColors.cardBorder,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            widget.icon,
            color: _hovered ? AppColors.textWhite : AppColors.textGray,
            size: 16,
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final AttractionStatus status;

  static ({String label, Color color}) _styleFor(AttractionStatus s) {
    switch (s) {
      case AttractionStatus.approved:
        return (label: 'Approved', color: const Color(0xFF00C48C));
      case AttractionStatus.pending:
        return (label: 'Pending', color: const Color(0xFFFFB020));
      case AttractionStatus.rejected:
        return (label: 'Rejected', color: const Color(0xFFFF4D6A));
      case AttractionStatus.warning:
        return (label: 'Warning', color: const Color(0xFFFFB020));
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: style.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: style.color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: style.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            style.label,
            style: TextStyle(
              color: style.color,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
