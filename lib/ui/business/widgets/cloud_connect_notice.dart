import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/session_service.dart';
import '../../../api/login_api.dart';

class CloudConnectNotice extends StatefulWidget {
  const CloudConnectNotice({super.key, required this.onConnected});
  final VoidCallback onConnected;

  @override
  State<CloudConnectNotice> createState() => _CloudConnectNoticeState();
}

class _CloudConnectNoticeState extends State<CloudConnectNotice> {
  bool _loading = false;
  final _passCtrl = TextEditingController();

  @override
  void dispose() {
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final session = SessionService.instance.current;
    if (session == null) return;

    setState(() => _loading = true);
    try {
      final result = await LoginApi().login(
        username: session.username ?? '',
        password: _passCtrl.text,
      );

      if (result.success && mounted) {
        widget.onConnected();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connected to Cloud! Syncing data...'),
            backgroundColor: Color(0xFF065F46),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Connection failed.'),
            backgroundColor: const Color(0xFFB91C1C),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showLoginDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Connect to Cloud',
            style: TextStyle(color: AppColors.textWhite)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your password to authorize this session and fetch online data.',
              style: TextStyle(color: AppColors.textGray, fontSize: 13),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passCtrl,
              obscureText: true,
              style: const TextStyle(color: AppColors.textWhite),
              decoration: InputDecoration(
                labelText: 'Password',
                labelStyle: const TextStyle(color: AppColors.textGray),
                filled: true,
                fillColor: AppColors.inputBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textGray)),
          ),
          ElevatedButton(
            onPressed: _loading ? null : _connect,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryCyan,
              foregroundColor: Colors.black,
            ),
            child: _loading
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Text('Connect Now'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryCyan.withOpacity(0.08),
        border: Border(
          bottom: BorderSide(color: AppColors.primaryCyan.withOpacity(0.25)),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded,
              color: AppColors.primaryCyan, size: 18),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Internet detected! Authorize now to see fresh cloud data.',
              style: TextStyle(
                color: AppColors.primaryCyan,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: _showLoginDialog,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              backgroundColor: AppColors.primaryCyan.withOpacity(0.15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text(
              'Authorize',
              style: TextStyle(
                color: AppColors.primaryCyan,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
