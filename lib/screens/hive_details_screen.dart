import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/beeguard_card.dart';

class HiveDetailsScreen extends StatefulWidget {
  const HiveDetailsScreen({super.key});

  @override
  State<HiveDetailsScreen> createState() => _HiveDetailsScreenState();
}

class _HiveDetailsScreenState extends State<HiveDetailsScreen> {
  StreamSubscription<DatabaseEvent>? _hiveSubscription;
  StreamSubscription<DatabaseEvent>? _commandsSubscription;

  double currentHoneyWeight = 0;
  bool smokePumpRunning = false;
  bool doorOpen = false;
  bool _loading = true;
  bool _collecting = false;
  int _step = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _hiveSubscription = FirebaseDatabase.instance
        .ref('hive_status')
        .onValue
        .listen((event) {
          final data = _asMap(event.snapshot.value);
          if (!mounted) return;
          setState(() {
            currentHoneyWeight = _readDouble(data['weight']);
            // The ESP echoes the physical door position here.
            doorOpen = data['door_open'] == true;
            _loading = false;
          });
        });
    _commandsSubscription = FirebaseDatabase.instance
        .ref('commands')
        .onValue
        .listen((event) {
          final data = _asMap(event.snapshot.value);
          if (!mounted) return;
          setState(() {
            smokePumpRunning = data['smoke_pump'] == true;
          });
        });
  }

  @override
  void dispose() {
    _hiveSubscription?.cancel();
    _commandsSubscription?.cancel();
    super.dispose();
  }

  // Start collection: open the door and run the smoke pump.
  // The door is intentionally LEFT OPEN — there is no automatic closing step.
  // The ESP handles the physical sequence (open door -> 4s smoke -> smoke off).
  Future<void> _collectHoney() async {
    if (_busy || doorOpen) return;
    setState(() {
      _busy = true;
      _collecting = true;
      _step = 0;
    });

    await FirebaseDatabase.instance.ref('commands/collect_honey').set(true);

    // Local timeline just mirrors the ESP sequence for visual feedback.
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _step = 1); // smoke running
    await Future<void>.delayed(const Duration(seconds: 4));
    if (mounted) {
      setState(() {
        _collecting = false;
        _busy = false;
      });
    }
  }

  // Manual close (the automatic closing step was removed by request).
  Future<void> _closeDoor() async {
    if (_busy) return;
    setState(() => _busy = true);
    await FirebaseDatabase.instance.ref('commands/collect_honey').set(false);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() {
        _busy = false;
        _collecting = false;
        _step = 0;
      });
    }
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

    return Scaffold(
      appBar: AppBar(title: const Text('Honey Collection')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const Text(
              'Honey Collection',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 18),
            _StatusCard(
              icon: doorOpen
                  ? Icons.door_sliding_rounded
                  : Icons.door_front_door_rounded,
              title: 'Door Status',
              value: _busy && !doorOpen
                  ? 'Opening'
                  : _busy && doorOpen
                  ? 'Closing'
                  : (doorOpen ? 'Open' : 'Closed'),
              color: doorOpen ? AppColors.secondary : AppColors.textSecondary,
            ),
            const SizedBox(height: 14),
            _StatusCard(
              icon: Icons.air_rounded,
              title: 'Smoke Pump',
              value: smokePumpRunning ? 'Running' : 'Stopped',
              color: smokePumpRunning
                  ? const Color(0xFFFF6F00)
                  : AppColors.textSecondary,
            ),
            const SizedBox(height: 18),
            BeeGuardCard(
              child: Column(
                children: [
                  _ProcessStep(
                    active: _collecting && _step == 0,
                    done: doorOpen || (_collecting && _step > 0),
                    title: 'Opening Door',
                  ),
                  const _ProcessDivider(),
                  _ProcessStep(
                    active: _collecting && _step == 1,
                    done: false,
                    title: 'Smoke Pump Running (4s)',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 56,
              // Toggle button: opens for collection, or closes the door manually.
              // There is no automatic closing step anymore — the door stays open
              // after collection until the farmer taps "Close Door".
              child: doorOpen
                  ? ElevatedButton.icon(
                      onPressed: _busy ? null : _closeDoor,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8D6E63),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.door_front_door_rounded),
                      label: Text(_busy ? 'Closing Door' : 'Close Door'),
                    )
                  : ElevatedButton.icon(
                      onPressed: _busy ? null : _collectHoney,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.textPrimary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: _collecting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.inventory_2_rounded),
                      label: Text(
                        _collecting ? 'Collecting Honey' : 'Collect Honey',
                      ),
                    ),
            ),
            const SizedBox(height: 18),
            BeeGuardCard(
              child: Row(
                children: [
                  const Icon(
                    Icons.scale_rounded,
                    color: Color(0xFF8D6E63),
                    size: 30,
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Current Honey Weight',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${currentHoneyWeight.toStringAsFixed(1)} kg',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
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

class _ProcessStep extends StatelessWidget {
  const _ProcessStep({
    required this.active,
    required this.done,
    required this.title,
  });

  final bool active;
  final bool done;
  final String title;

  @override
  Widget build(BuildContext context) {
    final color = done || active
        ? AppColors.secondary
        : AppColors.textSecondary;
    return Row(
      children: [
        if (active)
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.secondary,
            ),
          )
        else
          Icon(
            done ? Icons.check_circle_rounded : Icons.circle_outlined,
            color: color,
          ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProcessDivider extends StatelessWidget {
  const _ProcessDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 11, top: 8, bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          height: 18,
          child: VerticalDivider(width: 1, thickness: 1),
        ),
      ),
    );
  }
}
