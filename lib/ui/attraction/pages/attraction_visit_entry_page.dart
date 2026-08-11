// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/country_constants.dart';
import '../../../core/services/psgc_repository.dart';
import '../../../core/models/psgc_models.dart';
import '../../../api/attraction_visit_entry_api.dart';
// import '../../../router/app_routes.dart';
import '../../shared/layouts/attraction_layout.dart';

const _kInputFill = Color(0xFFF8FAFC);
const _kInputBorder = Color(0xFFD1D5DB);
const _kInputFocused = Color(0xFF3B82F6);
const _kDropBg = Color(0xFFFFFFFF);
const _kInputText = Color(0xFF111827);
const _kInputHint = Color(0xFF9CA3AF);
const _kReadOnlyFill = Color(0xFFEFF2F5);
const _kFieldHeight = 40.0;

class AttractionVisitEntryPage extends StatefulWidget {
  const AttractionVisitEntryPage({super.key});

  @override
  State<AttractionVisitEntryPage> createState() =>
      _AttractionVisitEntryPageState();
}

class _AttractionVisitEntryPageState extends State<AttractionVisitEntryPage> {
  final _api = AttractionVisitEntryApi();

  DateTime? _visitDate;
  final _guestCountCtrl = TextEditingController();
  final _maleCountCtrl = TextEditingController();
  final _femaleCountCtrl = TextEditingController();
  bool _isForeign = false;
  String? _selectedCountry;
  String? _selectedProvinceCode;
  String? _selectedCityCode;
  bool _isSaving = false;
  bool _psgcLoaded = false;

  Map<String, String?> _errors = {};

  @override
  void initState() {
    super.initState();
    _visitDate = DateTime.now();
    _loadPsgcIfAvailable();
  }

  @override
  void dispose() {
    _guestCountCtrl.dispose();
    _maleCountCtrl.dispose();
    _femaleCountCtrl.dispose();
    super.dispose();
  }

  ({String? provinceCode, String? cityCode}) _defaultOrigin() {
    final repo = PsgcRepository.instance;
    final laguna = repo.allProvinces
        .where((p) => p.name.toLowerCase() == 'laguna')
        .firstOrNull;
    final sanPablo = laguna != null
        ? repo.citiesFor(laguna.code)
            .where((c) => c.name.toLowerCase() == 'city of san pablo')
            .firstOrNull
        : null;
    return (provinceCode: laguna?.code, cityCode: sanPablo?.code);
  }

  Future<void> _loadPsgcIfAvailable() async {
    if (!PsgcRepository.instance.isLoaded) {
      await PsgcRepository.instance.load();
    }
    if (mounted) {
      final repo = PsgcRepository.instance;
      final defaults = _defaultOrigin();
      setState(() {
        _psgcLoaded = repo.isLoaded;
        _selectedProvinceCode ??= defaults.provinceCode;
        _selectedCityCode ??= defaults.cityCode;
      });
    }
  }

  int get _guestCount => int.tryParse(_guestCountCtrl.text) ?? 0;

  void _clearFieldError(String key) {
    if (_errors.containsKey(key)) {
      setState(() => _errors = Map.from(_errors)..remove(key));
    }
  }

  void _recomputeMissingSexCount() {
    final total = _guestCount;
    if (total <= 0) return;
    final male = int.tryParse(_maleCountCtrl.text);
    final female = int.tryParse(_femaleCountCtrl.text);
    if (male != null && female == null) {
      final f = total - male;
      _femaleCountCtrl.text = f >= 0 ? "$f" : _femaleCountCtrl.text;
    } else if (female != null && male == null) {
      final m = total - female;
      _maleCountCtrl.text = m >= 0 ? "$m" : _maleCountCtrl.text;
    }
  }

  void _toggleForeign(bool? value) {
    final isForeign = value ?? false;
    setState(() {
      _isForeign = isForeign;
      if (isForeign) {
        _selectedProvinceCode = null;
        _selectedCityCode = null;
        _selectedCountry = null;
      } else {
        _selectedCountry = null;
        final defaults = _defaultOrigin();
        _selectedProvinceCode = defaults.provinceCode;
        _selectedCityCode = defaults.cityCode;
      }
      _errors.remove("country");
      _errors.remove("province");
      _errors.remove("city");
    });
  }

  void _onProvinceChanged(String? value) {
    setState(() {
      _selectedProvinceCode = value;
      _selectedCityCode = null;
    });
    _clearFieldError("province");
    _clearFieldError("city");
  }

  void _onCountryChanged(String? value) {
    setState(() => _selectedCountry = value);
    _clearFieldError("country");
  }

  void _onCityChanged(String? value) {
    setState(() => _selectedCityCode = value);
    _clearFieldError("city");
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
    final defaults = _defaultOrigin();
    setState(() {
      _visitDate = DateTime.now();
      _guestCountCtrl.clear();
      _maleCountCtrl.clear();
      _femaleCountCtrl.clear();
      _isForeign = false;
      _selectedCountry = null;
      _selectedProvinceCode = defaults.provinceCode;
      _selectedCityCode = defaults.cityCode;
      _errors = {};
    });
  }

  bool _validateAndSetErrors() {
    final errors = <String, String?>{};
    bool hasError = false;

    if (_visitDate == null) {
      errors["visitDate"] = "Please select a visit date.";
      hasError = true;
    } else if (_visitDate!.isAfter(DateTime.now())) {
      errors["visitDate"] = "Visit date cannot be in the future.";
      hasError = true;
    }

    final guests = int.tryParse(_guestCountCtrl.text);
    if (guests == null || guests <= 0) {
      errors["guestCount"] = "Enter at least 1 tourist.";
      hasError = true;
    } else if (guests > 9999) {
      errors["guestCount"] = "Value seems too large.";
      hasError = true;
    }

    if (_isForeign) {
      if (_selectedCountry == null || _selectedCountry!.trim().isEmpty) {
        errors["country"] = "Please select a country.";
        hasError = true;
      }
    } else {
      if (_selectedProvinceCode == null) {
        errors["province"] = "Please select a province.";
        hasError = true;
      } else if (_selectedCityCode == null) {
        errors["city"] = "Please select a city / municipality.";
        hasError = true;
      }
    }

    setState(() => _errors = errors);
    return !hasError;
  }

  Future<void> _save() async {
    final isValid = _validateAndSetErrors();
    if (!isValid) return;

    setState(() => _isSaving = true);

    String? provinceName;
    String? cityName;

    if (!_isForeign && _psgcLoaded) {
      final repo = PsgcRepository.instance;
      if (_selectedProvinceCode != null) {
        provinceName = repo.allProvinces
                .where((p) => p.code == _selectedProvinceCode)
                .firstOrNull
                ?.name ??
            _selectedProvinceCode;
      }
      if (_selectedCityCode != null && _selectedProvinceCode != null) {
        final cities = repo.citiesFor(_selectedProvinceCode!);
        cityName = cities
                .where((c) => c.code == _selectedCityCode)
                .firstOrNull
                ?.name ??
            _selectedCityCode;
      }
    }

    final result = await _api.saveVisitEntry(
      VisitEntryData(
        visitDate: _visitDate!,
        guestCount: _guestCount,
        isForeign: _isForeign,
        country: _isForeign ? _selectedCountry : null,
        province: !_isForeign ? provinceName : null,
        cityMunicipality: !_isForeign ? cityName : null,
        maleCount: int.tryParse(_maleCountCtrl.text),
        femaleCount: int.tryParse(_femaleCountCtrl.text),
      ),
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result.success) {
      _clearForm();
      _showSnackBar("Visit entry saved successfully!");
    } else if (result.error != null) {
      _showSnackBar(
        result.error!,
        color: const Color(0xFFEF4444),
      );
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _visitDate ?? today,
      firstDate: DateTime(2020),
      lastDate: today,
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
      _visitDate = picked;
    });
    _clearFieldError("visitDate");
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    final provinces = _psgcLoaded ? PsgcRepository.instance.allProvinces : <Province>[];
    final cities = (_psgcLoaded && _selectedProvinceCode != null)
        ? PsgcRepository.instance.citiesFor(_selectedProvinceCode!)
        : <CityMunicipality>[];

    final foreignCountries =
        kCountryOptions.where((c) => c != "Philippines").toList();

    return AttractionLayout(
      title: "Visit Entry",
      selectedIndex: 1,
      onNavSelected: (_) {},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  if (_errors["submit"] != null) ...[
                    _GlobalErrorBanner(message: _errors["submit"]!),
                    const SizedBox(height: 12),
                  ],
                  _VisitInfoCard(
                    visitDate: _visitDate,
                    guestCountCtrl: _guestCountCtrl,
                    errors: _errors,
                    onPickDate: _pickDate,
                    onGuestCountChanged: (_) {
                      setState(() {});
                      _clearFieldError("guestCount");
                      _recomputeMissingSexCount();
                    },
                  ),
                  const SizedBox(height: 16),
                  _OriginCard(
                    isForeign: _isForeign,
                    selectedCountry: _selectedCountry,
                    selectedProvinceCode: _selectedProvinceCode,
                    selectedCityCode: _selectedCityCode,
                    provinces: provinces,
                    cities: cities,
                    psgcLoaded: _psgcLoaded,
                    foreignCountries: foreignCountries,
                    errors: _errors,
                    onForeignToggled: _toggleForeign,
                    onCountryChanged: _onCountryChanged,
                    onProvinceChanged: _onProvinceChanged,
                    onCityChanged: _onCityChanged,
                  ),
                  const SizedBox(height: 16),
                  _GenderCard(
                    guestCount: _guestCount,
                    maleCountCtrl: _maleCountCtrl,
                    femaleCountCtrl: _femaleCountCtrl,
                    errors: _errors,
                    onMaleChanged: (_) {
                      setState(() {});
                      _clearFieldError("maleCount");
                      _recomputeMissingSexCount();
                    },
                    onFemaleChanged: (_) {
                      setState(() {});
                      _clearFieldError("femaleCount");
                      _recomputeMissingSexCount();
                    },
                  ),
                  const SizedBox(height: 20),
                  _FormActions(
                    isSaving: _isSaving,
                    onClear: () {
                      _clearForm();
                      _showSnackBar("Form cleared.");
                    },
                    onSave: _save,
                    saveLabel: _isSaving ? "Saving..." : "Save Visit Entry",
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

// --- Page Header --------------------------------------------------------------

class _PageHeader extends StatelessWidget {
  const _PageHeader();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "New Visit Entry",
          style: TextStyle(
            color: AppColors.textWhite,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 4),
        Text(
          "Record tourist arrival data at your attraction",
          style: TextStyle(color: AppColors.textGray, fontSize: 13),
        ),
      ],
    );
  }
}

// --- Global Error Banner ------------------------------------------------------

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

// --- Visit Info Card ----------------------------------------------------------

class _VisitInfoCard extends StatelessWidget {
  const _VisitInfoCard({
    required this.visitDate,
    required this.guestCountCtrl,
    required this.errors,
    required this.onPickDate,
    required this.onGuestCountChanged,
  });

  final DateTime? visitDate;
  final TextEditingController guestCountCtrl;
  final Map<String, String?> errors;
  final VoidCallback onPickDate;
  final ValueChanged<String> onGuestCountChanged;

  String _fmt(DateTime? dt) {
    if (dt == null) return "";
    return "${dt.year.toString().padLeft(4, '0')}-"
        "${dt.month.toString().padLeft(2, '0')}-"
        "${dt.day.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: "Visit Information",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldCol(
            label: "Visit Date *",
            errorText: errors["visitDate"],
            child: _EntryDateField(
              value: _fmt(visitDate),
              hasError: errors["visitDate"] != null,
              onTap: onPickDate,
            ),
          ),
          const SizedBox(height: 14),
          _FieldCol(
            label: "Visitor/s Count *",
            errorText: errors["guestCount"],
            child: _EntryNumberField(
              controller: guestCountCtrl,
              hint: "e.g. 25",
              hasError: errors["guestCount"] != null,
              onChanged: onGuestCountChanged,
            ),
          ),
        ],
      ),
    );
  }
}

// --- Origin Card --------------------------------------------------------------

class _OriginCard extends StatelessWidget {
  const _OriginCard({
    required this.isForeign,
    this.selectedCountry,
    this.selectedProvinceCode,
    this.selectedCityCode,
    required this.provinces,
    required this.cities,
    required this.psgcLoaded,
    required this.foreignCountries,
    required this.errors,
    required this.onForeignToggled,
    required this.onCountryChanged,
    required this.onProvinceChanged,
    required this.onCityChanged,
  });

  final bool isForeign;
  final String? selectedCountry;
  final String? selectedProvinceCode;
  final String? selectedCityCode;
  final List<Province> provinces;
  final List<CityMunicipality> cities;
  final bool psgcLoaded;
  final List<String> foreignCountries;
  final Map<String, String?> errors;
  final ValueChanged<bool?> onForeignToggled;
  final ValueChanged<String?> onCountryChanged;
  final ValueChanged<String?> onProvinceChanged;
  final ValueChanged<String?> onCityChanged;

  @override
  Widget build(BuildContext context) {
    if (!psgcLoaded) {
      return _SectionCard(
        title: "Tourist Origin",
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EntryReadOnlyField(value: "Loading location data..."),
          ],
        ),
      );
    }

    return _SectionCard(
      title: "Tourist Origin",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // -- Foreign checkbox ---------------------------------------------
          GestureDetector(
            onTap: () => onForeignToggled(!isForeign),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: isForeign,
                    onChanged: onForeignToggled,
                    activeColor: const Color(0xFF3B82F6),
                    side: const BorderSide(
                        color: AppColors.textGray, width: 1.4),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  "Foreign tourist",
                  style: TextStyle(color: AppColors.textGray, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // -- Conditional fields -------------------------------------------
          if (isForeign) ...[
            _FieldCol(
              label: "Country *",
              errorText: errors["country"],
              child: _EntryDropdownField(
                value: selectedCountry,
                items: foreignCountries,
                hint: "Select country",
                hasError: errors["country"] != null,
                onChanged: onCountryChanged,
              ),
            ),
          ] else ...[
            _FieldCol(
              label: "Province *",
              errorText: errors["province"],
              child: _EntryDropdownField(
                value: selectedProvinceCode,
                items: provinces.map((p) => p.code).toList(),
                displayLabels:
                    {for (final p in provinces) p.code: p.name},
                hint: "Select province",
                hasError: errors["province"] != null,
                onChanged: onProvinceChanged,
              ),
            ),
            if (selectedProvinceCode != null) ...[
              const SizedBox(height: 12),
              _FieldCol(
                label: "City / Municipality *",
                errorText: errors["city"],
                child: _EntryDropdownField(
                  value: selectedCityCode,
                  items: cities.map((c) => c.code).toList(),
                  displayLabels:
                      {for (final c in cities) c.code: c.name},
                  hint: "Select city / municipality",
                  hasError: errors["city"] != null,
                  onChanged: onCityChanged,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// --- Gender Card --------------------------------------------------------------

class _GenderCard extends StatelessWidget {
  const _GenderCard({
    required this.guestCount,
    required this.maleCountCtrl,
    required this.femaleCountCtrl,
    required this.errors,
    required this.onMaleChanged,
    required this.onFemaleChanged,
  });

  final int guestCount;
  final TextEditingController maleCountCtrl;
  final TextEditingController femaleCountCtrl;
  final Map<String, String?> errors;
  final ValueChanged<String> onMaleChanged;
  final ValueChanged<String> onFemaleChanged;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return _SectionCard(
      title: "Gender Distribution",
      subtitle: "Optional - leave blank to auto-calculate (PSA 52.9% female / 47.1% male split)",
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FieldCol(
                  label: "Male Count (optional)",
                  errorText: errors["maleCount"],
                  child: _EntryNumberField(
                    controller: maleCountCtrl,
                    hint: "e.g. 12",
                    hasError: errors["maleCount"] != null,
                    onChanged: onMaleChanged,
                  ),
                ),
                const SizedBox(height: 12),
                _FieldCol(
                  label: "Female Count (optional)",
                  errorText: errors["femaleCount"],
                  child: _EntryNumberField(
                    controller: femaleCountCtrl,
                    hint: "e.g. 13",
                    hasError: errors["femaleCount"] != null,
                    onChanged: onFemaleChanged,
                  ),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _FieldCol(
                    label: "Male Count (optional)",
                    errorText: errors["maleCount"],
                    child: _EntryNumberField(
                      controller: maleCountCtrl,
                      hint: "e.g. 12",
                      hasError: errors["maleCount"] != null,
                      onChanged: onMaleChanged,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FieldCol(
                    label: "Female Count (optional)",
                    errorText: errors["femaleCount"],
                    child: _EntryNumberField(
                      controller: femaleCountCtrl,
                      hint: "e.g. 13",
                      hasError: errors["femaleCount"] != null,
                      onChanged: onFemaleChanged,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// --- Form Actions -------------------------------------------------------------

class _FormActions extends StatelessWidget {
  const _FormActions({
    required this.onClear,
    required this.onSave,
    required this.isSaving,
    required this.saveLabel,
  });

  final VoidCallback onClear;
  final VoidCallback onSave;
  final bool isSaving;
  final String saveLabel;

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
                Icons.save_rounded,
                size: 17,
                color: Colors.white,
              ),
        label: Text(
          saveLabel,
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
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9)),
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
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9)),
          padding: const EdgeInsets.symmetric(horizontal: 22),
        ),
        child: const Text(
          "Clear Form",
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

// --- Shared Section Card ------------------------------------------------------

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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
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
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

// --- Field Column -------------------------------------------------------------

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

// --- Inline Error -------------------------------------------------------------

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.error_outline_rounded,
            size: 12, color: AppColors.accentRed),
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

// -- Input Decoration ----------------------------------------------------------

InputDecoration _lightDecoration(
    {String? hint, bool hasError = false}) {
  final borderColor = hasError ? AppColors.accentRed : _kInputBorder;
  final focusColor = hasError ? AppColors.accentRed : _kInputFocused;
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: _kInputHint, fontSize: 13),
    filled: true,
    fillColor:
        hasError ? AppColors.accentRed.withOpacity(0.04) : _kInputFill,
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

// --- Date Field ---------------------------------------------------------------

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
          color: hasError
              ? AppColors.accentRed.withOpacity(0.04)
              : _kInputFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasError ? AppColors.accentRed : _kInputBorder,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value.isEmpty ? "yyyy-mm-dd" : value,
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

// --- Read-only Field ----------------------------------------------------------

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
        style: const TextStyle(
            color: Color(0xFF6B7280), fontSize: 13),
      ),
    );
  }
}

// --- Number Field -------------------------------------------------------------

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

// --- Dropdown Field -----------------------------------------------------------

class _EntryDropdownField extends StatelessWidget {
  const _EntryDropdownField({
    required this.value,
    required this.items,
    this.onChanged,
    this.hint = "Select option",
    this.hasError = false,
    this.displayLabels,
  });
  final String? value;
  final List<String> items;
  final ValueChanged<String?>? onChanged;
  final String hint;
  final bool hasError;
  final Map<String, String>? displayLabels;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kFieldHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: hasError
            ? AppColors.accentRed.withOpacity(0.04)
            : _kInputFill,
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
                    displayLabels?[e] ?? e,
                    style:
                        const TextStyle(color: _kInputText, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
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
