import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/data/session.dart';
import '../../auth/ui/sign_out_button.dart';
import '../data/models/order.dart';
import '../data/models/order_status.dart';
import '../logic/order_actions.dart';
import '../logic/orders_cubit.dart';
import 'courier_delivery_screen.dart';
import 'order_text.dart';
import 'widgets/order_card.dart';
import 'widgets/orders_view.dart';

/// The list the store and the courier work from. Each order offers the steps
/// the status machine gives the signed-in role, so one screen serves both.
class StaffOrdersScreen extends StatelessWidget {
  const StaffOrdersScreen({super.key, required this.session});

  final Session session;

  Future<void> _openDelivery(BuildContext context, Order order) async {
    final orders = context.read<OrdersCubit>();
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => CourierDeliveryScreen(order: order)));
    await orders.load();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OrdersCubit>();
    final isStore = session.user.role == Role.store;

    return Scaffold(
      appBar: AppBar(
        title: Text(isStore ? 'Store orders' : 'Deliveries'),
        actions: const [SignOutButton()],
      ),
      body: OrdersView(
        emptyMessage: isStore
            ? 'No orders yet. They show up here once customers order.'
            : 'Nothing is ready for pickup right now.',
        itemBuilder: (order, busy) => OrderCard(
          order: order,
          actions: [
            // Reversed, so that Cancel comes before the forward step.
            for (final to in allowedTransitions(order, session.user).reversed)
              switch (to) {
                OrderStatus.cancelled => TextButton(
                  onPressed: busy ? null : () => cubit.transition(order, to),
                  child: Text(to.actionLabel),
                ),
                // Delivering is done on the delivery screen, next to the map.
                OrderStatus.delivered => FilledButton.tonal(
                  onPressed: () => _openDelivery(context, order),
                  child: const Text('Open delivery'),
                ),
                _ => FilledButton(
                  onPressed: busy ? null : () => cubit.transition(order, to),
                  child: Text(to.actionLabel),
                ),
              },
          ],
        ),
      ),
    );
  }
}
