import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/offline_service.dart';
import '../../../api/business_room_api.dart';

// ─── Show helper ──────────────────────────────────────────────────────────────

Future<RoomData?> showEditRoomDialog(
  BuildContext context, {
  required RoomData room,
  List<String> existingNames = const [],
}) {
  return showDialog<RoomData>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.55),
    builder: (_) => _EditRoomDialog(
      room: room,
      existingNames: existingNames,
    ),
  );
}

// ─── Dialog ───────────────────────────────────────────────────────────────────

class _EditRoomDialog extends StatefulWidget {
  const _EditRoomDialog({
    required this.room,
    required this.existingNames,
  });
  final RoomData room;
  final List<String> existingNames;

  @override
  State<_EditRoomDialog> createState() => _EditRoomDialogState();
}

class _EditRoomDialogState extends State<_EditRoomDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _capacityCtrl;
  late String _selectedStatus;
  bool _isSaving = false;
  bool _isOffline = false;
  StreamSubscription<bool>? _connectivitySub;

  static const _statusLabels = {
    'vacant': 'Vacant',
    'occupied': 'Occupied',
    'unavailable': 'Unavailable',
    'reserved': 'Reserved',
  };

  static const _statusColors = {
    'vacant': AppColors.accentGreen,
    'occupied': AppColors.primaryBlue,
    'unavailable': AppColors.accentOrange,
    'reserved': AppColors.accentPurple,
  };

  static const _statusIcons = {
    'vacant': Icons.check_circle_outline_rounded,
    'occupied': Icons.person_rounded,
    'unavailable': Icons.block_rounded,
    'reserved': Icons.bookmark_outline_rounded,
  };

  bool get _statusChanged => _selectedStatus != widget.room.roomStatus;
  bool get _canChangeStatus => widget.room.roomStatus != 'occupied';

  List<String> _getAvailableStatusOptions() {
    switch (widget.room.roomStatus) {
      case 'unavailable':
        return ['vacant', 'unavailable', 'reserved'];
      case 'reserved':
        return ['vacant', 'unavailable', 'reserved'];
      default: // vacant
        return ['vacant', 'unavailable', 'reserved'];
    }
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.room.roomNumber);
    _capacityCtrl = TextEditingController(text: widget.room.capacity.toString());
    _selectedStatus = widget.room.roomStatus;
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

    // Update room details (name + capacity)
    final result = await api.updateRoom(
      roomId: widget.room.id,
      roomNumber: name,
      capacity: capacity,
    );

    if (!result.success) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Failed to update room.'),
            backgroundColor: AppColors.accentRed,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Update status separately if changed
    if (_statusChanged) {
      await api.updateRoomStatus(
        roomId: widget.room.id,
        roomStatus: _selectedStatus,
      );
    }

    if (!mounted) return;

    final isOnline = ConnectivityService.instance.isOnline;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(
      RoomData(
        id: widget.room.id,
        roomNumber: name,
        capacity: capacity,
        roomStatus: _selectedStatus,
        createdAt: widget.room.createdAt,
        updatedAt: widget.room.updatedAt,
      ),
    );

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          isOnline
              ? 'Room updated successfully!'
              : 'Changes saved offline — will sync when you\'re back online.',
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
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
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
                  padding: const EdgeInsets.fromLTRB(22, 20, 16, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Edit Room',
                              style: TextStyle(
                                color: AppColors.textWhite,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Update details for Room ${widget.room.roomNumber}',
                              style: const TextStyle(
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
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
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
                            final otherNames = widget.existingNames
                                .where((n) =>
                                    n.toLowerCase() !=
                                    widget.room.roomNumber.toLowerCase())
                                .toList();
                            if (otherNames.any(
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
                        const SizedBox(height: 20),

                        // Status section
                        _buildLabel('Status'),
                        const SizedBox(height: 8),
                        if (_canChangeStatus)
                          _buildStatusRadios(_getAvailableStatusOptions())
                        else
                          _buildStatusReadOnly(),
                      ],
                    ),
                  ),
                ),

                // ── Footer ──────────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
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
                                      'Save Changes',
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

  // ── Status radios ──────────────────────────────────────────────────────────

  Widget _buildStatusRadios(List<String> options) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: options.map((status) {
          final isSelected = _selectedStatus == status;
          final color = _statusColors[status]!;
          final icon = _statusIcons[status]!;
          return GestureDetector(
            onTap: () => setState(() => _selectedStatus = status),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin:
                  const EdgeInsets.only(left: 8, right: 8, top: 2, bottom: 2),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? color.withOpacity(0.08) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected
                      ? color.withOpacity(0.4)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  // Radio circle
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? color : AppColors.textSubtle,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? Center(
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: color,
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Icon(icon, size: 15, color: color),
                  const SizedBox(width: 8),
                  Text(
                    _statusLabels[status]!,
                    style: TextStyle(
                      color: isSelected ? color : AppColors.textGray,
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Status read-only (occupied rooms) ─────────────────────────────────────

  Widget _buildStatusReadOnly() {
    final status = widget.room.roomStatus;
    final color = _statusColors[status] ?? AppColors.textGray;
    final icon = _statusIcons[status] ?? Icons.help_outline_rounded;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.inputBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withOpacity(0.35)),
                ),
                child: Text(
                  _statusLabels[status] ?? status,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.accentOrange.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppColors.accentOrange.withOpacity(0.2)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: AppColors.accentOrange,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'An occupied room\'s status is managed automatically by guest check-in/check-out.',
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
    );
  }
}
