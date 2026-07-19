// ignore_for_file: use_null_aware_elements

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../pages/business_guest_records_page.dart';
import '../../../api/business_guest_entry_api.dart';
import 'dart:async';
import '../../../core/services/offline_service.dart';
import '../../../core/services/psgc_repository.dart';
import '../../../core/models/psgc_models.dart';

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

// ─── Option constants ────────────────────────────────────────────────────────

const _countryOptions = [
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

const _nationalityOptions = ['Filipino', 'Foreign'];

const _sexOptions = ['Male', 'Female'];

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

  // ── Lead guest fields ────────────────────────────────────────────────────
  late final TextEditingController _leadBirthdateCtrl;
  String? _leadCountry;
  String? _leadNationality;
  String? _selectedRegionCode;
  String? _selectedProvinceCode;
  String? _selectedCityCode;
  bool _leadIsOverseas = false;
  String? _leadSex;

  // ── Room selection ───────────────────────────────────────────────────────
  final Set<String> _selectedRoomIds = {};
  List<RoomInfo> _vacantRooms = [];
  bool _isLoadingRooms = false;
  final BusinessGuestEntryApi _entryApi = BusinessGuestEntryApi();

  // ── Inline validation state ───────────────────────────────────────────────
  Map<String, String?> _errors = {};

  // ── Post-checkout lock ───────────────────────────────────────────────────
  late final bool _isPostCheckout;

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

  // ─── Init ────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    final r = widget.record;

    _isPostCheckout = r.actualCheckOut != null;

    String stripTime(String d) {
      if (d.contains('T')) return d.split('T')[0];
      if (d.contains(' ')) return d.split(' ')[0];
      return d;
    }

    _checkInCtrl = TextEditingController(text: stripTime(r.checkIn));
    _checkOutCtrl = TextEditingController(text: stripTime(r.checkOut));
    _guestsCtrl = TextEditingController(text: r.guests.toString());

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

    // Lead guest
    _leadCountry = r.leadCountry;
    _leadNationality = r.leadNationality;
    _leadIsOverseas = r.leadIsOverseas;
    _leadBirthdateCtrl = TextEditingController(text: r.leadBirthdate ?? '');
    _leadSex = r.leadSex;

    // PSGC reverse-lookup: resolve names → codes for cascading dropdowns
    final repo = PsgcRepository.instance;
    _selectedRegionCode = r.leadPhilippinesRegion != null
        ? repo.findRegionCodeByName(r.leadPhilippinesRegion!)
        : null;
    if (_selectedRegionCode != null && r.leadProvince != null) {
      _selectedProvinceCode = repo.findProvinceCodeByName(
        _selectedRegionCode!,
        r.leadProvince!,
      );
    }
    if (_selectedProvinceCode != null && r.leadMunicipality != null) {
      _selectedCityCode = repo.findCityCodeByName(
        _selectedProvinceCode!,
        r.leadMunicipality!,
        regionCode: _selectedRegionCode,
      );
    } else if (_selectedRegionCode != null && r.leadMunicipality != null) {
      _selectedCityCode = repo.findCityCodeByName(
        '',
        r.leadMunicipality!,
        regionCode: _selectedRegionCode,
      );
    }

    // Room selection
    _selectedRoomIds.addAll(r.roomIds);

    _isOffline = !ConnectivityService.instance.isOnline;
    _connectivitySub = ConnectivityService.instance.onConnectivityChanged
        .listen((isOnline) {
          if (mounted) setState(() => _isOffline = !isOnline);
        });

    _loadVacantRooms();
  }

  @override
  void dispose() {
    _checkInCtrl.dispose();
    _checkOutCtrl.dispose();
    _guestsCtrl.dispose();
    _purposeOtherCtrl.dispose();
    _transportOtherCtrl.dispose();
    _leadBirthdateCtrl.dispose();
    _connectivitySub?.cancel();
    super.dispose();
  }

  // ─── Derived values ───────────────────────────────────────────────────────

  int get _totalGuests => int.tryParse(_guestsCtrl.text.trim()) ?? 0;

  bool get _isPhilippines => !_leadIsOverseas && _leadCountry == 'Philippines';

  // ─── Room loading ────────────────────────────────────────────────────────

  Future<void> _loadVacantRooms() async {
    setState(() => _isLoadingRooms = true);
    try {
      final businessId = await _entryApi.fetchBusinessId();
      if (businessId == null || !mounted) return;
      final rooms = await _entryApi.fetchVacantRooms(businessId);
      if (!mounted) return;

      final existingIds = rooms.map((r) => r.id).toSet();

      // Add assigned rooms from roomDetails (has full info)
      for (final gr in widget.record.roomDetails) {
        if (!existingIds.contains(gr.id)) {
          rooms.add(RoomInfo(id: gr.id, roomNumber: gr.roomNumber, capacity: gr.capacity));
          existingIds.add(gr.id);
        }
      }

      // Fallback: add rooms from roomIds (just UUIDs) if roomDetails was empty
      if (widget.record.roomDetails.isEmpty) {
        for (final roomId in widget.record.roomIds) {
          if (!existingIds.contains(roomId)) {
            rooms.add(RoomInfo(
              id: roomId,
              roomNumber: roomId.length > 8 ? roomId.substring(0, 8) : roomId,
              capacity: 0,
            ));
            existingIds.add(roomId);
          }
        }
      }

      setState(() {
        _vacantRooms = rooms;
        _isLoadingRooms = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingRooms = false);
    }
  }

  // ─── Nights calculation ──────────────────────────────────────────────────

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

  // ─── Error clearing ───────────────────────────────────────────────────────

  void _clearFieldError(String key) {
    if (_errors.containsKey(key)) {
      setState(() => _errors = Map.from(_errors)..remove(key));
    }
  }

  // ─── Validation ───────────────────────────────────────────────────────────

  bool _validateAndSetErrors() {
    final errors = <String, String?>{};
    bool hasError = false;

    // ── Check-in (skip if post-checkout — field is locked) ─────────────────
    if (!_isPostCheckout) {
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

      // ── Check-out ─────────────────────────────────────────────────────────
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

    // ── Purpose ─────────────────────────────────────────────────────────────
    if (_purpose.isEmpty) {
      errors['purpose'] = 'Please select a purpose of visit.';
      hasError = true;
    } else if (_purpose == 'Others' &&
        _purposeOtherCtrl.text.trim().isEmpty) {
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

    // ── Lead guest validation ─────────────────────────────────────────────
    if (!_leadIsOverseas) {
      if (_leadCountry == null) {
        errors['leadCountry'] = 'Please select a country.';
        hasError = true;
      } else if (_leadCountry == 'Philippines' &&
          _leadNationality == null) {
        errors['leadNationality'] = 'Please select nationality.';
        hasError = true;
      }
    }

    if (_leadBirthdateCtrl.text.trim().isEmpty) {
      errors['leadBirthdate'] = 'Please select a birthdate.';
      hasError = true;
    }

    if (_leadSex == null) {
      errors['leadSex'] = 'Please select sex.';
      hasError = true;
    }

    setState(() => _errors = errors);
    return !hasError;
  }

  // ─── Save ─────────────────────────────────────────────────────────────────

  void _save() {
    if (!_validateAndSetErrors()) return;

    final purposeValue =
        _purpose == 'Others' ? _purposeOtherCtrl.text.trim() : _purpose;
    final transportValue =
        _transport == 'Others' ? _transportOtherCtrl.text.trim() : _transport;

    // Derive PSGC names from selected codes
    final repo = PsgcRepository.instance;
    String? regionName;
    String? provinceName;
    String? cityName;
    if (!_leadIsOverseas && _leadCountry == 'Philippines') {
      if (_selectedRegionCode != null) {
        regionName = repo.regions
            .where((r) => r.code == _selectedRegionCode)
            .firstOrNull
            ?.name;
      }
      if (_selectedProvinceCode != null) {
        provinceName = repo
            .provincesFor(_selectedRegionCode ?? '')
            .where((p) => p.code == _selectedProvinceCode)
            .firstOrNull
            ?.name;
      }
      if (_selectedCityCode != null) {
        final cityProvince = _selectedProvinceCode != null
            ? repo.citiesFor(_selectedProvinceCode!)
            : <CityMunicipality>[];
        cityName = cityProvince
            .where((c) => c.code == _selectedCityCode)
            .firstOrNull
            ?.name;
        if (cityName == null && _selectedRegionCode != null) {
          cityName = repo
              .citiesForRegion(_selectedRegionCode!)
              .where((c) => c.code == _selectedCityCode)
              .firstOrNull
              ?.name;
        }
      }
    }

    final updated = GuestRecord(
      id: widget.record.id,
      checkIn: _isPostCheckout ? widget.record.checkIn : _checkInCtrl.text.trim(),
      checkOut: _isPostCheckout ? widget.record.checkOut : _checkOutCtrl.text.trim(),
      nights: _lengthOfStay,
      guests: _totalGuests,
      rooms: _isPostCheckout ? widget.record.rooms : _selectedRoomIds.length,
      roomDetails: widget.record.roomDetails,
      roomIds: _isPostCheckout ? widget.record.roomIds : _selectedRoomIds.toList(),
      purpose: purposeValue,
      transport: transportValue,
      status: widget.record.status,
      demographics: widget.record.demographics,
      leadCountry: _leadIsOverseas ? null : _leadCountry,
      leadMunicipality: cityName,
      leadProvince: provinceName,
      leadNationality:
          _leadIsOverseas ? null : _leadNationality,
      leadPhilippinesRegion:
          _leadIsOverseas || _leadCountry != 'Philippines' ? null : regionName,
      leadIsOverseas: _leadIsOverseas,
      leadBirthdate: _leadBirthdateCtrl.text.trim().isEmpty
          ? null
          : _leadBirthdateCtrl.text.trim(),
      leadSex: _leadSex,
    );

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
        backgroundColor:
            isOnline ? AppColors.primaryCyan : const Color(0xFFF59E0B),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ─── Clear form ──────────────────────────────────────────────────────────

  void _clearForm() {
    _checkInCtrl.clear();
    _checkOutCtrl.clear();
    _guestsCtrl.clear();
    _purposeOtherCtrl.clear();
    _transportOtherCtrl.clear();
    _leadBirthdateCtrl.clear();
    setState(() {
      _purpose = _purposes.first;
      _transport = _transports.first;
      _showPurposeOther = false;
      _showTransportOther = false;
      _lengthOfStay = '0 nights';
      _leadCountry = null;
      _leadNationality = null;
      _leadIsOverseas = false;
      _selectedRegionCode = null;
      _selectedProvinceCode = null;
      _selectedCityCode = null;
      _leadSex = null;
      _selectedRoomIds.clear();
      _errors = {};
    });
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
                            if (isNarrow) ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _FieldCol(
                                      label: 'Check-in Date *',
                                      errorText: _isPostCheckout ? null : _errors['checkIn'],
                                      child: _isPostCheckout
                                          ? _ReadOnlyField(value: _checkInCtrl.text)
                                          : _DateField(
                                              controller: _checkInCtrl,
                                              hint: 'yyyy-mm-dd',
                                              hasError: _errors['checkIn'] != null,
                                              lastDate: DateTime.now(),
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
                                      errorText: _isPostCheckout ? null : _errors['checkOut'],
                                      child: _isPostCheckout
                                          ? _ReadOnlyField(value: _checkOutCtrl.text)
                                          : _DateField(
                                              controller: _checkOutCtrl,
                                              hint: 'yyyy-mm-dd',
                                              hasError: _errors['checkOut'] != null,
                                              firstDate: DateTime.tryParse(
                                                    _checkInCtrl.text.trim(),
                                                  ) ??
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
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _FieldCol(
                                      label: 'Check-in Date *',
                                      errorText: _isPostCheckout ? null : _errors['checkIn'],
                                      child: _isPostCheckout
                                          ? _ReadOnlyField(value: _checkInCtrl.text)
                                          : _DateField(
                                              controller: _checkInCtrl,
                                              hint: 'yyyy-mm-dd',
                                              hasError: _errors['checkIn'] != null,
                                              lastDate: DateTime.now(),
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
                                      errorText: _isPostCheckout ? null : _errors['checkOut'],
                                      child: _isPostCheckout
                                          ? _ReadOnlyField(value: _checkOutCtrl.text)
                                          : _DateField(
                                              controller: _checkOutCtrl,
                                              hint: 'yyyy-mm-dd',
                                              hasError: _errors['checkOut'] != null,
                                              firstDate: DateTime.tryParse(
                                                    _checkInCtrl.text.trim(),
                                                  ) ??
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

                            // ── Total Guests ──────────────────────────
                            _FieldCol(
                              label: 'Total Guests *',
                              errorText: _errors['totalGuests'],
                              child: _NumberField(
                                controller: _guestsCtrl,
                                hint: 'e.g. 10',
                                hasError:
                                    _errors['totalGuests'] != null,
                                onChanged: (_) {
                                  setState(() {});
                                  _clearFieldError('totalGuests');
                                },
                              ),
                            ),
                            const SizedBox(height: 14),

                            // ── Rooms ─────────────────────────────────
                            _FieldCol(
                              label: _isPostCheckout
                                  ? 'Rooms (locked after check-out)'
                                  : 'Rooms (leave empty for day-tour guests)',
                              errorText: _isPostCheckout ? null : _errors['rooms'],
                              child: _EditRoomSelector(
                                vacantRooms: _vacantRooms,
                                selectedRoomIds: _selectedRoomIds,
                                isLoading: _isLoadingRooms,
                                hasError: _errors['rooms'] != null,
                                readOnly: _isPostCheckout,
                                onRoomToggled: (roomId) {
                                  setState(() {
                                    if (_selectedRoomIds.contains(roomId)) {
                                      _selectedRoomIds.remove(roomId);
                                    } else {
                                      _selectedRoomIds.add(roomId);
                                    }
                                  });
                                  _clearFieldError('rooms');
                                },
                              ),
                            ),
                            const SizedBox(height: 14),

                            // ── Purpose / Transport ─────────────────────
                            if (isNarrow) ...[
                              _FieldCol(
                                label: 'Purpose of Visit *',
                                errorText: _errors['purpose'],
                                child: _DropdownField(
                                  value:
                                      _purpose.isEmpty ? null : _purpose,
                                  items: _purposes,
                                  hint: 'Select purpose',
                                  hasError:
                                      _errors['purpose'] != null,
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
                                    hasError:
                                        _errors['purposeOther'] != null,
                                    onChanged: (_) => _clearFieldError(
                                        'purposeOther'),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
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
                                    hasError:
                                        _errors['transportOther'] !=
                                            null,
                                    onChanged: (_) => _clearFieldError(
                                        'transportOther'),
                                  ),
                                ),
                              ],
                            ] else ...[
                              Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _FieldCol(
                                          label: 'Purpose of Visit *',
                                          errorText:
                                              _errors['purpose'],
                                          child: _DropdownField(
                                            value: _purpose.isEmpty
                                                ? null
                                                : _purpose,
                                            items: _purposes,
                                            hint: 'Select purpose',
                                            hasError: _errors[
                                                    'purpose'] !=
                                                null,
                                            onChanged: (v) {
                                              setState(() {
                                                _purpose = v ?? '';
                                                _showPurposeOther =
                                                    v == 'Others';
                                                if (!_showPurposeOther) {
                                                  _purposeOtherCtrl
                                                      .clear();
                                                }
                                              });
                                              _clearFieldError(
                                                  'purpose');
                                              _clearFieldError(
                                                  'purposeOther');
                                            },
                                          ),
                                        ),
                                        if (_showPurposeOther) ...[
                                          const SizedBox(height: 10),
                                          _FieldCol(
                                            label: 'Please specify *',
                                            errorText: _errors[
                                                'purposeOther'],
                                            child: _PlainTextField(
                                              controller:
                                                  _purposeOtherCtrl,
                                              hint: 'Specify purpose',
                                              hasError: _errors[
                                                      'purposeOther'] !=
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
                                          label:
                                              'Mode of Transportation *',
                                          errorText:
                                              _errors['transport'],
                                          child: _DropdownField(
                                            value: _transport.isEmpty
                                                ? null
                                                : _transport,
                                            items: _transports,
                                            hint:
                                                'Select transportation',
                                            hasError: _errors[
                                                    'transport'] !=
                                                null,
                                            onChanged: (v) {
                                              setState(() {
                                                _transport = v ?? '';
                                                _showTransportOther =
                                                    v == 'Others';
                                                if (!_showTransportOther) {
                                                  _transportOtherCtrl
                                                      .clear();
                                                }
                                              });
                                              _clearFieldError(
                                                  'transport');
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
                                            errorText: _errors[
                                                'transportOther'],
                                            child: _PlainTextField(
                                              controller:
                                                  _transportOtherCtrl,
                                              hint:
                                                  'Specify transportation',
                                              hasError: _errors[
                                                      'transportOther'] !=
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

                      // ── Lead Guest Information ──────────────────────
                      _LeadGuestCard(
                        leadCountry: _leadCountry,
                        selectedRegionCode: _selectedRegionCode,
                        selectedProvinceCode: _selectedProvinceCode,
                        selectedCityCode: _selectedCityCode,
                        regions: PsgcRepository.instance.regions,
                        provinces: _selectedRegionCode != null
                            ? PsgcRepository.instance.provincesFor(_selectedRegionCode!)
                            : [],
                        cities: _selectedProvinceCode != null
                            ? PsgcRepository.instance.citiesFor(_selectedProvinceCode!)
                            : (_selectedRegionCode != null
                                ? PsgcRepository.instance.citiesForRegion(_selectedRegionCode!)
                                : []),
                        leadNationality: _leadNationality,
                        leadIsOverseas: _leadIsOverseas,
                        leadBirthdate: _leadBirthdateCtrl,
                        leadSex: _leadSex,
                        isPhilippines: _isPhilippines,
                        errors: _errors,
                        onCountryChanged: (v) {
                          setState(() {
                            _leadCountry = v;
                            if (v != 'Philippines') {
                              _leadNationality = null;
                              _selectedRegionCode = null;
                              _selectedProvinceCode = null;
                              _selectedCityCode = null;
                            }
                          });
                          _clearFieldError('leadCountry');
                        },
                        onOverseasToggled: (v) {
                          setState(() {
                            _leadIsOverseas = v;
                            if (v) {
                              _leadCountry = null;
                              _leadNationality = null;
                              _selectedRegionCode = null;
                              _selectedProvinceCode = null;
                              _selectedCityCode = null;
                            }
                          });
                        },
                        onRegionChanged: (v) {
                          setState(() {
                            _selectedRegionCode = v;
                            _selectedProvinceCode = null;
                            _selectedCityCode = null;
                          });
                        },
                        onProvinceChanged: (v) {
                          setState(() {
                            _selectedProvinceCode = v;
                            _selectedCityCode = null;
                          });
                        },
                        onCityChanged: (v) {
                          setState(() => _selectedCityCode = v);
                        },
                        onNationalityChanged: (v) {
                          setState(() => _leadNationality = v);
                          _clearFieldError('leadNationality');
                        },
                        onBirthdatePicked: () {
                          _clearFieldError('leadBirthdate');
                        },
                        onSexChanged: (v) {
                          setState(() => _leadSex = v);
                          _clearFieldError('leadSex');
                        },
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
                  style: TextStyle(
                    color: AppColors.textGray,
                    fontSize: 12.5,
                  ),
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
              style:
                  const TextStyle(color: AppColors.accentRed, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Lead Guest Card ──────────────────────────────────────────────────────────

class _LeadGuestCard extends StatelessWidget {
  const _LeadGuestCard({
    required this.leadCountry,
    required this.selectedRegionCode,
    required this.selectedProvinceCode,
    required this.selectedCityCode,
    required this.regions,
    required this.provinces,
    required this.cities,
    required this.leadNationality,
    required this.leadIsOverseas,
    required this.leadBirthdate,
    required this.leadSex,
    required this.isPhilippines,
    required this.errors,
    required this.onCountryChanged,
    required this.onOverseasToggled,
    required this.onRegionChanged,
    required this.onProvinceChanged,
    required this.onCityChanged,
    required this.onNationalityChanged,
    required this.onBirthdatePicked,
    required this.onSexChanged,
  });

  final String? leadCountry;
  final String? selectedRegionCode;
  final String? selectedProvinceCode;
  final String? selectedCityCode;
  final List<Region> regions;
  final List<Province> provinces;
  final List<CityMunicipality> cities;
  final String? leadNationality;
  final bool leadIsOverseas;
  final TextEditingController leadBirthdate;
  final String? leadSex;
  final bool isPhilippines;
  final Map<String, String?> errors;
  final ValueChanged<String?> onCountryChanged;
  final ValueChanged<bool> onOverseasToggled;
  final ValueChanged<String?> onRegionChanged;
  final ValueChanged<String?> onProvinceChanged;
  final ValueChanged<String?> onCityChanged;
  final ValueChanged<String?> onNationalityChanged;
  final VoidCallback onBirthdatePicked;
  final ValueChanged<String?> onSexChanged;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final hasProvinces = provinces.isNotEmpty;

    return _SectionCard(
      title: 'Lead Guest Information',
      subtitle: 'Guest whose valid ID was checked',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Overseas Filipino checkbox ─────────────────────────────────
          GestureDetector(
            onTap: () => onOverseasToggled(!leadIsOverseas),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: leadIsOverseas,
                    onChanged: (v) => onOverseasToggled(v ?? false),
                    activeColor: const Color(0xFF3B82F6),
                    side: const BorderSide(
                        color: AppColors.textGray, width: 1.4),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Overseas Filipino (Balikbayan/OFW)',
                  style:
                      TextStyle(color: AppColors.textGray, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Country & Nationality ─────────────────────────────────────
          if (isMobile) ...[
            _FieldCol(
              label: 'Country *',
              errorText: errors['leadCountry'],
              child: _DropdownField(
                value: leadIsOverseas ? null : leadCountry,
                items: _countryOptions,
                hint:
                    leadIsOverseas ? 'N/A (Overseas)' : 'Select country',
                hasError: errors['leadCountry'] != null,
                onChanged: leadIsOverseas ? null : onCountryChanged,
              ),
            ),
            if (isPhilippines) ...[
              const SizedBox(height: 12),
              _FieldCol(
                label: 'Nationality *',
                errorText: errors['leadNationality'],
                child: _DropdownField(
                  value: leadNationality,
                  items: _nationalityOptions,
                  hint: 'Select',
                  hasError:
                      errors['leadNationality'] != null,
                  onChanged: onNationalityChanged,
                ),
              ),
            ],
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _FieldCol(
                    label: 'Country *',
                    errorText: errors['leadCountry'],
                    child: _DropdownField(
                      value: leadIsOverseas ? null : leadCountry,
                      items: _countryOptions,
                      hint: leadIsOverseas
                          ? 'N/A (Overseas)'
                          : 'Select country',
                      hasError: errors['leadCountry'] != null,
                      onChanged:
                          leadIsOverseas ? null : onCountryChanged,
                    ),
                  ),
                ),
                if (isPhilippines) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _FieldCol(
                      label: 'Nationality *',
                      errorText: errors['leadNationality'],
                      child: _DropdownField(
                        value: leadNationality,
                        items: _nationalityOptions,
                        hint: 'Select',
                        hasError:
                            errors['leadNationality'] != null,
                        onChanged: onNationalityChanged,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 14),

          // ── Region / Province / City (Philippines only) ───────────────
          if (isPhilippines) ...[
            if (isMobile) ...[
              _FieldCol(
                label: 'Region *',
                child: _DropdownField(
                  value: selectedRegionCode,
                  items: regions.map((r) => r.code).toList(),
                  displayLabels: {for (final r in regions) r.code: r.name},
                  hint: 'Select region',
                  onChanged: onRegionChanged,
                ),
              ),
              if (hasProvinces) ...[
                const SizedBox(height: 12),
                _FieldCol(
                  label: 'Province *',
                  child: _DropdownField(
                    value: selectedProvinceCode,
                    items: provinces.map((p) => p.code).toList(),
                    displayLabels: {for (final p in provinces) p.code: p.name},
                    hint: 'Select province',
                    onChanged: onProvinceChanged,
                  ),
                ),
              ],
              if ((hasProvinces && selectedProvinceCode != null) ||
                  (!hasProvinces && selectedRegionCode != null)) ...[
                const SizedBox(height: 12),
                _FieldCol(
                  label: 'City / Municipality *',
                  child: _DropdownField(
                    value: selectedCityCode,
                    items: cities.map((c) => c.code).toList(),
                    displayLabels: {for (final c in cities) c.code: c.name},
                    hint: 'Select city/municipality',
                    onChanged: onCityChanged,
                  ),
                ),
              ],
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _FieldCol(
                      label: 'Region *',
                      child: _DropdownField(
                        value: selectedRegionCode,
                        items: regions.map((r) => r.code).toList(),
                        displayLabels: {for (final r in regions) r.code: r.name},
                        hint: 'Select region',
                        onChanged: onRegionChanged,
                      ),
                    ),
                  ),
                  if (hasProvinces) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: _FieldCol(
                        label: 'Province *',
                        child: _DropdownField(
                          value: selectedProvinceCode,
                          items: provinces.map((p) => p.code).toList(),
                          displayLabels: {for (final p in provinces) p.code: p.name},
                          hint: 'Select province',
                          onChanged: onProvinceChanged,
                        ),
                      ),
                    ),
                  ],
                  if ((hasProvinces && selectedProvinceCode != null) ||
                      (!hasProvinces && selectedRegionCode != null)) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: _FieldCol(
                        label: 'City / Municipality *',
                        child: _DropdownField(
                          value: selectedCityCode,
                          items: cities.map((c) => c.code).toList(),
                          displayLabels: {for (final c in cities) c.code: c.name},
                          hint: 'Select city/municipality',
                          onChanged: onCityChanged,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 14),
          ],

          // ── Birthdate & Sex ────────────────────────────────────────────
          if (isMobile) ...[
            _FieldCol(
              label: 'Birthdate *',
              errorText: errors['leadBirthdate'],
              child: _DateField(
                controller: leadBirthdate,
                hint: 'yyyy-mm-dd',
                hasError: errors['leadBirthdate'] != null,
                lastDate: DateTime.now(),
                firstDate: DateTime(1900),
                onPicked: onBirthdatePicked,
              ),
            ),
            const SizedBox(height: 12),
            _FieldCol(
              label: 'Sex *',
              errorText: errors['leadSex'],
              child: _DropdownField(
                value: leadSex,
                items: _sexOptions,
                hint: 'Select sex',
                hasError: errors['leadSex'] != null,
                onChanged: onSexChanged,
              ),
            ),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _FieldCol(
                    label: 'Birthdate *',
                    errorText: errors['leadBirthdate'],
                    child: _DateField(
                      controller: leadBirthdate,
                      hint: 'yyyy-mm-dd',
                      hasError: errors['leadBirthdate'] != null,
                      lastDate: DateTime.now(),
                      firstDate: DateTime(1900),
                      onPicked: onBirthdatePicked,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FieldCol(
                    label: 'Sex *',
                    errorText: errors['leadSex'],
                    child: _DropdownField(
                      value: leadSex,
                      items: _sexOptions,
                      hint: 'Select sex',
                      hasError: errors['leadSex'] != null,
                      onChanged: onSexChanged,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Edit Room Selector ───────────────────────────────────────────────────────

class _EditRoomSelector extends StatelessWidget {
  const _EditRoomSelector({
    required this.vacantRooms,
    required this.selectedRoomIds,
    required this.isLoading,
    required this.hasError,
    required this.onRoomToggled,
    this.readOnly = false,
  });

  final List<RoomInfo> vacantRooms;
  final Set<String> selectedRoomIds;
  final bool isLoading;
  final bool hasError;
  final ValueChanged<String> onRoomToggled;
  final bool readOnly;

  void _showRoomDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          actionsPadding: const EdgeInsets.only(right: 12, bottom: 8),
          title: const Text(
            'Select Rooms',
            style: TextStyle(
              color: _kInputText,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: SizedBox(
            width: 360,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: vacantRooms.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: _kInputBorder),
              itemBuilder: (ctx, index) {
                final room = vacantRooms[index];
                final isSelected =
                    selectedRoomIds.contains(room.id);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Checkbox(
                    value: isSelected,
                    onChanged: (_) {
                      onRoomToggled(room.id);
                      setDialogState(() {});
                    },
                    activeColor: const Color(0xFF3B82F6),
                    side: const BorderSide(
                        color: _kInputBorder, width: 1.4),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
                  ),
                  title: Text(
                    room.roomNumber,
                    style: TextStyle(
                      color: _kInputText,
                      fontSize: 13.5,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    '${room.capacity} pax',
                    style: const TextStyle(
                        color: _kInputHint, fontSize: 11.5),
                  ),
                  onTap: () {
                    onRoomToggled(room.id);
                    setDialogState(() {});
                  },
                  dense: true,
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                'Done',
                style: TextStyle(
                  color: Color(0xFF3B82F6),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = hasError ? AppColors.accentRed : _kInputBorder;

    final hint = selectedRoomIds.isEmpty
        ? 'Select rooms'
        : '${selectedRoomIds.length} room${selectedRoomIds.length == 1 ? '' : 's'} selected';

    final selectedRooms = vacantRooms
        .where((r) => selectedRoomIds.contains(r.id))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: (isLoading || vacantRooms.isEmpty || readOnly)
              ? null
              : () => _showRoomDialog(context),
          child: Container(
            height: _kFieldHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: hasError
                  ? AppColors.accentRed.withOpacity(0.04)
                  : _kInputFill,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                if (isLoading) ...[
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child:
                        CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                  const SizedBox(width: 10),
                  const Text('Loading rooms...',
                      style: TextStyle(
                          color: _kInputHint, fontSize: 13)),
                ] else if (vacantRooms.isEmpty) ...[
                  const Icon(Icons.meeting_room_outlined,
                      color: _kInputHint, size: 14),
                  const SizedBox(width: 8),
                  const Text('No vacant rooms available',
                      style: TextStyle(
                          color: _kInputHint, fontSize: 13)),
                ] else ...[
                  Expanded(
                    child: Text(
                      hint,
                      style: TextStyle(
                        color: selectedRoomIds.isEmpty
                            ? _kInputHint
                            : _kInputText,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: hasError
                        ? AppColors.accentRed
                        : _kInputHint,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (selectedRooms.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: selectedRooms.map((room) {
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: readOnly
                      ? _kReadOnlyFill
                      : const Color(0xFF3B82F6).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: readOnly
                        ? _kInputBorder
                        : const Color(0xFF3B82F6),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      room.roomNumber,
                      style: TextStyle(
                        color: readOnly ? const Color(0xFF6B7280) : const Color(0xFF3B82F6),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!readOnly) ...[
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => onRoomToggled(room.id),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 13,
                          color: Color(0xFF3B82F6),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}

// ─── Section card ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
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
  const _FieldCol(
      {required this.label, required this.child, this.errorText});

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

// ─── Footer ───────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer({required this.onClear, required this.onSave});
  final VoidCallback onClear;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: onClear,
            style: OutlinedButton.styleFrom(
              side:
                  const BorderSide(color: AppColors.cardBorder),
              foregroundColor: AppColors.textGray,
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Clear Form',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.save_outlined, size: 16),
              label: const Text(
                'Save Changes',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: 12),
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

InputDecoration _fieldDecoration(
    {String? hint, bool hasError = false}) {
  final borderColor =
      hasError ? AppColors.accentRed : _kInputBorder;
  final focusColor =
      hasError ? AppColors.accentRed : _kInputFocused;
  return InputDecoration(
    hintText: hint,
    hintStyle:
        const TextStyle(color: _kInputHint, fontSize: 13),
    filled: true,
    fillColor: hasError
        ? AppColors.accentRed.withOpacity(0.04)
        : _kInputFill,
    isDense: true,
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
        style:
            const TextStyle(color: _kInputText, fontSize: 13),
        decoration:
            _fieldDecoration(hint: hint, hasError: hasError)
                .copyWith(
          suffixIcon: Icon(
            Icons.calendar_today_outlined,
            color: hasError
                ? AppColors.accentRed
                : _kInputHint,
            size: 14,
          ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: _kFieldHeight,
          ),
        ),
        onTap: () async {
          final current =
              DateTime.tryParse(controller.text);
          final now = DateTime.now();
          final resolvedFirst =
              firstDate ?? DateTime(2020);
          final resolvedLast = lastDate ??
              now.add(const Duration(days: 730));
          final safeInitial = (current != null &&
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
        style: const TextStyle(
            color: Color(0xFF6B7280), fontSize: 13),
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
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly
        ],
        style:
            const TextStyle(color: _kInputText, fontSize: 13),
        decoration:
            _fieldDecoration(hint: hint, hasError: hasError),
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
        style:
            const TextStyle(color: _kInputText, fontSize: 13),
        decoration:
            _fieldDecoration(hint: hint, hasError: hasError),
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
    this.displayLabels,
  });
  final String? value;
  final String hint;
  final List<String> items;
  final ValueChanged<String?>? onChanged;
  final bool hasError;
  final Map<String, String>? displayLabels;

  @override
  Widget build(BuildContext context) {
    final borderColor =
        hasError ? AppColors.accentRed : _kInputBorder;
    return Container(
      height: _kFieldHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: hasError
            ? AppColors.accentRed.withOpacity(0.04)
            : _kInputFill,
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
            style: const TextStyle(
                color: _kInputHint, fontSize: 13),
          ),
          dropdownColor: _kDropBg,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: hasError
                ? AppColors.accentRed
                : _kInputHint,
            size: 18,
          ),
          style: const TextStyle(
              color: _kInputText, fontSize: 13),
          items: items
              .map(
                (e) => DropdownMenuItem<String>(
                  value: e,
                  child: Text(
                    displayLabels?[e] ?? e,
                    style: const TextStyle(
                        color: _kInputText, fontSize: 13),
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
