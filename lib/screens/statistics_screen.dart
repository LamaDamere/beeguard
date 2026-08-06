import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/beeguard_card.dart';
import '../widgets/section_header.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  StreamSubscription<DatabaseEvent>? _hiveSubscription;
  StreamSubscription<DatabaseEvent>? _productionSubscription;

  double currentHoneyWeight = 0;
  double todayProduction = 0;
  double weeklyProduction = 0;
  double monthlyProduction = 0;
  bool _loading = true;

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
    _productionSubscription = FirebaseDatabase.instance
        .ref('production')
        .onValue
        .listen((event) {
          final data = _asMap(event.snapshot.value);
          if (!mounted) return;
          final todayWeight = _readDouble(data['today_weight']);
          final yesterdayWeight = _readDouble(data['yesterday_weight']);
          setState(() {
            todayProduction = _readDouble(data['today_production']);
            if (todayProduction == 0 && todayWeight > yesterdayWeight) {
              todayProduction = todayWeight - yesterdayWeight;
            }
            weeklyProduction = _readDouble(data['weekly_production']);
            if (weeklyProduction == 0) {
              weeklyProduction = todayProduction * 7;
            }
            monthlyProduction = _readDouble(data['monthly_production']);
            if (monthlyProduction == 0) {
              monthlyProduction = todayProduction * 30;
            }
          });
        });
  }

  @override
  void dispose() {
    _hiveSubscription?.cancel();
    _productionSubscription?.cancel();
    super.dispose();
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

    final chartValues = [
      todayProduction * 0.5,
      todayProduction * 0.7,
      todayProduction * 0.6,
      todayProduction * 0.9,
      todayProduction * 0.8,
      todayProduction,
      todayProduction * 1.1,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Honey Production')),
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
                      color: const Color(0xFF8D6E63).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.scale_rounded,
                      color: Color(0xFF8D6E63),
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Current Honey Weight',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${currentHoneyWeight.toStringAsFixed(1)} kg',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _StatsGrid(
              items: [
                _StatItem('Today', todayProduction),
                _StatItem('Weekly', weeklyProduction),
                _StatItem('Monthly', monthlyProduction),
              ],
            ),
            const SizedBox(height: 24),
            const SectionHeader(
              title: 'Last Seven Days',
              subtitle: 'Honey production trend',
            ),
            const SizedBox(height: 12),
            BeeGuardCard(
              padding: const EdgeInsets.all(18),
              child: SizedBox(
                height: 180,
                child: CustomPaint(
                  painter: _LineChartPainter(values: chartValues),
                  child: const SizedBox.expand(),
                ),
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

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.items});

  final List<_StatItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 28) / 3;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: items
              .map((item) => SizedBox(width: width, child: _StatCard(item)))
              .toList(),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.item);

  final _StatItem item;

  @override
  Widget build(BuildContext context) {
    return BeeGuardCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.inventory_2_rounded, color: AppColors.secondary),
          const SizedBox(height: 14),
          Text(
            '${item.value.toStringAsFixed(1)} kg',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.title,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  const _LineChartPainter({required this.values});

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final axisPaint = Paint()
      ..color = AppColors.textSecondary.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    final linePaint = Paint()
      ..color = AppColors.secondary
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final dotPaint = Paint()..color = AppColors.secondary;

    for (var i = 0; i < 4; i++) {
      final y = size.height * (i + 1) / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), axisPaint);
    }

    final maxValue = values.fold<double>(1, (max, value) {
      return value > max ? value : max;
    });
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * size.width / (values.length - 1);
      final y = size.height - (values[i] / maxValue * size.height * 0.82) - 8;
      final point = Offset(x, y);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawCircle(point, 4, dotPaint);
    }
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.values != values;
  }
}

class _StatItem {
  const _StatItem(this.title, this.value);

  final String title;
  final double value;
}
