import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

const _disclaimerTr =
    'Bu uygulama, işaret dili ile günlük iletişimi desteklemek amacıyla '
    'geliştirilmiş bir araçtır ve sertifikalı işaret dili tercümanlarının '
    'yerini almaz.\n\n'
    'Resmi, hukuki, tıbbi veya acil durumlarda lütfen sertifikalı bir '
    'tercümana başvurun.';

const _disclaimerEn =
    'This application is a supportive tool designed to assist everyday '
    'sign language communication and is not a substitute for certified '
    'sign language interpreters.\n\n'
    'For official, legal, medical, or emergency situations, please consult '
    'a certified interpreter.';

/// "Önemli Not" / "Important Notice" uyarı dialog'u.
/// İlk açılışta (zorunlu) ve Settings'ten (isteğe bağlı) gösterilir.
Future<void> showDisclaimerDialog(
  BuildContext context, {
  required bool isTr,
  bool barrierDismissible = true,
}) {
  final c = AppColors.of(context);
  return showDialog<void>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (_) => AlertDialog(
      backgroundColor: c.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        isTr ? 'Önemli Not' : 'Important Notice',
        style: TextStyle(color: c.text, fontWeight: FontWeight.w800),
      ),
      content: Text(
        isTr ? _disclaimerTr : _disclaimerEn,
        style: TextStyle(color: c.textSub, height: 1.5, fontSize: 13.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            isTr ? 'Anladım' : 'Got it',
            style: const TextStyle(
              color: AppColors.green,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}
