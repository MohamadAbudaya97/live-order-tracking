import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/models/order.dart';
import '../data/models/order_status.dart';
import '../data/order_repository.dart';
import '../logic/courier_delivery_cubit.dart';
import 'widgets/snack.dart';
import 'widgets/tracking_map.dart';

class CourierDeliveryScreen extends StatelessWidget {
  const CourierDeliveryScreen({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => CourierDeliveryCubit(context.read<OrderRepository>(), order),
      child: const _DeliveryView(),
    );
  }
}

class _DeliveryView extends StatelessWidget {
  const _DeliveryView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<CourierDeliveryCubit>();

    return BlocConsumer<CourierDeliveryCubit, CourierDeliveryState>(
      listenWhen: (_, current) => current.failure != null,
      listener: (context, state) => showSnack(context, state.failure!.message),
      builder: (context, state) {
        final order = state.order;
        final carrying = order.status == OrderStatus.pickedUp;
        final idle = carrying && !state.delivering;

        return Scaffold(
          appBar: AppBar(title: Text('Delivery ${order.code}')),
          body: Column(
            children: [
              Expanded(
                child: TrackingMap(
                  pickup: order.pickup,
                  dropoff: order.dropoff,
                  courier: order.courierLocation,
                ),
              ),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      carrying
                          ? '${order.pickup.label} to ${order.dropoff.label}, for ${order.customerName}'
                          : 'Delivered to ${order.customerName}',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    if (state.step > 0) ...[
                      LinearProgressIndicator(value: state.step / CourierDeliveryCubit.routeSteps),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: idle && !state.walking ? cubit.simulateRoute : null,
                            child: const Text('Simulate route'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: idle ? cubit.markDelivered : null,
                            child: const Text('Delivered'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
