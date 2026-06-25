// ignore_for_file: deprecated_member_use

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/file_saver.dart';
import '../../../core/services/session_service.dart';
import '../models/accommodation_models.dart';

// ─── Business Details Data Model ─────────────────────────────────────────────

class BusinessDetails {
  const BusinessDetails({
    required this.name,
    required this.tradeName,
    required this.type,
    required this.businessLine,
    required this.rooms,
    required this.status,
    required this.owner,
    required this.permitNumber,
    required this.registrationNumber,
    required this.registeredDate,
    required this.address,
    required this.street,
    required this.barangay,
    required this.cityMunicipality,
    required this.province,
    required this.region,
    required this.phone,
    required this.email,
    required this.permitFileUrl,
    required this.validIdUrl,
  });

  final String name;
  final String tradeName;
  final String type;
  final String businessLine;
  final int rooms;
  final AccommodationStatus status;
  final String owner;
  final String permitNumber;
  final String registrationNumber;
  final String registeredDate;
  final String address;
  final String street;
  final String barangay;
  final String cityMunicipality;
  final String province;
  final String region;
  final String phone;
  final String email;
  final String permitFileUrl;
  final String validIdUrl;
}

// ─── Show Helper ──────────────────────────────────────────────────────────────

Future<void> showBusinessDetailsModal(
  BuildContext context,
  BusinessDetails details,
) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.6),
    barrierDismissible: true,
    builder: (_) => BusinessDetailsModal(details: details),
  );
}

// ─── Modal Widget ─────────────────────────────────────────────────────────────

class BusinessDetailsModal extends StatefulWidget {
  const BusinessDetailsModal({super.key, required this.details});
  final BusinessDetails details;

  @override
  State<BusinessDetailsModal> createState() => _BusinessDetailsModalState();
}

class _BusinessDetailsModalState extends State<BusinessDetailsModal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  static const _modalMaxWidth = 480.0;

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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _BusinessIdentity(details: widget.details),
                                  const SizedBox(height: 20),
                                  const Divider(
                                    color: AppColors.cardBorder,
                                    height: 1,
                                  ),
                                  const SizedBox(height: 20),
                                  _DetailsGrid(details: widget.details),
                                  const SizedBox(height: 20),
                                  const Divider(
                                    color: AppColors.cardBorder,
                                    height: 1,
                                  ),
                                  const SizedBox(height: 20),
                                  _ContactInfo(details: widget.details),
                                  const SizedBox(height: 20),
                                  const Divider(
                                    color: AppColors.cardBorder,
                                    height: 1,
                                  ),
                                  const SizedBox(height: 20),
                                  _DocumentsSection(
                                    permitFileUrl: widget.details.permitFileUrl,
                                    validIdUrl: widget.details.validIdUrl,
                                  ),
                                  const SizedBox(height: 4),
                                ],
                              ),
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
            'Business Details',
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

// ─── Business Identity ────────────────────────────────────────────────────────

class _BusinessIdentity extends StatelessWidget {
  const _BusinessIdentity({required this.details});
  final BusinessDetails details;

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
            Icons.apartment_rounded,
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
                '${details.type} • ${details.businessLine} • ${details.rooms} Rooms',
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

// ─── Details Grid ─────────────────────────────────────────────────────────────

class _DetailsGrid extends StatelessWidget {
  const _DetailsGrid({required this.details});
  final BusinessDetails details;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DetailRow(
          first: _DetailField(label: 'Trade Name', value: details.tradeName),
          second: _DetailField(label: 'Owner', value: details.owner),
        ),
        const SizedBox(height: 12),
        _DetailRow(
          first: _DetailField(label: 'Business Line', value: details.businessLine),
          second: _DetailField(
            label: 'Registered',
            value: _formatRegisteredDate(details.registeredDate),
          ),
        ),
        const SizedBox(height: 12),
        _DetailRow(
          first: _DetailField(label: 'Permit #', value: details.permitNumber),
          second: _DetailField(
            label: 'Registration #',
            value: details.registrationNumber,
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

  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    return value;
  }

  const monthNames = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  final local = parsed.toLocal();
  return '${monthNames[local.month - 1]} ${local.day}, ${local.year}';
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

// ─── Contact Info ─────────────────────────────────────────────────────────────

class _ContactInfo extends StatelessWidget {
  const _ContactInfo({required this.details});
  final BusinessDetails details;

  @override
  Widget build(BuildContext context) {
    // Compose structured address if available
    final parts = <String>[];
    if (details.street.isNotEmpty && details.street != '—') parts.add(details.street);
    if (details.barangay.isNotEmpty && details.barangay != '—') parts.add(details.barangay);
    if (details.cityMunicipality.isNotEmpty && details.cityMunicipality != '—') parts.add(details.cityMunicipality);
    if (details.province.isNotEmpty && details.province != '—') parts.add(details.province);
    if (details.region.isNotEmpty && details.region != '—') parts.add(details.region);
    final addressText = parts.isNotEmpty ? parts.join(', ') : details.address;

    return Column(
      children: [
        _ContactRow(icon: Icons.location_on_outlined, text: addressText),
        const SizedBox(height: 10),
        _ContactRow(icon: Icons.phone_outlined, text: details.phone),
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

// ─── Documents Section ────────────────────────────────────────────────────────

class _DocumentsSection extends StatelessWidget {
  const _DocumentsSection({
    required this.permitFileUrl,
    required this.validIdUrl,
  });

  final String permitFileUrl;
  final String validIdUrl;

  void _previewDocument(BuildContext context, String title, String url) {
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document URL not available.')),
      );
      return;
    }
    showDocumentPreviewModal(context, title, url);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Business Documents',
          style: TextStyle(
            color: AppColors.textSubtle,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _DocumentChip(
              label: 'Business Permit',
              onTap: () => _previewDocument(context, 'Business Permit', permitFileUrl),
            ),
            const SizedBox(width: 8),
            _DocumentChip(
              label: 'Valid ID',
              onTap: () => _previewDocument(context, 'Valid ID', validIdUrl),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Resolve URL Helper ──────────────────────────────────────────────────────

String _resolveUrl(String relativeOrAbsoluteUrl) {
  if (relativeOrAbsoluteUrl.isEmpty) return '';
  if (relativeOrAbsoluteUrl.startsWith('http://') || relativeOrAbsoluteUrl.startsWith('https://')) {
    return relativeOrAbsoluteUrl;
  }
  
  final String backendUrl;
  if (kIsWeb) {
    backendUrl = dotenv.env['BACKEND_URL'] ?? 'http://localhost:3000';
  } else if (defaultTargetPlatform == TargetPlatform.android) {
    backendUrl = dotenv.env['ANDROID_BACKEND_URL'] ?? 'http://10.0.2.2:3000';
  } else {
    backendUrl = dotenv.env['BACKEND_URL'] ?? 'http://localhost:3000';
  }
  
  final cleanBackend = backendUrl.endsWith('/') 
      ? backendUrl.substring(0, backendUrl.length - 1) 
      : backendUrl;
  final cleanRelative = relativeOrAbsoluteUrl.startsWith('/') 
      ? relativeOrAbsoluteUrl 
      : '/$relativeOrAbsoluteUrl';
      
  return '$cleanBackend$cleanRelative';
}

// ─── Document Preview Dialog ────────────────────────────────────────────────

Future<void> showDocumentPreviewModal(
  BuildContext context,
  String title,
  String url,
) {
  return showGeneralDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.6),
    barrierDismissible: true,
    barrierLabel: 'Close',
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
    transitionBuilder: (context, anim, secondaryAnim, child) {
      final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1.0).animate(curve),
          child: DocumentPreviewModal(title: title, url: url),
        ),
      );
    },
  );
}

// ─── Document Preview Modal Widget ──────────────────────────────────────────

class DocumentPreviewModal extends StatefulWidget {
  const DocumentPreviewModal({
    super.key,
    required this.title,
    required this.url,
  });
  
  final String title;
  final String url;
  
  @override
  State<DocumentPreviewModal> createState() => _DocumentPreviewModalState();
}

enum _DocType { pdf, png, jpeg, unknown }

_DocType _detectDocType(Uint8List bytes) {
  if (bytes.length >= 4) {
    if (bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46) {
      return _DocType.pdf;
    }
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      return _DocType.png;
    }
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return _DocType.jpeg;
    }
  }
  return _DocType.unknown;
}

class _DocumentPreviewModalState extends State<DocumentPreviewModal> {
  Uint8List? _bytes;
  bool _loading = true;
  String? _error;
  bool _saving = false;
  _DocType _docType = _DocType.unknown;
  
  @override
  void initState() {
    super.initState();
    _loadDocument();
  }
  
  Future<void> _loadDocument() async {
    if (widget.url.isEmpty) {
      setState(() {
        _error = 'Document URL is empty.';
        _loading = false;
      });
      return;
    }
    
    try {
      final resolved = _resolveUrl(widget.url);
      final token = SessionService.instance.current?.token;
      final apiKey = dotenv.env['API_KEY'] ?? '';
      
      final headers = {
        'x-api-key': apiKey,
        if (token != null) 'Authorization': 'Bearer $token',
      };
      
      final response = await http.get(Uri.parse(resolved), headers: headers);
      if (response.statusCode == 200) {
        if (mounted) {
          final bytes = response.bodyBytes;
          setState(() {
            _bytes = bytes;
            _docType = _detectDocType(bytes);
            _loading = false;
          });
        }
      } else {
        throw Exception('HTTP Error ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load document: $e';
          _loading = false;
        });
      }
    }
  }
  
  String get _fileExtension {
    switch (_docType) {
      case _DocType.pdf:
        return 'pdf';
      case _DocType.png:
        return 'png';
      case _DocType.jpeg:
        return 'jpg';
      case _DocType.unknown:
        final uri = Uri.parse(widget.url);
        final seg = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
        final ext = seg.split('.').last.toLowerCase();
        return (ext == 'pdf' || ext == 'png' || ext == 'jpg' || ext == 'jpeg') ? ext : 'png';
    }
  }
  
  String get _docTypeLabel {
    switch (_docType) {
      case _DocType.pdf:
        return 'PDF Document';
      case _DocType.png:
        return 'PNG Image';
      case _DocType.jpeg:
        return 'JPEG Image';
      case _DocType.unknown:
        return 'Document';
    }
  }
  
  Future<void> _download() async {
    if (_bytes == null || _saving) return;
    setState(() => _saving = true);
    try {
      final fileName = '${widget.title.replaceAll(' ', '_')}_'
          '${DateTime.now().millisecondsSinceEpoch}.$_fileExtension';
          
      await saveFileToDownloads(fileName, _bytes!);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded successfully: $fileName'),
            backgroundColor: const Color(0xFF00C48C),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download: $e'),
            backgroundColor: const Color(0xFFFF4D6A),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 600;
    final isPdf = _docType == _DocType.pdf;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: isMobile 
          ? const EdgeInsets.all(12) 
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 900),
        width: isMobile ? size.width : size.width * 0.85,
        height: isMobile ? size.height * 0.85 : size.height * 0.85,
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 40,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: AppColors.textWhite,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _docTypeLabel,
                          style: const TextStyle(
                            color: AppColors.textGray,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_loading && _error == null) ...[
                    // Download Button
                    GestureDetector(
                      onTap: _saving ? null : _download,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryCyan.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.primaryCyan.withOpacity(0.35)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_saving)
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primaryCyan,
                                ),
                              )
                            else
                              const Icon(Icons.download_rounded, color: AppColors.primaryCyan, size: 14),
                            const SizedBox(width: 6),
                            const Text(
                              'Download',
                              style: TextStyle(
                                color: AppColors.primaryCyan,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Close Button
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.backgroundDark,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textGray,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.cardBorder, height: 1),
            
            // Content preview
            Expanded(
              child: Container(
                color: AppColors.backgroundDark,
                width: double.infinity,
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primaryCyan,
                        ),
                      )
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.error_outline_rounded,
                                    color: Color(0xFFFF4D6A),
                                    size: 48,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: AppColors.textGray,
                                      fontSize: 14,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: () {
                                      setState(() {
                                        _loading = true;
                                        _error = null;
                                      });
                                      _loadDocument();
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primaryCyan,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _bytes == null
                            ? const Center(
                                child: Text(
                                  'No data available.',
                                  style: TextStyle(color: AppColors.textGray),
                                ),
                              )
                            : isPdf
                                ? ClipRRect(
                                    borderRadius: const BorderRadius.only(
                                      bottomLeft: Radius.circular(16),
                                      bottomRight: Radius.circular(16),
                                    ),
                                    child: PdfPreview(
                                      build: (format) => _bytes!,
                                      useActions: false,
                                      loadingWidget: const Center(
                                        child: CircularProgressIndicator(
                                          color: AppColors.primaryCyan,
                                        ),
                                      ),
                                    ),
                                  )
                                : _docType == _DocType.unknown
                                    ? const Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.insert_drive_file_outlined,
                                              color: AppColors.textSubtle,
                                              size: 64,
                                            ),
                                            SizedBox(height: 12),
                                            Text(
                                              'Unable to preview this document format.',
                                              style: TextStyle(
                                                color: AppColors.textGray,
                                                fontSize: 14,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),
                                      )
                                    : ClipRRect(
                                        borderRadius: const BorderRadius.only(
                                          bottomLeft: Radius.circular(16),
                                          bottomRight: Radius.circular(16),
                                        ),
                                        child: InteractiveViewer(
                                          maxScale: 4.0,
                                          minScale: 0.5,
                                          child: Center(
                                            child: Image.memory(
                                              _bytes!,
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                        ),
                                      ),
              ),
            ),
          ],
        ),
      ),
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

// ─── Hover Icon Button ────────────────────────────────────────────────────────

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

// ─── Status Badge ─────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final AccommodationStatus status;

  static ({String label, Color color}) _styleFor(AccommodationStatus s) {
    switch (s) {
      case AccommodationStatus.approved:
        return (label: 'Approved', color: const Color(0xFF00C48C));
      case AccommodationStatus.pending:
        return (label: 'Pending', color: const Color(0xFFFFB020));
      case AccommodationStatus.rejected:
        return (label: 'Rejected', color: const Color(0xFFFF4D6A));
      case AccommodationStatus.warning:
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