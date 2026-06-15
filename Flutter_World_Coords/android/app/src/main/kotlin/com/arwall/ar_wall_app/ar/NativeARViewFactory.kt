package com.arwall.ar_wall_app.ar

import android.content.Context
import androidx.activity.ComponentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

// Instantiates one NativeARViewController per Flutter PlatformView request.
class NativeARViewFactory(
    private val messenger: BinaryMessenger,
    private val methodChannelName: String,
    private val eventChannelName: String,
    private val activity: ComponentActivity
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return NativeARViewController(
            context = context,
            messenger = messenger,
            methodChannelName = methodChannelName,
            eventChannelName = eventChannelName,
            activity = activity
        )
    }
}
