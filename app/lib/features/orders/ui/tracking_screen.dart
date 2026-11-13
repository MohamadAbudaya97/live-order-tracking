import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/data/session.dart';
import '../data/models/order.dart';
import '../data/models/order_status.dart';
import '../data/order_repository.dart';
import '../data/tracking_socket.dart';
import '../logic/order_actions.dart';
import '../logic/order_tracking_bloc.dart';
import 'order_text.dart';
import 'widgets/notice_banner.dart';
import 'widgets/snack.dart';
import 'widgets/status_timeline.dart';
import 'widgets/tracking_map.dart';

class TrackingScreen extends StatelessWidget {
  const TrackingScreen({super.key, required this.order, required this.session});

  /// The order as the list last saw it. Tracking starts from here and asks
  /// the server for whatever happened since.
  final Order order;
  final Session session;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => OrderTrackingBloc(
        order: order,
        repository: context.read<OrderRepository>(),
        socket: context.read<TrackingSocketFactory>()(session.token),
      ),
      child: _TrackingView(user: session.user),
    );
  }
}

class _TrackingView extends StatelessWidget {
  const _TrackingView({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bloc = context.read<OrderTrackingBloc>();

    return BlocConsumer<OrderTrackingBloc, OrderTrackingState>(
      listenWhen: (_, current) => current.cancelFailure != null,
      listener: (context, state) => showSnack(context, state.cancelFailure!.message),
      builder: (context, state) {
        final order = state.order;
        final courierName = order.courierName;
        final canCancel = allowedTransitions(order, user).contains(OrderStatus.cancelled);

        return Scaffold(
          appBar: AppBar(title: Text('Order ${order.code}')),
          body: Column(
            children: [
              if (state.connection == LiveConnection.reconnecting)
                const NoticeBanner(message: 'Connection lost. Reconnecting…')
              else if (state.syncFailed && state.connection == LiveConnection.connected)
                NoticeBanner(
                  message: 'Could not load the latest updates.',
                  action: TextButton(
                    onPressed: () => bloc.add(const TrackingRetryRequested()),
                    child: const Text('Retry'),
                  ),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        height: 260,
                        child: TrackingMap(
                          pickup: order.pickup,
                          dropoff: order.dropoff,
                          courier: order.courierLocation,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${order.pickup.label} to ${order.dropoff.label}',
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      [
                        order.itemsSummary,
                        formatAmount(order.total),
                        if (courierName != null) 'Courier: $courierName',
                      ].join(' · '),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    StatusTimeline(status: order.status),
                    if (canCancel) ...[
                      const SizedBox(height: 24),
                      OutlinedButton(
                        onPressed: state.cancelling
                            ? null
                            : () => bloc.add(const TrackingCancelRequested()),
                        child: const Text('Cancel order'),
                      ),
                    ],
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
