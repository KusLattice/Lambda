import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Enum para el modo de autenticación principal
enum _AuthMode { email, phone }

// Enum para los pasos del flujo de autenticación por teléfono
enum _PhoneAuthState { idle, codeSent }

class LoginScreen extends ConsumerStatefulWidget {
  static const String routeName = '/login';
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  // --- State Variables ---
  late AnimationController _animationController;
  late Animation<double> _glow;

  // Controllers para el flujo de Email
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoginView = true;
  bool _obscurePassword = true;
  bool _rememberMe = false;

  // State y Controllers para el flujo de Teléfono
  _AuthMode _authMode = _AuthMode.email;
  _PhoneAuthState _phoneAuthState = _PhoneAuthState.idle;
  bool _isSendingCode = false; // loading local para el paso de envío de SMS
  final _phoneController = TextEditingController();
  final _smsController = TextEditingController();
  String? _verificationId;

  // Timer para código SMS
  Timer? _resendTimer;
  int _resendSeconds = 60;

  // --- Lifecycle Methods ---
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _glow = Tween<double>(begin: 2.0, end: 35.0).animate(_animationController);
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('saved_email');
    final savedPassword = prefs.getString('saved_password');
    if (savedEmail != null && savedPassword != null) {
      if (mounted) {
        setState(() {
          _emailController.text = savedEmail;
          _passwordController.text = savedPassword;
          _rememberMe = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _animationController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _smsController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        if (_resendSeconds > 0) {
          setState(() => _resendSeconds--);
        } else {
          timer.cancel();
        }
      } else {
        timer.cancel();
      }
    });
  }

  // --- Logic & Handlers ---
  void _showError(Object error) {
    if (!mounted) return;

    String errorMessage = error.toString();

    // Desempaquetar errores específicos de Firebase para dar un mensaje más útil
    if (error is FirebaseException) {
      errorMessage = error.message ?? 'Ocurrió un error en la base de datos.';
    }

    // Simplificar el texto visual quitando prefijos de error
    errorMessage = errorMessage.replaceAll('Exception: ', '').trim();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(
          errorMessage,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  // --- Build Methods ---
  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    ref.listen<AsyncValue<User?>>(authProvider, (_, next) {
      next.when(
        data: (_) {
          // Lógica pasiva: main.dart gestiona la navegación al detectar el usuario.
        },
        loading: () {}, // El build se encarga del loading indicator
        error: (error, stack) => _showError(error),
      );
    });

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(30.0, 30.0, 30.0, 50.0),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: authState.isLoading ? _buildLoadingView() : _buildAuthFlow(),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthFlow() {
    switch (_authMode) {
      case _AuthMode.email:
        return _buildEmailFlow();
      case _AuthMode.phone:
        return _buildPhoneFlow();
    }
  }

  Widget _buildLoadingView() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 20),
        Text(
          'Verificando credenciales...',
          style: TextStyle(color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildEmailFlow() {
    final authState = ref.watch(authProvider);
    final isLoading = authState.isLoading;

    final showGoogleButton = defaultTargetPlatform != TargetPlatform.windows;

    return Column(
      key: const ValueKey('emailFlow'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLogo(),
        const SizedBox(height: 40),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: _isLoginView
                ? 'Apodo o Correo Electrónico'
                : 'Correo Electrónico',
            labelStyle: const TextStyle(color: Colors.white54),
            border: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.greenAccent),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 16,
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Contraseña',
            labelStyle: const TextStyle(color: Colors.white54),
            border: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.greenAccent),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 16,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: Colors.white70,
              ),
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
          ),
        ),
        if (_isLoginView) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Theme(
                    data: ThemeData(unselectedWidgetColor: Colors.white54),
                    child: Checkbox(
                      value: _rememberMe,
                      onChanged: (value) {
                        setState(() {
                          _rememberMe = value ?? false;
                        });
                      },
                      activeColor: Colors.greenAccent,
                      checkColor: Colors.black,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _rememberMe = !_rememberMe;
                      });
                    },
                    child: const Text(
                      'Recordarme',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: isLoading ? null : _recoverPassword,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(50, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  '¿Olvidaste tu contraseña?',
                  style: TextStyle(color: Colors.greenAccent, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ] else ...[
          const SizedBox(height: 24),
        ],
        SizedBox(
          width: double.infinity,
          height: 50,
          child: TextButton(
            onPressed: isLoading ? null : _submitEmail,
            style: TextButton.styleFrom(foregroundColor: Colors.greenAccent),
            child: Text(
              _isLoginView ? 'INGRESAR' : 'REGISTRARSE',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildDivider(),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            if (showGoogleButton)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: SizedBox(
                    height: 48,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(
                            color: Colors.white24,
                            width: 1.5,
                          ),
                        ),
                      ),
                      onPressed: isLoading
                          ? null
                          : () => ref
                                .read(authProvider.notifier)
                                .signInWithGoogle(),
                      icon: const Icon(
                        Icons.g_mobiledata,
                        size: 28,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'con Google',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: showGoogleButton ? 8.0 : 0.0),
                child: SizedBox(
                  height: 48,
                  child: TextButton.icon(
                    onPressed: isLoading
                        ? null
                        : () => setState(() => _authMode = _AuthMode.phone),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: _authMode == _AuthMode.phone
                              ? Colors.greenAccent
                              : Colors.white24,
                          width: 1.5,
                        ),
                      ),
                    ),
                    icon: Icon(
                      Icons.phone_android,
                      size: 20,
                      color: _authMode == _AuthMode.phone
                          ? Colors.greenAccent
                          : Colors.white,
                    ),
                    label: Text(
                      'Teléfono',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.2,
                        color: _authMode == _AuthMode.phone
                            ? Colors.greenAccent
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        TextButton(
          onPressed: isLoading
              ? null
              : () => setState(() => _isLoginView = !_isLoginView),
          child: Text(
            _isLoginView
                ? '¿No tienes cuenta? Regístrate'
                : '¿Ya tienes cuenta? Inicia Sesión',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneFlow() {
    return Column(
      key: const ValueKey('phoneFlow'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLogo(),
        const SizedBox(height: 50),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _phoneAuthState == _PhoneAuthState.idle
              ? _buildPhoneInputView()
              : _buildSmsInputView(),
        ),
        const SizedBox(height: 20),
        TextButton(
          onPressed: ref.watch(authProvider).isLoading
              ? null
              : () => setState(() {
                  _authMode = _AuthMode.email;
                  _phoneAuthState = _PhoneAuthState.idle;
                }),
          child: const Text('Volver a otros métodos'),
        ),
      ],
    );
  }

  Widget _buildPhoneInputView() {
    return Column(
      key: const ValueKey('phoneInput'),
      children: [
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Número de Teléfono',
            hintText: '+569xxxxxxxx',
            labelStyle: TextStyle(color: Colors.white54),
            hintStyle: TextStyle(color: Colors.white24),
            border: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.greenAccent),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: TextButton(
            onPressed: _isSendingCode ? null : _submitPhoneNumber,
            style: TextButton.styleFrom(foregroundColor: Colors.greenAccent),
            child: _isSendingCode
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.greenAccent,
                    ),
                  )
                : const Text(
                    'ENVIAR CÓDIGO',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSmsInputView() {
    return Column(
      key: const ValueKey('smsInput'),
      children: [
        TextField(
          controller: _smsController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            letterSpacing: 8.0,
            fontSize: 18,
          ),
          decoration: const InputDecoration(
            labelText: 'Código SMS',
            labelStyle: TextStyle(color: Colors.white54, letterSpacing: 0),
            border: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.greenAccent),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: TextButton(
            onPressed: ref.watch(authProvider).isLoading
                ? null
                : _submitSmsCode,
            style: TextButton.styleFrom(foregroundColor: Colors.greenAccent),
            child: const Text(
              'VERIFICAR Y ENTRAR',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _resendSeconds > 0
              ? 'El código expirará en $_resendSeconds s'
              : 'El código ha expirado.',
          style: TextStyle(
            color: _resendSeconds > 0 ? Colors.white54 : Colors.redAccent,
            fontSize: 13,
          ),
        ),
        if (_resendSeconds == 0) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              setState(() => _phoneAuthState = _PhoneAuthState.idle);
              _submitPhoneNumber();
            },
            child: const Text(
              'Reenviar Código',
              style: TextStyle(color: Colors.greenAccent),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.greenAccent.withAlpha(128),
                blurRadius: _glow.value,
                spreadRadius: _glow.value / 3,
              ),
            ],
          ),
          child: const Text(
            'λ',
            style: TextStyle(
              fontSize: 120,
              color: Colors.greenAccent,
              fontWeight: FontWeight.w100,
            ),
          ),
        );
      },
    );
  }

  Widget _buildDivider() {
    return const Row(
      children: [
        Expanded(child: Divider(color: Colors.white24)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text('o', style: TextStyle(color: Colors.white24)),
        ),
        Expanded(child: Divider(color: Colors.white24)),
      ],
    );
  }

  // --- Submission Logic ---
  Future<void> _recoverPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showError(
        'Por favor, ingresa un correo electrónico válido arriba para recuperar tu contraseña.',
      );
      return;
    }

    try {
      await ref.read(authProvider.notifier).sendPasswordResetEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          content: Text('Se ha enviado un enlace de recuperación a $email'),
        ),
      );
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _submitEmail() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      _showError('Ambos campos son obligatorios.');
      return;
    }

    if (!_isLoginView && !email.contains('@')) {
      _showError(
        'Para registrarte, debes usar un correo electrónico válido, no un apodo.',
      );
      return;
    }

    final authNotifier = ref.read(authProvider.notifier);
    if (_isLoginView) {
      await authNotifier.login(email, password);
      if (mounted) {
        final authState = ref.read(authProvider);
        if (!authState.hasError && authState.value != null) {
          final prefs = await SharedPreferences.getInstance();
          if (_rememberMe) {
            await prefs.setString('saved_email', email);
            await prefs.setString('saved_password', password);
          } else {
            await prefs.remove('saved_email');
            await prefs.remove('saved_password');
          }
        }
      }
    } else {
      await authNotifier.signUp(email, password);
    }
  }

  Future<void> _submitPhoneNumber() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _showError('El número de teléfono es obligatorio.');
      return;
    }

    setState(() => _isSendingCode = true);
    try {
      final authNotifier = ref.read(authProvider.notifier);
      await authNotifier.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (credential) async {
          // Auto-retrieval (Android only)
          final authNotifier = ref.read(authProvider.notifier);
          await authNotifier.signInWithSmsCode(
            credential.verificationId!,
            credential.smsCode!,
          );
        },
        verificationFailed: (e) {
          if (mounted) setState(() => _isSendingCode = false);
          _showError('Error de verificación: ${e.message}');
        },
        codeSent: (verificationId, forceResendingToken) {
          if (mounted) {
            setState(() {
              _isSendingCode = false;
              _verificationId = verificationId;
              _phoneAuthState = _PhoneAuthState.codeSent;
            });
            _startResendTimer();
          }
        },
        codeAutoRetrievalTimeout: (verificationId) {
          if (mounted) {
            setState(() {
              _isSendingCode = false;
              _verificationId = verificationId;
              _resendSeconds = 0; // Expiró el tiempo de firebase
            });
            _resendTimer?.cancel();
          }
        },
      );
    } catch (e) {
      if (mounted) setState(() => _isSendingCode = false);
      _showError(e);
    }
  }

  Future<void> _submitSmsCode() async {
    final code = _smsController.text.trim();
    if (code.isEmpty || _verificationId == null) {
      _showError('El código SMS es obligatorio.');
      return;
    }
    final authNotifier = ref.read(authProvider.notifier);
    await authNotifier.signInWithSmsCode(_verificationId!, code);
  }
}
