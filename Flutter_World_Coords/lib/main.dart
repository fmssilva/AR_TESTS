import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/ar/ar_session_bridge.dart';
import 'core/config/ar_config_loader.dart';
import 'features/calibration/cubit/calibration_cubit.dart';
import 'features/wall_view/cubit/wall_view_cubit.dart';
import 'features/wall_view/presentation/wall_viewport_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ARWallApp());
}

class ARWallApp extends StatelessWidget {
  ARWallApp({super.key});

  final ARSessionBridge _bridge = ARSessionBridge();
  final ARConfigLoader _configLoader = ARConfigLoader();

  // Build the root MaterialApp with the WallViewCubit provided at top level.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AR Wall',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => WallViewCubit(
              bridge: _bridge,
              configLoader: _configLoader,
              // Set to true during development to show debug axes and wireframes.
              debugMode: true,
            ),
          ),
          BlocProvider(
            create: (_) => CalibrationCubit(bridge: _bridge),
          ),
        ],
        child: const WallViewportPage(),
      ),
    );
  }
}
