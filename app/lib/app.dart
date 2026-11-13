import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/api_client.dart';
import 'core/config.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/data/session.dart';
import 'features/auth/logic/auth_cubit.dart';
import 'features/auth/ui/sign_in_screen.dart';
import 'features/orders/data/order_repository.dart';
import 'features/orders/data/tracking_socket.dart';
import 'features/orders/logic/orders_cubit.dart';
import 'features/orders/ui/customer_orders_screen.dart';
import 'features/orders/ui/staff_orders_screen.dart';

class App extends StatelessWidget {
  const App({super.key});

  static const _seed = Color(0xFF0F766E);

  @override
  Widget build(BuildContext context) {
    // Everything is provided above the navigator, so pushed screens can reach
    // it as well as the home screen.
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (_) => ApiClient(baseUrl: apiUrl)),
        RepositoryProvider(create: (context) => AuthRepository(context.read<ApiClient>())),
        RepositoryProvider(create: (context) => OrderRepository(context.read<ApiClient>())),
        RepositoryProvider<TrackingSocketFactory>(
          create: (_) =>
              (token) => SocketIoTrackingSocket(baseUrl: apiUrl, token: token),
        ),
      ],
      child: BlocProvider(
        create: (context) => AuthCubit(context.read<AuthRepository>()),
        child: MaterialApp(
          title: 'Live Order Tracking',
          theme: ThemeData(colorSchemeSeed: _seed),
          darkTheme: ThemeData(colorSchemeSeed: _seed, brightness: Brightness.dark),
          home: const _Home(),
        ),
      ),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    final session = context.select((AuthCubit cubit) => cubit.state.session);
    if (session == null) return const SignInScreen();

    return BlocProvider(
      create: (context) => OrdersCubit(context.read<OrderRepository>())..load(),
      child: switch (session.user.role) {
        Role.customer => CustomerOrdersScreen(session: session),
        Role.store || Role.courier => StaffOrdersScreen(session: session),
      },
    );
  }
}
