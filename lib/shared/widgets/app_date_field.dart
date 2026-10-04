import 'package:flutter/material.dart';
import 'package:offline_first_app_flutter_demo/core/utils/date_formatter.dart';
import 'package:offline_first_app_flutter_demo/shared/widgets/app_text_field.dart';

/// Reusable labeled date picker field that matches [AppTextField] styling.
/// Tapping the field opens the material date picker. Being a [FormField],
/// it is validated together with the rest of the [Form].
class AppDateField extends StatelessWidget {
  const AppDateField({
    super.key,
    required this.label,
    required this.onChanged,
    this.value,
    this.hint = 'Select date',
    this.prefixIcon = Icons.calendar_today_outlined,
    this.firstDate,
    this.lastDate,
    this.validator,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final String hint;
  final IconData prefixIcon;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final FormFieldValidator<DateTime>? validator;

  Future<void> _pickDate(
    BuildContext context,
    FormFieldState<DateTime> field,
  ) async {
    final now = DateTime.now();
    final first = firstDate ?? DateTime(now.year - 1);
    final current = field.value;
    final picked = await showDatePicker(
      context: context,
      // initialDate must not be before firstDate, or the picker throws.
      initialDate: current != null && !current.isBefore(first) ? current : now,
      firstDate: first,
      lastDate: lastDate ?? DateTime(now.year + 5),
    );
    if (picked == null) return;
    field.didChange(picked);
    onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppFieldLabel(
      label: label,
      child: FormField<DateTime>(
        initialValue: value,
        validator: validator,
        builder: (field) => InkWell(
          borderRadius: BorderRadius.circular(12.0),
          onTap: () => _pickDate(context, field),
          child: InputDecorator(
            isEmpty: field.value == null,
            decoration: appInputDecoration(
              context,
              hint: hint,
              prefixIcon: prefixIcon,
              suffixIcon: const Icon(Icons.arrow_drop_down),
            ).copyWith(errorText: field.errorText),
            child: field.value == null
                ? null
                : Text(field.value!.toShortDate(), style: textTheme.bodyLarge),
          ),
        ),
      ),
    );
  }
}
