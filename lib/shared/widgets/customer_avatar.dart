import 'package:flutter/material.dart';
import 'package:customer_callbook/core/theme/app_colors.dart';
import 'package:customer_callbook/data/models/customer.dart';

/// آواتار گرادیان شیک به‌جای حرف اول
class CustomerAvatar extends StatelessWidget {
  final String name;
  final String? tag;
  final String? status;
  final double size;
  final bool favorite;

  const CustomerAvatar({
    super.key,
    required this.name,
    this.tag,
    this.status,
    this.size = 48,
    this.favorite = false,
  });

  static const _gradients = [
    [Color(0xFF6C63FF), Color(0xFF8B5CF6)],
    [Color(0xFF00C2D8), Color(0xFF3B82F6)],
    [Color(0xFFF59E0B), Color(0xFFEF4444)],
    [Color(0xFF10B981), Color(0xFF059669)],
    [Color(0xFFEC4899), Color(0xFF8B5CF6)],
    [Color(0xFF6366F1), Color(0xFF06B6D4)],
  ];

  List<Color> get _colors {
    final h = name.hashCode.abs() % _gradients.length;
    return _gradients[h];
  }

  IconData get _icon {
    if (favorite) return Icons.star_rounded;
    switch (tag) {
      case 'همکار':
        return Icons.badge_rounded;
      case 'سایر':
        return Icons.person_outline_rounded;
      default:
        return Icons.person_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        boxShadow: [
          BoxShadow(
            color: colors[0].withOpacity(0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(_icon, color: Colors.white, size: size * 0.48),
    );
  }
}

/// بج کوچک دسته
class TagBadge extends StatelessWidget {
  final String tag;
  final String? status;
  const TagBadge({super.key, required this.tag, this.status});

  Color get _color {
    switch (tag) {
      case 'همکار':
        return const Color(0xFF3B82F6);
      case 'سایر':
        return const Color(0xFF64748B);
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _color.withOpacity(0.35)),
      ),
      child: Text(
        status != null && status!.isNotEmpty ? '$tag · $status' : tag,
        style: TextStyle(color: _color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
