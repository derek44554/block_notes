import 'package:flutter/material.dart';
import '../core/platform_helper.dart';
import 'about_screen.dart';
import 'setup_screen.dart';

Future<void> showSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _SettingsDialog(),
  );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(appBar: _SettingsAppBar(), body: _SettingsContent());
  }
}

class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = size.width < 572 ? size.width - 32 : 540.0;
    final height = size.height < 668 ? size.height - 48 : 620.0;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: width,
        height: height,
        child: Navigator(
          onGenerateRoute: (_) {
            return MaterialPageRoute<void>(
              builder: (_) => const _SettingsDialogHome(),
            );
          },
        ),
      ),
    );
  }
}

class _SettingsAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _SettingsAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final needsMacLeadingGap =
        PlatformHelper.isMacOS && (ModalRoute.of(context)?.canPop ?? false);

    return AppBar(
      leading: needsMacLeadingGap
          ? const Padding(
              padding: EdgeInsets.only(left: 64),
              child: BackButton(),
            )
          : null,
      leadingWidth: needsMacLeadingGap ? 112 : null,
      title: const Text('设置'),
    );
  }
}

class _SettingsDialogHome extends StatelessWidget {
  const _SettingsDialogHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('设置'),
        actions: [
          IconButton(
            tooltip: '关闭',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: const _SettingsContent(inDialog: true),
    );
  }
}

class _SettingsContent extends StatelessWidget {
  const _SettingsContent({this.inDialog = false});

  final bool inDialog;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        const _SectionLabel(label: '连接'),
        _SettingsTile(
          icon: Icons.dns_rounded,
          iconColor: cs.primary,
          label: '节点设置',
          subtitle: '管理 Block 节点连接',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SetupScreen(inDialog: inDialog)),
          ),
        ),
        const SizedBox(height: 16),
        const _SectionLabel(label: '其他'),
        _SettingsTile(
          icon: Icons.info_outline_rounded,
          iconColor: cs.secondary,
          label: '关于',
          subtitle: 'BlockNotes · Derek X',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AboutScreen(inDialog: inDialog)),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: cs.primary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
