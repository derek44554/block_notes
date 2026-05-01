import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/platform_helper.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, this.inDialog = false});

  final bool inDialog;

  static const _version = '1.0.0';
  static const _author = 'Derek X';
  static const _github = 'https://github.com/derek44554/block_notes';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final needsMacLeadingGap =
        !inDialog &&
        PlatformHelper.isMacOS &&
        (ModalRoute.of(context)?.canPop ?? false);

    return Scaffold(
      appBar: AppBar(
        leading: needsMacLeadingGap
            ? const Padding(
                padding: EdgeInsets.only(left: 64),
                child: BackButton(),
              )
            : null,
        leadingWidth: needsMacLeadingGap ? 112 : null,
        title: const Text('关于'),
      ),
      body: ListView(
        children: [
          // ── 顶部 Logo + 信息 ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: cs.primary.withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.note_alt_rounded,
                    color: cs.onPrimary,
                    size: 44,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'BlockNotes',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'v$_version',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '作者: ',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => launchUrl(
                        Uri.parse('https://derekx.com'),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Text(
                        _author,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.primary,
                          decoration: TextDecoration.underline,
                          decorationColor: cs.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    'BlockNotes 是一款基于 Block 去中心化网络的加密备忘录应用，让你的笔记安全存储在节点上，只有你能访问。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── 链接选项 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _LinkTile(
              icon: Icons.code_rounded,
              iconColor: cs.onSurface,
              label: 'GitHub',
              url: _github,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.url,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () =>
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.open_in_new_rounded,
                size: 16,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
