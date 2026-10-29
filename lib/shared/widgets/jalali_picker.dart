import 'package:flutter/material.dart';
import 'package:customer_callbook/core/theme/app_colors.dart';
import 'package:customer_callbook/core/utils/jalali.dart';

/// دیالوگ انتخاب تاریخ و ساعت شمسی
Future<DateTime?> showJalaliDateTimePicker(BuildContext context, {DateTime? initial}) async {
  final now = DateTime.now();
  var base = initial ?? now.add(const Duration(hours: 1));
  if (base.isBefore(now)) base = now.add(const Duration(hours: 1));

  final j = Jalali.toJalali(base);
  int jy = j[0], jm = j[1], jd = j[2];
  int hour = base.hour, minute = base.minute;

  return showDialog<DateTime>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSt) {
          final maxDay = Jalali.daysInMonth(jy, jm);
          if (jd > maxDay) jd = maxDay;
          return AlertDialog(
            title: const Text('انتخاب تاریخ و ساعت شمسی'),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _dd('سال', jy, List.generate(6, (i) => jy - 1 + i), (v) => setSt(() => jy = v)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: _dd('ماه', jm, List.generate(12, (i) => i + 1), (v) => setSt(() => jm = v)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: _dd('روز', jd, List.generate(maxDay, (i) => i + 1), (v) => setSt(() => jd = v)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _dd('ساعت', hour, List.generate(24, (i) => i), (v) => setSt(() => hour = v))),
                      const SizedBox(width: 8),
                      Expanded(child: _dd('دقیقه', minute, [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55], (v) => setSt(() => minute = v))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    Jalali.format(Jalali.fromJalali(jy, jm, jd, hour, minute), withTime: true),
                    style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, Jalali.fromJalali(jy, jm, jd, hour, minute)),
                child: const Text('تأیید'),
              ),
            ],
          );
        },
      );
    },
  );
}

Widget _dd(String label, int value, List<int> items, ValueChanged<int> onChanged) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 4),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: items.contains(value) ? value : items.first,
            isExpanded: true,
            isDense: true,
            borderRadius: BorderRadius.circular(12),
            items: items
                .map(
                  (e) => DropdownMenuItem(
                    value: e,
                    child: Text(
                      '$e',
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.1),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ),
    ],
  );
}
