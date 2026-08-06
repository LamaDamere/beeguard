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
  bool doorLocked = true;
  bool _loading = true;
  bool _collecting = false;
  int _step = 0;

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
            doorLocked = data['emergency_lock'] == true;
          });
        });
  }

  @override
  void dispose() {
    _hiveSubscription?.cancel();
    _commandsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _collectHoney() async {
    if (_collecting) return;
    setState(() {
      _collecting = true;
      _step = 0;
    });

    final commands = FirebaseDatabase.instance.ref('commands');
    await commands.child('emergency_lock').set(false);
    await Future<void>.delayed(const Duration(seconds: 1));
    if (mounted) setState(() => _step = 1);
    await commands.child('smoke_pump').set(true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _step = 2);
    await commands.child('smoke_pump').set(false);
    await commands.child('emergency_lock').set(true);
    await Future<void>.delayed(const Duration(seconds: 1));
    if (mounted) {
      setState(() {
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
              icon: doorLocked
                  ? Icons.door_front_door_rounded
                  : Icons.door_sliding_rounded,
              title: 'Door Status',
              value: _collecting
                  ? (_step == 0
                        ? 'Opening'
                        : _step == 2
                        ? 'Closing'
                        : 'Open')
                  : (doorLocked ? 'Closed' : 'Open'),
              color: doorLocked ? AppColors.textSecondary : AppColors.secondary,
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
                    done: _collecting && _step > 0,
                    title: 'Opening Door',
                  ),
                  const _ProcessDivider(),
                  _ProcessStep(
                    active: _collecting && _step == 1,
                    done: _collecting && _step > 1,
                    title: 'Smoke Pump Running',
                  ),
                  const _ProcessDivider(),
                  _ProcessStep(
                    active: _collecting && _step == 2,
                    done: false,
                    title: 'Closing Door',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _collecting ? null : _collectHoney,
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
                label: Text(_collecting ? 'Collecting Honey' : 'Collect Honey'),
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
