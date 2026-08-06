import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/beeguard_card.dart';

class HornetDetectionScreen extends StatefulWidget {
  const HornetDetectionScreen({super.key});

  @override
  State<HornetDetectionScreen> createState() => _HornetDetectionScreenState();
}

class _HornetDetectionScreenState extends State<HornetDetectionScreen> {
  StreamSubscription<DatabaseEvent>? _subscription;
  bool detected = false;
  String entranceStatus = 'open';
  String lastDetection = 'No detection yet';
  String imageUrl = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _subscription = FirebaseDatabase.instance
        .ref('hornet_detection')
        .onValue
        .listen((event) {
          final data = _asMap(event.snapshot.value);
          if (!mounted) return;
          setState(() {
            detected = data['detected'] == true;
            entranceStatus = data['entrance_status']?.toString() ?? 'open';
            lastDetection =
                data['last_detection']?.toString() ?? 'No detection yet';
            imageUrl = data['image_url']?.toString() ?? '';
            _loading = false;
          });
        });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _setEntrance(String value) async {
    await FirebaseDatabase.instance.ref('commands/entrance').set(value);
    if (!mounted) return;
    setState(() => entranceStatus = value);
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

    final narrowed = entranceStatus == 'narrow';
    final statusColor = detected
        ? const Color(0xFFE53935)
        : AppColors.secondary;

    return Scaffold(
      appBar: AppBar(title: const Text('Hornet Detection')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            BeeGuardCard(
              padding: const EdgeInsets.all(22),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      detected
                          ? Icons.pest_control_rounded
                          : Icons.check_circle_rounded,
                      color: statusColor,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Detection Status',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _StatusChip(
                          label: detected ? 'Hornet Detected' : 'No Hornet',
                          color: statusColor,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            BeeGuardCard(
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: SizedBox(
                  height: 230,
                  width: double.infinity,
                  child: imageUrl.isNotEmpty
                      ? Image.network(imageUrl, fit: BoxFit.cover)
                      : Container(
                          color: Colors.white,
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.image_rounded,
                                  color: AppColors.textSecondary,
                                  size: 42,
                                ),
                                SizedBox(height: 10),
                                Text(
                                  'Latest captured image',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            BeeGuardCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        narrowed
                            ? Icons.door_sliding_rounded
                            : Icons.door_front_door_rounded,
                        color: narrowed
                            ? const Color(0xFFFF6F00)
                            : AppColors.secondary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        narrowed ? 'Entrance: Narrow' : 'Entrance: Open',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _setEntrance('open'),
                          child: const Text('Open Entrance'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _setEntrance('narrow'),
                          child: const Text('Narrow Entrance'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            BeeGuardCard(
              child: Row(
                children: [
                  const Icon(
                    Icons.access_time_rounded,
                    color: AppColors.secondary,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Last Detection: $lastDetection',
                      style: Theme.of(context).textTheme.titleMedium,
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
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }
}
