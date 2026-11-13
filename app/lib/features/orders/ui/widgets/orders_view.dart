import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/order.dart';
import '../../logic/orders_cubit.dart';
import 'message_view.dart';
import 'snack.dart';

/// The body every order list shares: loading, a failed first load, an empty
/// list and the list itself, with pull to refresh.
class OrdersView extends StatelessWidget {
  const OrdersView({super.key, required this.emptyMessage, required this.itemBuilder});

  final String emptyMessage;

  /// [busy] is true while a step for that order is on its way to the server.
  final Widget Function(Order order, bool busy) itemBuilder;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OrdersCubit>();

    return BlocConsumer<OrdersCubit, OrdersState>(
      // With a list on screen a failure is a passing message; without one it
      // is the whole screen and the builder shows it.
      listenWhen: (_, current) => current.orders != null && current.failure != null,
      listener: (context, state) => showSnack(context, state.failure!.message),
      builder: (context, state) {
        final orders = state.orders;
        final failure = state.failure;
        if (orders == null) {
          return failure == null
              ? const Center(child: CircularProgressIndicator())
              : MessageView(
                  icon: Icons.cloud_off,
                  message: failure.message,
                  action: FilledButton.tonal(onPressed: cubit.load, child: const Text('Try again')),
                );
        }

        return RefreshIndicator(
          onRefresh: cubit.load,
          child: orders.isEmpty
              // Still a scroll view, so that an empty list can be pulled as well.
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [MessageView(icon: Icons.receipt_long, message: emptyMessage)],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: orders.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    return itemBuilder(order, state.busyOrderId == order.id);
                  },
                ),
        );
      },
    );
  }
}
