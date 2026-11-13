import 'package:flutter/material.dart';

import '../../data/models/order.dart';
import '../../data/models/order_status.dart';
import '../order_text.dart';

class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order, this.onTap, this.actions = const []});

  final Order order;
  final VoidCallback? onTap;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final placedAt = TimeOfDay.fromDateTime(order.createdAt.toLocal());

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(order.code, style: theme.textTheme.titleLarge)),
                  Text(
                    order.status.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: order.status == OrderStatus.cancelled ? scheme.error : scheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(order.itemsSummary),
              const SizedBox(height: 4),
              Text(
                '${order.customerName} · ${placedAt.format(context)} · ${formatAmount(order.total)}',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Wrap(spacing: 8, children: actions),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
