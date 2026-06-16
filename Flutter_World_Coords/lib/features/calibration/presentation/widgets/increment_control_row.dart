import 'package:flutter/material.dart';

class IncrementControlRow extends StatelessWidget {
  const IncrementControlRow({
    super.key,
    required this.label,
    required this.valueLabel,
    required this.decrements,
    required this.increments,
  });

  final String label;
  final String valueLabel;
  final List<Widget> decrements;
  final List<Widget> increments;

  // Build one compact control row for a calibration axis.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            Text(valueLabel, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...decrements,
            ...increments,
          ],
        ),
      ],
    );
  }
}