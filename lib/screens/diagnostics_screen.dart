import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/diagnostics.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/common.dart';

/// Generates a diagnostics report and sends it by email.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
      );

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  String? _report;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
  }

  Future<void> _generate() async {
    final report = await Diagnostics.buildReport(AppScope.of(context));
    if (mounted) setState(() => _report = report);
  }

  Future<void> _send() async {
    final sent = await Diagnostics.email(_report!);
    if (!mounted) return;
    switch (sent) {
      case ReportSent.email:
        break;
      case ReportSent.share:
        showSnack(context,
            'No email app found, so it\'s shared instead. Send it to ${Diagnostics.reportEmail}.');
      case null:
        await _copy(
            'No email app found. The report is copied: paste it into an '
            'email to ${Diagnostics.reportEmail}, or into WhatsApp.');
    }
  }

  Future<void> _share() async {
    if (await Diagnostics.share(_report!)) return;
    await _copy('Sharing isn\'t available. The report is copied.');
  }

  Future<void> _copy([String message = 'Report copied.']) async {
    await Clipboard.setData(ClipboardData(text: _report!));
    if (mounted) showSnack(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final report = _report ?? '';
    final ready = report.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics report'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
      ),
      body: ready
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                report,
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 12, height: 1.35),
              ),
            )
          : const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.orange),
                  SizedBox(height: 16),
                  Text('Generating report…'),
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PrimaryButton(
                label: 'Send report by email',
                icon: Icons.email_outlined,
                onPressed: ready ? _send : null,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: ready ? _share : null,
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text('Share (WhatsApp…)'),
                  ),
                  TextButton.icon(
                    onPressed: ready ? _copy : null,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy'),
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

/// "Generate report" bar shown at the bottom of every screen in
/// diagnostics builds.
class DiagnosticsBar extends StatelessWidget {
  const DiagnosticsBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.navy,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => DiagnosticsScreen.open(context),
          style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
          icon: const Icon(Icons.bug_report_outlined),
          label: const Text('Generate Report'),
        ),
      ),
    );
  }
}
