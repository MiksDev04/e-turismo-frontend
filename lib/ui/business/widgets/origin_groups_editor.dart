import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/country_constants.dart';
import '../../../core/models/psgc_models.dart';
import '../../../core/services/psgc_repository.dart';
import '../../../models/origin_group.dart';
import 'entry_form_widgets.dart';

// ─── Origin Groups Editor ────────────────────────────────────────────────────

class OriginGroupsEditor extends StatefulWidget {
  const OriginGroupsEditor({
    super.key,
    required this.groups,
    required this.onGroupsChanged,
    required this.totalGuests,
    this.leadProvinceCode,
    this.leadCityCode,
    this.leadCountry,
    this.maleGuestsCtrl,
    this.femaleGuestsCtrl,
  });

  final List<OriginGroup> groups;
  final ValueChanged<List<OriginGroup>> onGroupsChanged;
  final int totalGuests;
  final String? leadProvinceCode;
  final String? leadCityCode;
  final String? leadCountry;
  final TextEditingController? maleGuestsCtrl;
  final TextEditingController? femaleGuestsCtrl;

  @override
  State<OriginGroupsEditor> createState() => _OriginGroupsEditorState();
}

class _OriginGroupsEditorState extends State<OriginGroupsEditor> {
  List<OriginGroup> _localGroups = [];

  @override
  void initState() {
    super.initState();
    _localGroups = List.of(widget.groups);
  }

  @override
  void didUpdateWidget(covariant OriginGroupsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groups != widget.groups) {
      _localGroups = List.of(widget.groups);
    }
  }

  int get _breakdownTotal =>
      _localGroups.fold<int>(0, (sum, g) => sum + g.total);

  bool get _hasMismatch =>
      _localGroups.isNotEmpty && _breakdownTotal != widget.totalGuests;

  void _addGroup() {
    String? province;
    String? city;
    int male = 0;
    int female = 0;

    if (_localGroups.isEmpty) {
      // First group: inherit from lead guest
      province = widget.leadProvinceCode != null
          ? _resolveProvinceName(widget.leadProvinceCode!)
          : null;
      city = widget.leadCityCode != null
          ? _resolveCityName(widget.leadProvinceCode, widget.leadCityCode!)
          : null;
      male = int.tryParse(widget.maleGuestsCtrl?.text ?? '') ?? 0;
      female = int.tryParse(widget.femaleGuestsCtrl?.text ?? '') ?? 0;
    }

    final newGroup = OriginGroup(
      country: _localGroups.isEmpty ? (widget.leadCountry ?? 'Philippines') : null,
      province: province,
      cityMunicipality: city,
      maleCount: male,
      femaleCount: female,
    );

    setState(() => _localGroups = [..._localGroups, newGroup]);
    widget.onGroupsChanged(_localGroups);
  }

  void _removeGroup(int index) {
    setState(() => _localGroups = [
          for (int i = 0; i < _localGroups.length; i++)
            if (i != index) _localGroups[i],
        ]);
    widget.onGroupsChanged(_localGroups);
  }

  void _updateGroup(int index, OriginGroup updated) {
    setState(() => _localGroups = [
          for (int i = 0; i < _localGroups.length; i++)
            if (i == index) updated else _localGroups[i],
        ]);
    widget.onGroupsChanged(_localGroups);
  }

  String? _resolveProvinceName(String code) {
    for (final p in PsgcRepository.instance.allProvinces) {
      if (p.code == code) return p.name;
    }
    return null;
  }

  String? _resolveCityName(String? provinceCode, String code) {
    if (provinceCode == null) return null;
    for (final c in PsgcRepository.instance.citiesFor(provinceCode)) {
      if (c.code == code) return c.name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Origin Groups',
      subtitle: 'Optional \u2014 break down guests by origin',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_localGroups.isNotEmpty) ...[
            for (int i = 0; i < _localGroups.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i < _localGroups.length - 1 ? 14 : 0),
                child: _GroupCard(
                  index: i,
                  group: _localGroups[i],
                  onChanged: (g) => _updateGroup(i, g),
                  onRemove: () => _removeGroup(i),
                ),
              ),
            const SizedBox(height: 12),
            _SummaryLine(
              breakdownTotal: _breakdownTotal,
              totalGuests: widget.totalGuests,
              hasMismatch: _hasMismatch,
            ),
            const SizedBox(height: 12),
          ],
          _AddGroupButton(onTap: _addGroup),
        ],
      ),
    );
  }
}

// ─── Group Card ──────────────────────────────────────────────────────────────

class _GroupCard extends StatefulWidget {
  const _GroupCard({
    required this.index,
    required this.group,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final OriginGroup group;
  final ValueChanged<OriginGroup> onChanged;
  final VoidCallback onRemove;

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  late String? _country;
  late bool _isOverseas;
  late String? _provinceCode;
  late String? _cityCode;
  late final TextEditingController _maleCtrl;
  late final TextEditingController _femaleCtrl;

  List<Province> get _provinces => PsgcRepository.instance.allProvinces;
  List<CityMunicipality> get _cities =>
      _provinceCode != null ? PsgcRepository.instance.citiesFor(_provinceCode!) : [];

  bool get _showProvinceCity =>
      !_isOverseas && _country == 'Philippines';

  @override
  void initState() {
    super.initState();
    _country = widget.group.country;
    _isOverseas = widget.group.isOverseas;
    _provinceCode = widget.group.province != null
        ? PsgcRepository.instance.findProvinceCodeAnywhere(widget.group.province!)
        : null;
    _cityCode = widget.group.cityMunicipality != null && _provinceCode != null
        ? PsgcRepository.instance.findCityCodeByName(
            _provinceCode!, widget.group.cityMunicipality!)
        : null;
    _maleCtrl = TextEditingController(text: widget.group.maleCount > 0 ? '${widget.group.maleCount}' : '');
    _femaleCtrl = TextEditingController(text: widget.group.femaleCount > 0 ? '${widget.group.femaleCount}' : '');
  }

  @override
  void didUpdateWidget(covariant _GroupCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group != widget.group) {
      _country = widget.group.country;
      _isOverseas = widget.group.isOverseas;
      _provinceCode = widget.group.province != null
          ? PsgcRepository.instance.findProvinceCodeAnywhere(widget.group.province!)
          : null;
      _cityCode = widget.group.cityMunicipality != null && _provinceCode != null
          ? PsgcRepository.instance.findCityCodeByName(
              _provinceCode!, widget.group.cityMunicipality!)
          : null;
      if (_maleCtrl.text != '${widget.group.maleCount}' &&
          widget.group.maleCount > 0) {
        _maleCtrl.text = '${widget.group.maleCount}';
      } else if (widget.group.maleCount == 0 && _maleCtrl.text.isNotEmpty) {
        _maleCtrl.clear();
      }
      if (_femaleCtrl.text != '${widget.group.femaleCount}' &&
          widget.group.femaleCount > 0) {
        _femaleCtrl.text = '${widget.group.femaleCount}';
      } else if (widget.group.femaleCount == 0 && _femaleCtrl.text.isNotEmpty) {
        _femaleCtrl.clear();
      }
    }
  }

  @override
  void dispose() {
    _maleCtrl.dispose();
    _femaleCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    final male = int.tryParse(_maleCtrl.text) ?? 0;
    final female = int.tryParse(_femaleCtrl.text) ?? 0;
    final provinceName = _resolveProvinceName(_provinceCode);
    final cityName = _resolveCityName(_cityCode);

    widget.onChanged(OriginGroup(
      country: _isOverseas ? null : _country,
      isOverseas: _isOverseas,
      province: _showProvinceCity ? provinceName : null,
      cityMunicipality: _showProvinceCity ? cityName : null,
      maleCount: male,
      femaleCount: female,
    ));
  }

  String? _resolveProvinceName(String? code) {
    if (code == null) return null;
    for (final p in _provinces) {
      if (p.code == code) return p.name;
    }
    return null;
  }

  String? _resolveCityName(String? code) {
    if (code == null) return null;
    for (final c in _cities) {
      if (c.code == code) return c.name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kInputFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kInputBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ─────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: AppColors.primaryCyan.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${widget.index + 1}',
                  style: const TextStyle(
                    color: AppColors.primaryCyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Origin Group',
                  style: TextStyle(
                    color: kInputText,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GestureDetector(
                onTap: widget.onRemove,
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.accentRed.withOpacity(0.7),
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Overseas Filipino checkbox ─────────────────────────────────
          GestureDetector(
            onTap: () {
              setState(() {
                _isOverseas = !_isOverseas;
                if (_isOverseas) {
                  _country = null;
                  _provinceCode = null;
                  _cityCode = null;
                } else {
                  _country = 'Philippines';
                }
              });
              _emit();
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: Checkbox(
                    value: _isOverseas,
                    onChanged: (v) {
                      setState(() {
                        _isOverseas = v ?? false;
                        if (_isOverseas) {
                          _country = null;
                          _provinceCode = null;
                          _cityCode = null;
                        } else {
                          _country = 'Philippines';
                        }
                      });
                      _emit();
                    },
                    activeColor: const Color(0xFF3B82F6),
                    side: const BorderSide(color: AppColors.textGray, width: 1.4),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Overseas Filipino (Balikbayan/OFW)',
                  style: TextStyle(color: AppColors.textGray, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Country ────────────────────────────────────────────────────
          if (isMobile) ...[
            FieldCol(
              label: 'Country *',
              child: EntryDropdownField(
                value: _isOverseas ? null : _country,
                items: kCountryOptions,
                hint: _isOverseas ? 'N/A (Overseas)' : 'Select country',
                onChanged: _isOverseas
                    ? null
                    : (v) {
                        setState(() {
                          _country = v;
                          if (v != 'Philippines') {
                            _provinceCode = null;
                            _cityCode = null;
                          }
                        });
                        _emit();
                      },
              ),
            ),
          ] else ...[
            FieldCol(
              label: 'Country *',
              child: EntryDropdownField(
                value: _isOverseas ? null : _country,
                items: kCountryOptions,
                hint: _isOverseas ? 'N/A (Overseas)' : 'Select country',
                onChanged: _isOverseas
                    ? null
                    : (v) {
                        setState(() {
                          _country = v;
                          if (v != 'Philippines') {
                            _provinceCode = null;
                            _cityCode = null;
                          }
                        });
                        _emit();
                      },
              ),
            ),
          ],

          // ── Province & City (Philippines only) ─────────────────────────
          if (_showProvinceCity) ...[
            const SizedBox(height: 10),
            if (isMobile) ...[
              FieldCol(
                label: 'Province',
                child: EntryDropdownField(
                  value: _provinceCode,
                  items: _provinces.map((p) => p.code).toList(),
                  displayLabels: {for (final p in _provinces) p.code: p.name},
                  hint: 'Select province',
                  onChanged: (v) {
                    setState(() {
                      _provinceCode = v;
                      _cityCode = null;
                    });
                    _emit();
                  },
                ),
              ),
              if (_provinceCode != null) ...[
                const SizedBox(height: 10),
                FieldCol(
                  label: 'City / Municipality',
                  child: EntryDropdownField(
                    value: _cityCode,
                    items: _cities.map((c) => c.code).toList(),
                    displayLabels: {for (final c in _cities) c.code: c.name},
                    hint: 'Select city/municipality',
                    onChanged: (v) {
                      setState(() => _cityCode = v);
                      _emit();
                    },
                  ),
                ),
              ],
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: FieldCol(
                      label: 'Province',
                      child: EntryDropdownField(
                        value: _provinceCode,
                        items: _provinces.map((p) => p.code).toList(),
                        displayLabels: {for (final p in _provinces) p.code: p.name},
                        hint: 'Select province',
                        onChanged: (v) {
                          setState(() {
                            _provinceCode = v;
                            _cityCode = null;
                          });
                          _emit();
                        },
                      ),
                    ),
                  ),
                  if (_provinceCode != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: FieldCol(
                        label: 'City / Municipality',
                        child: EntryDropdownField(
                          value: _cityCode,
                          items: _cities.map((c) => c.code).toList(),
                          displayLabels: {for (final c in _cities) c.code: c.name},
                          hint: 'Select city/municipality',
                          onChanged: (v) {
                            setState(() => _cityCode = v);
                            _emit();
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],

          // ── Male / Female ──────────────────────────────────────────────
          const SizedBox(height: 10),
          if (isMobile) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: FieldCol(
                    label: 'Male',
                    child: SizedBox(
                      height: kFieldHeight,
                      child: TextField(
                        controller: _maleCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (_) => _emit(),
                        style: const TextStyle(color: kInputText, fontSize: 13),
                        decoration: lightDecoration(hint: '0'),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FieldCol(
                    label: 'Female',
                    child: SizedBox(
                      height: kFieldHeight,
                      child: TextField(
                        controller: _femaleCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (_) => _emit(),
                        style: const TextStyle(color: kInputText, fontSize: 13),
                        decoration: lightDecoration(hint: '0'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: FieldCol(
                    label: 'Male',
                    child: SizedBox(
                      height: kFieldHeight,
                      child: TextField(
                        controller: _maleCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (_) => _emit(),
                        style: const TextStyle(color: kInputText, fontSize: 13),
                        decoration: lightDecoration(hint: '0'),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FieldCol(
                    label: 'Female',
                    child: SizedBox(
                      height: kFieldHeight,
                      child: TextField(
                        controller: _femaleCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (_) => _emit(),
                        style: const TextStyle(color: kInputText, fontSize: 13),
                        decoration: lightDecoration(hint: '0'),
                      ),
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

// ─── Summary Line ────────────────────────────────────────────────────────────

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.breakdownTotal,
    required this.totalGuests,
    required this.hasMismatch,
  });

  final int breakdownTotal;
  final int totalGuests;
  final bool hasMismatch;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          hasMismatch ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
          size: 14,
          color: hasMismatch ? const Color(0xFFF59E0B) : AppColors.textGray,
        ),
        const SizedBox(width: 6),
        Text(
          'Breakdown total: $breakdownTotal / Total Guests: $totalGuests',
          style: TextStyle(
            color: hasMismatch ? const Color(0xFFF59E0B) : AppColors.textGray,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ─── Add Group Button ────────────────────────────────────────────────────────

class _AddGroupButton extends StatelessWidget {
  const _AddGroupButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primaryCyan.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.primaryCyan.withOpacity(0.3),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 16, color: AppColors.primaryCyan),
            SizedBox(width: 6),
            Text(
              'Add Origin Group',
              style: TextStyle(
                color: AppColors.primaryCyan,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
