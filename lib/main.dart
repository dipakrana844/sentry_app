import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bootstrap.dart';
import 'core/router/app_router.dart' show createAppRouter;
import 'domain/entities/user.dart';
import 'presentation/auth/login_controller.dart';

Future<void> main() async {
  await bootstrap(
    (autoLoginUser) =>
        ProviderScope(child: MyApp(autoLoginUser: autoLoginUser)),
  );
}

class MyApp extends ConsumerWidget {
  final User? autoLoginUser;

  const MyApp({super.key, this.autoLoginUser});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // If auto-login user exists, set it in the login controller
    if (autoLoginUser != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final controller = ref.read(loginControllerProvider.notifier);
        // Use setUser method which is public
        controller.setUser(autoLoginUser!);
      });
    }

    // Create router with ref for redirect logic
    final router = createAppRouter(ref);

    return MaterialApp.router(
      title: 'FieldOps',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
