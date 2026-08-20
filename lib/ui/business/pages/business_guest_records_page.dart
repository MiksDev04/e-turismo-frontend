import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/local_database.dart';
import '../../../core/services/offline_service.dart';
import '../../../models/origin_group.dart';
import '../../shared/layouts/business_layout.dart';
import '../../shared/widgets/paginator.dart';
import '../../shared/widgets/action_icon_button.dart';
import '../widgets/edit_guest_dialog.dart';
import '../../../api/business_guest_record_api.dart';
import '../../../api/business_room_api.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _roomsDisplay(GuestRecord r) => r.roomDetails.isNotEmpty
    ? r.roomDetails.map((x) => 'Room ${x.roomNumber}').join(', ')
    : 'None';

String _dateOnly(String v) => v.length >= 10 ? v.substring(0, 10) : v;

String _actualCheckOutDate(GuestRecord r) {
  final v = r.actualCheckOut;
  if (v == null || v.isEmpty) return '—';
  return v.substring(0, 10);
}

// ─── Models ───────────────────────────────────────────────────────────────────

enum GuestRecordStatus { active, archived }

class GuestBreakdownEntry {
  const GuestBreakdownEntry({
    this.country,
    this.nationality,
    this.province,
    this.municipalityCity,
    required this.sex,
    required this.ageGroup,
    required this.count,
    required this.isOverseas,
  });

  final String? country;
  final String? nationality;
  final String? province;
  final String? municipalityCity;
  final String sex;
  final String ageGroup;
  final int count;
  final bool isOverseas;
}

class GuestDemographics {
  const GuestDemographics({
    required this.ageGroups,
    required this.sexDistribution,
    required this.countries,
    required this.breakdowns,
  });

  final Map<String, int> ageGroups;
  final Map<String, int> sexDistribution;
  final Map<String, int> countries;
  final List<GuestBreakdownEntry> breakdowns;
}

class GuestRoom {
  const GuestRoom({required this.id, required this.roomNumber, this.capacity = 0, this.status = 'active'});
  final String id;
  final String roomNumber;
  final int capacity;
  final String status;
}

class GuestRecord {
  const GuestRecord({
    required this.id,
    required this.checkIn,
    required this.checkOut,
    this.actualCheckOut,
    required this.nights,
    required this.guests,
    required this.rooms,
    this.roomDetails = const [],
    this.roomIds = const [],
    required this.purpose,
    required this.status,
    required this.demographics,
    this.maleCount,
    this.femaleCount,
    this.createdAt,
    this.leadCountry,
    this.leadMunicipality,
    this.leadProvince,
    this.leadNationality,
    this.leadIsOverseas = false,
    this.leadBirthdate,
    this.leadSex,
    this.originGroups = const [],
  });

  final String id;
  final String checkIn;
  final String checkOut;
  final String? actualCheckOut;
  final String nights;
  final int guests;
  final int rooms;
  final List<GuestRoom> roomDetails;
  final List<String> roomIds;
  final String purpose;
  final GuestRecordStatus status;
  final GuestDemographics? demographics;
  final int? maleCount;
  final int? femaleCount;
  final String? createdAt;
  final String? leadCountry;
  final String? leadMunicipality;
  final String? leadProvince;
  final String? leadNationality;
  final bool leadIsOverseas;
  final String? leadBirthdate;
  final String? leadSex;
  final List<OriginGroup> originGroups;
}

// ─── Filter Options ───────────────────────────────────────────────────────────

enum _Filter { active, archived }

// ─── Guest Records Page ───────────────────────────────────────────────────────

class BusinessGuestRecordsPage extends StatefulWidget {
  const BusinessGuestRecordsPage({super.key});

  @override
  State<BusinessGuestRecordsPage> createState() =>
      _BusinessGuestRecordsPageState();
}

class _BusinessGuestRecordsPageState extends State<BusinessGuestRecordsPage> {
  final _api = BusinessGuestRecordApi();

  String? _businessId;
  List<GuestRecord> _records = [];
  bool _isLoading = true;
  String? _loadError;

  // ── Connectivity & sync state ───────────────────────────────────────────
  bool _isOffline       = false;
  StreamSubscription<bool>? _connectivitySub;
  StreamSubscription<SyncState>? _syncSub;

  _Filter _activeFilter = _Filter.active;
  bool _showFilters = false;
  int _currentPage = 0;
  int _pageSize = 10;
  int _totalPages = 0;
  int _totalItems = 0;

  DateTime? _checkInFrom;
  DateTime? _checkOutTo;
  String? _selectedPurpose;

  final List<String> _purposeOptions = [
    'All', 'Leisure', 'Business', 'Education', 'Medical', 'Religious', 'Others',
  ];

  static const List<int> _pageSizeOptions = [10, 20, 30];

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _isOffline = !ConnectivityService.instance.isOnline;
    _subscribeToConnectivity();
    _subscribeToSync();

    _init();
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }

  // ── Connectivity subscription ─────────────────────────────────────────────

  void _subscribeToConnectivity() {
    _connectivitySub =
        ConnectivityService.instance.onConnectivityChanged.listen((isOnline) {
      if (!mounted) return;

      if (isOnline && _isOffline) {
        setState(() {
          _isOffline = false;
        });
      } else if (!isOnline && !_isOffline) {
        // Just went offline — show the offline strip.
        setState(() {
          _isOffline = true;
        });
      }
    });
  }

  // ── Sync completion subscription ───────────────────────────────────────

  void _subscribeToSync() {
    _syncSub = SyncService.instance.syncStateStream.listen((state) {
      if (!mounted) return;
      if (state.status == SyncStatus.synced) {
        _loadRecords(showLoading: false);
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
    if (_isLoading) await _loadRecords();
  }

  Future<void> _loadRecords({bool showLoading = true}) async {
    if (_businessId == null) return;
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    } else {
      _loadError = null;
    }
    final result = await _api.fetchGuestRecords(
      _businessId!,
      page: _currentPage + 1,
      pageSize: _pageSize,
      status: _activeFilter == _Filter.active ? 'active' : 'archived',
      checkInFrom: _checkInFrom?.toIso8601String().split('T').first,
      checkOutTo: _checkOutTo?.toIso8601String().split('T').first,
      purpose: _selectedPurpose,
    );
    if (!mounted) return;
    if (result.isSuccess) {
      final data = result.data!;
      setState(() {
        _records   = data.data;
        _totalPages = data.pageCount;
        _totalItems = data.totalCount;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
        _loadError = result.error;
      });
    }
  }

  // ── Date pickers ──────────────────────────────────────────────────────────

  Future<void> _pickDate(BuildContext context, bool isCheckIn) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isCheckIn ? _checkInFrom : _checkOutTo) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.dark(
            primary: AppColors.primaryCyan,
            onPrimary: Colors.black,
            primaryContainer: AppColors.primaryCyan.withOpacity(0.25),
            onPrimaryContainer: AppColors.primaryCyan,
            surface: AppColors.cardBackground,
            onSurface: AppColors.textWhite,
            onSurfaceVariant: AppColors.textGray,
            outline: AppColors.cardBorder,
            surfaceVariant: AppColors.inputBackground,
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: AppColors.cardBackground,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppColors.cardBorder),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: AppColors.primaryCyan),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isCheckIn) {
        _checkInFrom = picked;
      } else {
        _checkOutTo = picked;
      }
      _currentPage = 0;
    });
    _loadRecords();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _onEdit(GuestRecord record) async {
    final updated = await showEditGuestDialog(context, record: record);
    if (updated == null || !mounted) return;

    final result = await _api.updateRecord(
      recordId:               updated.id,
      checkIn:                updated.checkIn,
      checkOut:               updated.checkOut,
      totalGuests:            updated.guests,
      roomIds:                updated.roomIds,
      purposeOfVisit:         updated.purpose,
      maleCount:              updated.maleCount,
      femaleCount:            updated.femaleCount,
      breakdowns:             updated.demographics?.breakdowns ?? [],
      originGroups:           updated.originGroups,
      leadCountry:            updated.leadCountry,
      leadMunicipality:       updated.leadMunicipality,
      leadProvince:           updated.leadProvince,
      leadNationality:        updated.leadNationality,
      leadIsOverseas:         updated.leadIsOverseas,
      leadBirthdate:          updated.leadBirthdate,
      leadSex:                updated.leadSex,
      actualCheckOut:         updated.actualCheckOut,
    );
    if (!mounted) return;

    if (result.isSuccess) {
      _loadRecords();
    } else {
      _showSnack(result.error ?? 'Failed to update.', isError: true);
    }
  }

  Future<void> _onCheckOut(GuestRecord record) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (_) => Dialog(
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
                    color: const Color(0xFFFFB020).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.logout_rounded,
                    color: Color(0xFFFFB020),
                    size: 20,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Check Out Guest',
                  style: TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'This will mark ${record.rooms > 1 ? '${record.rooms} rooms' : 'the room'} as vacant. Continue?',
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
                            color: const Color(0xFFFFB020).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(
                              color: const Color(0xFFFFB020).withOpacity(0.4),
                            ),
                          ),
                          child: const Center(
                            child: Text(
                              'Confirm',
                              style: TextStyle(
                                color: Color(0xFFFFB020),
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

    final roomApi = BusinessRoomApi();
    final roomIds = record.roomIds.isNotEmpty
        ? record.roomIds
        : record.roomDetails.map((r) => r.id).toList();

    bool allSuccess = true;
    for (final roomId in roomIds) {
      final result = await roomApi.updateRoomStatus(
        roomId: roomId,
        roomStatus: 'vacant',
      );
      if (!result.success) {
        allSuccess = false;
      }
    }

    // Mark junction table rows as completed during checkout
    if (!kIsWeb) {
      try {
        final db = await LocalDatabase.instance.database;
        final now = DateTime.now().toUtc().toIso8601String();
        for (final roomId in roomIds) {
          await db.update(
            LocalDatabase.tableGuestRecordRooms,
            {
              'status':           'completed',
              'deleted_at':       now,
              'updated_at':       now,
              'sync_status':      LocalDatabase.syncPendingUpdate,
              'local_updated_at': now,
            },
            where:
                'guest_record_id = ? AND room_id = ? AND status = ?',
            whereArgs: [record.id, roomId, 'active'],
          );
        }
      } catch (e) {
        debugPrint('⚠️ Failed to update junction table during checkout: $e');
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop();

    final now = DateTime.now();
    final actualCheckOut = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    final updateResult = await _api.updateRecord(
      recordId:               record.id,
      checkIn:                record.checkIn,
      checkOut:               record.checkOut,
      totalGuests:            record.guests,
      roomIds:                roomIds,
      purposeOfVisit:         record.purpose,
      maleCount:              record.maleCount,
      femaleCount:            record.femaleCount,
      breakdowns:             record.demographics?.breakdowns ?? [],
      originGroups:           record.originGroups,
      leadCountry:            record.leadCountry,
      leadMunicipality:       record.leadMunicipality,
      leadProvince:           record.leadProvince,
      leadNationality:        record.leadNationality,
      leadIsOverseas:         record.leadIsOverseas,
      leadBirthdate:          record.leadBirthdate,
      leadSex:                record.leadSex,
      actualCheckOut:         actualCheckOut,
      status:                 'archived',
    );
    if (updateResult.isSuccess) {
      _showSnack(
        allSuccess
            ? 'Guest checked out successfully.'
            : 'Guest checked out, but some rooms could not be marked vacant.',
      );
    } else {
      _showSnack(
        'Guest checked out but the check-out time was not recorded.',
        isError: true,
      );
    }

    // The junction rows were marked pending_update above so a failed cloud
    // update keeps them queued. Now that the record was archived successfully,
    // clear the pending marker so no stale pending rows linger locally.
    if (updateResult.isSuccess && !kIsWeb) {
      try {
        final db = await LocalDatabase.instance.database;
        await db.update(
          LocalDatabase.tableGuestRecordRooms,
          {
            'sync_status':      LocalDatabase.syncSynced,
            'local_updated_at': null,
          },
          where:     'guest_record_id = ?',
          whereArgs: [record.id],
        );
      } catch (e) {
        debugPrint('⚠️ Failed to mark junction rows synced during checkout: $e');
      }
    }

    _loadRecords();
  }

  void _showSnack(String msg, {bool isError = false, Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError
            ? AppColors.accentRed
            : (color ?? AppColors.primaryCyan),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _clearAllFilters() {
    setState(() {
      _checkInFrom      = null;
      _checkOutTo       = null;
      _selectedPurpose  = null;
      _currentPage      = 0;
    });
    _loadRecords();
  }

  void _reload() {
    _currentPage = 0;
    _loadRecords();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return BusinessLayout(
      title: 'Guest Records',
      selectedIndex: 2,
      onNavSelected: (_) {},
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 700;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Connectivity banners (outside scroll so always visible) ──
              if (_isOffline) const _OfflineBanner(),

              // ── Main scrollable content ────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(isNarrow ? 16 : 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PageHeader(
                        activeFilter: _activeFilter,
                        onFilterChanged: (f) {
                          setState(() => _activeFilter = f);
                          _reload();
                        },
                        showFilters: _showFilters,
                        onFilterToggle: () =>
                            setState(() => _showFilters = !_showFilters),
                        isNarrow: isNarrow,
                        totalRecords: _totalItems,
                      ),
                      const SizedBox(height: 8),
                      if (_showFilters) ...[
                        _FiltersSection(
                          checkInFrom:       _checkInFrom,
                          checkOutTo:        _checkOutTo,
                          selectedPurpose:   _selectedPurpose,
                          purposeOptions:    _purposeOptions,
                          onCheckInFromTap:  () => _pickDate(context, true),
                          onCheckOutToTap:   () => _pickDate(context, false),
                          onPurposeChanged:  (v) {
                            setState(() => _selectedPurpose = v);
                            _reload();
                          },
                          onClearAll: _clearAllFilters,
                          isNarrow:   isNarrow,
                        ),
                        const SizedBox(height: 14),
                      ],
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primaryCyan,
                            ),
                          ),
                        )
                      else if (_loadError != null)
                        _ErrorBanner(
                          message: _loadError!,
                          onRetry: _businessId == null ? _init : _loadRecords,
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _GuestTable(
                              records:  _records,
                              isNarrow: isNarrow,
                              isArchived: _activeFilter == _Filter.archived,
                              onEdit:   _onEdit,
                              onCheckOut: _onCheckOut,
                            ),
                            const SizedBox(height: 12),
                            Paginator(
                              currentPage:     _currentPage,
                              totalPages:      _totalPages,
                              totalItems:      _totalItems,
                              pageSize:        _pageSize,
                              pageSizeOptions: _pageSizeOptions,
                              onPageSizeChanged: (size) {
                                setState(() {
                                  _pageSize    = size;
                                  _currentPage = 0;
                                });
                                _loadRecords();
                              },
                              onPageChanged: (page) {
                                setState(() => _currentPage = page);
                                _loadRecords();
                              },
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Offline Banner ───────────────────────────────────────────────────────────
// Shown as a thin strip at the top when the device is offline.
// Non-dismissible — it disappears automatically when connectivity returns.

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
              'You\'re offline — showing locally saved records.',
              style: TextStyle(color: Color(0xFF8A9BB5), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Error Banner ─────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.accentRed.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accentRed.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.accentRed,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.accentRed,
                fontSize: 13.5,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text(
              'Retry',
              style: TextStyle(color: AppColors.primaryCyan),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Filters Section ──────────────────────────────────────────────────────────

class _FiltersSection extends StatelessWidget {
  const _FiltersSection({
    required this.checkInFrom,
    required this.checkOutTo,
    required this.selectedPurpose,
    required this.purposeOptions,
    required this.onCheckInFromTap,
    required this.onCheckOutToTap,
    required this.onPurposeChanged,
    required this.onClearAll,
    required this.isNarrow,
  });

  final DateTime? checkInFrom;
  final DateTime? checkOutTo;
  final String? selectedPurpose;
  final List<String> purposeOptions;
  final VoidCallback onCheckInFromTap;
  final VoidCallback onCheckOutToTap;
  final ValueChanged<String?> onPurposeChanged;
  final VoidCallback onClearAll;
  final bool isNarrow;

  bool get _hasActiveFilters =>
      checkInFrom != null ||
      checkOutTo != null ||
      (selectedPurpose != null && selectedPurpose != 'All');

  @override
  Widget build(BuildContext context) {
    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _DateFilter(
                  label: 'Check-in From',
                  date: checkInFrom,
                  onTap: onCheckInFromTap,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DateFilter(
                  label: 'Check-out To',
                  date: checkOutTo,
                  onTap: onCheckOutToTap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _DropFilter(
            label: 'Purpose',
            value: selectedPurpose,
            items: purposeOptions,
            onChanged: onPurposeChanged,
            icon: Icons.work_outline,
          ),
          if (_hasActiveFilters) ...[
            const SizedBox(height: 10),
            _ClearAllBtn(onTap: onClearAll),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: _DateFilter(
            label: 'Check-in From',
            date: checkInFrom,
            onTap: onCheckInFromTap,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _DateFilter(
            label: 'Check-out To',
            date: checkOutTo,
            onTap: onCheckOutToTap,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _DropFilter(
            label: 'Purpose',
            value: selectedPurpose,
            items: purposeOptions,
            onChanged: onPurposeChanged,
            icon: Icons.work_outline,
          ),
        ),
        if (_hasActiveFilters) ...[
          const SizedBox(width: 12),
          _ClearAllBtn(onTap: onClearAll),
        ],
      ],
    );
  }
}

// ─── Filter Widgets ───────────────────────────────────────────────────────────

class _DateFilter extends StatelessWidget {
  const _DateFilter({
    required this.label,
    required this.date,
    required this.onTap,
  });

  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  String get _display {
    if (date == null) return 'mm/dd/yyyy';
    return '${date!.month.toString().padLeft(2, '0')}/'
        '${date!.day.toString().padLeft(2, '0')}/${date!.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textGray,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today,
                  color: AppColors.textSubtle,
                  size: 14,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _display,
                    style: TextStyle(
                      color: date != null
                          ? AppColors.textWhite
                          : AppColors.textSubtle,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DropFilter extends StatelessWidget {
  const _DropFilter({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.icon,
  });

  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textGray,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isDense: true,
              isExpanded: true,
              hint: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Icon(icon, color: AppColors.textSubtle, size: 14),
                    const SizedBox(width: 6),
                    const Text(
                      'All',
                      style: TextStyle(
                        color: AppColors.textSubtle,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              dropdownColor: AppColors.cardBackground,
              iconEnabledColor: AppColors.textGray,
              style: const TextStyle(
                color: AppColors.textWhite,
                fontSize: 12.5,
              ),
              items: items
                  .map(
                    (e) => DropdownMenuItem(
                      value: e,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(e),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _ClearAllBtn extends StatelessWidget {
  const _ClearAllBtn({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.clear_all, color: AppColors.textGray, size: 15),
            SizedBox(width: 5),
            Text(
              'Clear All',
              style: TextStyle(color: AppColors.textGray, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Page Header ──────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.activeFilter,
    required this.onFilterChanged,
    required this.showFilters,
    required this.onFilterToggle,
    required this.isNarrow,
    required this.totalRecords,
  });

  final _Filter activeFilter;
  final ValueChanged<_Filter> onFilterChanged;
  final bool showFilters;
  final VoidCallback onFilterToggle;
  final bool isNarrow;
  final int totalRecords;

  @override
  Widget build(BuildContext context) {
    final filterRow = _FilterToggle(
      activeFilter: activeFilter,
      onChanged: onFilterChanged,
    );
    final toggleBtn = _FilterPanelButton(
      isActive: showFilters,
      onTap: onFilterToggle,
    );

    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TitleSubtitle(totalRecords: totalRecords),
          const SizedBox(height: 12),
          Row(children: [filterRow, const SizedBox(width: 10), toggleBtn]),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _TitleSubtitle(totalRecords: totalRecords),
        const Spacer(),
        filterRow,
        const SizedBox(width: 10),
        toggleBtn,
      ],
    );
  }
}

class _TitleSubtitle extends StatelessWidget {
  const _TitleSubtitle({required this.totalRecords});
  final int totalRecords;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Guest Records ($totalRecords)',
          style: const TextStyle(
            color: AppColors.textWhite,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'View and manage all guest entries',
          style: TextStyle(color: AppColors.textGray, fontSize: 13),
        ),
      ],
    );
  }
}

class _FilterPanelButton extends StatelessWidget {
  const _FilterPanelButton({required this.isActive, required this.onTap});
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primaryCyan.withOpacity(0.15)
              : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? AppColors.primaryCyan : AppColors.cardBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_list_rounded,
              color: isActive ? AppColors.primaryCyan : AppColors.textGray,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              'Filters',
              style: TextStyle(
                color: isActive ? AppColors.primaryCyan : AppColors.textGray,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Filter Toggle (Active / Archived) ───────────────────────────────────────

class _FilterToggle extends StatelessWidget {
  const _FilterToggle({required this.activeFilter, required this.onChanged});

  final _Filter activeFilter;
  final ValueChanged<_Filter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FilterTab(
            label: 'Active',
            isActive: activeFilter == _Filter.active,
            onTap: () => onChanged(_Filter.active),
          ),
          _FilterTab(
            label: 'Archived',
            isActive: activeFilter == _Filter.archived,
            onTap: () => onChanged(_Filter.archived),
          ),
        ],
      ),
    );
  }
}

class _FilterTab extends StatelessWidget {
  const _FilterTab({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: isActive
              ? const LinearGradient(
                  colors: [AppColors.gradientStart, AppColors.gradientEnd],
                )
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : AppColors.textGray,
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ─── Guest Table ──────────────────────────────────────────────────────────────

class _GuestTable extends StatelessWidget {
  const _GuestTable({
    required this.records,
    required this.isNarrow,
    required this.isArchived,
    required this.onEdit,
    required this.onCheckOut,
  });

  final List<GuestRecord> records;
  final bool isNarrow;
  final bool isArchived;
  final ValueChanged<GuestRecord> onEdit;
  final ValueChanged<GuestRecord> onCheckOut;

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
          if (!isNarrow) ...[
            _TableHeader(isArchived: isArchived),
            const Divider(color: AppColors.cardBorder, height: 1),
          ],
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: Text(
                  'No records found.',
                  style: TextStyle(color: AppColors.textGray),
                ),
              ),
            )
          else
            ...records.map((r) {
              final isLast = r == records.last;
              return Column(
                children: [
                  if (isNarrow)
                    _RecordCard(record: r, isArchived: isArchived, onEdit: onEdit, onCheckOut: onCheckOut)
                  else
                    _RecordRow(record: r, isArchived: isArchived, onEdit: onEdit, onCheckOut: onCheckOut),
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
  const _TableHeader({required this.isArchived});

  final bool isArchived;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          const Expanded(flex: 3, child: _HeaderCell('Check-in')),
          Expanded(
            flex: 3,
            child: _HeaderCell(isArchived ? 'Actual Check-out' : 'Check-out'),
          ),
          const Expanded(flex: 2, child: _HeaderCell('Nights')),
          const Expanded(flex: 1, child: _HeaderCell('Guests')),
          const Expanded(flex: 3, child: _HeaderCell('Room(s)')),
          const Expanded(flex: 2, child: _HeaderCell('Purpose')),
          const Expanded(flex: 3, child: _HeaderCell('Actions')),
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

// ─── Table Row (wide) ─────────────────────────────────────────────────────────

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record, required this.isArchived, required this.onEdit, required this.onCheckOut});

  final GuestRecord record;
  final bool isArchived;
  final ValueChanged<GuestRecord> onEdit;
  final ValueChanged<GuestRecord> onCheckOut;

  @override
  Widget build(BuildContext context) {
    final r = record;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              r.checkIn,
              style: const TextStyle(
                color: AppColors.textWhite,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              isArchived ? _actualCheckOutDate(r) : r.checkOut,
              style: const TextStyle(color: AppColors.textGray, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              r.nights,
              style: const TextStyle(color: AppColors.textGray, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${r.guests}',
              style: const TextStyle(
                color: AppColors.textWhite,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _roomsDisplay(r),
              style: const TextStyle(color: AppColors.textGray, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              r.purpose,
              style: const TextStyle(color: AppColors.textGray, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 3,
            child: _ActionButtons(
              status: r.status,
              actualCheckOut: r.actualCheckOut,
              onEdit: () => onEdit(r),
              onView: () => _showRecordModal(context, r),
              onCheckOut: () => onCheckOut(r),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Record Card (narrow) ─────────────────────────────────────────────────────

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record, required this.isArchived, required this.onEdit, required this.onCheckOut});

  final GuestRecord record;
  final bool isArchived;
  final ValueChanged<GuestRecord> onEdit;
  final ValueChanged<GuestRecord> onCheckOut;

  @override
  Widget build(BuildContext context) {
    final r = record;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.checkIn,
                      style: const TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${isArchived ? _actualCheckOutDate(r) : r.checkOut}  •  ${r.nights}',
                      style: const TextStyle(
                        color: AppColors.textGray,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _GuestBadge(count: r.guests),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _InfoChip(label: 'Room(s)', value: _roomsDisplay(r)),
              _InfoChip(label: 'Purpose', value: r.purpose),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ActionIconButton(
                icon: Icons.visibility_outlined,
                label: 'View',
                color: AppColors.accentGreen,
                showBorder: true,
                compact: true,
                onTap: () => _showRecordModal(context, r),
              ),
              if (r.status == GuestRecordStatus.active) ...[
                const SizedBox(width: 6),
                ActionIconButton(
                  icon: Icons.edit_outlined,
                  label: 'Edit',
                  color: AppColors.primaryCyan,
                  showBorder: true,
                  compact: true,
                  onTap: () => onEdit(r),
                ),
                if (r.actualCheckOut == null) ...[
                  const SizedBox(width: 6),
                  ActionIconButton(
                    icon: Icons.logout_rounded,
                    label: 'Check Out',
                    color: const Color(0xFFFFB020),
                    showBorder: true,
                    compact: true,
                    onTap: () => onCheckOut(r),
                  ),
                ],
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(color: AppColors.textSubtle),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(color: AppColors.textGray),
          ),
        ],
      ),
    );
  }
}

class _GuestBadge extends StatelessWidget {
  const _GuestBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primaryCyan.withOpacity(0.1),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.primaryCyan.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.people_outline,
            color: AppColors.primaryCyan,
            size: 13,
          ),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: const TextStyle(
              color: AppColors.primaryCyan,
              fontSize: 12.5,
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
    required this.status,
    required this.actualCheckOut,
    required this.onEdit,
    required this.onView,
    required this.onCheckOut,
  });

  final GuestRecordStatus status;
  final String? actualCheckOut;
  final VoidCallback onEdit;
  final VoidCallback onView;
  final VoidCallback onCheckOut;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        ActionIconButton(
          icon: Icons.visibility_outlined,
          label: 'View',
          color: AppColors.accentGreen,
          showBorder: true,
          compact: true,
          onTap: onView,
        ),
        if (status == GuestRecordStatus.active) ...[
          ActionIconButton(
            icon: Icons.edit_outlined,
            label: 'Edit',
            color: AppColors.primaryCyan,
            showBorder: true,
            compact: true,
            onTap: onEdit,
          ),
          if (actualCheckOut == null)
            ActionIconButton(
              icon: Icons.logout_rounded,
              label: 'Check Out',
              color: const Color(0xFFFFB020),
              showBorder: true,
              compact: true,
              onTap: onCheckOut,
            ),
        ],
      ],
    );
  }
}

// ─── Full Record Modal ────────────────────────────────────────────────────────

void _showRecordModal(BuildContext context, GuestRecord record) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (_) => _RecordDetailModal(record: record),
  );
}

class _RecordDetailModal extends StatelessWidget {
  const _RecordDetailModal({required this.record});
  final GuestRecord record;

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 560;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isNarrow ? 16 : 40,
        vertical: 32,
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 640),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryCyan.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: AppColors.primaryCyan,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Guest Record Details',
                      style: TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.textGray,
                      size: 20,
                    ),
                    splashRadius: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // ── Body ───────────────────────────────────────────────────
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.inputBackground,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.cardBorder.withOpacity(0.4)),
                      ),
                      child: const _ModalSectionLabel('Stay Information'),
                    ),
                    const SizedBox(height: 10),
                    _StayInfoGrid(record: record),
                    const SizedBox(height: 24),

                    Container(
                      width: double.infinity,
                      height: 1,
                      color: AppColors.cardBorder.withOpacity(0.6),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.inputBackground,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.cardBorder.withOpacity(0.4)),
                      ),
                      child: const _ModalSectionLabel('Demographic Data (Lead Guest)'),
                    ),
                    const SizedBox(height: 12),

                    _LeadGuestDemoGrid(record: record),

                    if (record.originGroups.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        height: 1,
                        color: AppColors.cardBorder.withOpacity(0.6),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.inputBackground,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.cardBorder.withOpacity(0.4)),
                        ),
                        child: const _ModalSectionLabel('Origin Groups'),
                      ),
                      const SizedBox(height: 12),
                      _OriginGroupsDisplay(record: record),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Stay Info Grid ───────────────────────────────────────────────────────────

class _StayInfoGrid extends StatelessWidget {
  const _StayInfoGrid({required this.record});
  final GuestRecord record;

  @override
  Widget build(BuildContext context) {
    final roomsDisplay = record.roomDetails.isNotEmpty
        ? '${record.rooms} (${record.roomDetails.map((r) => '${'Room '}${r.roomNumber}${r.status == 'completed' ? ' (used)' : ''}').join(', ')})'
        : '${record.rooms}';

    final items = [
      (Icons.login,                 'Check-in',          _dateOnly(record.checkIn)),
      (Icons.logout,                'Check-out (Planned)', _dateOnly(record.checkOut)),
      if (record.actualCheckOut != null)
        (Icons.event_available,     'Actual Check-out',  _dateOnly(record.actualCheckOut!)),
      (Icons.nights_stay_outlined,  'Length of Stay',    record.nights),
      (Icons.people_outline,        'Total Guests',      '${record.guests}'),
      (Icons.meeting_room_outlined, 'Rooms Occupied',    roomsDisplay),
      (Icons.work_outline,          'Purpose of Visit',  record.purpose),
      (Icons.male_outlined,         'Male Guests',       record.maleCount?.toString() ?? '-'),
      (Icons.female_outlined,       'Female Guests',     record.femaleCount?.toString() ?? '-'),
    ];

    const spacing = 12.0;
    const rowGap  = 12.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: rowGap,
          children: [
            for (final item in items)
              SizedBox(
                width: itemWidth,
                child: _DetailField(
                  icon: item.$1,
                  label: item.$2,
                  value: item.$3,
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─── Lead Guest Demographics Grid ──────────────────────────────────────────────

class _LeadGuestDemoGrid extends StatelessWidget {
  const _LeadGuestDemoGrid({required this.record});
  final GuestRecord record;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.person_outline,            'Sex',               record.leadSex ?? '-'),
      (Icons.cake_outlined,             'Birthdate',         record.leadBirthdate ?? '-'),
      (Icons.flag_outlined,             'Country',           record.leadCountry ?? '-'),
      (Icons.account_balance_outlined,  'Nationality',       record.leadNationality ?? '-'),
      (Icons.map_outlined,              'Province',          record.leadProvince ?? '-'),
      (Icons.location_city_outlined,    'City/Municipality', record.leadMunicipality ?? '-'),
      (Icons.flight_outlined,           'Is Overseas',       record.leadIsOverseas ? 'Yes' : 'No'),
    ];

    const spacing = 12.0;
    const rowGap  = 12.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: rowGap,
          children: [
            for (final item in items)
              SizedBox(
                width: itemWidth,
                child: _DetailField(
                  icon: item.$1,
                  label: item.$2,
                  value: item.$3,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.textSubtle, size: 13),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSubtle,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
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

// ─── Origin Groups Display ────────────────────────────────────────────────────

class _OriginGroupsDisplay extends StatelessWidget {
  const _OriginGroupsDisplay({required this.record});
  final GuestRecord record;

  @override
  Widget build(BuildContext context) {
    final groups = record.originGroups;
    final totalMale = groups.fold<int>(0, (s, g) => s + g.maleCount);
    final totalFemale = groups.fold<int>(0, (s, g) => s + g.femaleCount);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 500;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final g in groups) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.inputBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.cardBorder.withOpacity(0.4)),
                ),
                child: isNarrow
                    ? _buildGroupContent(g, true)
                    : Row(
                        children: [
                          Expanded(flex: 3, child: _buildGroupContent(g, false)),
                          const SizedBox(width: 12),
                          _buildSexCounts(g),
                        ],
                      ),
              ),
              const SizedBox(height: 8),
            ],
            // Total row
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primaryCyan.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primaryCyan.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.summarize_outlined, color: AppColors.primaryCyan, size: 14),
                  const SizedBox(width: 8),
                  Text(
                    'Total: $totalMale male, $totalFemale female (${totalMale + totalFemale} guests)',
                    style: const TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGroupContent(OriginGroup g, bool stacked) {
    final locationParts = <String>[];
    if (g.isOverseas) {
      locationParts.add('Overseas Filipino');
    } else {
      if (g.country != null) locationParts.add(g.country!);
      if (g.province != null) locationParts.add(g.province!);
      if (g.cityMunicipality != null) locationParts.add(g.cityMunicipality!);
    }
    final location = locationParts.join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (g.isOverseas)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'OFW/Balikbayan',
                  style: TextStyle(color: Color(0xFFF59E0B), fontSize: 10, fontWeight: FontWeight.w600),
                ),
              )
            else
              Icon(Icons.public_outlined, color: AppColors.textSubtle, size: 13),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                location.isNotEmpty ? location : '—',
                style: const TextStyle(color: AppColors.textWhite, fontSize: 12.5),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (g.nationality != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: (g.nationality == 'Filipino'
                          ? AppColors.primaryCyan
                          : AppColors.accentGreen)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  g.nationality!,
                  style: TextStyle(
                    color: g.nationality == 'Filipino'
                        ? AppColors.primaryCyan
                        : AppColors.accentGreen,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
        if (stacked) ...[
          const SizedBox(height: 6),
          _buildSexCounts(g),
        ],
      ],
    );
  }

  Widget _buildSexCounts(OriginGroup g) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.male_outlined, color: AppColors.textSubtle, size: 13),
        const SizedBox(width: 3),
        Text('${g.maleCount}', style: const TextStyle(color: AppColors.textWhite, fontSize: 12)),
        const SizedBox(width: 10),
        Icon(Icons.female_outlined, color: AppColors.textSubtle, size: 13),
        const SizedBox(width: 3),
        Text('${g.femaleCount}', style: const TextStyle(color: AppColors.textWhite, fontSize: 12)),
      ],
    );
  }
}

// ─── Modal Helpers ────────────────────────────────────────────────────────────

class _ModalSectionLabel extends StatelessWidget {
  const _ModalSectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.textWhite,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );
  }
}
