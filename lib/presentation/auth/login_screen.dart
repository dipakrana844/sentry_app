import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../core/sentry/sentry_config.dart';
import '../../domain/entities/user.dart';
import 'login_controller.dart';

/// Login screen with proper form validation and error handling.
///
/// **Sentry integration:**
/// - Tracks form interactions as breadcrumbs
/// - Captures validation errors
/// - Monitors login performance
/// - Handles all error scenarios (invalid credentials, 500 errors, network issues)
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    // Start screen load transaction
    final transaction = SentryConfig.startScreenTransaction('login_screen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SentryConfig.finishScreenTransaction(transaction);
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      SentryConfig.addBreadcrumb(
        'Login form validation failed',
        category: 'auth',
        level: SentryLevel.warning,
      );
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    // Log form submission
    SentryConfig.addBreadcrumb(
      'Login form submitted',
      category: 'user.action',
      data: {'email': email},
    );

    await ref.read(loginControllerProvider.notifier).login(email, password);
  }

  void _simulateExpiredToken() {
    SentryConfig.addBreadcrumb(
      'Simulating expired token scenario',
      category: 'auth',
      level: SentryLevel.warning,
    );

    // Simulate expired token error
    SentryConfig.captureException(
      Exception('Token expired: Please login again'),
      hint: Hint.withMap({
        'error_type': 'expired_token',
        'http_status': 401,
        'message': 'Your session has expired. Please login again.',
      }),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Expired token error simulated and sent to Sentry'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loginState = ref.watch(loginControllerProvider);

    // Navigate to dashboard on successful login.
    // Riverpod requires listen calls inside build for ConsumerState.
    ref.listen<AsyncValue<User?>>(loginControllerProvider, (previous, next) {
      if (next.hasValue && next.value != null && mounted) {
        context.go('/dashboard');
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('FieldOps Login'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                // Logo/Title
                const Icon(
                  Icons.work_outline,
                  size: 80,
                  color: Colors.blueAccent,
                ),
                const SizedBox(height: 16),
                const Text(
                  'FieldOps',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Field Operations Management',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                ),
                const SizedBox(height: 48),

                // Email field
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      SentryConfig.addBreadcrumb(
                        'Email validation failed: empty',
                        category: 'validation',
                        level: SentryLevel.warning,
                      );
                      return 'Please enter your email';
                    }
                    if (!value.contains('@')) {
                      SentryConfig.addBreadcrumb(
                        'Email validation failed: invalid format',
                        category: 'validation',
                        level: SentryLevel.warning,
                      );
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                  onChanged: (value) {
                    SentryConfig.addBreadcrumb(
                      'Email field changed',
                      category: 'user.input',
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Password field
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      SentryConfig.addBreadcrumb(
                        'Password validation failed: empty',
                        category: 'validation',
                        level: SentryLevel.warning,
                      );
                      return 'Please enter your password';
                    }
                    if (value.length < 3) {
                      SentryConfig.addBreadcrumb(
                        'Password validation failed: too short',
                        category: 'validation',
                        level: SentryLevel.warning,
                      );
                      return 'Password must be at least 3 characters';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _handleLogin(),
                ),
                const SizedBox(height: 24),

                // Login button
                ElevatedButton(
                  onPressed: loginState.isLoading ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: loginState.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Login'),
                ),

                // Error display
                if (loginState.hasError) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      border: Border.all(color: Colors.red[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            loginState.error.toString().replaceAll(
                              'Exception: ',
                              '',
                            ),
                            style: TextStyle(color: Colors.red[700]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),

                // Debug actions (only in debug mode)
                if (const bool.fromEnvironment('dart.vm.product') == false) ...[
                  const Text(
                    'Debug Actions',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      _emailController.text = 'user@fieldops.com';
                      _passwordController.text = 'password';
                    },
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('Fill Test Credentials'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[100],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      _emailController.text = 'user@fieldops.com';
                      _passwordController.text = 'wrong';
                    },
                    icon: const Icon(Icons.error_outline),
                    label: const Text('Test Invalid Credentials'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[100],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _simulateExpiredToken,
                    icon: const Icon(Icons.access_time),
                    label: const Text('Simulate Expired Token'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[100],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      throw Exception(
                        'Intentional Crash: Login Screen Exception',
                      );
                    },
                    icon: const Icon(Icons.bug_report),
                    label: const Text('TRIGGER CRASH'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
