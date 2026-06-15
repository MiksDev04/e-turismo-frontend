import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:app/core/services/file_saver.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:printing/printing.dart';
import '../../../core/constants/app_colors.dart';
import '../../../api/admin_report_api.dart';

// ─── Report Viewer Modal ──────────────────────────────────────────────────────

class ReportViewerModal extends StatefulWidget {
  const ReportViewerModal({
    super.key,
    required this.report,
    required this.onDownloadExcel,
  });

  final GeneratedReport report;
  final VoidCallback onDownloadExcel;

  @override
  State<ReportViewerModal> createState() => _ReportViewerModalState();
}

class _ReportViewerModalState extends State<ReportViewerModal> {
  bool _loading = true;
  String? _error;
  Uint8List? _pdfBytes;

  bool _exportingExcel = false;
  bool _exportingPdf = false;

  final _reportService = ReportService();

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      final pdfUrl = widget.report.fileUrl!.replaceAll('.xlsx', '.pdf');
      final bytes = await _reportService.downloadReportFile(pdfUrl);
      if (!mounted) return;
      setState(() {
        _pdfBytes = bytes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _exportExcel() async {
    setState(() => _exportingExcel = true);
    try {
      widget.onDownloadExcel();
    } finally {
      if (mounted) setState(() => _exportingExcel = false);
    }
  }

  Future<void> _exportPdf() async {
    if (_pdfBytes == null) return;
    setState(() => _exportingPdf = true);
    try {
      final fileName = 'Report_${widget.report.shortId}_'
          '${widget.report.periodLabel.replaceAll(' ', '_')}.pdf';

      if (kIsWeb) {
        await saveFileToDownloads(fileName, _pdfBytes!);
        _showModalSnack('PDF downloaded: $fileName');
      } else {
        final downloadsDir = await getDownloadsDirectory();
        if (downloadsDir == null) {
          _showModalSnack('Could not access Downloads folder.', isError: true);
          return;
        }
        final file = File('${downloadsDir.path}/$fileName');
        await file.writeAsBytes(_pdfBytes!);
        _showModalSnack('PDF saved: $fileName');
        
        final uri = Uri.file(file.path);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      _showModalSnack('Error exporting PDF: $e', isError: true);
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<void> _printPdf() async {
    if (_pdfBytes == null) return;
    try {
      await Printing.layoutPdf(
        onLayout: (format) async => _pdfBytes!,
        name: 'Report_${widget.report.shortId}',
      );
    } catch (e) {
      _showModalSnack('Error printing PDF: $e', isError: true);
    }
  }

  void _showModalSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor:
            isError ? const Color(0xFFFF4D6A) : const Color(0xFF00C48C),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;
    final isMobile = size.width < 600;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: isMobile
          ? EdgeInsets.only(top: topPadding)
          : const EdgeInsets.all(20),
      child: Container(
        width: isMobile ? size.width : size.width * 0.95,
        height: isMobile ? size.height - topPadding : size.height * 0.92,
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(isMobile ? 0 : 16),
          border: isMobile ? null : Border.all(color: AppColors.cardBorder),
          boxShadow: isMobile
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 40,
                    offset: const Offset(0, 16),
                  ),
                ],
        ),
        child: Column(
          children: [
            _ModalHeader(
              report: widget.report,
              onClose: () => Navigator.pop(context),
              onExportExcel: _exportingExcel ? null : _exportExcel,
              exportingExcel: _exportingExcel,
              onExportPdf: (_exportingPdf || _pdfBytes == null) ? null : _exportPdf,
              exportingPdf: _exportingPdf,
              onPrint: (_pdfBytes == null) ? null : _printPdf,
            ),
            const Divider(color: AppColors.cardBorder, height: 1),
            Expanded(
              child: _loading
                  ? const _LoadingView()
                  : _error != null
                      ? _ErrorView(error: _error!)
                      : _PdfView(pdfBytes: _pdfBytes!),
            ),
          ],
        ),
      ),
    );
  }
}

class _PdfView extends StatelessWidget {
  const _PdfView({required this.pdfBytes});
  final Uint8List pdfBytes;

  @override
  Widget build(BuildContext context) {
    return PdfPreview(
      build: (format) => pdfBytes,
      useActions: false,
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      loadingWidget: const _LoadingView(),
      onError: (context, error) => const _ErrorView(error: 'Could not render PDF.'),
      pdfPreviewPageDecoration: const BoxDecoration(
        color: Colors.transparent,
      ),
    );
  }
}

// ── Modal Header ──────────────────────────────────────────────────────────────

class _ModalHeader extends StatelessWidget {
  const _ModalHeader({
    required this.report,
    required this.onClose,
    required this.onExportExcel,
    required this.exportingExcel,
    required this.onExportPdf,
    required this.exportingPdf,
    required this.onPrint,
  });

  final GeneratedReport report;
  final VoidCallback onClose;
  final VoidCallback? onExportExcel;
  final bool exportingExcel;
  final VoidCallback? onExportPdf;
  final bool exportingPdf;
  final VoidCallback? onPrint;

  Widget _buildIcon() => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.primaryCyan.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.picture_as_pdf_rounded,
          color: AppColors.primaryCyan,
          size: 18,
        ),
      );

  Widget _buildInfo() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  report.reportType,
                  style: const TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryCyan.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: AppColors.primaryCyan.withOpacity(0.25),
                  ),
                ),
                child: Text(
                  report.periodLabel,
                  style: const TextStyle(
                    color: AppColors.primaryCyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Report ID: ${report.shortId}',
            style: const TextStyle(
              color: AppColors.textGray,
              fontSize: 11.5,
              fontFamily: 'monospace',
            ),
          ),
        ],
      );

  Widget _buildCloseBtn() => GestureDetector(
        onTap: onClose,
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
      );

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _buildIcon(),
                const SizedBox(width: 10),
                Expanded(child: _buildInfo()),
                const SizedBox(width: 8),
                _buildCloseBtn(),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ExportButton(
                  icon: Icons.picture_as_pdf_rounded,
                  label: 'PDF',
                  color: const Color(0xFFD32F2F),
                  borderColor: const Color(0xFFD32F2F),
                  isLoading: exportingPdf,
                  onTap: onExportPdf,
                ),
                _ExportButton(
                  icon: Icons.table_rows_rounded,
                  label: 'Excel',
                  color: const Color(0xFF1D6F42),
                  borderColor: const Color(0xFF1D6F42),
                  isLoading: exportingExcel,
                  onTap: onExportExcel,
                ),
                _ExportButton(
                  icon: Icons.print_rounded,
                  label: 'Print',
                  color: AppColors.primaryCyan,
                  borderColor: AppColors.primaryCyan,
                  onTap: onPrint,
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      child: Row(
        children: [
          _buildIcon(),
          const SizedBox(width: 12),
          Expanded(child: _buildInfo()),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ExportButton(
                icon: Icons.picture_as_pdf_rounded,
                label: 'Export PDF',
                color: const Color(0xFFD32F2F),
                borderColor: const Color(0xFFD32F2F),
                isLoading: exportingPdf,
                onTap: onExportPdf,
              ),
              const SizedBox(width: 8),
              _ExportButton(
                icon: Icons.table_rows_rounded,
                label: 'Export Excel',
                color: const Color(0xFF1D6F42),
                borderColor: const Color(0xFF1D6F42),
                isLoading: exportingExcel,
                onTap: onExportExcel,
              ),
              const SizedBox(width: 8),
              _ExportButton(
                icon: Icons.print_rounded,
                label: 'Print',
                color: AppColors.primaryCyan,
                borderColor: AppColors.primaryCyan,
                onTap: onPrint,
              ),
              const SizedBox(width: 10),
              _buildCloseBtn(),
            ],
          ),
        ],
      ),
    );
  }
}


// ── Export Button ─────────────────────────────────────────────────────────────

class _ExportButton extends StatelessWidget {
  const _ExportButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.borderColor,
    required this.onTap,
    this.isLoading = false,
    this.expand = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color borderColor;
  final VoidCallback? onTap;
  final bool isLoading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !isLoading;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.5,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor.withOpacity(0.35)),
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              else
                Icon(icon, color: color, size: 14),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Loading & Error Views ─────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: AppColors.primaryCyan,
            strokeWidth: 2,
          ),
          SizedBox(height: 14),
          Text(
            'Loading report preview…',
            style: TextStyle(color: AppColors.textGray, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFFF4D6A),
              size: 40,
            ),
            const SizedBox(height: 12),
            const Text(
              'Could not load the report preview.',
              style: TextStyle(
                color: AppColors.textWhite,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              error,
              style:
                  const TextStyle(color: AppColors.textGray, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
