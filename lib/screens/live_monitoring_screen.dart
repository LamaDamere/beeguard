import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/beeguard_card.dart';

class LiveMonitoringScreen extends StatefulWidget {
  const LiveMonitoringScreen({super.key});

  @override
  State<LiveMonitoringScreen> createState() => _LiveMonitoringScreenState();
}

class _LiveMonitoringScreenState extends State<LiveMonitoringScreen> {
  StreamSubscription<DatabaseEvent>? _subscription;

  bool _loading = true;
  double temperature = 0;
  double humidity = 0;
  double honeyWeight = 0;
  double waterLevel = 0;
  String soundResult = 'Unknown';
  String lastSync = 'Waiting for data';

  @override
  void initState() {
    super.initState();
    _subscription = FirebaseDatabase.instance.ref('hive_status').onValue.listen(
      (event) {
        final data = _asMap(event.snapshot.value);
        if (!mounted) return;

        setState(() {
          temperature = _readDouble(data['temperature']);
          humidity = _readDouble(data['humidity']);
          honeyWeight = _readDouble(data['weight']);
          waterLevel = _readDouble(data['water_level']);
          soundResult = data['sound_result']?.toString() ?? 'Unknown';
          lastSync = data['last_sync']?.toString() ?? 'No sync yet';
          _loading = false;
        });
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFFFC928)),
        ),
      );
    }

    final sensors = [
      _SensorItem(
        name: 'Temperature',
        value: '${temperature.toStringAsFixed(1)} C',
        icon: Icons.thermostat_rounded,
        color: const Color(0xFFE53935),
        warning: temperature > 36,
      ),
      _SensorItem(
        name: 'Humidity',
        value: '${humidity.toStringAsFixed(0)}%',
        icon: Icons.water_drop_rounded,
        color: const Color(0xFF42A5F5),
        warning: humidity > 75 || humidity < 40,
      ),
      _SensorItem(
        name: 'Collected Honey',
        value: '${honeyWeight.toStringAsFixed(1)} kg',
        icon: Icons.scale_rounded,
        color: const Color(0xFF8D6E63),
        warning: false,
      ),
      _SensorItem(
        name: 'Sound',
        value: soundResult,
        icon: Icons.graphic_eq_rounded,
        color: AppColors.secondary,
        warning: soundResult.toLowerCase() != 'normal',
      ),
      _SensorItem(
        name: 'Water Level',
        value: '${waterLevel.toStringAsFixed(0)}%',
        icon: Icons.water_rounded,
        color: const Color(0xFF42A5F5),
        warning: waterLevel < 30,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Monitoring'),
        leading: IconButton(
          color: const Color(0xFFFFC928),
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const _LiveStatusRow(),
            const SizedBox(height: 18),
            ...sensors.map(
              (sensor) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _SensorCard(sensor: sensor),
              ),
            ),
            const SizedBox(height: 6),
            _ConnectionStatusCard(lastSync: lastSync),
          ],
        ),
      ),
    );
  }

  Map<dynamic, dynamic> _asMap(Object? value) {
    if (value is Map) return value;
    return {};
  }

  double _readDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class _LiveStatusRow extends StatelessWidget {
  const _LiveStatusRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _StatusDot(color: AppColors.secondary, size: 9),
        SizedBox(width: 8),
        Text(
          'Live - just now',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SensorCard extends StatelessWidget {
  const _SensorCard({required this.sensor});

  final _SensorItem sensor;

  @override
  Widget build(BuildContext context) {
    final statusColor = sensor.warning
        ? const Color(0xFFFFC928)
        : AppColors.secondary;

    return BeeGuardCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: sensor.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(sensor.icon, color: sensor.color, size: 30),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sensor.name,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        sensor.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusChip(
                  label: sensor.warning ? 'Warning' : 'Normal',
                  color: statusColor,
                ),
              ],
            ),
          ),
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(22),
                bottomRight: Radius.circular(22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ConnectionStatusCard extends StatelessWidget {
  const _ConnectionStatusCard({required this.lastSync});

  final String lastSync;

  @override
  Widget build(BuildContext context) {
    return BeeGuardCard(
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.textPrimary,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.wifi_rounded, color: Color(0xFFFFC928), size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'ESP32 Connected',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const _StatusDot(color: AppColors.secondary, size: 10),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Signal Strong',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  'Last sync: $lastSync',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _SensorItem {
  const _SensorItem({
    required this.name,
    required this.value,
    required this.icon,
    required this.color,
    required this.warning,
  });

  final String name;
  final String value;
  final IconData icon;
  final Color color;
  final bool warning;
}
