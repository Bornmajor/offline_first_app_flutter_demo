import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reusable labeled text field used across all forms in the app.
/// [label] - text shown above the input
/// [hint] - placeholder text inside the input
/// [prefixIcon] - optional leading icon
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.prefixIcon,
    this.prefixText,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.inputFormatters,
    this.validator,
    this.onChanged,
    this.textCapitalization = TextCapitalization.none,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final IconData? prefixIcon;
  final String? prefixText;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return AppFieldLabel(
      label: label,
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        inputFormatters: inputFormatters,
        validator: validator,
        onChanged: onChanged,
        textCapitalization: textCapitalization,
        decoration: appInputDecoration(
          context,
          hint: hint,
          prefixIcon: prefixIcon,
          prefixText: prefixText,
        ),
      ),
    );
  }
}

/// Places a small label above any form input so all fields look consistent.
class AppFieldLabel extends StatelessWidget {
  const AppFieldLabel({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8.0,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        child,
      ],
    );
  }
}

/// Shared input decoration so every field (text, dropdown, date) matches.
InputDecoration appInputDecoration(
  BuildContext context, {
  String? hint,
  IconData? prefixIcon,
  String? prefixText,
  Widget? suffixIcon,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12.0),
    borderSide: BorderSide.none,
  );

  return InputDecoration(
    hintText: hint,
    prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
    prefixText: prefixText,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: const Color(0xFFF2F2F2),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 16.0,
      vertical: 16.0,
    ),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
    ),
    errorBorder: border.copyWith(
      borderSide: BorderSide(color: colorScheme.error),
    ),
    focusedErrorBorder: border.copyWith(
      borderSide: BorderSide(color: colorScheme.error, width: 1.5),
    ),
  );
}
