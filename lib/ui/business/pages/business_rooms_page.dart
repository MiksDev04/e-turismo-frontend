import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/business_page_cache.dart';
import '../../../core/services/offline_service.dart';
import '../../shared/layouts/business_layout.dart';
import '../../shared/widgets/paginator.dart';
import '../../../api/business_room_api.dart';
import '../../shared/widgets/action_icon_button.dart';
import '../widgets/edit_room_dialog.dart';
import '../widgets/add_room_dialog.dart';

// ─── Filter Options ───────────────────────────────────────────────────────────

enum _Filter { all, vacant, occupied, unavailable, reserved }

// ─── Business Rooms Page ──────────────────────────────────────────────────────

class BusinessRoomsPage extends StatefulWidget {
  const BusinessRoomsPage({super.key});

  @override
  State<BusinessRoomsPage> createState() => _BusinessRoomsPageState();
}

class _BusinessRoomsPageState extends State<BusinessRoomsPage> {
  final _api = BusinessRoomApi();

  String? _businessId;
  List<RoomData> _rooms = [];
  bool _isLoading = true;
  String? _loadError;

  bool _isOffline = false;
  StreamSubscription<bool>? _connectivitySub;
  StreamSubscription<SyncState>? _syncSub;

  _Filter _activeFilter = _Filter.all;
  int _currentPage = 0;
  int _pageSize = 10;
  int _totalPages = 0;
  int _totalItems = 0;

  static const List<int> _pageSizeOptions = [10, 20, 30];

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _isOffline = !ConnectivityService.instance.isOnline;
    _subscribeToConnectivity();
    _subscribeToSync();

    // Sync cache check — renders immediately, no spinner.
    final cache = BusinessPageCacheService();
    if (_activeFilter == _Filter.all &&
        _currentPage == 0 &&
        cache.hasData(BusinessPageCacheKeys.rooms)) {
      final cached = cache.get<Map<String, dynamic>>(BusinessPageCacheKeys.rooms);
      if (cached != null) {
        _rooms      = cached['rooms'];
        _totalPages = cached['totalPages'];
        _totalItems = cached['totalItems'];
        _isLoading  = false;
      }
    }

    _init();
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }

  // ── Connectivity ──────────────────────────────────────────────────────────

  void _subscribeToConnectivity() {
    _connectivitySub =
        ConnectivityService.instance.onConnectivityChanged.listen((isOnline) {
      if (!mounted) return;
      if (isOnline && _isOffline) {
        setState(() => _isOffline = false);
      } else if (!isOnline && !_isOffline) {
        setState(() => _isOffline = true);
      }
    });
  }

  // ── Sync completion subscription ───────────────────────────────────────

  void _subscribeToSync() {
    _syncSub = SyncService.instance.syncStateStream.listen((state) {
      if (!mounted) return;
      if (state.status == SyncStatus.synced) {
        _loadRooms(showLoading: false);
      }
    });
  }

  // ── Init & data loading ───────────────────────────────────────────────────

  Future<void> _init() async {
    final id = await _api.fetchBusinessId();
    if (!mounted) return;

    if (id == null) {
      setState(() {
        _isLoading = false;
        _loadError = 'Business account not found. Please check your connection '
            'and try again.';
      });
      return;
    }

    _businessId = id;
    if (_isLoading) await _loadRooms();
  }

  String? _serverStatus() => switch (_activeFilter) {
        _Filter.all => null,
        _Filter.vacant => 'vacant',
        _Filter.occupied => 'occupied',
        _Filter.unavailable => 'unavailable',
        _Filter.reserved => 'reserved',
      };

  Future<void> _loadRooms({bool showLoading = true}) async {
    if (_businessId == null) return;
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    } else {
      _loadError = null;
    }
    final result = await _api.fetchRoomsPaginated(
      _businessId!,
      page: _currentPage + 1,
      pageSize: _pageSize,
      status: _serverStatus(),
    );
    if (!mounted) return;
    if (result.isSuccess) {
      final data = result.data!;
      setState(() {
        _rooms = data.data;
        _totalPages = data.pageCount;
        _totalItems = data.totalCount;
        _isLoading = false;
      });
      // Only cache the default filter state (all, page 0).
      if (_activeFilter == _Filter.all && _currentPage == 0) {
        BusinessPageCacheService().set(BusinessPageCacheKeys.rooms, {
          'rooms':      data.data,
          'totalPages': data.pageCount,
          'totalItems': data.totalCount,
        });
      }
    } else {
      setState(() {
        _isLoading = false;
        _loadError = result.error;
      });
    }
  }

  // ── Status change ─────────────────────────────────────────────────────────

  static const _labels = {
    'vacant': 'Vacant',
    'occupied': 'Occupied',
    'unavailable': 'Unavailable',
    'reserved': 'Reserved',
  };

  Future<void> _onStatusChange(RoomData room, String newStatus) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (_) => _ConfirmDialog(
        roomNumber: room.roomNumber,
        newStatus: newStatus,
        statusColor: _statusColor(newStatus),
        statusIcon: _statusIcon(newStatus),
      ),
    );

    if (confirm != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.primaryCyan),
      ),
    );

    final result = await _api.updateRoomStatus(
      roomId: room.id,
      roomStatus: newStatus,
    );

    if (!mounted) return;
    Navigator.of(context).pop();

    if (result.success) {
      _showSnack(
          'Room ${room.roomNumber} marked as ${_labels[newStatus]?.toLowerCase()}.');
      // Invalidate dashboard cache — room stats may have changed.
      BusinessPageCacheService().invalidate(BusinessPageCacheKeys.dashboardDash);
      _loadRooms();
    } else {
      _showSnack(result.error ?? 'Failed to update room status.',
          isError: true);
    }
  }

  Future<void> _onEditRoom(RoomData room) async {
    final names = _rooms.map((r) => r.roomNumber).toList();
    final updated = await showEditRoomDialog(
      context,
      room: room,
      existingNames: names,
    );
    if (updated != null && mounted) {
      // Invalidate dashboard cache — room count or details may have changed.
      BusinessPageCacheService().invalidate(BusinessPageCacheKeys.dashboardDash);
      _loadRooms();
    }
  }

  Future<void> _onAddRoom() async {
    if (_businessId == null) {
      _showSnack('Business account not found.', isError: true);
      return;
    }
    final names = _rooms.map((r) => r.roomNumber).toList();
    final created = await showAddRoomDialog(
      context,
      businessId: _businessId!,
      existingNames: names,
    );
    if (created == true && mounted) {
      // Invalidate dashboard cache — room count may have changed.
      BusinessPageCacheService().invalidate(BusinessPageCacheKeys.dashboardDash);
      _loadRooms();
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.accentRed : AppColors.primaryCyan,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Color _statusColor(String status) => switch (status) {
        'vacant' => AppColors.accentGreen,
        'occupied' => AppColors.primaryBlue,
        'unavailable' => AppColors.accentOrange,
        'reserved' => AppColors.accentPurple,
        _ => AppColors.textGray,
      };

  IconData _statusIcon(String status) => switch (status) {
        'vacant' => Icons.check_circle_outline_rounded,
        'occupied' => Icons.person_rounded,
        'unavailable' => Icons.block_rounded,
        'reserved' => Icons.bookmark_outline_rounded,
        _ => Icons.help_outline_rounded,
      };

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return BusinessLayout(
      title: 'Rooms',
      selectedIndex: 3,
      onNavSelected: (_) {},
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 600;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isOffline) const _OfflineBanner(),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.primaryCyan,
                  backgroundColor: AppColors.cardBackground,
                  onRefresh: _loadRooms,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.all(isNarrow ? 16 : 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PageHeader(
                          totalRooms: _totalItems,
                          onCreateRoom: _onAddRoom,
                          isOffline: _isOffline,
                        ),
                        const SizedBox(height: 16),
                        _FilterTabBar(
                          activeFilter: _activeFilter,
                          onChanged: (f) {
                            setState(() {
                              _activeFilter = f;
                              _currentPage = 0;
                            });
                            _loadRooms();
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildBody(isNarrow),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(bool isNarrow) {
    if (_isLoading) return const _LoadingState();
    if (_loadError != null) return _ErrorState(message: _loadError!, onRetry: _businessId == null ? _init : _loadRooms);
    if (_rooms.isEmpty) return const _EmptyState();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isNarrow)
          _RoomTable(
            rooms: _rooms,
            statusColor: _statusColor,
            statusIcon: _statusIcon,
            onEdit: _onEditRoom,
          )
        else
          ..._rooms.map((room) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RoomCard(
                room: room,
                statusColor: _statusColor,
                statusIcon: _statusIcon,
                onEdit: _onEditRoom,
              ),
            );
          }),
        const SizedBox(height: 12),
        Paginator(
          currentPage: _currentPage,
          totalPages: _totalPages,
          totalItems: _totalItems,
          pageSize: _pageSize,
          pageSizeOptions: _pageSizeOptions,
          onPageSizeChanged: (size) {
            setState(() {
              _pageSize = size;
              _currentPage = 0;
            });
            _loadRooms();
          },
          onPageChanged: (page) {
            setState(() => _currentPage = page);
            _loadRooms();
          },
        ),
      ],
    );
  }
}

// ─── Confirm Dialog ───────────────────────────────────────────────────────────

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.roomNumber,
    required this.newStatus,
    required this.statusColor,
    required this.statusIcon,
  });

  final String roomNumber;
  final String newStatus;
  final Color statusColor;
  final IconData statusIcon;

  static const _labels = {
    'vacant': 'Vacant',
    'occupied': 'Occupied',
    'unavailable': 'Unavailable',
    'reserved': 'Reserved',
  };

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardBackground,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.cardBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(statusIcon, color: statusColor, size: 20),
              ),
              const SizedBox(height: 12),
              Text(
                'Change to ${_labels[newStatus]}?',
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Room $roomNumber will be marked as ${_labels[newStatus]?.toLowerCase()}.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textGray,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.inputBackground,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: const Center(
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: AppColors.textGray,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: statusColor.withOpacity(0.4),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'Confirm',
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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
    );
  }
}

// ─── Page Header ──────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.totalRooms,
    required this.onCreateRoom,
    required this.isOffline,
  });
  final int totalRooms;
  final VoidCallback onCreateRoom;
  final bool isOffline;

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 500;
    return isNarrow
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Rooms',
                style: TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$totalRooms total room${totalRooms == 1 ? '' : 's'}',
                style: const TextStyle(
                  color: AppColors.textSubtle,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              if (!isOffline) _CreateRoomButton(onTap: onCreateRoom),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Rooms',
                      style: TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$totalRooms total room${totalRooms == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color: AppColors.textSubtle,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isOffline) _CreateRoomButton(onTap: onCreateRoom),
            ],
          );
  }
}

// ─── Create Room Button ──────────────────────────────────────────────────────

class _CreateRoomButton extends StatelessWidget {
  const _CreateRoomButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.gradientStart, AppColors.gradientEnd],
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 14, color: Colors.white),
            SizedBox(width: 4),
            Text(
              'Create Room',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Filter Tab Bar ───────────────────────────────────────────────────────────

class _FilterTabBar extends StatelessWidget {
  const _FilterTabBar({required this.activeFilter, required this.onChanged});

  final _Filter activeFilter;
  final ValueChanged<_Filter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _FilterChip(
            label: 'All',
            emoji: null,
            isActive: activeFilter == _Filter.all,
            onTap: () => onChanged(_Filter.all),
          ),
          _FilterChip(
            label: 'Vacant',
            emoji: '✅',
            isActive: activeFilter == _Filter.vacant,
            onTap: () => onChanged(_Filter.vacant),
          ),
          _FilterChip(
            label: 'Occupied',
            emoji: '🛏️',
            isActive: activeFilter == _Filter.occupied,
            onTap: () => onChanged(_Filter.occupied),
          ),
          _FilterChip(
            label: 'Unavailable',
            emoji: '🔧',
            isActive: activeFilter == _Filter.unavailable,
            onTap: () => onChanged(_Filter.unavailable),
          ),
          _FilterChip(
            label: 'Reserved',
            emoji: '📌',
            isActive: activeFilter == _Filter.reserved,
            onTap: () => onChanged(_Filter.reserved),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.emoji,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final String? emoji;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          gradient: isActive
              ? const LinearGradient(
                  colors: [AppColors.gradientStart, AppColors.gradientEnd],
                )
              : null,
          color: isActive ? null : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? Colors.transparent : AppColors.cardBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (emoji != null) ...[
              Text(emoji!, style: const TextStyle(fontSize: 10)),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : AppColors.textGray,
                fontSize: 11.5,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Room Card ────────────────────────────────────────────────────────────────

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.statusColor,
    required this.statusIcon,
    required this.onEdit,
  });

  final RoomData room;
  final Color Function(String) statusColor;
  final IconData Function(String) statusIcon;
  final Function(RoomData) onEdit;

  String _displayDate(String? date) {
    if (date == null) return '—';
    try {
      final dt = DateTime.parse(date).toLocal();
      final y = dt.year.toString();
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    } catch (_) {
      return date;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: _NarrowLayout(
        room: room,
        displayDate: _displayDate(room.updatedAt ?? room.createdAt),
        statusColor: statusColor,
        statusIcon: statusIcon,
        onEdit: onEdit,
      ),
    );
  }
}

// ─── Room Table (desktop) ─────────────────────────────────────────────────────

class _RoomTable extends StatelessWidget {
  const _RoomTable({
    required this.rooms,
    required this.statusColor,
    required this.statusIcon,
    required this.onEdit,
  });

  final List<RoomData> rooms;
  final Color Function(String) statusColor;
  final IconData Function(String) statusIcon;
  final Function(RoomData) onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          _TableHeader(),
          const Divider(color: AppColors.cardBorder, height: 1),
          ...rooms.map((r) {
            final isLast = r == rooms.last;
            return Column(
              children: [
                _RoomRow(
                  room: r,
                  statusColor: statusColor,
                  statusIcon: statusIcon,
                  onEdit: onEdit,
                ),
                if (!isLast)
                  const Divider(color: AppColors.cardBorder, height: 1),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ─── Table Header ─────────────────────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 3, child: _HeaderCell('Room #')),
          Expanded(flex: 2, child: _HeaderCell('Capacity')),
          Expanded(flex: 3, child: _HeaderCell('Status')),
          Expanded(flex: 3, child: _HeaderCell('Updated')),
          Expanded(flex: 2, child: _HeaderCell('Actions')),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.textGray,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

// ─── Table Row (desktop) ──────────────────────────────────────────────────────

class _RoomRow extends StatelessWidget {
  const _RoomRow({
    required this.room,
    required this.statusColor,
    required this.statusIcon,
    required this.onEdit,
  });

  final RoomData room;
  final Color Function(String) statusColor;
  final IconData Function(String) statusIcon;
  final Function(RoomData) onEdit;

  String _displayDate(String? date) {
    if (date == null) return '—';
    try {
      final dt = DateTime.parse(date).toLocal();
      final y = dt.year.toString();
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    } catch (_) {
      return date;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              'Room ${room.roomNumber}',
              style: const TextStyle(
                color: AppColors.textWhite,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${room.capacity} pax',
              style: const TextStyle(color: AppColors.textGray, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusBadge(
                  status: room.roomStatus,
                  color: statusColor(room.roomStatus),
                  icon: statusIcon(room.roomStatus),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _displayDate(room.updatedAt ?? room.createdAt),
              style: const TextStyle(color: AppColors.textGray, fontSize: 12.5),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _ActionButtons(
                room: room,
                statusColor: statusColor,
                onEdit: onEdit,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Narrow Layout ────────────────────────────────────────────────────────────

class _NarrowLayout extends StatelessWidget {
  const _NarrowLayout({
    required this.room,
    required this.displayDate,
    required this.statusColor,
    required this.statusIcon,
    required this.onEdit,
  });

  final RoomData room;
  final String displayDate;
  final Color Function(String) statusColor;
  final IconData Function(String) statusIcon;
  final Function(RoomData) onEdit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.meeting_room_rounded,
              color: statusColor(room.roomStatus),
              size: 18,
            ),
            const SizedBox(width: 8),
            _StatusBadge(
              status: room.roomStatus,
              color: statusColor(room.roomStatus),
              icon: statusIcon(room.roomStatus),
            ),
            const Spacer(),
            Text(
              displayDate,
              style: const TextStyle(
                color: AppColors.textSubtle,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Room ${room.roomNumber}',
          style: const TextStyle(
            color: AppColors.textWhite,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${room.capacity} pax capacity',
          style: const TextStyle(
            color: AppColors.textGray,
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        _ActionButtons(
          room: room,
          statusColor: statusColor,
          onEdit: onEdit,
        ),
      ],
    );
  }
}

// ─── Status Badge (self-contained) ────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.status,
    required this.color,
    required this.icon,
  });

  final String status;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final label = status[0].toUpperCase() + status.substring(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Action Buttons ───────────────────────────────────────────────────────────

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.room,
    required this.statusColor,
    required this.onEdit,
  });

  final RoomData room;
  final Color Function(String) statusColor;
  final Function(RoomData) onEdit;

  @override
  Widget build(BuildContext context) {
    return ActionIconButton(
      icon: Icons.edit_outlined,
      label: 'Edit',
      color: AppColors.primaryCyan,
      showBorder: true,
      compact: true,
      onTap: () => onEdit(room),
    );
  }
}

// ─── Loading State ────────────────────────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 64),
      child: Center(
        child: CircularProgressIndicator(
          color: AppColors.primaryCyan,
          strokeWidth: 2,
        ),
      ),
    );
  }
}

// ─── Offline Banner ───────────────────────────────────────────────────────────

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF1A1A2E),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: Color(0xFF8A9BB5), size: 14),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'You\'re offline — showing locally saved rooms.',
              style: TextStyle(color: Color(0xFF8A9BB5), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Error State ──────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: AppColors.accentRed.withOpacity(0.6),
            size: 44,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(color: AppColors.textSubtle, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.gradientStart, AppColors.gradientEnd],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Retry',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(
            Icons.meeting_room_outlined,
            color: AppColors.textSubtle.withOpacity(0.4),
            size: 48,
          ),
          const SizedBox(height: 12),
          const Text(
            'No rooms found.',
            style: TextStyle(color: AppColors.textSubtle, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
