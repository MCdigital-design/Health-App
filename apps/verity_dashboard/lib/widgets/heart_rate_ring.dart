import 'package:flutter/material.dart';

class HeartRateRing extends StatelessWidget {
  final int? heartRate;
  final double size;

  const HeartRateRing({super.key, this.heartRate, this.size = 200});

  @override
  Widget build(BuildContext context) {
    final hr = heartRate ?? 0;
    final progress = (hr / 200).clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 12,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(
                hr > 140 ? Colors.redAccent : hr > 100 ? Colors.orangeAccent : Colors.greenAccent,
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                hr > 0 ? '$hr' : '--',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
              ),
              Text(
                'BPM',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
