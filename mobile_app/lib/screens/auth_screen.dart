import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../providers/socket_provider.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'camera_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  bool _isLogin = true;
  bool _isLoading = false;
  String? _error;

  late AnimationController _anim;
  late Animation<double> _fadeAnim;

  final _emailCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _passwordVisible = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _anim, curve: Curves.easeIn);
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    _emailCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isLogin = !_isLogin;
      _error = null;
    });
    _anim.forward(from: 0);
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final username = _usernameCtrl.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Completează toate câmpurile');
      return;
    }
    if (!_isLogin && username.isEmpty) {
      setState(() => _error = 'Completează username-ul');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      final socketProvider = context.read<SocketProvider>();
      AuthService.serverUrl = socketProvider.serverUrl;

      late final String token;
      late final AuthUser user;

      if (_isLogin) {
        final result = await AuthService.login(email: email, password: password);
        token = result.token;
        user = result.user;
      } else {
        final result = await AuthService.register(email: email, username: username, password: password);
        token = result.token;
        user = result.user;
      }

      await AuthService.saveToken(token, user);

      if (mounted) {
        context.read<AppStateProvider>().setUsername(user.username);
        _navigateToCamera();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _navigateToCamera() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CameraScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: Stack(
        children: [
          // Neon background grid
          CustomPaint(painter: _GridBgPainter(), size: Size.infinite),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo
                      _buildLogo(),
                      const SizedBox(height: 40),

                      // Card
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppTheme.darkBgSecondary,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.neonCyan.withOpacity(0.4), width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.neonCyan.withOpacity(0.08),
                              blurRadius: 30,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Tab switcher
                            _buildTabSwitcher(),
                            const SizedBox(height: 24),

                            // Email field
                            _buildField(
                              controller: _emailCtrl,
                              label: 'Email',
                              icon: Icons.alternate_email,
                              keyboardType: TextInputType.emailAddress,
                            ),

                            // Username (register only)
                            if (!_isLogin) ...[
                              const SizedBox(height: 14),
                              _buildField(
                                controller: _usernameCtrl,
                                label: 'Username',
                                icon: Icons.person_outline,
                              ),
                            ],

                            const SizedBox(height: 14),

                            // Password field
                            _buildField(
                              controller: _passwordCtrl,
                              label: 'Parolă',
                              icon: Icons.lock_outline,
                              obscure: !_passwordVisible,
                              suffix: IconButton(
                                icon: Icon(
                                  _passwordVisible ? Icons.visibility_off : Icons.visibility,
                                  color: AppTheme.neonCyan.withOpacity(0.6),
                                  size: 20,
                                ),
                                onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                              ),
                            ),

                            // Error
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppTheme.neonRed.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.neonRed.withOpacity(0.4)),
                                ),
                                child: Text(
                                  _error!,
                                  style: const TextStyle(color: AppTheme.neonRed, fontSize: 13),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],

                            const SizedBox(height: 24),

                            // Submit button
                            _buildSubmitButton(),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Toggle login/register
                      GestureDetector(
                        onTap: _toggle,
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(color: Colors.white54, fontSize: 14),
                            children: [
                              TextSpan(text: _isLogin ? 'Nu ai cont? ' : 'Ai deja cont? '),
                              TextSpan(
                                text: _isLogin ? 'Înregistrează-te' : 'Autentifică-te',
                                style: const TextStyle(
                                  color: AppTheme.neonCyan,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.neonCyan, width: 2),
            boxShadow: [BoxShadow(color: AppTheme.neonCyan.withOpacity(0.4), blurRadius: 20)],
          ),
          child: const Icon(Icons.layers, color: AppTheme.neonCyan, size: 40),
        ),
        const SizedBox(height: 16),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [AppTheme.neonCyan, AppTheme.neonPurple],
          ).createShader(bounds),
          child: const Text(
            'iTEC OVERRIDE',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 4),
          ),
        ),
        const SizedBox(height: 4),
        const Text('BATTLE ARENA', style: TextStyle(color: Colors.white38, fontSize: 12, letterSpacing: 3)),
      ],
    );
  }

  Widget _buildTabSwitcher() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _buildTab('AUTENTIFICARE', _isLogin),
          _buildTab('ÎNREGISTRARE', !_isLogin),
        ],
      ),
    );
  }

  Widget _buildTab(String label, bool active) {
    return Expanded(
      child: GestureDetector(
        onTap: active ? null : _toggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppTheme.neonCyan.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: active ? Border.all(color: AppTheme.neonCyan.withOpacity(0.5)) : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? AppTheme.neonCyan : Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      cursorColor: AppTheme.neonCyan,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 14),
        prefixIcon: Icon(icon, color: AppTheme.neonCyan.withOpacity(0.7), size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppTheme.darkBg,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.neonCyan.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.neonCyan, width: 1.5),
        ),
      ),
      onSubmitted: (_) => _submit(),
    );
  }

  Widget _buildSubmitButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _submit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: _isLoading
                ? [AppTheme.neonCyan.withOpacity(0.3), AppTheme.neonPurple.withOpacity(0.3)]
                : [AppTheme.neonCyan.withOpacity(0.8), AppTheme.neonPurple.withOpacity(0.8)],
          ),
          boxShadow: _isLoading
              ? null
              : [BoxShadow(color: AppTheme.neonCyan.withOpacity(0.3), blurRadius: 16)],
        ),
        child: Center(
          child: _isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  _isLogin ? 'INTRĂ ÎN ARENĂ' : 'CREEAZĂ CONT',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
        ),
      ),
    );
  }
}

class _GridBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.neonCyan.withOpacity(0.04)
      ..strokeWidth = 0.5;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridBgPainter old) => false;
}
