package com.arwall.ar_wall_app

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.ComponentActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.arwall.ar_wall_app.ar.NativeARViewFactory
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val CAMERA_PERMISSION_CODE = 1001
        const val METHOD_CHANNEL = "com.tileapp/ar_methods"
        const val EVENT_CHANNEL  = "com.tileapp/ar_events"
        const val VIEW_TYPE      = "com.tileapp/native_ar_view"
    }

    // Register the ARCore platform view factory and the method + event channels.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine.platformViewsController.registry.registerViewFactory(
            VIEW_TYPE,
            NativeARViewFactory(
                messenger = flutterEngine.dartExecutor.binaryMessenger,
                methodChannelName = METHOD_CHANNEL,
                eventChannelName = EVENT_CHANNEL,
                activity = this
            )
        )
    }

    // Request CAMERA at runtime — required for ARCore on Android 6+.
    // The manifest declaration alone is not sufficient; we must ask the user.
    override fun onStart() {
        super.onStart()
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
                != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.CAMERA),
                CAMERA_PERMISSION_CODE
            )
        }
    }
}

