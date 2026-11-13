import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/data/session.dart';
import '../../auth/ui/sign_out_button.dart';
import '../data/models/order.dart';
import '../data/order_repository.dart';
import '../logic/orders_cubit.dart';
import '../logic/place_order_cubit.dart';
import 'tracking_screen.dart';
import 'widgets/order_card.dart';
import 'widgets/orders_view.dart';
import 'widgets/snack.dart';

class CustomerOrdersScreen extends StatelessWidget {
  const CustomerOrdersScreen({super.key, required this.session});

  final Session session;

  Future<void> _openTracking(BuildContext context, Order order) async {
    final orders = context.read<OrdersCubit>();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TrackingScreen(order: order, session: session),
      ),
    );
    await orders.load();
  }

  void _onPlaceOrderChanged(BuildContext context, PlaceOrderState state) {
    final placed = state.placed;
    final failure = state.failure;
    if (placed != null) {
      _openTracking(context, placed);
    } else if (failure != null) {
      showSnack(
        context,
        failure.message,
        action: failure.outcomeUnknown
            ? SnackBarAction(
                label: 'Retry',
                onPressed: context.read<PlaceOrderCubit>().placeDemoOrder,
              )
            : null,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => PlaceOrderCubit(context.read<OrderRepository>()),
      child: BlocListener<PlaceOrderCubit, PlaceOrderState>(
        listener: _onPlaceOrderChanged,
        child: Scaffold(
          appBar: AppBar(title: const Text('Your orders'), actions: const [SignOutButton()]),
          body: OrdersView(
            emptyMessage: 'No orders yet. Place a demo order to follow it.',
            itemBuilder: (order, _) =>
                OrderCard(order: order, onTap: () => _openTracking(context, order)),
          ),
          floatingActionButton: const _PlaceOrderButton(),
        ),
      ),
    );
  }
}

class _PlaceOrderButton extends StatelessWidget {
  const _PlaceOrderButton();

  @override
  Widget build(BuildContext context) {
    final submitting = context.select((PlaceOrderCubit cubit) => cubit.state.submitting);

    return FloatingActionButton.extended(
      onPressed: submitting ? null : context.read<PlaceOrderCubit>().placeDemoOrder,
      icon: const Icon(Icons.add),
      label: Text(submitting ? 'Placing…' : 'Place a demo order'),
    );
  }
}
