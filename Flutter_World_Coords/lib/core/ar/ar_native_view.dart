import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

// Platform-adaptive widget that embeds the native ARCore view.
// On Android, uses PlatformViewLink with a SurfaceAndroidView for correct
// Vulkan/OpenGL compositing. Falls back to an error widget on unsupported platforms.
class ARNativeView extends StatelessWidget {
  /// Called once when the native PlatformView is fully created and its
  /// MethodChannel/EventChannel handlers are registered.
  final VoidCallback? onViewCreated;

  const ARNativeView({super.key, this.onViewCreated});

  static const _viewType = 'com.tileapp/native_ar_view';

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      // SurfaceAndroidView is required for ARCore - it uses a SurfaceTexture
      // which ARCore renders into directly via OpenGL/Vulkan.
      return PlatformViewLink(
        viewType: _viewType,
        surfaceFactory: (context, controller) => AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const {},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        ),
        onCreatePlatformView: (params) =>
            PlatformViewsService.initSurfaceAndroidView(
              id: params.id,
              viewType: _viewType,
              layoutDirection: TextDirection.ltr,
              creationParamsCodec: const StandardMessageCodec(),
            )
              ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
              ..addOnPlatformViewCreatedListener((_) => onViewCreated?.call())
              ..create(),
      );
    }
    return const Center(
      child: Text('AR not supported on this platform'),
    );
  }
}
