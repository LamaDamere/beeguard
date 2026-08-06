import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/beeguard_card.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  StreamSubscription<DatabaseEvent>? _commandsSubscription;
  StreamSubscription<DatabaseEvent>? _hiveSubscription;

  bool pumpRunning = false;
  double feedingLevel = 0;
  double waterHeight = 0;
  bool _loading = true;
  bool _feeding = false;

  @override
  void initState() {
    super.initState();
    _commandsSubscription = FirebaseDatabase.instance
        .ref('commands/pump')
        .onValue
        .listen((event) {
          if (!mounted) return;
          setState(() => pumpRunning = event.snapshot.value == true);
        });
    _hiveSubscription = FirebaseDatabase.instance
        .ref('hive_status')
        .onValue
        .listen((event) {
          final data = _asMap(event.snapshot.value);
          if (!mounted) return;
          setState(() {
            feedingLevel = _readDouble(data['water_level']);
            waterHeight = _readDouble(
              data['water_height_cm'] ?? data['water_height'],
            );
            _loading = false;
          });
        });
  }

  @override
  void dispose() {
    _commandsSubscription?.cancel();
    _hiveSubscription?.cancel();
    super.dispose();
  }

  Future<void> _feedBees() async {
    if (_feeding) return;
    setState(() => _feeding = true);
    await FirebaseDatabase.instance.ref('commands/pump').set(true);
    await Future<void>.delayed(const Duration(seconds: 5));
    await FirebaseDatabase.instance.ref('commands/pump').set(false);
    if (mounted) setState(() => _feeding = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.secondary),
        ),
      );
    }

    final level = feedingLevel.clamp(0, 100).toDouble();
    final warning = level < 20;
    final critical = level < 10;

    return Scaffold(
      appBar: AppBar(title: const Text('Feeding')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const Text(
              'Feeding Solution',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 18),
            BeeGuardCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  SizedBox(
                    width: 180,
                    height: 180,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CircularProgressIndicator(
                          value: level / 100,
                          strokeWidth: 14,
                          backgroundColor: const Color(
                            0xFF42A5F5,
                          ).withValues(alpha: 0.14),
                          color: critical
                              ? const Color(0xFFE53935)
                              : warning
                              ? const Color(0xFFFF6F00)
                              : const Color(0xFF42A5F5),
                        ),
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Feeding Level',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${level.toStringAsFixed(0)}%',
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Remaining Water Height: ${waterHeight.toStringAsFixed(1)} cm',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _StatusCard(
              icon: Icons.water_rounded,
              title: 'Pump Status',
              value: pumpRunning ? 'Running' : 'Stopped',
              color: pumpRunning
                  ? AppColors.secondary
                  : AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _feeding ? null : _feedBees,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.textPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: _feeding
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(_feeding ? 'Feeding for 5 Seconds' : 'Feed Bees'),
              ),
            ),
            const SizedBox(height: 16),
            if (critical)
              const _LevelNotice(
                icon: Icons.error_rounded,
                title: 'Critical Feeding Level',
                message: 'Refill the feeding container immediately.',
                color: Color(0xFFE53935),
              )
            else if (warning)
              const _LevelNotice(
                icon: Icons.warning_rounded,
                title: 'Low Feeding Level',
                message: 'Refill is recommended soon.',
                color: Color(0xFFFF6F00),
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

  double _readDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return BeeGuardCard(
      child: Row(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _LevelNotice extends StatelessWidget {
  const _LevelNotice({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return BeeGuardCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
