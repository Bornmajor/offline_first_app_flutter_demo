import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:offline_first_app_flutter_demo/core/enums/billing_cycles.dart';
import 'package:offline_first_app_flutter_demo/core/utils/form_validators.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/subscription_repository.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/domain/entities/subscription.dart';
import 'package:offline_first_app_flutter_demo/shared/widgets/app_date_field.dart';
import 'package:offline_first_app_flutter_demo/shared/widgets/app_dropdown_field.dart';
import 'package:offline_first_app_flutter_demo/shared/widgets/app_primary_button.dart';
import 'package:offline_first_app_flutter_demo/shared/widgets/app_text_field.dart';

/// One form for both CREATE and UPDATE.
///
///   SubscriptionFormPage(repository: r)              → create mode
///   SubscriptionFormPage(repository: r, initial: s)  → edit mode, pre-filled
///
/// Save writes to the local database through [repository].
class SubscriptionFormPage extends StatefulWidget {
  const SubscriptionFormPage({
    super.key,
    required this.repository,
    this.initial,
  });

  /// Injected by the HomePage (same instance created in main.dart).
  final SubscriptionRepository repository;

  /// The subscription being edited, or null when creating a new one.
  final Subscription? initial;

  @override
  State<SubscriptionFormPage> createState() => _SubscriptionFormPageState();
}

class _SubscriptionFormPageState extends State<SubscriptionFormPage> {
  static const _defaultCategories = [
    'Entertainment',
    'Music',
    'Productivity',
    'Utilities',
    'Health',
    'Education',
    'Other',
  ];

  /// Digits with an optional decimal part (max 2 places), e.g. "9.99".
  /// Any other input, typed or pasted, is rejected and the old text is kept.
  static final _priceFormatter = TextInputFormatter.withFunction(
    (oldValue, newValue) => RegExp(r'^\d*\.?\d{0,2}$').hasMatch(newValue.text)
        ? newValue
        : oldValue,
  );

  final _formKey = GlobalKey<FormState>();

  // Pre-filled from `initial` in edit mode, empty in create mode.
  late final _nameController = TextEditingController(
    text: widget.initial?.name,
  );
  late final _priceController = TextEditingController(
    text: widget.initial == null ? null : _formatPrice(widget.initial!.price),
  );
  late String? _category = widget.initial?.category;
  late BillingCycles? _billingCycle =
      widget.initial?.billingCycle ?? BillingCycles.monthly;
  late DateTime? _dueDate = widget.initial?.dueDate;

  /// True while the database write is running: shows a spinner on the
  /// button and blocks double taps (which would insert two rows).
  bool _isSaving = false;

  bool get _isEditing => widget.initial != null;

  /// A category saved earlier may not be in today's list; the dropdown would
  /// crash on a value it doesn't contain, so make sure it's included.
  List<String> get _categories => [
    ..._defaultCategories,
    if (_category != null && !_defaultCategories.contains(_category))
      _category!,
  ];

  /// 9.0 → "9", 9.5 → "9.50", 9.99 → "9.99" (fits the 2-decimal formatter).
  static String _formatPrice(double price) => price == price.roundToDouble()
      ? price.toInt().toString()
      : price.toStringAsFixed(2);

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  /// In edit mode an old subscription may already be overdue. Re-validating
  /// that unchanged date as "not in the past" would block every other edit
  /// (e.g. fixing a typo in the name), so the rule only applies to a date
  /// the user actually picked.
  String? _validateDueDate(DateTime? value) {
    final isUnchanged = _isEditing && value == widget.initial!.dueDate;
    if (isUnchanged) return null;
    return FormValidators.notPastDate(value, fieldName: 'Due date');
  }

  Future<void> _onSubmit() async {
    // 1. Validate. Every field must pass before we touch the database.
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    // The `!` are safe because the validators above guarantee values.
    final name = _nameController.text.trim();
    final price = double.parse(_priceController.text);

    try {
      // 2. Write to SQLite. No network: works the same in airplane mode.
      if (_isEditing) {
        // UPDATE: same id as before → the DAO changes that row.
        await widget.repository.update(
          Subscription(
            id: widget.initial!.id,
            name: name,
            billingCycle: _billingCycle!,
            dueDate: _dueDate!,
            category: _category!,
            price: price,
          ),
        );
      } else {
        // CREATE: no id → the table generates one.
        await widget.repository.create(
          name: name,
          billingCycle: _billingCycle!,
          dueDate: _dueDate!,
          category: _category!,
          price: price,
        );
      }

      // 3. The page may have been closed while we awaited; using its
      //    context after that would crash, so check `mounted` first.
      if (!mounted) return;

      // 4. Go back. Note: we DON'T tell the home page to refresh — its
      //    watchAll() stream already emitted the new list after the write.
      Navigator.of(context).pop();
    } catch (e) {
      // Rare for a local DB (e.g. disk full, row deleted meanwhile), but
      // never fail silently.
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit subscription' : 'New subscription'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          // After the first interaction, errors update as the user types.
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              Column(
                spacing: 20.0,
                children: [
                  AppTextField(
                    label: 'Name',
                    hint: 'e.g. Netflix',
                    prefixIcon: Icons.subscriptions_outlined,
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    validator: (value) =>
                        FormValidators.required(value, fieldName: 'Name'),
                  ),
                  AppTextField(
                    label: 'Price',
                    hint: '0.00',
                    prefixIcon: Icons.attach_money,
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [_priceFormatter],
                    validator: FormValidators.price,
                  ),
                  AppDropdownField<String>(
                    label: 'Category',
                    hint: 'Select category',
                    prefixIcon: Icons.category_outlined,
                    items: _categories,
                    itemLabel: (item) => item,
                    value: _category,
                    onChanged: (value) => setState(() => _category = value),
                    validator: (value) =>
                        FormValidators.required(value, fieldName: 'Category'),
                  ),
                  AppDropdownField<BillingCycles>(
                    label: 'Billing cycle',
                    hint: 'Select billing cycle',
                    prefixIcon: Icons.autorenew,
                    items: BillingCycles.values,
                    itemLabel: (item) => item.label,
                    value: _billingCycle,
                    onChanged: (value) => setState(() => _billingCycle = value),
                    validator: (value) => FormValidators.required(
                      value,
                      fieldName: 'Billing cycle',
                    ),
                  ),
                  AppDateField(
                    label: 'Next due date',
                    value: _dueDate,
                    // Past days are greyed out in the picker...
                    firstDate: today,
                    onChanged: (date) => setState(() => _dueDate = date),
                    // ...and still rejected here in case "today" rolls over
                    // while the form is open (unless unchanged in edit mode).
                    validator: _validateDueDate,
                  ),
                ],
              ),
              const SizedBox(height: 32.0),
              AppPrimaryButton(
                label: _isEditing ? 'Save changes' : 'Save subscription',
                icon: Icons.check,
                isLoading: _isSaving,
                onPressed: _onSubmit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
