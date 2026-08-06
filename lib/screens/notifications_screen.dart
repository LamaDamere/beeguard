import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/beeguard_card.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const Color honeyYellow = Color(0xFFFFC928);

  StreamSubscription<DatabaseEvent>? _subscription;
  List<_AlertEntry> alerts = const [];
  String selectedFilter = 'all';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _subscription = FirebaseDatabase.instance.ref('alerts').onValue.listen((
      event,
    ) {
      final data = _asMap(event.snapshot.value);
      final nextAlerts = data.entries.map((entry) {
        final row = _asMap(entry.value);
        return _AlertEntry(
          id: entry.key.toString(),
          type: row['type']?.toString().toLowerCase() ?? 'security',
          message: row['message']?.toString() ?? 'No message',
          timestamp: row['timestamp']?.toString() ?? 'Unknown time',
          read: row['read'] == true,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        alerts = nextAlerts.reversed.toList();
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sourceAlerts = alerts.isEmpty ? _demoAlerts : alerts;
    final filteredAlerts = selectedFilter == 'all'
        ? sourceAlerts
        : sourceAlerts.where((alert) => alert.type == selectedFilter).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.notifications_rounded, color: honeyYellow),
            SizedBox(width: 10),
            Text('Alerts'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: honeyYellow))
          : SafeArea(
              top: false,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  _FilterChips(
                    selected: selectedFilter,
                    onSelected: (filter) => setState(() {
                      selectedFilter = filter;
                    }),
                  ),
                  const SizedBox(height: 18),
                  if (filteredAlerts.isEmpty)
                    const _EmptyAlerts()
                  else
                    ...filteredAlerts.map(
                      (alert) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _AlertCard(alert: alert),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Map<dynamic, dynamic> _asMap(Object? value) {
    if (value is Map) return value;
    return {};
  }

  static const List<_AlertEntry> _demoAlerts = [
    _AlertEntry(
      id: 'demo-low-water',
      type: 'water',
      message: 'Feeding solution is below the safe level.',
      timestamp: '5 min ago',
      read: false,
    ),
    _AlertEntry(
      id: 'demo-hornet',
      type: 'hornet',
      message: 'Hornet detected near the hive entrance.',
      timestamp: '20 min ago',
      read: false,
    ),
    _AlertEntry(
      id: 'demo-rfid',
      type: 'rfid',
      message: 'Authorized RFID card scanned successfully.',
      timestamp: '50 min ago',
      read: true,
    ),
    _AlertEntry(
      id: 'demo-door-opened',
      type: 'door_opened',
      message: 'Main door servo opened after RFID approval.',
      timestamp: '1h ago',
      read: true,
    ),
    _AlertEntry(
      id: 'demo-door-closed',
      type: 'door_closed',
      message: 'Main door servo closed and lock returned.',
      timestamp: '1h ago',
      read: true,
    ),
    _AlertEntry(
      id: 'demo-smoke',
      type: 'smoke',
      message: 'Smoke pump relay activated automatically.',
      timestamp: '2h ago',
      read: true,
    ),
  ];
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  static const filters = [
    _FilterItem('all', 'All', Icons.apps_rounded),
    _FilterItem('water', 'Water', Icons.water_drop_rounded),
    _FilterItem('hornet', 'Hornet', Icons.pest_control_rounded),
    _FilterItem('rfid', 'RFID', Icons.credit_card_rounded),
    _FilterItem('door_opened', 'Door Opened', Icons.door_sliding_rounded),
    _FilterItem('door_closed', 'Door Closed', Icons.door_front_door_rounded),
    _FilterItem('smoke', 'Smoke', Icons.air_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final active = selected == filter.value;
          return ChoiceChip(
            avatar: Icon(
              filter.icon,
              size: 18,
              color: active ? const Color(0xFF2B1A05) : AppColors.secondary,
            ),
            label: Text(filter.label),
            selected: active,
            selectedColor: const Color(0xFFFFC928),
            backgroundColor: AppColors.card,
            showCheckmark: false,
            side: BorderSide(
              color: active
                  ? const Color(0xFFFFC928)
                  : AppColors.textSecondary.withValues(alpha: 0.3),
            ),
            labelStyle: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
            onSelected: (_) => onSelected(filter.value),
          );
        },
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});

  final _AlertEntry alert;

  @override
  Widget build(BuildContext context) {
    final color = _typeColor(alert.type);

    return BeeGuardCard(
      padding: EdgeInsets.zero,
      onTap: alert.read
          ? null
          : () async {
              await FirebaseDatabase.instance
                  .ref('alerts/${alert.id}/read')
                  .set(true);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Alert marked as read')),
                );
              }
            },
      child: Container(
        decoration: BoxDecoration(
          color: alert.read ? AppColors.card : const Color(0xFFFFF3B8),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 104,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(22),
                  bottomLeft: Radius.circular(22),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        _typeIcon(alert.type),
                        color: color,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _typeTitle(alert.type),
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            alert.message,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            alert.timestamp,
                            style: TextStyle(
                              color: AppColors.textSecondary.withValues(
                                alpha: 0.8,
                              ),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'security':
      case 'rfid':
      case 'door_opened':
      case 'door_closed':
        return const Color(0xFFE53935);
      case 'sound':
      case 'smoke':
        return const Color(0xFFFFC928);
      case 'water':
        return const Color(0xFF42A5F5);
      case 'hornet':
        return const Color(0xFFFF6F00);
      default:
        return AppColors.secondary;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'temperature':
        return Icons.thermostat_rounded;
      case 'sound':
        return Icons.graphic_eq_rounded;
      case 'security':
        return Icons.lock_rounded;
      case 'rfid':
        return Icons.credit_card_rounded;
      case 'door_opened':
        return Icons.door_sliding_rounded;
      case 'door_closed':
        return Icons.door_front_door_rounded;
      case 'smoke':
        return Icons.air_rounded;
      case 'water':
        return Icons.water_drop_rounded;
      case 'hornet':
        return Icons.pest_control_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  String _typeTitle(String type) {
    switch (type) {
      case 'temperature':
        return 'Temperature Alert';
      case 'sound':
        return 'Sound Alert';
      case 'security':
        return 'Security Alert';
      case 'rfid':
        return 'RFID Access Granted';
      case 'door_opened':
        return 'Door Opened';
      case 'door_closed':
        return 'Door Closed';
      case 'smoke':
        return 'Smoke Pump Activated';
      case 'water':
        return 'Low Water Level';
      case 'hornet':
        return 'Hornet Detected';
      default:
        return 'Hive Alert';
    }
  }
}

class _EmptyAlerts extends StatelessWidget {
  const _EmptyAlerts();

  @override
  Widget build(BuildContext context) {
    return const BeeGuardCard(
      padding: EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(Icons.hive_rounded, color: Color(0xFFFFC928), size: 58),
          SizedBox(height: 14),
          Text(
            'No alerts yet. Your hive is happy!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertEntry {
  const _AlertEntry({
    required this.id,
    required this.type,
    required this.message,
    required this.timestamp,
    required this.read,
  });

  final String id;
  final String type;
  final String message;
  final String timestamp;
  final bool read;
}

class _FilterItem {
  const _FilterItem(this.value, this.label, this.icon);
  final String value;
  final String label;
  final IconData icon;
}
