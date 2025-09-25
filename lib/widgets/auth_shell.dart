import 'package:flutter/material.dart';

/// Shared glassmorphism-style background used by the auth screens.
class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.child,
    this.maxWidth = 480,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF2E335A), Color(0xFF1C1B33)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: Colors.white.withOpacity(0.16)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.28),
                          blurRadius: 32,
                          offset: const Offset(0, 20),
                        ),
                      ],
                    ),
                    child: DefaultTextStyle.merge(
                      style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
                      child: IconTheme.merge(
                        data: const IconThemeData(color: Colors.white70),
                        child: Padding(
                          padding: padding,
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
