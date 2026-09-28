import 'package:flutter/material.dart';

/// The small shared visual system used by both HateVPN desktop and Android.
abstract final class HateColors {
  static const background = Color(0xFF080A0C);
  static const sheet = Color(0xFF0B0D0F);
  static const card = Color(0xFF1B2024);
  static const cardBorder = Color(0xFF3D454C);
  static const text = Color(0xFFF3F5F6);
  static const muted = Color(0xFFB1BBC3);
  static const button = Color(0xFFEFF2F4);
  static const buttonText = Color(0xFF161A1E);
}

class HateBrandHeader extends StatelessWidget {
  const HateBrandHeader({super.key, this.onSettings});

  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 66,
    child: Row(
      children: [
        const CustomPaint(size: Size(23, 27), painter: _HateMark()),
        const SizedBox(width: 12),
        const Text(
          'HateVPN',
          style: TextStyle(
            color: HateColors.text,
            fontSize: 25,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(left: 4, top: 13),
          child: CircleAvatar(radius: 2.5, backgroundColor: Color(0xFFDCE2E6)),
        ),
        const Spacer(),
        if (onSettings != null)
          IconButton(
            tooltip: 'Настройки',
            onPressed: onSettings,
            icon: const Icon(
              Icons.tune_rounded,
              size: 21,
              color: Color(0xFFBBC4CB),
            ),
          ),
      ],
    ),
  );
}

class _HateMark extends CustomPainter {
  const _HateMark();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFEFF2F4);
    canvas.save();
    canvas.scale(size.width / 23, size.height / 27);
    final path = Path()
      ..moveTo(4, 1)
      ..lineTo(10, 1)
      ..lineTo(6, 26)
      ..lineTo(0, 26)
      ..close()
      ..moveTo(17, 1)
      ..lineTo(23, 1)
      ..lineTo(19, 26)
      ..lineTo(13, 26)
      ..close()
      ..moveTo(6, 11)
      ..lineTo(19, 11)
      ..lineTo(18, 16)
      ..lineTo(5, 16)
      ..close();
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class HatePrimaryButton extends StatelessWidget {
  const HatePrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 54,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onPressed == null ? .45 : 1,
    child: Material(
      color: HateColors.button,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: HateColors.buttonText),
                const SizedBox(width: 10),
              ],
              Text(
                label,
                style: const TextStyle(
                  color: HateColors.buttonText,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class HateDarkButton extends StatelessWidget {
  const HateDarkButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.height = 46,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) => Material(
    color: HateColors.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(15),
      side: const BorderSide(color: HateColors.cardBorder),
    ),
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(15),
      child: SizedBox(
        height: height,
        child: Center(
          child: Text(
            label,
            style: const TextStyle(color: HateColors.text, fontSize: 13),
          ),
        ),
      ),
    ),
  );
}

class HateConnectionCard extends StatelessWidget {
  const HateConnectionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.selected = false,
    this.leading,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool selected;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? const Color(0xFF2A3035) : HateColors.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(13),
      side: BorderSide(
        color: selected ? const Color(0xFFBBC5CC) : HateColors.cardBorder,
      ),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 13)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: HateColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: HateColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              selected ? Icons.check_rounded : Icons.chevron_right_rounded,
              size: 22,
              color: const Color(0xFFC1CAD0),
            ),
          ],
        ),
      ),
    ),
  );
}
