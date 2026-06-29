// ignore_for_file: use_null_aware_elements

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/country_constants.dart';
import '../pages/business_guest_records_page.dart';
import 'dart:async';
import '../../../core/services/offline_service.dart';

// ─── Light input colours ──────────────────────────────────────────────────────

const _kInputFill = Color(0xFFF8FAFC);
const _kInputBorder = Color(0xFFD1D5DB);
const _kInputFocused = Color(0xFF3B82F6);
const _kDropBg = Color(0xFFFFFFFF);
const _kInputText = Color(0xFF111827);
const _kInputHint = Color(0xFF9CA3AF);
const _kReadOnlyFill = Color(0xFFEFF2F5);

/// Uniform height for every input, dropdown, and read-only field.
const _kFieldHeight = 40.0;

// ─── Public model for one demographic row ─────────────────────────────────────

class DemographicEntry {
  DemographicEntry({
    this.country = '',
    this.nationality = '', // ← ADD
    this.region = 'N/A',
    this.sex = '',
    this.ageGroup = '',
    this.count = 0,
    this.isOverseas = false,
  });

  String country;
  String nationality;
  String region;
  String sex;
  String ageGroup;
  int count;
  bool isOverseas;

  /// Auto-derived from country + isOverseas — never stored separately.
  String get residenceCategory {
    if (country.isEmpty) return 'unspecified_guest';
    if (country == 'Philippines') {
      return isOverseas ? 'overseas_filipino' : 'philippine_resident';
    }
    return 'foreign_resident';
  }

  DemographicEntry copyWith({
    String? country,
    String? nationality,
    String? region,
    String? sex,
    String? ageGroup,
    int? count,
    bool? isOverseas,
  }) => DemographicEntry(
    country: country ?? this.country,
    nationality: nationality ?? this.nationality,
    region: region ?? this.region,
    sex: sex ?? this.sex,
    ageGroup: ageGroup ?? this.ageGroup,
    count: count ?? this.count,
    isOverseas: isOverseas ?? this.isOverseas,
  );
}

// ─── Show helper ──────────────────────────────────────────────────────────────

Future<GuestRecord?> showEditGuestDialog(
  BuildContext context, {
  required GuestRecord record,
}) {
  return showDialog<GuestRecord>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.55),
    builder: (_) => _EditGuestDialog(record: record),
  );
}

// ─── Dialog widget ────────────────────────────────────────────────────────────

class _EditGuestDialog extends StatefulWidget {
  const _EditGuestDialog({required this.record});
  final GuestRecord record;

  @override
  State<_EditGuestDialog> createState() => _EditGuestDialogState();
}

class _EditGuestDialogState extends State<_EditGuestDialog> {
  late final TextEditingController _checkInCtrl;
  late final TextEditingController _checkOutCtrl;
  late final TextEditingController _guestsCtrl;
  late final TextEditingController _roomsCtrl;
  late String _purpose;
  late String _transport;

  // ── Connectivity ──────────────────────────────────────────────────────────
  bool _isOffline = false;
  StreamSubscription<bool>? _connectivitySub;
  final TextEditingController _purposeOtherCtrl = TextEditingController();
  final TextEditingController _transportOtherCtrl = TextEditingController();
  bool _showPurposeOther = false;
  bool _showTransportOther = false;
  String _lengthOfStay = '0 nights';

  late List<DemographicEntry> _demoRows;

  // ── Inline validation state ───────────────────────────────────────────────
  Map<String, String?> _errors = {};
  List<Map<String, String?>> _rowErrors = [];

  // ─── Options ────────────────────────────────────────────────────────────────

  static const _purposes = [
    'Leisure',
    'Business',
    'Education',
    'Medical',
    'Religious',
    'Others',
  ];

  static const _transports = [
    'Private Car',
    'Bus',
    'Van',
    'Motorcycle',
    'Tricycle',
    'Others',
  ];

  static const _sexOptions = ['Male', 'Female'];

  static const _ageGroupOptions = [
    '0–9',
    '10–17',
    '18–25',
    '26–35',
    '36–45',
    '46–55',
    '56+',
    'Prefer not to say',
  ];

  static const _countries = [
    'Philippines',
    'Argentina',
    'Australia',
    'Austria',
    'Bahrain',
    'Bangladesh',
    'Belgium',
    'Brazil',
    'Brunei',
    'Cambodia',
    'Canada',
    'China',
    'Colombia',
    'CIS',
    'Denmark',
    'Egypt',
    'Finland',
    'France',
    'Germany',
    'Greece',
    'Guam',
    'Hong Kong',
    'India',
    'Indonesia',
    'Iran',
    'Ireland',
    'Israel',
    'Italy',
    'Japan',
    'Jordan',
    'Korea',
    'Kuwait',
    'Laos',
    'Luxembourg',
    'Malaysia',
    'Mexico',
    'Myanmar',
    'Nauru',
    'Nepal',
    'Netherlands',
    'New Zealand',
    'Nigeria',
    'Norway',
    'Pakistan',
    'Papua NG',
    'Peru',
    'Poland',
    'Portugal',
    'Russia',
    'Saudi Arabia',
    'Singapore',
    'South Africa',
    'Spain',
    'Sri Lanka',
    'Sweden',
    'Switzerland',
    'Taiwan',
    'Thailand',
    'Serbia & Montenegro',
    'UAE',
    'United Kingdom',
    'USA',
    'Venezuela',
    'Vietnam',
    'Others',
  ];

  static const _phRegions = [
    'NCR',
    'CAR',
    'Region I',
    'Region II',
    'Region III',
    'Region IV-A (CALABARZON)',
    'Region IV-B (MIMAROPA)',
    'Region V',
    'Region VI',
    'Region VII',
    'Region VIII',
    'Region IX',
    'Region X',
    'Region XI',
    'Region XII',
    'Region XIII',
    'BARMM',
  ];

  static const _nationalityOptions = ['Filipino', 'Foreign'];

  // ─── Normalise age-group from DB (hyphen) → UI option (en-dash) ───────────

  static String _normaliseAgeGroup(String raw) {
    if (_ageGroupOptions.contains(raw)) return raw;
    final withEndash = raw.trim().replaceAll('-', '–');
    if (_ageGroupOptions.contains(withEndash)) return withEndash;
    if (raw.trim() == '1-9' || raw.trim() == '1–9') return '0–9';
    if (raw.toLowerCase().replaceAll('_', ' ').contains('prefer')) {
      return 'Prefer not to say';
    }
    return '';
  }

  // ─── Init ────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    
    String stripTime(String d) {
      if (d.contains('T')) return d.split('T')[0];
      if (d.contains(' ')) return d.split(' ')[0];
      return d;
    }
    
    _checkInCtrl = TextEditingController(text: stripTime(r.checkIn));
    _checkOutCtrl = TextEditingController(text: stripTime(r.checkOut));
    _guestsCtrl = TextEditingController(text: r.guests.toString());
    _roomsCtrl = TextEditingController(text: r.rooms.toString());

    if (_purposes.contains(r.purpose)) {
      _purpose = r.purpose;
      _showPurposeOther = r.purpose == 'Others';
    } else {
      _purpose = 'Others';
      _showPurposeOther = true;
      _purposeOtherCtrl.text = r.purpose;
    }

    if (_transports.contains(r.transport)) {
      _transport = r.transport;
      _showTransportOther = r.transport == 'Others';
    } else {
      _transport = 'Others';
      _showTransportOther = true;
      _transportOtherCtrl.text = r.transport;
    }

    _lengthOfStay = r.nights;

    if (r.demographics != null && r.demographics!.breakdowns.isNotEmpty) {
      _demoRows = _convertFromBreakdowns(r.demographics!.breakdowns);
    } else {
      _demoRows = [DemographicEntry()];
    }

    _rowErrors = List.generate(_demoRows.length, (_) => {});

    _isOffline = !ConnectivityService.instance.isOnline;
    _connectivitySub = ConnectivityService.instance.onConnectivityChanged
        .listen((isOnline) {
          if (mounted) setState(() => _isOffline = !isOnline);
        });
  }

  List<DemographicEntry> _convertFromBreakdowns(
    List<GuestBreakdownEntry> breakdowns,
  ) {
    return breakdowns.map((b) {
      // ── Country ──────────────────────────────────────────────────────
      final rawCountry = b.country ?? '';
      String nat = rawCountry.isEmpty ? 'N/A' : mapFromReportFormat(rawCountry);
      if (!_countries.contains(nat)) nat = 'N/A';

      // ── Region — only meaningful for philippine_resident ─────────────
      String reg = b.philippinesRegion ?? 'N/A';
      if (!_phRegions.contains(reg)) reg = 'N/A';

      // ── Sex ──────────────────────────────────────────────────────────
      String rawSex = b.sex;
      String sex = rawSex.isNotEmpty
          ? '${rawSex[0].toUpperCase()}${rawSex.substring(1).toLowerCase()}'
          : '';
      if (!_sexOptions.contains(sex)) sex = '';

      // ── Age group ────────────────────────────────────────────────────
      final age = _normaliseAgeGroup(b.ageGroup);

      return DemographicEntry(
        country: nat,
        nationality: b.nationality ?? '', // ← ADD
        region: reg,
        sex: sex,
        ageGroup: age,
        count: b.count,
        isOverseas: b.isOverseas,
      );
    }).toList();
  }

  @override
  void dispose() {
    _checkInCtrl.dispose();
    _checkOutCtrl.dispose();
    _guestsCtrl.dispose();
    _roomsCtrl.dispose();
    _purposeOtherCtrl.dispose();
    _transportOtherCtrl.dispose();
    _connectivitySub?.cancel();
    super.dispose();
  }

  // ─── Derived values ───────────────────────────────────────────────────────

  int get _demoTotal => _demoRows.fold(0, (sum, e) => sum + e.count);
  int get _totalGuests => int.tryParse(_guestsCtrl.text.trim()) ?? 0;

  // AFTER
  void _recalcNights() {
    final checkIn = DateTime.tryParse(_checkInCtrl.text.trim());
    final checkOut = DateTime.tryParse(_checkOutCtrl.text.trim());
    if (checkIn == null || checkOut == null) {
      setState(() => _lengthOfStay = '0 nights');
      return;
    }
    final nights = checkOut.difference(checkIn).inDays.clamp(0, 999);
    setState(() {
      _lengthOfStay = '$nights night${nights == 1 ? '' : 's'}';
    });
  }

  // ─── Row management ───────────────────────────────────────────────────────

  void _addRow() {
    setState(() {
      _demoRows.add(DemographicEntry());
      _rowErrors.add({});
    });
  }

  void _removeRow(int i) {
    setState(() {
      _demoRows.removeAt(i);
      _rowErrors.removeAt(i);
    });
  }

  // ─── Error clearing ───────────────────────────────────────────────────────

  void _clearFieldError(String key) {
    if (_errors.containsKey(key)) {
      setState(() => _errors = Map.from(_errors)..remove(key));
    }
  }

  void _clearRowFieldError(int index, String key) {
    if (_rowErrors.length > index && _rowErrors[index].containsKey(key)) {
      setState(() {
        _rowErrors = List.from(_rowErrors);
        _rowErrors[index] = Map.from(_rowErrors[index])..remove(key);
      });
    }
  }

  // ─── Validation ───────────────────────────────────────────────────────────

  bool _validateAndSetErrors() {
    final errors = <String, String?>{};
    final rowErrors = List.generate(
      _demoRows.length,
      (_) => <String, String?>{},
    );
    bool hasError = false;

    // ── Check-in ────────────────────────────────────────────────────────────
    final checkInText = _checkInCtrl.text.trim();
    final checkIn = DateTime.tryParse(checkInText);

    if (checkInText.isEmpty) {
      errors['checkIn'] = 'Please select a check-in date.';
      hasError = true;
    } else if (checkIn == null) {
      errors['checkIn'] = 'Invalid date — use yyyy-mm-dd format.';
      hasError = true;
    } else if (checkIn.isAfter(DateTime.now())) {
      errors['checkIn'] = 'Check-in date cannot be in the future.';
      hasError = true;
    }

    // ── Check-out ───────────────────────────────────────────────────────────
    final checkOutText = _checkOutCtrl.text.trim();
    final checkOut = DateTime.tryParse(checkOutText);

    if (checkOutText.isEmpty) {
      errors['checkOut'] = 'Please select a check-out date.';
      hasError = true;
    } else if (checkOut == null) {
      errors['checkOut'] = 'Invalid date — use yyyy-mm-dd format.';
      hasError = true;
    } else if (checkIn != null && checkOut.isBefore(checkIn)) {
      errors['checkOut'] =
          'Check-out must be the same day as check-in or later.';
      hasError = true;
    }

    // ── Total Guests ────────────────────────────────────────────────────────
    final guests = int.tryParse(_guestsCtrl.text.trim());
    if (guests == null || guests <= 0) {
      errors['totalGuests'] = 'Enter at least 1 guest.';
      hasError = true;
    } else if (guests > 9999) {
      errors['totalGuests'] = 'Value seems too large (max 9,999).';
      hasError = true;
    }

    // ── Rooms Occupied ──────────────────────────────────────────────────────
    final rooms = int.tryParse(_roomsCtrl.text.trim());
    if (rooms == null || rooms < 0) {
      errors['roomsOccupied'] = 'Enter a valid number of rooms.';
      hasError = true;
    } else if (guests != null && guests > 0 && rooms > guests) {
      errors['roomsOccupied'] = 'Rooms cannot exceed total guests.';
      hasError = true;
    } else if (checkIn != null && checkOut != null &&
               checkOut.difference(checkIn).inDays > 0 && rooms == 0) {
      errors['roomsOccupied'] = 'At least 1 room is required when staying overnight.';
      hasError = true;
    }

    // ── Purpose ─────────────────────────────────────────────────────────────
    if (_purpose.isEmpty) {
      errors['purpose'] = 'Please select a purpose of visit.';
      hasError = true;
    } else if (_purpose == 'Others' && _purposeOtherCtrl.text.trim().isEmpty) {
      errors['purposeOther'] = 'Please specify the purpose.';
      hasError = true;
    }

    // ── Transport ───────────────────────────────────────────────────────────
    if (_transport.isEmpty) {
      errors['transport'] = 'Please select a mode of transportation.';
      hasError = true;
    } else if (_transport == 'Others' &&
        _transportOtherCtrl.text.trim().isEmpty) {
      errors['transportOther'] = 'Please specify the transportation.';
      hasError = true;
    }

    // ── Demographic rows ────────────────────────────────────────────────
    final seen = <String>{};
    for (int i = 0; i < _demoRows.length; i++) {
      final row = _demoRows[i];

      // Country only required when NOT overseas
      if (!row.isOverseas && row.country.isEmpty) {
        rowErrors[i]['country'] = 'Required';
        hasError = true;
      }

      if (row.country == 'Philippines' &&
          !row.isOverseas &&
          row.nationality.isEmpty) {
        rowErrors[i]['nationality'] = 'Required';
        hasError = true;
      }

      // Region required only for Philippine residents (not OFW).
      if (row.country == 'Philippines' &&
          !row.isOverseas &&
          (row.region.isEmpty || row.region == 'N/A')) {
        rowErrors[i]['region'] = 'Required for Philippine residents';
        hasError = true;
      }

      if (row.sex.isEmpty) {
        rowErrors[i]['sex'] = 'Required';
        hasError = true;
      }

      if (row.ageGroup.isEmpty) {
        rowErrors[i]['ageGroup'] = 'Required';
        hasError = true;
      }

      if (row.count <= 0) {
        rowErrors[i]['count'] = 'Min 1';
        hasError = true;
      }

      // Duplicate detection — overseas rows key on isOverseas+sex+ageGroup only
      if (row.sex.isNotEmpty && row.ageGroup.isNotEmpty) {
        final String key;
        if (row.isOverseas) {
          key = 'overseas|${row.sex}|${row.ageGroup}';
        } else if (row.country == 'Philippines') {
          key =
              '${row.country}|${row.nationality}|${row.region}|${row.sex}|${row.ageGroup}';
        } else {
          key = '${row.country}|${row.sex}|${row.ageGroup}';
        }
        if (!seen.add(key)) {
          rowErrors[i]['country'] = 'Duplicate row — merge counts instead';
          hasError = true;
        }
      }
    }

    if (!hasError && guests != null && guests > 0) {
      if (_demoTotal != guests) {
        errors['demographicSum'] =
            'Demographic total ($_demoTotal) must equal total guests ($guests).';
        hasError = true;
      }
    }

    setState(() {
      _errors = errors;
      _rowErrors = rowErrors;
    });

    return !hasError;
  }

  // ─── Save ─────────────────────────────────────────────────────────────────

  void _save() {
    if (!_validateAndSetErrors()) return;

    final purposeValue = _purpose == 'Others'
        ? _purposeOtherCtrl.text.trim()
        : _purpose;
    final transportValue = _transport == 'Others'
        ? _transportOtherCtrl.text.trim()
        : _transport;

    final breakdowns = _demoRows
        .where((e) => (e.isOverseas || e.country.isNotEmpty) && e.count > 0)
        .map(
          (e) => GuestBreakdownEntry(
            country: e.isOverseas ? null : mapToReportFormat(e.country),
            nationality: (e.isOverseas || e.country != 'Philippines')
                ? null
                : e.nationality,
            philippinesRegion:
                (!e.isOverseas &&
                    e.country == 'Philippines' &&
                    e.region != 'N/A')
                ? e.region
                : null,
            sex: e.sex.toLowerCase(),
            ageGroup: e.ageGroup,
            count: e.count,
            isOverseas: e.isOverseas,
          ),
        )
        .toList();

    final ageGroups = <String, int>{};
    final sexDist = <String, int>{};
    final countries = <String, int>{};

    for (final b in breakdowns) {
      if (b.ageGroup.isNotEmpty) {
        ageGroups[b.ageGroup] = (ageGroups[b.ageGroup] ?? 0) + b.count;
      }
      if (b.sex.isNotEmpty) {
        sexDist[b.sex] = (sexDist[b.sex] ?? 0) + b.count;
      }
      final key = b.isOverseas
          ? 'Overseas'
          : (b.country == 'Philippines' &&
                b.philippinesRegion != null &&
                b.philippinesRegion != 'N/A')
          ? 'PH – ${b.philippinesRegion}'
          : (b.country ?? '');
      if (key.isNotEmpty) countries[key] = (countries[key] ?? 0) + b.count;
    }

    final demographics = GuestDemographics(
      ageGroups: ageGroups,
      sexDistribution: sexDist,
      countries: countries,
      breakdowns: breakdowns,
    );

    final updated = GuestRecord(
      id: widget.record.id,
      checkIn: _checkInCtrl.text.trim(),
      checkOut: _checkOutCtrl.text.trim(),
      nights: _lengthOfStay,
      guests: _totalGuests,
      rooms: int.tryParse(_roomsCtrl.text.trim()) ?? widget.record.rooms,
      purpose: purposeValue,
      transport: transportValue,
      status: widget.record.status,
      demographics: demographics,
    );

    // Capture before pop — context becomes invalid after dismiss.
    final messenger = ScaffoldMessenger.of(context);
    final isOnline = ConnectivityService.instance.isOnline;

    Navigator.of(context).pop(updated);

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          isOnline
              ? 'Guest record updated successfully!'
              : 'Changes saved offline — will sync when you\'re back online.',
        ),
        backgroundColor: isOnline
            ? AppColors.primaryCyan
            : const Color(0xFFF59E0B),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 600;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isNarrow ? 12 : 24,
        vertical: 24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(14),
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
              _TitleBar(onClose: () => Navigator.of(context).pop()),
              if (_isOffline)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: const Color(0xFF1A1A2E),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.wifi_off_rounded,
                        color: Color(0xFF8A9BB5),
                        size: 14,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You\'re offline — changes will be saved locally and synced later.',
                          style: TextStyle(
                            color: Color(0xFF8A9BB5),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(isNarrow ? 14 : 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Global submit error ─────────────────────────
                      if (_errors['submit'] != null) ...[
                        _GlobalErrorBanner(message: _errors['submit']!),
                        const SizedBox(height: 12),
                      ],

                      // ── Stay Information ────────────────────────────
                      _SectionCard(
                        title: 'Stay Information',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Check-in / Check-out / Length of Stay ──
                            // Desktop: all three in one row
                            // Mobile: dates row, then LOS below
                            if (isNarrow) ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _FieldCol(
                                      label: 'Check-in Date *',
                                      errorText: _errors['checkIn'],
                                      child: _DateField(
                                        controller: _checkInCtrl,
                                        hint: 'yyyy-mm-dd',
                                        hasError: _errors['checkIn'] != null,
                                        lastDate:
                                            DateTime.now(), // ← no future check-ins
                                        onPicked: () {
                                          _recalcNights();
                                          _clearFieldError('checkIn');
                                          _clearFieldError('checkOut');
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _FieldCol(
                                      label: 'Check-out Date *',
                                      errorText: _errors['checkOut'],
                                      // AFTER — check-out field (both layouts)
                                      child: _DateField(
                                        controller: _checkOutCtrl,
                                        hint: 'yyyy-mm-dd',
                                        hasError: _errors['checkOut'] != null,
                                        firstDate:
                                            DateTime.tryParse(
                                              _checkInCtrl.text.trim(),
                                            ) // ← same day allowed
                                            ??
                                            DateTime(2020),
                                        onPicked: () {
                                          _recalcNights();
                                          _clearFieldError('checkOut');
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _FieldCol(
                                label: 'Length of Stay',
                                child: _ReadOnlyField(value: _lengthOfStay),
                              ),
                            ] else ...[
                              // Desktop: 3-column row
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _FieldCol(
                                      label: 'Check-in Date *',
                                      errorText: _errors['checkIn'],
                                      child: _DateField(
                                        controller: _checkInCtrl,
                                        hint: 'yyyy-mm-dd',
                                        hasError: _errors['checkIn'] != null,
                                        lastDate:
                                            DateTime.now(), // ← no future check-ins
                                        onPicked: () {
                                          _recalcNights();
                                          _clearFieldError('checkIn');
                                          _clearFieldError('checkOut');
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _FieldCol(
                                      label: 'Check-out Date *',
                                      errorText: _errors['checkOut'],
                                      // AFTER — check-out field (both layouts)
                                      child: _DateField(
                                        controller: _checkOutCtrl,
                                        hint: 'yyyy-mm-dd',
                                        hasError: _errors['checkOut'] != null,
                                        firstDate:
                                            DateTime.tryParse(
                                              _checkInCtrl.text.trim(),
                                            ) // ← same day allowed
                                            ??
                                            DateTime(2020),
                                        onPicked: () {
                                          _recalcNights();
                                          _clearFieldError('checkOut');
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _FieldCol(
                                      label: 'Length of Stay',
                                      child: _ReadOnlyField(
                                        value: _lengthOfStay,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 14),

                            // ── Total Guests / Rooms ────────────────────
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _FieldCol(
                                    label: 'Total Guests *',
                                    errorText: _errors['totalGuests'],
                                    child: _NumberField(
                                      controller: _guestsCtrl,
                                      hint: 'e.g. 10',
                                      hasError: _errors['totalGuests'] != null,
                                      onChanged: (_) {
                                        setState(() {});
                                        _clearFieldError('totalGuests');
                                        _clearFieldError('roomsOccupied');
                                        _clearFieldError('demographicSum');
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _FieldCol(
                                    label: 'Rooms Occupied *',
                                    errorText: _errors['roomsOccupied'],
                                    child: _NumberField(
                                      controller: _roomsCtrl,
                                      hint: 'e.g. 3',
                                      hasError:
                                          _errors['roomsOccupied'] != null,
                                      onChanged: (_) =>
                                          _clearFieldError('roomsOccupied'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // ── Purpose / Transport ─────────────────────
                            if (isNarrow) ...[
                              _FieldCol(
                                label: 'Purpose of Visit *',
                                errorText: _errors['purpose'],
                                child: _DropdownField(
                                  value: _purpose.isEmpty ? null : _purpose,
                                  items: _purposes,
                                  hint: 'Select purpose',
                                  hasError: _errors['purpose'] != null,
                                  onChanged: (v) {
                                    setState(() {
                                      _purpose = v ?? '';
                                      _showPurposeOther = v == 'Others';
                                      if (!_showPurposeOther) {
                                        _purposeOtherCtrl.clear();
                                      }
                                    });
                                    _clearFieldError('purpose');
                                    _clearFieldError('purposeOther');
                                  },
                                ),
                              ),
                              if (_showPurposeOther) ...[
                                const SizedBox(height: 10),
                                _FieldCol(
                                  label: 'Please specify *',
                                  errorText: _errors['purposeOther'],
                                  child: _PlainTextField(
                                    controller: _purposeOtherCtrl,
                                    hint: 'Specify purpose',
                                    hasError: _errors['purposeOther'] != null,
                                    onChanged: (_) =>
                                        _clearFieldError('purposeOther'),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              _FieldCol(
                                label: 'Mode of Transportation *',
                                errorText: _errors['transport'],
                                child: _DropdownField(
                                  value: _transport.isEmpty ? null : _transport,
                                  items: _transports,
                                  hint: 'Select transportation',
                                  hasError: _errors['transport'] != null,
                                  onChanged: (v) {
                                    setState(() {
                                      _transport = v ?? '';
                                      _showTransportOther = v == 'Others';
                                      if (!_showTransportOther) {
                                        _transportOtherCtrl.clear();
                                      }
                                    });
                                    _clearFieldError('transport');
                                    _clearFieldError('transportOther');
                                  },
                                ),
                              ),
                              if (_showTransportOther) ...[
                                const SizedBox(height: 10),
                                _FieldCol(
                                  label: 'Please specify *',
                                  errorText: _errors['transportOther'],
                                  child: _PlainTextField(
                                    controller: _transportOtherCtrl,
                                    hint: 'Specify transportation',
                                    hasError: _errors['transportOther'] != null,
                                    onChanged: (_) =>
                                        _clearFieldError('transportOther'),
                                  ),
                                ),
                              ],
                            ] else ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _FieldCol(
                                          label: 'Purpose of Visit *',
                                          errorText: _errors['purpose'],
                                          child: _DropdownField(
                                            value: _purpose.isEmpty
                                                ? null
                                                : _purpose,
                                            items: _purposes,
                                            hint: 'Select purpose',
                                            hasError:
                                                _errors['purpose'] != null,
                                            onChanged: (v) {
                                              setState(() {
                                                _purpose = v ?? '';
                                                _showPurposeOther =
                                                    v == 'Others';
                                                if (!_showPurposeOther) {
                                                  _purposeOtherCtrl.clear();
                                                }
                                              });
                                              _clearFieldError('purpose');
                                              _clearFieldError('purposeOther');
                                            },
                                          ),
                                        ),
                                        if (_showPurposeOther) ...[
                                          const SizedBox(height: 10),
                                          _FieldCol(
                                            label: 'Please specify *',
                                            errorText: _errors['purposeOther'],
                                            child: _PlainTextField(
                                              controller: _purposeOtherCtrl,
                                              hint: 'Specify purpose',
                                              hasError:
                                                  _errors['purposeOther'] !=
                                                  null,
                                              onChanged: (_) =>
                                                  _clearFieldError(
                                                    'purposeOther',
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _FieldCol(
                                          label: 'Mode of Transportation *',
                                          errorText: _errors['transport'],
                                          child: _DropdownField(
                                            value: _transport.isEmpty
                                                ? null
                                                : _transport,
                                            items: _transports,
                                            hint: 'Select transportation',
                                            hasError:
                                                _errors['transport'] != null,
                                            onChanged: (v) {
                                              setState(() {
                                                _transport = v ?? '';
                                                _showTransportOther =
                                                    v == 'Others';
                                                if (!_showTransportOther) {
                                                  _transportOtherCtrl.clear();
                                                }
                                              });
                                              _clearFieldError('transport');
                                              _clearFieldError(
                                                'transportOther',
                                              );
                                            },
                                          ),
                                        ),
                                        if (_showTransportOther) ...[
                                          const SizedBox(height: 10),
                                          _FieldCol(
                                            label: 'Please specify *',
                                            errorText:
                                                _errors['transportOther'],
                                            child: _PlainTextField(
                                              controller: _transportOtherCtrl,
                                              hint: 'Specify transportation',
                                              hasError:
                                                  _errors['transportOther'] !=
                                                  null,
                                              onChanged: (_) =>
                                                  _clearFieldError(
                                                    'transportOther',
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Demographic Breakdown ───────────────────────
                      _SectionCard(
                        title: 'Guest Demographic Breakdown',
                        subtitle:
                            'Breakdown must sum to $_totalGuests total guests',
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$_demoTotal / $_totalGuests',
                              style: TextStyle(
                                color: _demoTotal == _totalGuests
                                    ? const Color(0xFF00C48C)
                                    : AppColors.textGray,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_errors['demographicSum'] != null) ...[
                              const SizedBox(height: 4),
                              _InlineError(message: _errors['demographicSum']!),
                              const SizedBox(height: 10),
                            ],

                            ..._demoRows.asMap().entries.map(
                              (e) => _DemoEntryRow(
                                key: ValueKey(e.key),
                                index: e.key,
                                entry: e.value,
                                isNarrow: isNarrow,
                                countries: _countries,
                                nationalityOptions: _nationalityOptions,
                                phRegions: _phRegions,
                                sexOptions: _sexOptions,
                                ageGroupOptions: _ageGroupOptions,
                                rowErrors: e.key < _rowErrors.length
                                    ? _rowErrors[e.key]
                                    : {},
                                onChanged: (updated) {
                                  setState(() => _demoRows[e.key] = updated);
                                  _clearRowFieldError(e.key, 'country');
                                  _clearRowFieldError(e.key, 'nationality');
                                  _clearRowFieldError(e.key, 'region');
                                  _clearRowFieldError(e.key, 'sex');
                                  _clearRowFieldError(e.key, 'ageGroup');
                                  _clearRowFieldError(e.key, 'count');
                                  _clearFieldError('demographicSum');
                                },
                                onRemove: _demoRows.length > 1
                                    ? () => _removeRow(e.key)
                                    : null,
                              ),
                            ),

                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Icon(
                                  Icons.lightbulb_outline,
                                  color: Color(0xFFD4A017),
                                  size: 13,
                                ),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Each row is a unique combination of country, region, OFW status, sex, and age group. '
                                    'Add multiple rows to cover all guest segments.',
                                    style: TextStyle(
                                      color: AppColors.textSubtle,
                                      fontSize: 11,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: _AddRowButton(onTap: _addRow),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _Footer(onClear: _clearForm, onSave: _save),
            ],
          ),
        ),
      ),
    );
  }

  void _clearForm() {
    _checkInCtrl.clear();
    _checkOutCtrl.clear();
    _guestsCtrl.clear();
    _roomsCtrl.clear();
    _purposeOtherCtrl.clear();
    _transportOtherCtrl.clear();
    setState(() {
      _purpose = _purposes.first;
      _transport = _transports.first;
      _showPurposeOther = false;
      _showTransportOther = false;
      _lengthOfStay = '0 nights';
      _demoRows = [DemographicEntry()];
      _errors = {};
      _rowErrors = [{}];
    });
  }
}

// ─── Title bar ────────────────────────────────────────────────────────────────

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 16, 14),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edit Guest Entry',
                  style: TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Update tourist demographic data',
                  style: TextStyle(color: AppColors.textGray, fontSize: 12.5),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onClose,
            child: const Icon(
              Icons.close_rounded,
              color: AppColors.textGray,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Global error banner ──────────────────────────────────────────────────────

class _GlobalErrorBanner extends StatelessWidget {
  const _GlobalErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.accentRed.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accentRed.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: AppColors.accentRed,
            size: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.accentRed, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section card ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.backgroundDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
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
                      title,
                      style: const TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: AppColors.primaryCyan,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

// ─── Field column (label + field + inline error) ──────────────────────────────

class _FieldCol extends StatelessWidget {
  const _FieldCol({required this.label, required this.child, this.errorText});

  final String label;
  final Widget child;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textGray,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        child,
        if (errorText != null) ...[
          const SizedBox(height: 5),
          _InlineError(message: errorText!),
        ],
      ],
    );
  }
}

// ─── Inline error ─────────────────────────────────────────────────────────────

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            Icons.error_outline_rounded,
            size: 12,
            color: AppColors.accentRed,
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: AppColors.accentRed,
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Add Row button ───────────────────────────────────────────────────────────

class _AddRowButton extends StatelessWidget {
  const _AddRowButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.add, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Text(
                'Add Row',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Demographic entry row ────────────────────────────────────────────────────

class _DemoEntryRow extends StatelessWidget {
  const _DemoEntryRow({
    super.key,
    required this.index,
    required this.entry,
    required this.isNarrow,
    required this.countries,
    required this.nationalityOptions,
    required this.phRegions,
    required this.sexOptions,
    required this.ageGroupOptions,
    required this.rowErrors,
    required this.onChanged,
    this.onRemove,
  });

  final int index;
  final DemographicEntry entry;
  final bool isNarrow;
  final List<String> countries;
  final List<String> nationalityOptions;
  final List<String> phRegions;
  final List<String> sexOptions;
  final List<String> ageGroupOptions;
  final Map<String, String?> rowErrors;
  final ValueChanged<DemographicEntry> onChanged;
  final VoidCallback? onRemove;

  // Region is only active for Philippine residents — not OFW.
  // `_regionEnabled` removed because it was unused; use inline checks where needed.

  @override
  Widget build(BuildContext context) {
    final countCtrl =
        TextEditingController(text: entry.count == 0 ? '' : '${entry.count}')
          ..selection = TextSelection.collapsed(
            offset: entry.count == 0 ? 0 : '${entry.count}'.length,
          );

    final deleteBtn = GestureDetector(
      onTap: onRemove,
      child: Icon(
        Icons.delete_rounded,
        size: 16,
        color: onRemove != null
            ? AppColors.accentRed
            : AppColors.textSubtle.withOpacity(0.3),
      ),
    );

    // ── Mobile card ──────────────────────────────────────────────────────────
    if (isNarrow) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.backgroundDark,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: rowErrors.isNotEmpty
                ? AppColors.accentRed.withOpacity(0.5)
                : AppColors.cardBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: entry.isOverseas,
                    onChanged: (v) => onChanged(
                      entry.copyWith(
                        isOverseas: v ?? false,
                        nationality: '', // always reset when toggling
                        region: 'N/A', // always reset when toggling
                      ),
                    ),
                    activeColor: const Color(0xFF3B82F6),
                    side: const BorderSide(
                      color: AppColors.textGray,
                      width: 1.4,
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Overseas Fil.',
                  style: TextStyle(color: AppColors.textGray, fontSize: 12.5),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // ── Country + delete ──────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _CompactDropWithError(
                    errorText: rowErrors['country'],
                    child: _CompactDrop(
                      hint: entry.isOverseas ? 'N/A (Overseas)' : 'Country',
                      value: entry.country.isEmpty ? null : entry.country,
                      items: countries,
                      enabled: !entry.isOverseas,
                      onChanged: (v) => onChanged(
                        entry.copyWith(
                          country: v ?? '',
                          region: v != 'Philippines' ? 'N/A' : entry.region,
                          nationality: '', // ← ADD
                          isOverseas: v != 'Philippines'
                              ? false
                              : entry.isOverseas,
                        ),
                      ),
                    ),
                  ),
                ),
                if (onRemove != null) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: deleteBtn,
                  ),
                ],
              ],
            ),

            // ── OFW + Region — Philippines only ───────────────────────
            // OFW checkbox

            // Nationality + Region — hidden when OFW
            if (entry.country == 'Philippines' && !entry.isOverseas) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _CompactDropWithError(
                      errorText: rowErrors['nationality'],
                      child: _CompactDrop(
                        hint: 'Nationality',
                        value: entry.nationality.isEmpty
                            ? null
                            : entry.nationality,
                        items: nationalityOptions,
                        onChanged: (v) =>
                            onChanged(entry.copyWith(nationality: v ?? '')),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: _CompactDropWithError(
                      errorText: rowErrors['region'],
                      child: _CompactDrop(
                        hint: 'Region',
                        value: entry.region != 'N/A' ? entry.region : null,
                        items: phRegions,
                        onChanged: (v) =>
                            onChanged(entry.copyWith(region: v ?? 'N/A')),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 8),

            // ── Sex + Age Group + Count ───────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _CompactDropWithError(
                    errorText: rowErrors['sex'],
                    child: _CompactDrop(
                      hint: 'Sex',
                      value: entry.sex.isEmpty ? null : entry.sex,
                      items: sexOptions,
                      onChanged: (v) => onChanged(entry.copyWith(sex: v ?? '')),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CompactDropWithError(
                    errorText: rowErrors['ageGroup'],
                    child: _CompactDrop(
                      hint: 'Age Group',
                      value: entry.ageGroup.isEmpty ? null : entry.ageGroup,
                      items: ageGroupOptions,
                      onChanged: (v) =>
                          onChanged(entry.copyWith(ageGroup: v ?? '')),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 64,
                  child: _CompactDropWithError(
                    errorText: rowErrors['count'],
                    child: _CountField(
                      controller: countCtrl,
                      hasError: rowErrors['count'] != null,
                      onChanged: (v) => onChanged(
                        entry.copyWith(count: int.tryParse(v) ?? 0),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // ── Desktop row ──────────────────────────────────────────────────────────
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 112,
            height: _kFieldHeight,
            child: Tooltip(
              message: 'Filipino guest living overseas',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: entry.isOverseas,
                    onChanged: (v) => onChanged(
                      entry.copyWith(
                        isOverseas: v ?? false,
                        nationality: '', // reset when toggling
                        region: 'N/A', // reset when toggling
                      ),
                    ),
                    activeColor: const Color(0xFF3B82F6),
                    side: const BorderSide(
                      color: AppColors.textGray,
                      width: 1.4,
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 4),
                  const Flexible(
                    child: Text(
                      'Overseas Fil.',
                      style: TextStyle(color: AppColors.textGray, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Country — always visible
          Expanded(
            flex: 3,
            child: _CompactDropWithError(
              errorText: rowErrors['country'],
              child: _CompactDrop(
                hint: entry.isOverseas ? 'N/A (Overseas)' : 'Country',
                value: entry.country.isEmpty ? null : entry.country,
                items: countries,
                enabled: !entry.isOverseas,
                onChanged: (v) => onChanged(
                  entry.copyWith(
                    country: v ?? '',
                    region: v != 'Philippines' ? 'N/A' : entry.region,
                    isOverseas: v != 'Philippines' ? false : entry.isOverseas,
                  ),
                ),
              ),
            ),
          ),

          // Region + OFW checkbox — only visible when Philippines is selected
          // OFW checkbox

          // Nationality + Region — hidden when OFW
          if (entry.country == 'Philippines' && !entry.isOverseas) ...[
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _CompactDropWithError(
                errorText: rowErrors['nationality'],
                child: _CompactDrop(
                  hint: 'Nationality',
                  value: entry.nationality.isEmpty ? null : entry.nationality,
                  items: nationalityOptions,
                  onChanged: (v) =>
                      onChanged(entry.copyWith(nationality: v ?? '')),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: _CompactDropWithError(
                errorText: rowErrors['region'],
                child: _CompactDrop(
                  hint: 'Region',
                  value: entry.region != 'N/A' ? entry.region : null,
                  items: phRegions,
                  onChanged: (v) =>
                      onChanged(entry.copyWith(region: v ?? 'N/A')),
                ),
              ),
            ),
          ],

          const SizedBox(width: 8),

          // Sex
          Expanded(
            flex: 2,
            child: _CompactDropWithError(
              errorText: rowErrors['sex'],
              child: _CompactDrop(
                hint: 'Sex',
                value: entry.sex.isEmpty ? null : entry.sex,
                items: sexOptions,
                onChanged: (v) => onChanged(entry.copyWith(sex: v ?? '')),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Age Group
          Expanded(
            flex: 2,
            child: _CompactDropWithError(
              errorText: rowErrors['ageGroup'],
              child: _CompactDrop(
                hint: 'Age Group',
                value: entry.ageGroup.isEmpty ? null : entry.ageGroup,
                items: ageGroupOptions,
                onChanged: (v) => onChanged(entry.copyWith(ageGroup: v ?? '')),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Count
          SizedBox(
            width: 60,
            child: _CompactDropWithError(
              errorText: rowErrors['count'],
              child: _CountField(
                controller: countCtrl,
                hasError: rowErrors['count'] != null,
                onChanged: (v) =>
                    onChanged(entry.copyWith(count: int.tryParse(v) ?? 0)),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Delete
          SizedBox(width: 20, child: deleteBtn),
        ],
      ),
    );
  }
}

// ─── Footer ───────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer({required this.onClear, required this.onSave});
  final VoidCallback onClear;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: onClear,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.cardBorder),
              foregroundColor: AppColors.textGray,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Clear Form',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.save_outlined, size: 16),
              label: const Text(
                'Save Changes',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SHARED INPUT DECORATION
// ─────────────────────────────────────────────────────────────────────────────

InputDecoration _fieldDecoration({String? hint, bool hasError = false}) {
  final borderColor = hasError ? AppColors.accentRed : _kInputBorder;
  final focusColor = hasError ? AppColors.accentRed : _kInputFocused;
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: _kInputHint, fontSize: 13),
    filled: true,
    fillColor: hasError ? AppColors.accentRed.withOpacity(0.04) : _kInputFill,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: borderColor),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: borderColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: focusColor, width: 1.4),
    ),
  );
}

// ─── Date field ───────────────────────────────────────────────────────────────

class _DateField extends StatelessWidget {
  const _DateField({
    required this.controller,
    required this.hint,
    this.hasError = false,
    this.onPicked,
    this.firstDate,
    this.lastDate,
  });
  final TextEditingController controller;
  final String hint;
  final bool hasError;
  final VoidCallback? onPicked;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kFieldHeight,
      child: TextField(
        controller: controller,
        readOnly: true,
        style: const TextStyle(color: _kInputText, fontSize: 13),
        decoration: _fieldDecoration(hint: hint, hasError: hasError).copyWith(
          suffixIcon: Icon(
            Icons.calendar_today_outlined,
            color: hasError ? AppColors.accentRed : _kInputHint,
            size: 14,
          ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: _kFieldHeight,
          ),
        ),
        onTap: () async {
          final current = DateTime.tryParse(controller.text);
          final now = DateTime.now();
          // AFTER
          final resolvedFirst = firstDate ?? DateTime(2020);
          final resolvedLast = lastDate ?? now.add(const Duration(days: 730));
          final safeInitial =
              (current != null &&
                  !current.isBefore(resolvedFirst) &&
                  !current.isAfter(resolvedLast))
              ? current
              : resolvedFirst;

          final picked = await showDatePicker(
            context: context,
            initialDate: safeInitial,
            firstDate: resolvedFirst,
            lastDate: resolvedLast,
            builder: (ctx, child) => Theme(
              data: ThemeData(
                useMaterial3: true,
                colorScheme: const ColorScheme.light(
                  primary: Color(0xFF3B82F6),
                  onPrimary: Colors.white,
                  surface: Colors.white,
                  onSurface: Color(0xFF111827),
                ),
                dialogTheme: DialogThemeData(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              child: child!,
            ),
          );
          if (picked != null) {
            controller.text =
                '${picked.year.toString().padLeft(4, '0')}-'
                '${picked.month.toString().padLeft(2, '0')}-'
                '${picked.day.toString().padLeft(2, '0')}';
            onPicked?.call();
          }
        },
      ),
    );
  }
}

// ─── Read-only field ──────────────────────────────────────────────────────────

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kFieldHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _kReadOnlyFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kInputBorder),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        value,
        style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
      ),
    );
  }
}

// ─── Number field ─────────────────────────────────────────────────────────────

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.hint,
    this.hasError = false,
    this.onChanged,
  });
  final TextEditingController controller;
  final String hint;
  final bool hasError;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kFieldHeight,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(color: _kInputText, fontSize: 13),
        decoration: _fieldDecoration(hint: hint, hasError: hasError),
        onChanged: onChanged,
      ),
    );
  }
}

// ─── Plain text field ─────────────────────────────────────────────────────────

class _PlainTextField extends StatelessWidget {
  const _PlainTextField({
    required this.controller,
    required this.hint,
    this.hasError = false,
    this.onChanged,
  });
  final TextEditingController controller;
  final String hint;
  final bool hasError;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kFieldHeight,
      child: TextField(
        controller: controller,
        style: const TextStyle(color: _kInputText, fontSize: 13),
        decoration: _fieldDecoration(hint: hint, hasError: hasError),
        onChanged: onChanged,
      ),
    );
  }
}

// ─── Full-width dropdown field (Purpose / Transport) ─────────────────────────

class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
    this.hasError = false,
  });
  final String? value;
  final String hint;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final borderColor = hasError ? AppColors.accentRed : _kInputBorder;
    return Container(
      height: _kFieldHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: hasError ? AppColors.accentRed.withOpacity(0.04) : _kInputFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isDense: true,
          value: value,
          isExpanded: true,
          hint: Text(
            hint,
            style: const TextStyle(color: _kInputHint, fontSize: 13),
          ),
          dropdownColor: _kDropBg,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: hasError ? AppColors.accentRed : _kInputHint,
            size: 18,
          ),
          style: const TextStyle(color: _kInputText, fontSize: 13),
          items: items
              .map(
                (e) => DropdownMenuItem<String>(
                  value: e,
                  child: Text(
                    e,
                    style: const TextStyle(color: _kInputText, fontSize: 13),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ─── Compact dropdown for demographic rows ────────────────────────────────────

class _CompactDrop extends StatelessWidget {
  const _CompactDrop({
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
  });
  final String hint;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final effectiveValue = (value != null && items.contains(value))
        ? value
        : null;
    final fillColor = enabled ? _kInputFill : _kReadOnlyFill;
    final textColor = enabled ? _kInputText : const Color(0xFF9CA3AF);
    final hintColor = enabled ? _kInputHint : const Color(0xFFD1D5DB);
    final iconColor = enabled ? _kInputHint : const Color(0xFFD1D5DB);
    final borderColor = enabled ? _kInputBorder : const Color(0xFFE5E7EB);

    return Container(
      height: _kFieldHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: effectiveValue,
          hint: Text(
            hint,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: hintColor, fontSize: 12.5),
          ),
          style: TextStyle(color: textColor, fontSize: 12.5),
          dropdownColor: _kDropBg,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: iconColor,
            size: 16,
          ),
          isExpanded: true,
          isDense: true,
          onChanged: enabled ? onChanged : null,
          items: items
              .map(
                (e) => DropdownMenuItem<String>(
                  value: e,
                  child: Text(
                    e,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: textColor, fontSize: 12.5),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

// ─── Compact drop with inline error wrapper ───────────────────────────────────

class _CompactDropWithError extends StatelessWidget {
  const _CompactDropWithError({required this.child, this.errorText});

  final Widget child;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    if (errorText == null) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        child,
        const SizedBox(height: 3),
        _InlineError(message: errorText!),
      ],
    );
  }
}

// ─── Count field ──────────────────────────────────────────────────────────────

class _CountField extends StatelessWidget {
  const _CountField({
    required this.controller,
    required this.onChanged,
    this.hasError = false,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final borderColor = hasError ? AppColors.accentRed : _kInputBorder;
    return SizedBox(
      height: _kFieldHeight,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        style: const TextStyle(color: _kInputText, fontSize: 13),
        decoration: InputDecoration(
          hintText: '0',
          hintStyle: const TextStyle(color: _kInputHint, fontSize: 12.5),
          filled: true,
          fillColor: hasError
              ? AppColors.accentRed.withOpacity(0.04)
              : _kInputFill,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 11,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: BorderSide(color: borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: const BorderSide(color: _kInputFocused, width: 1.4),
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}
