import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:intl/intl.dart';

enum PeriodType { week, month, year }

class UserEvolutionCandlestick extends StatefulWidget {
  final List<User> users;
  const UserEvolutionCandlestick({super.key, required this.users});

  @override
  State<UserEvolutionCandlestick> createState() =>
      _UserEvolutionCandlestickState();
}

class _UserEvolutionCandlestickState extends State<UserEvolutionCandlestick> {
  PeriodType _periodType = PeriodType.month;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSegmentedControl(),
        const SizedBox(height: 20),
        Expanded(child: _buildChart()),
      ],
    );
  }

  Widget _buildSegmentedControl() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSegmentButton(PeriodType.week, 'SEMANA'),
          _buildSegmentButton(PeriodType.month, 'MES'),
          _buildSegmentButton(PeriodType.year, 'AÑO'),
        ],
      ),
    );
  }

  Widget _buildSegmentButton(PeriodType type, String label) {
    final isSelected = _periodType == type;
    return InkWell(
      onTap: () => setState(() => _periodType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.greenAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white54,
            fontWeight: FontWeight.bold,
            fontSize: 10,
            fontFamily: 'Courier',
          ),
        ),
      ),
    );
  }

  Widget _buildChart() {
    final candleData = _processData();
    if (candleData.isEmpty) {
      return const Center(
        child: Text(
          'SIN DATOS SUFICIENTES',
          style: TextStyle(color: Colors.white24, fontFamily: 'Courier'),
        ),
      );
    }

    final barGroups = candleData.asMap().entries.map((entry) {
      final index = entry.key;
      final data = entry.value;

      // Un gráfico de velas simulado:
      // El "Cuerpo" de la vela es el cambio en ese periodo.
      // Si sube, es verde; si baja (raro en evolución), es roja.
      // En este contexto, como es acumulativo, siempre será verde o neutro.
      // Usaremos el rod para el cuerpo y ExtraLines para la mecha.

      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            fromY: data.low,
            toY: data.high,
            color: Colors.greenAccent,
            width: 12,
            borderRadius: BorderRadius.zero,
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: data.high + (data.high * 0.1),
              color: Colors.white.withOpacity(0.02),
            ),
          ),
        ],
      );
    }).toList();

    return BarChart(
      BarChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: Colors.white10, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt()}',
                style: const TextStyle(color: Colors.white24, fontSize: 10),
              ),
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= candleData.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    candleData[index].label,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 9,
                      fontFamily: 'Courier',
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: barGroups,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.black,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final data = candleData[groupIndex];
              return BarTooltipItem(
                '${data.label}\n',
                const TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                ),
                children: [
                  TextSpan(
                    text:
                        'MIN: ${data.low.toInt()}\nMAX: ${data.high.toInt()}\nDELTA: +${(data.high - data.low).toInt()}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.normal,
                      fontSize: 10,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<_CandleData> _processData() {
    final sortedUsers = List<User>.from(widget.users)
      ..sort(
        (a, b) => (a.fechaDeIngreso ?? DateTime(2000)).compareTo(
          b.fechaDeIngreso ?? DateTime(2000),
        ),
      );

    if (sortedUsers.isEmpty) return [];

    final List<_CandleData> result = [];
    final now = DateTime.now();

    switch (_periodType) {
      case PeriodType.week:
        // Últimas 12 semanas
        for (int i = 11; i >= 0; i--) {
          final start = now.subtract(Duration(days: 7 * (i + 1)));
          final end = now.subtract(Duration(days: 7 * i));

          final countAtStart = sortedUsers
              .where(
                (u) => (u.fechaDeIngreso ?? DateTime(2000)).isBefore(start),
              )
              .length;
          final countAtEnd = sortedUsers
              .where((u) => (u.fechaDeIngreso ?? DateTime(2000)).isBefore(end))
              .length;

          result.add(
            _CandleData(
              label: 'S${now.subtract(Duration(days: 7 * i)).day}',
              low: countAtStart.toDouble(),
              high: countAtEnd.toDouble(),
            ),
          );
        }
        break;
      case PeriodType.month:
        // Últimos 6 meses
        for (int i = 5; i >= 0; i--) {
          final date = DateTime(now.year, now.month - i, 1);
          final nextMonth = DateTime(now.year, now.month - i + 1, 1);

          final countAtStart = sortedUsers
              .where((u) => (u.fechaDeIngreso ?? DateTime(2000)).isBefore(date))
              .length;
          final countAtEnd = sortedUsers
              .where(
                (u) => (u.fechaDeIngreso ?? DateTime(2000)).isBefore(nextMonth),
              )
              .length;

          result.add(
            _CandleData(
              label: DateFormat('MMM').format(date).toUpperCase(),
              low: countAtStart.toDouble(),
              high: countAtEnd.toDouble(),
            ),
          );
        }
        break;
      case PeriodType.year:
        // Últimos 3 años
        for (int i = 2; i >= 0; i--) {
          final year = now.year - i;
          final date = DateTime(year, 1, 1);
          final nextYear = DateTime(year + 1, 1, 1);

          final countAtStart = sortedUsers
              .where((u) => (u.fechaDeIngreso ?? DateTime(2000)).isBefore(date))
              .length;
          final countAtEnd = sortedUsers
              .where(
                (u) => (u.fechaDeIngreso ?? DateTime(2000)).isBefore(nextYear),
              )
              .length;

          result.add(
            _CandleData(
              label: year.toString(),
              low: countAtStart.toDouble(),
              high: countAtEnd.toDouble(),
            ),
          );
        }
        break;
    }

    return result;
  }
}

class _CandleData {
  final String label;
  final double low;
  final double high;

  _CandleData({required this.label, required this.low, required this.high});
}
