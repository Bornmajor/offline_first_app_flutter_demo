import 'package:flutter/material.dart';

class NetStatusTopbar extends StatelessWidget {
  final bool isOffline;

  const NetStatusTopbar({super.key, required this.isOffline});

  @override
  Widget build(BuildContext context) {
    return isOffline
        ? const Padding(
            padding: EdgeInsetsGeometry.all(12.0),
            child: Row(
              spacing: 8.0,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.signal_wifi_off, size: 16.0),
                Text('Offline'),
              ],
            ),
          )
        : const Padding(
            padding: EdgeInsetsGeometry.all(12.0),
            child: Row(
              spacing: 8.0,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.signal_wifi_4_bar,
                  size: 16.0,
                  color: Color.fromARGB(255, 30, 88, 32),
                ),
                Text(
                  'Online',
                  style: TextStyle(color: Color.fromARGB(255, 30, 88, 32)),
                ),
              ],
            ),
          );
  }
}
