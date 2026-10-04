import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:offline_first_app_flutter_demo/core/enums/billing_cycles.dart';
import 'package:offline_first_app_flutter_demo/core/utils/form_validators.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/subscription_repository.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/domain/entities/subscription.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/cubits/subscription_form/subscription_form_cubit.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/cubits/subscription_form/subscription_form_state.dart';
import 'package:offline_first_app_flutter_demo/shared/widgets/app_date_field.dart';
import 'package:offline_first_app_flutter_demo/shared/widgets/app_dropdown_field.dart';
import 'package:offline_first_app_flutter_demo/shared/widgets/app_primary_button.dart';
import 'package:offline_first_app_flutter_demo/shared/widgets/app_text_field.dart';

/// One form for both CREATE and UPDATE — PAGE part: wiring only.
///
///   SubscriptionFormPage()            → create mode
///   SubscriptionFormPage(initial: s)  → edit mode, pre-filled
///
/// Creates a fresh [SubscriptionFormCubit] for this screen; BlocProvider
/// closes it when the page is popped.
class SubscriptionFormPage extends StatelessWidget {
  const SubscriptionFormPage({super.key, this.initial});

  /// The subscription being edited, or null when creating a new one.
  final Subscription? initial;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => SubscriptionFormCubit(
        context.read<SubscriptionRepository>(),
        initial: initial,
      ),
      child: const SubscriptionFormView(),
    );
  }
}

/// VIEW part: owns the field values (controllers, dropdown/date values) and
/// Flutter's Form validation. Saving is delegated to the Cubit.
class SubscriptionFormView extends StatefulWidget {
  const SubscriptionFormView({super.key});

  @override
  State<SubscriptionFormView> createState() => _SubscriptionFormViewState();
}

class _SubscriptionFormViewState extends State<SubscriptionFormView> {
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

  // Field values. Pre-filled from the Cubit's `initial` in edit mode.
  late final Subscription? _initial;
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  String? _category;
  BillingCycles? _billingCycle;
  DateTime? _dueDate;

  bool get _isEditing => _initial != null;

  @override
  void initState() {
    super.initState();
    // The subscription being edited lives in the Cubit (one source of
    // truth). `read` is fine here: initState runs once, outside build.
    _initial = context.read<SubscriptionFormCubit>().initial;

    _nameController = TextEditingController(text: _initial?.name);
    _priceController = TextEditingController(
      text: _initial == null ? null : _formatPrice(_initial.price),
    );
    _category = _initial?.category;
    _billingCycle = _initial?.billingCycle ?? BillingCycles.monthly;
    _dueDate = _initial?.dueDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

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

  /// In edit mode an old subscription may already be overdue. Re-validating
  /// that unchanged date as "not in the past" would block every other edit
  /// (e.g. fixing a typo in the name), so the rule only applies to a date
  /// the user actually picked.
  String? _validateDueDate(DateTime? value) {
    final isUnchanged = _isEditing && value == _initial!.dueDate;
    if (isUnchanged) return null;
    return FormValidators.notPastDate(value, fieldName: 'Due date');
  }

  /// Validate here (UI concern), then hand the values to the Cubit.
  /// No try/catch, no Navigator, no setState: the Cubit reports the outcome
  /// through its state, and the BlocListener in build() reacts to it.
  void _onSubmit() {
    if (!_formKey.currentState!.validate()) return;

    // The `!` are safe because the validators above guarantee values.
    context.read<SubscriptionFormCubit>().save(
      name: _nameController.text.trim(),
      billingCycle: _billingCycle!,
      dueDate: _dueDate!,
      category: _category!,
      price: double.parse(_priceController.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // BlocListener: one-off reactions to the save outcome.
    return BlocListener<SubscriptionFormCubit, SubscriptionFormState>(
      // Only success/failure need a reaction (not idle/saving).
      listenWhen: (previous, current) =>
          current.status == SubscriptionFormStatus.success ||
          current.status == SubscriptionFormStatus.failure,
      listener: (context, state) {
        if (state.status == SubscriptionFormStatus.success) {
          // Saved → go back. The home list already shows the change: its
          // own Cubit listens to the database.
          Navigator.of(context).pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.errorMessage ?? 'Could not save')),
          );
        }
      },
      child: Scaffold(
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
                      onChanged: (value) =>
                          setState(() => _billingCycle = value),
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
                      // ...and still rejected here in case "today" rolls
                      // over while the form is open (unless unchanged in
                      // edit mode).
                      validator: _validateDueDate,
                    ),
                  ],
                ),
                const SizedBox(height: 32.0),
                // BlocBuilder: only the button depends on the Cubit's state
                // (spinner while saving), so only the button rebuilds.
                BlocBuilder<SubscriptionFormCubit, SubscriptionFormState>(
                  buildWhen: (previous, current) =>
                      previous.isSaving != current.isSaving,
                  builder: (context, state) => AppPrimaryButton(
                    label: _isEditing ? 'Save changes' : 'Save subscription',
                    icon: Icons.check,
                    isLoading: state.isSaving,
                    onPressed: _onSubmit,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
