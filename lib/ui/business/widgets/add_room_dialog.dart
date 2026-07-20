import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/offline_service.dart';
import '../../../api/business_room_api.dart';

// ─── Show helper ──────────────────────────────────────────────────────────────

Future<bool?> showAddRoomDialog(
  BuildContext context, {
  required String businessId,
  List<String> existingNames = const [],
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.55),
    builder: (_) => _AddRoomDialog(
      businessId: businessId,
      existingNames: existingNames,
    ),
  );
}

// ─── Dialog ───────────────────────────────────────────────────────────────────

class _AddRoomDialog extends StatefulWidget {
  const _AddRoomDialog({
    required this.businessId,
    required this.existingNames,
  });
  final String businessId;
  final List<String> existingNames;

  @override
  State<_AddRoomDialog> createState() => _AddRoomDialogState();
}

class _AddRoomDialogState extends State<_AddRoomDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController();
  bool _isSaving = false;
  bool _isOffline = false;
  StreamSubscription<bool>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _isOffline = !ConnectivityService.instance.isOnline;
    _connectivitySub =
        ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOffline = !online);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _capacityCtrl.dispose();
    _connectivitySub?.cancel();
    super.dispose();
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final api = BusinessRoomApi();
    final name = _nameCtrl.text.trim();
    final capacity = int.parse(_capacityCtrl.text.trim());

    final result = await api.createRoom(
      businessId: widget.businessId,
      roomNumber: name,
      capacity: capacity,
    );

    if (!result.success) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Failed to create room.'),
            backgroundColor: AppColors.accentRed,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    final isOnline = ConnectivityService.instance.isOnline;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(true);

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          isOnline
              ? 'Room created successfully!'
              : 'Room saved offline — will sync when you\'re back online.',
        ),
        backgroundColor:
            isOnline ? AppColors.primaryCyan : const Color(0xFFF59E0B),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 400;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 16 : 20,
        vertical: 24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Title bar ──────────────────────────────────────────────
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    isCompact ? 18 : 22,
                    isCompact ? 16 : 20,
                    isCompact ? 12 : 16,
                    14,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              AppColors.gradientStart,
                              AppColors.gradientEnd,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      SizedBox(width: isCompact ? 10 : 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Add New Room',
                              style: TextStyle(
                                color: AppColors.textWhite,
                                fontSize: isCompact ? 16 : 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Create a new room for your property',
                              style: TextStyle(
                                color: AppColors.textGray,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: const Icon(
                          Icons.close_rounded,
                          color: AppColors.textGray,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),

                if (_isOffline)
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: const Color(0xFFFFF8E1),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.wifi_off_rounded,
                          color: Color(0xFFF4A261),
                          size: 14,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Offline — changes will sync when you\'re back online.',
                            style: TextStyle(
                              color: Color(0xFF8D6E00),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // ── Form ────────────────────────────────────────────────────
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      isCompact ? 18 : 22,
                      0,
                      isCompact ? 18 : 22,
                      20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Room Name
                        _buildLabel('Room Name'),
                        const SizedBox(height: 6),
                        _buildField(
                          controller: _nameCtrl,
                          hint: 'e.g. 101',
                          validator: (v) {
                            final name = (v ?? '').trim();
                            if (name.isEmpty) return 'Room name is required.';
                            if (widget.existingNames.any(
                                (e) => e.toLowerCase() == name.toLowerCase())) {
                              return 'A room with this name already exists.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Capacity
                        _buildLabel('Capacity (pax)'),
                        const SizedBox(height: 6),
                        _buildField(
                          controller: _capacityCtrl,
                          hint: 'e.g. 4',
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          validator: (v) {
                            final cap = int.tryParse((v ?? '').trim());
                            if (cap == null || cap < 1) {
                              return 'Capacity must be at least 1.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Status info
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.accentGreen.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.accentGreen.withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline_rounded,
                                size: 14,
                                color: AppColors.accentGreen,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Room will be created with "Vacant" status by default.',
                                  style: TextStyle(
                                    color: AppColors.textGray,
                                    fontSize: 11.5,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Footer ──────────────────────────────────────────────────
                Container(
                  padding: EdgeInsets.fromLTRB(
                    isCompact ? 18 : 22,
                    0,
                    isCompact ? 18 : 22,
                    isCompact ? 14 : 18,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _isSaving
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.inputBackground,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.cardBorder),
                            ),
                            child: const Center(
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  color: AppColors.textGray,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: _isSaving ? null : _save,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              gradient: _isSaving
                                  ? null
                                  : const LinearGradient(
                                      colors: [
                                        AppColors.gradientStart,
                                        AppColors.gradientEnd,
                                      ],
                                    ),
                              color: _isSaving ? AppColors.textSubtle : null,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: _isSaving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Save',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textGray,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      style: const TextStyle(
        color: AppColors.textWhite,
        fontSize: 13,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: AppColors.textSubtle.withOpacity(0.6),
          fontSize: 13,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: AppColors.inputBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primaryCyan, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.accentRed),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.accentRed, width: 1.2),
        ),
        errorStyle: const TextStyle(
          color: AppColors.accentRed,
          fontSize: 11,
          height: 1.3,
        ),
      ),
    );
  }
}
