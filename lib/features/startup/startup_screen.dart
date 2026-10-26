import 'dart:async';

import 'package:flutter/material.dart';

import '../../widgets/app_states.dart';
import 'startup_view_model.dart';

class StartupScreen extends StatefulWidget {
  const StartupScreen({
    super.key,
    required this.initialize,
    required this.dashboard,
  });
  final AppInitializer initialize;
  final Widget dashboard;

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen>
    with TickerProviderStateMixin {
  static const _background = Color(0xFFF4EFFF);
  static const _brandColor = Color(0xFF6F4BB8);
  late final StartupViewModel _model;
  late final AnimationController _entranceAndHold;
  late final AnimationController _exit;
  late final Animation<double> _entranceFade;
  late final Animation<double> _exitFade;
  bool _dashboardMounted = false;
  bool _dashboardShown = false;

  @override
  void initState() {
    super.initState();
    _model = StartupViewModel(widget.initialize)..addListener(_maybeExit);
    // Initialization runs concurrently with a 400ms entrance and 1200ms hold.
    // The 300ms crossfade makes the minimum presentation 1900ms in total.
    // Preserve timing even when visual motion is disabled by accessibility.
    _entranceAndHold = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
      animationBehavior: AnimationBehavior.preserve,
    )..addListener(_maybeExit);
    _exit =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 300),
          animationBehavior: AnimationBehavior.preserve,
        )..addListener(() {
          if (_exit.value == 1 && mounted && !_dashboardShown) {
            _exit.stop();
            setState(() => _dashboardShown = true);
          }
        });
    _entranceFade = _entranceAndHold.drive(
      CurveTween(curve: const Interval(0, 0.25, curve: Curves.easeOutCubic)),
    );
    _exitFade = Tween(begin: 1.0, end: 0.0).animate(_exit);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _entranceAndHold.forward();
      unawaited(_model.initialize());
    });
  }

  void _maybeExit() {
    if (!mounted ||
        _dashboardMounted ||
        _model.state != StartupState.ready ||
        _entranceAndHold.value < 1) {
      return;
    }
    // Mount the dashboard once beneath the fading splash. Its state remains in
    // the same tree position after the overlay leaves, so it never loads twice.
    setState(() => _dashboardMounted = true);
    _entranceAndHold.stop();
    _exit.forward();
  }

  @override
  void dispose() {
    _model.removeListener(_maybeExit);
    _model.dispose();
    _entranceAndHold.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _model,
    builder: (context, _) {
      final reducedMotion =
          MediaQuery.disableAnimationsOf(context) ||
          MediaQuery.accessibleNavigationOf(context);
      return Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(
            excluding: !_dashboardShown,
            child: IgnorePointer(
              ignoring: !_dashboardShown,
              child: _dashboardMounted
                  ? widget.dashboard
                  : const SizedBox.expand(),
            ),
          ),
          if (!_dashboardShown)
            Positioned.fill(
              child: FadeTransition(
                key: const ValueKey('startup-exit'),
                opacity: reducedMotion
                    ? const AlwaysStoppedAnimation(1)
                    : _exitFade,
                child: AbsorbPointer(
                  absorbing: _dashboardMounted,
                  child: _splash(context, reducedMotion),
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _wordmark(BuildContext context, bool reducedMotion) => FadeTransition(
    key: const ValueKey('startup-fade'),
    opacity: reducedMotion || _model.state == StartupState.error
        ? const AlwaysStoppedAnimation(1)
        : _entranceFade,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Semantics(
        header: true,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'FlashQuest',
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              fontSize: 44,
              fontWeight: FontWeight.bold,
              color: _brandColor,
              letterSpacing: -1.2,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _splash(BuildContext context, bool reducedMotion) => Scaffold(
    backgroundColor: _background,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wordmark = _wordmark(context, reducedMotion);
          if (_model.state == StartupState.error) {
            return SingleChildScrollView(
              key: const ValueKey('startup-scroll'),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 32,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          wordmark,
                          const SizedBox(height: 32),
                          InlineError(message: _model.error!),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            key: const ValueKey('retry-startup'),
                            onPressed: _model.initialize,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
          return Stack(
            children: [
              Center(child: wordmark),
              Positioned(
                left: 24,
                right: 24,
                bottom: constraints.maxHeight < 440 ? 16 : 32,
                child: Semantics(
                  container: true,
                  label: 'Getting your flashcards ready...',
                  child: ExcludeSemantics(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: reducedMotion
                              ? const Icon(
                                  Icons.hourglass_empty_rounded,
                                  size: 18,
                                  color: _brandColor,
                                )
                              : const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _brandColor,
                                ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            'Getting your flashcards ready...',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: _brandColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
