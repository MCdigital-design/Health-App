import 'package:flutter/material.dart';

/// Long Q&A copy, collapsed by default so session numbers stay on screen.
class CollapsibleHint extends StatelessWidget {
  final String label;
  final String body;
  final bool initiallyExpanded;

  const CollapsibleHint({
    super.key,
    required this.label,
    required this.body,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        initiallyExpanded: initiallyExpanded,
        dense: true,
        title: Text(label, style: style?.copyWith(fontWeight: FontWeight.w600)),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(body, style: style),
          ),
        ],
      ),
    );
  }
}
