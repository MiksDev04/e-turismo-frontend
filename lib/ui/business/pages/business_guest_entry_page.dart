import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/offline_service.dart';
import '../../shared/layouts/business_layout.dart';
import '../../../api/business_guest_entry_api.dart';

// ─── Light input colours ──────────────────────────────────────────────────────

const _kInputFill = Color(0xFFF8FAFC);
const _kInputBorder = Color(0xFFD1D5DB);
const _kInputFocused = Color(0xFF3B82F6);
const _kDropBg = Color(0xFFFFFFFF);
const _kInputText = Color(0xFF111827);
const _kInputHint = Color(0xFF9CA3AF);
const _kReadOnlyFill = Color(0xFFEFF2F5);

const _kFieldHeight = 40.0;

// ─── Options ──────────────────────────────────────────────────────────────────

const _purposeOptions = [
  'Leisure',
  'Business',
  'Education',
  'Medical',
  'Religious',
  'Others',
];

const _transportOptions = [
  'Private Car',
  'Bus',
  'Van',
  'Motorcycle',
  'Tricycle',
  'Others',
];

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

const _regionOptions = [
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

const _nationalityOptions = ['Filipino', 'Foreign'];

const _sexOptions = ['Male', 'Female'];

// ─── Guest Entry Page ─────────────────────────────────────────────────────────

class BusinessGuestEntryPage extends StatefulWidget {
  const BusinessGuestEntryPage({super.key});

  @override
  State<BusinessGuestEntryPage> createState() => _BusinessGuestEntryPageState();
}

class _BusinessGuestEntryPageState extends State<BusinessGuestEntryPage> {
  final _api = BusinessGuestEntryApi();
  String? _businessId;

  DateTime? _checkIn;
  DateTime? _checkOut;
  final _totalGuestsCtrl = TextEditingController();
  String? _purpose;
  String? _transport;
  final _purposeOtherCtrl = TextEditingController();
  final _transportOtherCtrl = TextEditingController();
  bool _showPurposeOther = false;
  bool _showTransportOther = false;
  bool _isSaving = false;

  // ── Room selection ──────────────────────────────────────────────────────────
  List<RoomInfo> _vacantRooms = [];
  final Set<String> _selectedRoomIds = {};
  bool _isLoadingRooms = false;

  // ── Lead guest fields ───────────────────────────────────────────────────────
  String? _leadCountry;
  String? _leadMunicipality;
  String? _leadProvince;
  String? _leadNationality;
  String? _leadRegion;
  bool _leadIsOverseas = false;
  DateTime? _leadBirthdate;
  String? _leadSex;

  Map<String, String?> _errors = {};

  // ── Connectivity state ────────────────────────────────────────────────────
  bool _isOffline = false;
  StreamSubscription<bool>? _connectivitySub;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _isOffline = !ConnectivityService.instance.isOnline;
    _subscribeToConnectivity();
    _loadBusinessId();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _totalGuestsCtrl.dispose();
    _purposeOtherCtrl.dispose();
    _transportOtherCtrl.dispose();
    super.dispose();
  }

  // ── Connectivity subscription ─────────────────────────────────────────────

  void _subscribeToConnectivity() {
    _connectivitySub = ConnectivityService.instance.onConnectivityChanged.listen(
      (isOnline) {
        if (!mounted) return;

        if (isOnline && _isOffline) {
          setState(() {
            _isOffline = false;
          });
          _loadBusinessId();
          SyncService.instance.sync();
        } else if (!isOnline && !_isOffline) {
          setState(() {
            _isOffline = true;
          });
        }
      },
    );
  }

  // ── Business ID loading ───────────────────────────────────────────────────

  Future<void> _loadBusinessId() async {
    final id = await _api.fetchBusinessId();
    if (mounted) {
      setState(() => _businessId = id);
      if (id != null) _loadVacantRooms(id);
    }
  }

  // ── Load vacant rooms ──────────────────────────────────────────────────────

  Future<void> _loadVacantRooms(String businessId) async {
    setState(() => _isLoadingRooms = true);
    try {
      final rooms = await _api.fetchVacantRooms(businessId);
      if (mounted) {
        setState(() {
          _vacantRooms = rooms;
          _isLoadingRooms = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingRooms = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  int get _nightsCount {
    if (_checkIn == null || _checkOut == null) return 0;
    return _checkOut!.difference(_checkIn!).inDays.clamp(0, 999);
  }

  int get _totalGuests => int.tryParse(_totalGuestsCtrl.text) ?? 0;

  bool get _isPhilippines =>
      !_leadIsOverseas && _leadCountry == 'Philippines';

  void _clearFieldError(String key) {
    if (_errors.containsKey(key)) {
      setState(() => _errors = Map.from(_errors)..remove(key));
    }
  }

  void _showSnackBar(String message, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color ?? AppColors.primaryCyan,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _clearForm() {
    setState(() {
      _checkIn = null;
      _checkOut = null;
      _totalGuestsCtrl.clear();
      _purpose = null;
      _transport = null;
      _purposeOtherCtrl.clear();
      _transportOtherCtrl.clear();
      _showPurposeOther = false;
      _showTransportOther = false;
      _selectedRoomIds.clear();
      _leadCountry = null;
      _leadMunicipality = null;
      _leadProvince = null;
      _leadNationality = null;
      _leadRegion = null;
      _leadIsOverseas = false;
      _leadBirthdate = null;
      _leadSex = null;
      _errors = {};
    });
  }

  bool _validateAndSetErrors() {
    final errors = <String, String?>{};
    bool hasError = false;

    if (_checkIn == null) {
      errors['checkIn'] = 'Please select a check-in date.';
      hasError = true;
    } else if (_checkIn!.isAfter(DateTime.now())) {
      errors['checkIn'] = 'Check-in date cannot be in the future.';
      hasError = true;
    }

    if (_checkOut == null) {
      errors['checkOut'] = 'Please select a check-out date.';
      hasError = true;
    } else if (_checkIn != null && _checkOut!.isBefore(_checkIn!)) {
      errors['checkOut'] =
          'Check-out must be the same day as check-in or later.';
      hasError = true;
    }

    final guests = int.tryParse(_totalGuestsCtrl.text);
    if (guests == null || guests <= 0) {
      errors['totalGuests'] = 'Enter at least 1 guest.';
      hasError = true;
    } else if (guests > 9999) {
      errors['totalGuests'] = 'Value seems too large.';
      hasError = true;
    }

    if (_selectedRoomIds.isEmpty) {
      errors['rooms'] = 'Please select at least one room.';
      hasError = true;
    }

    if (_purpose == null) {
      errors['purpose'] = 'Please select a purpose of visit.';
      hasError = true;
    } else if (_purpose == 'Others' && _purposeOtherCtrl.text.trim().isEmpty) {
      errors['purposeOther'] = 'Please specify the purpose.';
      hasError = true;
    }

    if (_transport == null) {
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
      } else if (_leadCountry == 'Philippines') {
        if (_leadNationality == null) {
          errors['leadNationality'] = 'Please select nationality.';
          hasError = true;
        }
      }
    }

    if (_leadBirthdate == null) {
      errors['leadBirthdate'] = 'Please select birthdate.';
      hasError = true;
    }

    if (_leadSex == null) {
      errors['leadSex'] = 'Please select sex.';
      hasError = true;
    }

    setState(() => _errors = errors);
    return !hasError;
  }

  Future<void> _save() async {
    final isValid = _validateAndSetErrors();
    if (!isValid) return;

    if (_businessId == null) {
      setState(
        () => _errors = {
          'businessId': 'Business account not found. Please try again.',
        },
      );
      return;
    }

    setState(() => _isSaving = true);

    final purposeValue = _purpose == 'Others'
        ? _purposeOtherCtrl.text.trim()
        : _purpose!;
    final transportValue = _transport == 'Others'
        ? _transportOtherCtrl.text.trim()
        : _transport!;

    final result = await _api.saveGuestEntry(
      GuestEntryData(
        businessId: _businessId!,
        checkIn: _checkIn!,
        checkOut: _checkOut!,
        totalGuests: _totalGuests,
        roomIds: _selectedRoomIds.toList(),
        purposeOfVisit: purposeValue,
        transportationMode: transportValue,
        leadCountry: !_leadIsOverseas ? _leadCountry : null,
        leadMunicipality: _leadMunicipality,
        leadProvince: _leadProvince,
        leadNationality: _isPhilippines ? _leadNationality : null,
        leadPhilippinesRegion: _isPhilippines ? _leadRegion : null,
        leadIsOverseas: _leadIsOverseas,
        leadBirthdate: _leadBirthdate,
        leadSex: _leadSex,
      ),
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result.success) {
      _clearForm();
      if (result.syncedToCloud) {
        _showSnackBar('Guest entry saved successfully!');
      } else {
        _showSnackBar(
          ConnectivityService.instance.isOnline
              ? 'Entry saved — will sync in the background.'
              : 'Entry saved offline — will sync when you\'re back online.',
          color: const Color(0xFFF59E0B),
        );
      }
    }
  }

  Future<void> _pickDate(BuildContext context, bool isCheckIn) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstDate = isCheckIn
        ? DateTime(2020)
        : (_checkIn != null ? _checkIn! : today);
    final lastDate = isCheckIn ? today : today.add(const Duration(days: 730));
    final initialDate = isCheckIn
        ? today
        : (_checkIn != null ? _checkIn! : today);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
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
    if (picked == null) return;
    setState(() {
      if (isCheckIn) {
        _checkIn = picked;
        if (_checkOut != null && _checkOut!.isBefore(picked)) _checkOut = null;
        _clearFieldError('checkIn');
      } else {
        _checkOut = picked;
        _clearFieldError('checkOut');
      }
    });
  }

  Future<void> _pickLeadBirthdate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _leadBirthdate ?? DateTime(1990),
      firstDate: DateTime(1900),
      lastDate: now,
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
    if (picked == null) return;
    setState(() {
      _leadBirthdate = picked;
    });
    _clearFieldError('leadBirthdate');
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return BusinessLayout(
      title: 'Guest Entry',
      selectedIndex: 1,
      onNavSelected: (_) {},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isOffline) const _OfflineBanner(),

          Expanded(
            child: SingleChildScrollView(
              padding: isMobile
                  ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                  : const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _PageHeader(),
                  const SizedBox(height: 20),

                  if (_errors['submit'] != null) ...[
                    _GlobalErrorBanner(message: _errors['submit']!),
                    const SizedBox(height: 12),
                  ],
                  if (_errors['businessId'] != null) ...[
                    _GlobalErrorBanner(message: _errors['businessId']!),
                    const SizedBox(height: 12),
                  ],

                  _StayInfoCard(
                    checkIn: _checkIn,
                    checkOut: _checkOut,
                    nights: _nightsCount,
                    totalGuestsCtrl: _totalGuestsCtrl,
                    purpose: _purpose,
                    transport: _transport,
                    showPurposeOther: _showPurposeOther,
                    showTransportOther: _showTransportOther,
                    purposeOtherCtrl: _purposeOtherCtrl,
                    transportOtherCtrl: _transportOtherCtrl,
                    vacantRooms: _vacantRooms,
                    selectedRoomIds: _selectedRoomIds,
                    isLoadingRooms: _isLoadingRooms,
                    errors: _errors,
                    onPickCheckIn: () => _pickDate(context, true),
                    onPickCheckOut: () => _pickDate(context, false),
                    onPurposeChanged: (v) {
                      setState(() {
                        _purpose = v;
                        _showPurposeOther = v == 'Others';
                        if (!_showPurposeOther) _purposeOtherCtrl.clear();
                      });
                      _clearFieldError('purpose');
                      _clearFieldError('purposeOther');
                    },
                    onTransportChanged: (v) {
                      setState(() {
                        _transport = v;
                        _showTransportOther = v == 'Others';
                        if (!_showTransportOther) _transportOtherCtrl.clear();
                      });
                      _clearFieldError('transport');
                      _clearFieldError('transportOther');
                    },
                    onGuestsChanged: (_) {
                      setState(() {});
                      _clearFieldError('totalGuests');
                    },
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
                    onPurposeOtherChanged: (_) =>
                        _clearFieldError('purposeOther'),
                    onTransportOtherChanged: (_) =>
                        _clearFieldError('transportOther'),
                  ),
                  const SizedBox(height: 16),

                  _LeadGuestCard(
                    leadCountry: _leadCountry,
                    leadMunicipality: _leadMunicipality,
                    leadProvince: _leadProvince,
                    leadNationality: _leadNationality,
                    leadRegion: _leadRegion,
                    leadIsOverseas: _leadIsOverseas,
                    leadBirthdate: _leadBirthdate,
                    leadSex: _leadSex,
                    isPhilippines: _isPhilippines,
                    errors: _errors,
                    onCountryChanged: (v) {
                      setState(() {
                        _leadCountry = v;
                        if (v != 'Philippines') {
                          _leadNationality = null;
                          _leadRegion = null;
                        }
                      });
                      _clearFieldError('leadCountry');
                    },
                    onMunicipalityChanged: (v) {
                      _leadMunicipality = v;
                      _clearFieldError('leadMunicipality');
                    },
                    onProvinceChanged: (v) {
                      _leadProvince = v;
                      _clearFieldError('leadProvince');
                    },
                    onNationalityChanged: (v) {
                      setState(() => _leadNationality = v);
                      _clearFieldError('leadNationality');
                    },
                    onRegionChanged: (v) {
                      setState(() => _leadRegion = v);
                    },
                    onOverseasToggled: (v) {
                      setState(() {
                        _leadIsOverseas = v;
                        if (v) {
                          _leadCountry = null;
                          _leadNationality = null;
                          _leadRegion = null;
                        }
                      });
                    },
                    onBirthdateTap: _pickLeadBirthdate,
                    onSexChanged: (v) {
                      setState(() => _leadSex = v);
                      _clearFieldError('leadSex');
                    },
                  ),
                  const SizedBox(height: 20),

                  _FormActions(
                    isSaving: _isSaving,
                    onClear: () {
                      _clearForm();
                      _showSnackBar('Form cleared.');
                    },
                    onSave: _save,
                  ),
                ],
              ),
            ),
          ),
        ],
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
      child: const Row(
        children: [
          Icon(Icons.wifi_off_rounded, color: Color(0xFF8A9BB5), size: 14),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'You\'re offline — entries will be saved locally and synced later.',
              style: TextStyle(color: Color(0xFF8A9BB5), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Page Header ──────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  const _PageHeader();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'New Guest Entry',
          style: TextStyle(
            color: AppColors.textWhite,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Record tourist demographic data',
          style: TextStyle(color: AppColors.textGray, fontSize: 13),
        ),
      ],
    );
  }
}

// ─── Global Error Banner ──────────────────────────────────────────────────────

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

// ─── Stay Info Card ───────────────────────────────────────────────────────────

class _StayInfoCard extends StatelessWidget {
  const _StayInfoCard({
    required this.checkIn,
    required this.checkOut,
    required this.nights,
    required this.totalGuestsCtrl,
    required this.purpose,
    required this.transport,
    required this.showPurposeOther,
    required this.showTransportOther,
    required this.purposeOtherCtrl,
    required this.transportOtherCtrl,
    required this.vacantRooms,
    required this.selectedRoomIds,
    required this.isLoadingRooms,
    required this.errors,
    required this.onPickCheckIn,
    required this.onPickCheckOut,
    required this.onPurposeChanged,
    required this.onTransportChanged,
    required this.onGuestsChanged,
    required this.onRoomToggled,
    required this.onPurposeOtherChanged,
    required this.onTransportOtherChanged,
  });

  final DateTime? checkIn;
  final DateTime? checkOut;
  final int nights;
  final TextEditingController totalGuestsCtrl;
  final String? purpose;
  final String? transport;
  final bool showPurposeOther;
  final bool showTransportOther;
  final TextEditingController purposeOtherCtrl;
  final TextEditingController transportOtherCtrl;
  final List<RoomInfo> vacantRooms;
  final Set<String> selectedRoomIds;
  final bool isLoadingRooms;
  final Map<String, String?> errors;
  final VoidCallback onPickCheckIn;
  final VoidCallback onPickCheckOut;
  final ValueChanged<String?> onPurposeChanged;
  final ValueChanged<String?> onTransportChanged;
  final ValueChanged<String> onGuestsChanged;
  final ValueChanged<String> onRoomToggled;
  final ValueChanged<String> onPurposeOtherChanged;
  final ValueChanged<String> onTransportOtherChanged;

  String _fmt(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final nightsLabel = '$nights night${nights == 1 ? '' : 's'}';

    return _SectionCard(
      title: 'Stay Information',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobile) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _FieldCol(
                    label: 'Check-in Date *',
                    errorText: errors['checkIn'],
                    child: _EntryDateField(
                      value: _fmt(checkIn),
                      hasError: errors['checkIn'] != null,
                      onTap: onPickCheckIn,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FieldCol(
                    label: 'Check-out Date *',
                    errorText: errors['checkOut'],
                    child: _EntryDateField(
                      value: _fmt(checkOut),
                      hasError: errors['checkOut'] != null,
                      onTap: onPickCheckOut,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _FieldCol(
              label: 'Length of Stay',
              child: _EntryReadOnlyField(value: nightsLabel),
            ),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _FieldCol(
                    label: 'Check-in Date *',
                    errorText: errors['checkIn'],
                    child: _EntryDateField(
                      value: _fmt(checkIn),
                      hasError: errors['checkIn'] != null,
                      onTap: onPickCheckIn,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FieldCol(
                    label: 'Check-out Date *',
                    errorText: errors['checkOut'],
                    child: _EntryDateField(
                      value: _fmt(checkOut),
                      hasError: errors['checkOut'] != null,
                      onTap: onPickCheckOut,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FieldCol(
                    label: 'Length of Stay',
                    child: _EntryReadOnlyField(value: nightsLabel),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),

          _FieldCol(
            label: 'Total Guests *',
            errorText: errors['totalGuests'],
            child: _EntryNumberField(
              controller: totalGuestsCtrl,
              hint: 'e.g. 10',
              hasError: errors['totalGuests'] != null,
              onChanged: onGuestsChanged,
            ),
          ),
          const SizedBox(height: 14),

          // ── Room Selection ─────────────────────────────────────────────
          _FieldCol(
            label: 'Rooms *',
            errorText: errors['rooms'],
            child: _RoomSelector(
              vacantRooms: vacantRooms,
              selectedRoomIds: selectedRoomIds,
              isLoading: isLoadingRooms,
              hasError: errors['rooms'] != null,
              onRoomToggled: onRoomToggled,
            ),
          ),
          const SizedBox(height: 14),

          if (isMobile) ...[
            _FieldCol(
              label: 'Purpose of Visit *',
              errorText: errors['purpose'],
              child: _EntryDropdownField(
                value: purpose,
                items: _purposeOptions,
                hint: 'Select purpose',
                hasError: errors['purpose'] != null,
                onChanged: onPurposeChanged,
              ),
            ),
            if (showPurposeOther) ...[
              const SizedBox(height: 10),
              _FieldCol(
                label: 'Please specify *',
                errorText: errors['purposeOther'],
                child: _EntryTextField(
                  controller: purposeOtherCtrl,
                  hint: 'Specify purpose',
                  hasError: errors['purposeOther'] != null,
                  onChanged: onPurposeOtherChanged,
                ),
              ),
            ],
            const SizedBox(height: 14),
            _FieldCol(
              label: 'Mode of Transportation *',
              errorText: errors['transport'],
              child: _EntryDropdownField(
                value: transport,
                items: _transportOptions,
                hint: 'Select transportation',
                hasError: errors['transport'] != null,
                onChanged: onTransportChanged,
              ),
            ),
            if (showTransportOther) ...[
              const SizedBox(height: 10),
              _FieldCol(
                label: 'Please specify *',
                errorText: errors['transportOther'],
                child: _EntryTextField(
                  controller: transportOtherCtrl,
                  hint: 'Specify transportation',
                  hasError: errors['transportOther'] != null,
                  onChanged: onTransportOtherChanged,
                ),
              ),
            ],
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldCol(
                        label: 'Purpose of Visit *',
                        errorText: errors['purpose'],
                        child: _EntryDropdownField(
                          value: purpose,
                          items: _purposeOptions,
                          hint: 'Select purpose',
                          hasError: errors['purpose'] != null,
                          onChanged: onPurposeChanged,
                        ),
                      ),
                      if (showPurposeOther) ...[
                        const SizedBox(height: 10),
                        _FieldCol(
                          label: 'Please specify *',
                          errorText: errors['purposeOther'],
                          child: _EntryTextField(
                            controller: purposeOtherCtrl,
                            hint: 'Specify purpose',
                            hasError: errors['purposeOther'] != null,
                            onChanged: onPurposeOtherChanged,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldCol(
                        label: 'Mode of Transportation *',
                        errorText: errors['transport'],
                        child: _EntryDropdownField(
                          value: transport,
                          items: _transportOptions,
                          hint: 'Select transportation',
                          hasError: errors['transport'] != null,
                          onChanged: onTransportChanged,
                        ),
                      ),
                      if (showTransportOther) ...[
                        const SizedBox(height: 10),
                        _FieldCol(
                          label: 'Please specify *',
                          errorText: errors['transportOther'],
                          child: _EntryTextField(
                            controller: transportOtherCtrl,
                            hint: 'Specify transportation',
                            hasError: errors['transportOther'] != null,
                            onChanged: onTransportOtherChanged,
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
    );
  }
}

// ─── Room Selector (multi-select dropdown + dialog) ──────────────────────────

class _RoomSelector extends StatelessWidget {
  const _RoomSelector({
    required this.vacantRooms,
    required this.selectedRoomIds,
    required this.isLoading,
    required this.hasError,
    required this.onRoomToggled,
  });

  final List<RoomInfo> vacantRooms;
  final Set<String> selectedRoomIds;
  final bool isLoading;
  final bool hasError;
  final ValueChanged<String> onRoomToggled;

  void _showRoomDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text(
            'Select Rooms',
            style: TextStyle(
              color: _kInputText,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: vacantRooms.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: _kInputBorder),
              itemBuilder: (ctx, index) {
                final room = vacantRooms[index];
                final isSelected = selectedRoomIds.contains(room.id);
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: Checkbox(
                    value: isSelected,
                    onChanged: (_) {
                      onRoomToggled(room.id);
                      setDialogState(() {});
                    },
                    activeColor: const Color(0xFF3B82F6),
                    side: const BorderSide(color: _kInputBorder, width: 1.4),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  title: Text(
                    room.roomNumber,
                    style: TextStyle(
                      color: _kInputText,
                      fontSize: 13.5,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    '${room.capacity} pax',
                    style:
                        const TextStyle(color: _kInputHint, fontSize: 11.5),
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
          onTap: (isLoading || vacantRooms.isEmpty)
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
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                  const SizedBox(width: 10),
                  const Text('Loading rooms...',
                      style: TextStyle(color: _kInputHint, fontSize: 13)),
                ] else if (vacantRooms.isEmpty) ...[
                  const Icon(Icons.meeting_room_outlined,
                      color: _kInputHint, size: 14),
                  const SizedBox(width: 8),
                  const Text('No vacant rooms available',
                      style: TextStyle(color: _kInputHint, fontSize: 13)),
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
                    color: hasError ? AppColors.accentRed : _kInputHint,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: const Color(0xFF3B82F6),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      room.roomNumber,
                      style: const TextStyle(
                        color: Color(0xFF3B82F6),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}

// ─── Lead Guest Card ──────────────────────────────────────────────────────────

class _LeadGuestCard extends StatelessWidget {
  const _LeadGuestCard({
    required this.leadCountry,
    required this.leadMunicipality,
    required this.leadProvince,
    required this.leadNationality,
    required this.leadRegion,
    required this.leadIsOverseas,
    required this.leadBirthdate,
    required this.leadSex,
    required this.isPhilippines,
    required this.errors,
    required this.onCountryChanged,
    required this.onMunicipalityChanged,
    required this.onProvinceChanged,
    required this.onNationalityChanged,
    required this.onRegionChanged,
    required this.onOverseasToggled,
    required this.onBirthdateTap,
    required this.onSexChanged,
  });

  final String? leadCountry;
  final String? leadMunicipality;
  final String? leadProvince;
  final String? leadNationality;
  final String? leadRegion;
  final bool leadIsOverseas;
  final DateTime? leadBirthdate;
  final String? leadSex;
  final bool isPhilippines;
  final Map<String, String?> errors;
  final ValueChanged<String?> onCountryChanged;
  final ValueChanged<String> onMunicipalityChanged;
  final ValueChanged<String> onProvinceChanged;
  final ValueChanged<String?> onNationalityChanged;
  final ValueChanged<String?> onRegionChanged;
  final ValueChanged<bool> onOverseasToggled;
  final VoidCallback onBirthdateTap;
  final ValueChanged<String?> onSexChanged;

  String _fmtBirthdate(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

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
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Overseas Filipino (Balikbayan/OFW)',
                  style: TextStyle(color: AppColors.textGray, fontSize: 12),
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
              child: _EntryDropdownField(
                value: leadIsOverseas ? null : leadCountry,
                items: _countryOptions,
                hint: leadIsOverseas ? 'N/A (Overseas)' : 'Select country',
                hasError: errors['leadCountry'] != null,
                onChanged: leadIsOverseas ? null : onCountryChanged,
              ),
            ),
            if (isPhilippines) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _FieldCol(
                      label: 'Nationality *',
                      errorText: errors['leadNationality'],
                      child: _EntryDropdownField(
                        value: leadNationality,
                        items: _nationalityOptions,
                        hint: 'Select',
                        hasError: errors['leadNationality'] != null,
                        onChanged: onNationalityChanged,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FieldCol(
                      label: 'Region',
                      child: _EntryDropdownField(
                        value: leadRegion,
                        items: _regionOptions,
                        hint: 'Select region',
                        onChanged: onRegionChanged,
                      ),
                    ),
                  ),
                ],
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
                    child: _EntryDropdownField(
                      value: leadIsOverseas ? null : leadCountry,
                      items: _countryOptions,
                      hint: leadIsOverseas ? 'N/A (Overseas)' : 'Select country',
                      hasError: errors['leadCountry'] != null,
                      onChanged: leadIsOverseas ? null : onCountryChanged,
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
                      child: _EntryDropdownField(
                        value: leadNationality,
                        items: _nationalityOptions,
                        hint: 'Select',
                        hasError: errors['leadNationality'] != null,
                        onChanged: onNationalityChanged,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: _FieldCol(
                      label: 'Region',
                      child: _EntryDropdownField(
                        value: leadRegion,
                        items: _regionOptions,
                        hint: 'Select region',
                        onChanged: onRegionChanged,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 14),

          // ── Municipality & Province ────────────────────────────────────
          if (isMobile) ...[
            _FieldCol(
              label: 'City / Municipality',
              child: _EntryTextField(
                controller: TextEditingController(text: leadMunicipality ?? ''),
                hint: 'City/Municipality',
                onChanged: onMunicipalityChanged,
              ),
            ),
            const SizedBox(height: 12),
            _FieldCol(
              label: 'Province',
              child: _EntryTextField(
                controller: TextEditingController(text: leadProvince ?? ''),
                hint: 'Province',
                onChanged: onProvinceChanged,
              ),
            ),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _FieldCol(
                    label: 'City / Municipality',
                    child: _EntryTextField(
                      controller: TextEditingController(text: leadMunicipality ?? ''),
                      hint: 'City/Municipality',
                      onChanged: onMunicipalityChanged,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FieldCol(
                    label: 'Province',
                    child: _EntryTextField(
                      controller: TextEditingController(text: leadProvince ?? ''),
                      hint: 'Province',
                      onChanged: onProvinceChanged,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),

          // ── Birthdate & Sex ────────────────────────────────────────────
          if (isMobile) ...[
            _FieldCol(
              label: 'Birthdate *',
              errorText: errors['leadBirthdate'],
              child: GestureDetector(
                onTap: onBirthdateTap,
                child: _EntryDateField(
                  value: _fmtBirthdate(leadBirthdate),
                  hasError: errors['leadBirthdate'] != null,
                  onTap: onBirthdateTap,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _FieldCol(
              label: 'Sex *',
              errorText: errors['leadSex'],
              child: _EntryDropdownField(
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
                    child: GestureDetector(
                      onTap: onBirthdateTap,
                      child: _EntryDateField(
                        value: _fmtBirthdate(leadBirthdate),
                        hasError: errors['leadBirthdate'] != null,
                        onTap: onBirthdateTap,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FieldCol(
                    label: 'Sex *',
                    errorText: errors['leadSex'],
                    child: _EntryDropdownField(
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

// ─── Form Actions ─────────────────────────────────────────────────────────────

class _FormActions extends StatelessWidget {
  const _FormActions({
    required this.onClear,
    required this.onSave,
    required this.isSaving,
  });

  final VoidCallback onClear;
  final VoidCallback onSave;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    final saveBtn = SizedBox(
      height: 46,
      child: ElevatedButton.icon(
        onPressed: isSaving ? null : onSave,
        icon: isSaving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(
                Icons.person_add_rounded,
                size: 17,
                color: Colors.white,
              ),
        label: Text(
          isSaving ? 'Saving...' : 'Save Guest Entry',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF3B82F6),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
    );

    final clearBtn = SizedBox(
      height: 46,
      child: OutlinedButton(
        onPressed: isSaving ? null : onClear,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.cardBorder),
          foregroundColor: AppColors.textGray,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          padding: const EdgeInsets.symmetric(horizontal: 22),
        ),
        child: const Text(
          'Clear Form',
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ),
    );

    if (isMobile) {
      return Column(
        children: [
          SizedBox(width: double.infinity, child: saveBtn),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: clearBtn),
        ],
      );
    }

    return Row(
      children: [
        clearBtn,
        const SizedBox(width: 14),
        Expanded(child: saveBtn),
      ],
    );
  }
}

// ─── Shared Section Card ──────────────────────────────────────────────────────

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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
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
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

// ─── Field Column ─────────────────────────────────────────────────────────────

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

// ─── Inline Error ─────────────────────────────────────────────────────────────

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.error_outline_rounded, size: 12, color: AppColors.accentRed),
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

// ─────────────────────────────────────────────────────────────────────────────
//  INPUT WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

InputDecoration _lightDecoration({String? hint, bool hasError = false}) {
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

class _EntryDateField extends StatelessWidget {
  const _EntryDateField({
    required this.value,
    required this.onTap,
    this.hasError = false,
  });
  final String value;
  final VoidCallback onTap;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: _kFieldHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: hasError ? AppColors.accentRed.withOpacity(0.04) : _kInputFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasError ? AppColors.accentRed : _kInputBorder,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value.isEmpty ? 'yyyy-mm-dd' : value,
                style: TextStyle(
                  color: value.isEmpty ? _kInputHint : _kInputText,
                  fontSize: 13,
                ),
              ),
            ),
            Icon(
              Icons.calendar_today_outlined,
              color: hasError ? AppColors.accentRed : _kInputHint,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryReadOnlyField extends StatelessWidget {
  const _EntryReadOnlyField({required this.value});
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

class _EntryNumberField extends StatelessWidget {
  const _EntryNumberField({
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
        onChanged: onChanged,
        style: const TextStyle(color: _kInputText, fontSize: 13),
        decoration: _lightDecoration(hint: hint, hasError: hasError),
      ),
    );
  }
}

class _EntryTextField extends StatelessWidget {
  const _EntryTextField({
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
        onChanged: onChanged,
        style: const TextStyle(color: _kInputText, fontSize: 13),
        decoration: _lightDecoration(hint: hint, hasError: hasError),
      ),
    );
  }
}

class _EntryDropdownField extends StatelessWidget {
  const _EntryDropdownField({
    required this.value,
    required this.items,
    this.onChanged,
    this.hint = 'Select option',
    this.hasError = false,
  });
  final String? value;
  final List<String> items;
  final ValueChanged<String?>? onChanged;
  final String hint;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kFieldHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: hasError ? AppColors.accentRed.withOpacity(0.04) : _kInputFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasError ? AppColors.accentRed : _kInputBorder,
        ),
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
            size: 18,
            color: hasError ? AppColors.accentRed : _kInputHint,
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
