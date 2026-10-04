import 'package:flutter/material.dart';
import 'package:offline_first_app_flutter_demo/shared/widgets/app_text_field.dart';

/// Reusable labeled dropdown that matches [AppTextField] styling.
/// [items] - values to choose from
/// [itemLabel] - converts a value into display text
class AppDropdownField<T> extends StatelessWidget {
  const AppDropdownField({
    super.key,
    required this.label,
    required this.items,
    required this.itemLabel,
    this.value,
    this.hint,
    this.prefixIcon,
    this.onChanged,
    this.validator,
  });

  final String label;
  final List<T> items;
  final String Function(T item) itemLabel;
  final T? value;
  final String? hint;
  final IconData? prefixIcon;
  final ValueChanged<T?>? onChanged;
  final FormFieldValidator<T>? validator;

  @override
  Widget build(BuildContext context) {
    return AppFieldLabel(
      label: label,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        validator: validator,
        onChanged: onChanged,
        borderRadius: BorderRadius.circular(12.0),
        decoration: appInputDecoration(
          context,
          hint: hint,
          prefixIcon: prefixIcon,
        ),
        items: items
            .map(
              (item) => DropdownMenuItem<T>(
                value: item,
                child: Text(itemLabel(item)),
              ),
            )
            .toList(),
      ),
    );
  }
}
