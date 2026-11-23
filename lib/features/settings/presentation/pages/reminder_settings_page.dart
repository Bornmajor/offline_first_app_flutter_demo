import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:offline_first_subscription_app/core/notifications/device_registration.dart';
import 'package:offline_first_subscription_app/core/notifications/reminder_timing.dart';

/// "When should we remind you?" — 1 day before, or on the due date.
///
/// The choice is saved on the phone right away and sent to the server
/// (now, or on the next try if offline); the server uses it to decide when
/// to push the reminder.
class ReminderSettingsPage extends StatefulWidget {
  const ReminderSettingsPage({super.key});

  @override
  State<ReminderSettingsPage> createState() => _ReminderSettingsPageState();
}

class _ReminderSettingsPageState extends State<ReminderSettingsPage> {
  ReminderTiming? _timing; // null while loading

  @override
  void initState() {
    super.initState();
    context.read<DeviceRegistration>().getReminderTiming().then((timing) {
      if (mounted) setState(() => _timing = timing);
    });
  }

  Future<void> _choose(ReminderTiming? timing) async {
    if (timing == null) return;
    setState(() => _timing = timing); // update the screen immediately
    await context.read<DeviceRegistration>().setReminderTiming(timing);
  }

  @override
  Widget build(BuildContext context) {
    final timing = _timing;
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      body: timing == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Remind me when a subscription is about to renew',
                  ),
                ),
                RadioGroup<ReminderTiming>(
                  groupValue: timing,
                  onChanged: _choose,
                  child: Column(
                    children: [
                      for (final option in ReminderTiming.values)
                        RadioListTile<ReminderTiming>(
                          value: option,
                          title: Text(option.label),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
