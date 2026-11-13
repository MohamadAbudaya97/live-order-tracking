import 'package:flutter/material.dart';

import '../../data/models/order_status.dart';
import '../order_text.dart';

/// The way an order travels from placed to delivered, with the steps behind
/// it ticked off. A cancelled order has left that path and shows as such.
class StatusTimeline extends StatelessWidget {
  const StatusTimeline({super.key, required this.status});

  final OrderStatus status;

  static const _path = [
    OrderStatus.placed,
    OrderStatus.accepted,
    OrderStatus.preparing,
    OrderStatus.ready,
    OrderStatus.pickedUp,
    OrderStatus.delivered,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (status == OrderStatus.cancelled) {
      return Row(
        children: [
          Icon(Icons.cancel, color: scheme.error),
          const SizedBox(width: 12),
          Text(
            'This order was cancelled',
            style: theme.textTheme.titleMedium?.copyWith(color: scheme.error),
          ),
        ],
      );
    }

    final reached = _path.indexOf(status);
    return Column(
      children: [
        for (final (index, step) in _path.indexed)
          _Step(
            label: step.label,
            // Delivered is the end of the path, so it is ticked off as well.
            done: index < reached || status == OrderStatus.delivered,
            current: index == reached,
            last: index == _path.length - 1,
          ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.done, required this.current, required this.last});

  final String label;
  final bool done;
  final bool current;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final icon = done
        ? Icons.check_circle
        : current
        ? Icons.radio_button_checked
        : Icons.radio_button_unchecked;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Icon(icon, color: done || current ? scheme.primary : scheme.outlineVariant),
            if (!last)
              Container(width: 2, height: 20, color: done ? scheme.primary : scheme.outlineVariant),
          ],
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            label,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: current && !done ? FontWeight.w600 : null,
              color: done || current ? scheme.onSurface : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
