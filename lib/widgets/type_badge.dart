import 'package:flutter/material.dart';
import '../models/translation_entry.dart';
import '../theme/app_theme.dart';

class TypeBadge extends StatelessWidget {
  final TranslationType type;

  const TypeBadge({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    final isTSID = type == TranslationType.TSID;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isTSID ? AppColors.badgeTSID.withOpacity(0.2) : AppColors.badgeTID.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isTSID ? AppColors.badgeTSID.withOpacity(0.5) : AppColors.badgeTID.withOpacity(0.5),
          width: 0.8,
        ),
      ),
      child: Text(
        isTSID ? 'TSİD' : 'TİD',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: isTSID ? AppColors.badgeTSID : AppColors.badgeTID,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
