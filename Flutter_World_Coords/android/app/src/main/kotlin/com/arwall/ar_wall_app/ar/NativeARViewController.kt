package com.arwall.ar_wall_app.ar

import android.content.Context
import android.graphics.BitmapFactory
import android.opengl.Matrix
import android.view.View
import androidx.activity.ComponentActivity
import com.google.ar.core.AugmentedImage
import com.google.ar.core.AugmentedImageDatabase
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import dev.romainguy.kotlin.math.Float3
import io.github.sceneview.ar.ARSceneView
import io.github.sceneview.ar.arcore.getUpdatedAugmentedImages
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.io.InputStream
import kotlin.math.sqrt

// Native ARCore view controller - the bridge between Flutter platform channels
// and the live ARCore + SceneView render loop.
// One instance is created per Flutter PlatformView lifecycle.
class NativeARViewController(
    private val context: Context,
    messenger: BinaryMessenger,
    methodChannelName: String,
    eventChannelName: String,
    activity: ComponentActivity
) : PlatformView, EventChannel.StreamHandler {

    // ARSceneView needs the ComponentActivity for ARCore session lifecycle management
    // (permission checks, session resume/pause tied to Activity lifecycle) and
    // the Lifecycle so it auto-starts the ARCore session when the activity resumes.
    // Positional constructor: (context, attrs=null, defStyleAttr=0, defStyleRes=0, activity, lifecycle)
    private val arSceneView = ARSceneView(context, null, 0, 0, activity, activity.lifecycle)
    private val methodChannel = MethodChannel(messenger, methodChannelName)
    private val eventChannel  = EventChannel(messenger, eventChannelName)
    private var eventSink: EventChannel.EventSink? = null

    // ARCore Session captured from onSessionCreated — needed for image DB setup and
    // for explicit pause/resume calls (ARSceneView.pause/resume take no useful arguments).
    private var capturedSession: Session? = null
    // Anchors that arrived before the session was ready; applied on session creation.
    private var pendingAnchors: List<AnchorBlueprintNative>? = null

    private val worldCoordinateManager = WorldCoordinateManager(arSceneView)
    private val diagnosticRenderer     = DiagnosticRenderer(arSceneView)
    private var poiNodeBuilder: POINodeBuilder? = null
    private var debugMode = false

    // Track which anchors we have already sent a detected event for this frame
    // to avoid flooding the channel on every tracking update.
    private val reportedAnchors = mutableSetOf<String>()
    private val lastPoiVisibility = mutableMapOf<String, Boolean>()
    private val lastTrackingMethods = mutableMapOf<String, AugmentedImage.TrackingMethod>()

    // Throttle the per-frame log so we print once every N updates.
    private var sessionUpdateCount = 0

    init {
        android.util.Log.d("ARController",
            "[INIT] NativeARViewController created — wiring channels")
        eventChannel.setStreamHandler(this)
        setupMethodChannel()
        setupARSessionCallbacks()
        android.util.Log.d("ARController",
            "[INIT] NativeARViewController init complete — ready to receive method calls")
    }

    override fun getView(): View = arSceneView

    // Release channels when Flutter disposes the PlatformView.
    // The ARSceneView View will be detached from the window hierarchy by Flutter which
    // triggers its own lifecycle cleanup (onDetachedFromWindow).
    override fun dispose() {
        methodChannel.setMethodCallHandler(null)
        eventSink = null
    }

    // EventChannel.StreamHandler - Flutter side opened the stream.
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        sendEvent(mapOf("type" to "session_ready"))
    }

    // EventChannel.StreamHandler - Flutter side closed the stream.
    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // Send a typed event map to Flutter on the main thread.
    private fun sendEvent(map: Map<String, Any>) {
        arSceneView.post { eventSink?.success(map) }
    }

    // Register MethodChannel handlers for all Flutter -> native commands.
    private fun setupMethodChannel() {
        methodChannel.setMethodCallHandler { call, result ->
            android.util.Log.d("ARController",
                "[METHOD] Received call: '${call.method}' args=${call.arguments?.let { it::class.java.simpleName } ?: "null"}")
            when (call.method) {
                "initializeARSession" -> {
                    val args = call.arguments as? Map<*, *>
                    handleInitialize(args, result)
                }
                "setDebugMode" -> {
                    debugMode = (call.arguments as? Map<*, *>)?.get("enabled") as? Boolean ?: false
                    diagnosticRenderer.setDebugMode(debugMode)
                    result.success("ok")
                }
                "pauseSession"  -> {
                    capturedSession?.pause()
                    result.success("ok")
                }
                "resumeSession" -> {
                    capturedSession?.resume()
                    result.success("ok")
                }
                else -> result.notImplemented()
            }
        }
    }

    // Parse anchor + POI data from the channel, build the image database, and
    // attach all POI nodes under the world root.
    @Suppress("UNCHECKED_CAST")
    private fun handleInitialize(args: Map<*, *>?, result: MethodChannel.Result) {
        android.util.Log.d("ARController",
            "[INIT_ARGS] handleInitialize called — args null? ${args == null}")
        if (args == null) {
            android.util.Log.e("ARController", "[INIT_ARGS] REJECTED: null args")
            result.error("INVALID_ARGS", "null arguments map", null)
            return
        }

        val anchorMaps = args["anchors"] as? List<Map<*, *>> ?: emptyList()
        val poiMaps    = args["pois"]    as? List<Map<*, *>> ?: emptyList()
        debugMode = args["debugMode"] as? Boolean ?: false

        val anchors = anchorMaps.mapNotNull { AnchorBlueprintNative.from(it) }
        val pois    = poiMaps.mapNotNull    { POINative.from(it) }

        android.util.Log.d("ARController",
            "[INIT_ARGS] Raw anchorMaps=${anchorMaps.size} poiMaps=${poiMaps.size}")
        android.util.Log.d("ARController",
            "[INIT_ARGS] Parsed: ${anchors.size} anchors, ${pois.size} POIs — debugMode=$debugMode")

        worldCoordinateManager.registerBlueprints(anchors)
        worldCoordinateManager.registerPOIs(pois)

        // Clear any existing POI nodes before rebuilding.
        poiNodeBuilder?.clearAll()
        poiNodeBuilder = POINodeBuilder(pois, arSceneView, worldCoordinateManager)
        poiNodeBuilder?.buildAll()

        diagnosticRenderer.setDebugMode(debugMode)
        setupImageDatabase(anchors)

        result.success("ok")
    }

    // Register all anchor reference images with ARCore's AugmentedImageDatabase.
    // Preferred source is the Flutter asset bundle path under assets/ar_anchors/.
    // We keep a fallback to the legacy android/app/src/main/assets/ar_anchors/ mirror.
    // If the session is already captured (either from onSessionCreated or from the
    // first onSessionUpdated frame) we configure it immediately; otherwise we queue
    // the anchors in pendingAnchors and let onSessionUpdated apply them on frame 1.
    private fun setupImageDatabase(anchors: List<AnchorBlueprintNative>) {
        android.util.Log.d("ARController",
            "[IMAGE_DB] setupImageDatabase: ${anchors.size} anchors, session=${if (capturedSession != null) "READY" else "NOT_YET_READY"}")
        val session = capturedSession ?: run {
            android.util.Log.w("ARController",
                "[IMAGE_DB] Session not ready — queuing ${anchors.size} anchors for first onSessionUpdated frame")
            pendingAnchors = anchors
            return
        }
        applyImageDatabase(anchors, session)
    }

    private fun applyImageDatabase(anchors: List<AnchorBlueprintNative>, session: Session) {
        android.util.Log.d("ARController",
            "[IMAGE_DB] applyImageDatabase: building DB for ${anchors.size} anchors")
        val db = AugmentedImageDatabase(session)
        var addedCount = 0
        for (anchor in anchors) {
            val flutterAssetPath = "flutter_assets/assets/ar_anchors/${anchor.imageAssetName}.jpg"
            val legacyAssetPath = "ar_anchors/${anchor.imageAssetName}.jpg"
            android.util.Log.d("ARController",
                "[IMAGE_DB] Loading asset for '${anchor.id}' from Flutter assets first: " +
                "'assets/ar_anchors/${anchor.imageAssetName}.jpg' (width=${anchor.physicalWidthMeters}m)")
            try {
                val stream = openAnchorAsset(flutterAssetPath, legacyAssetPath)
                val bitmap = BitmapFactory.decodeStream(stream)
                stream.close()
                if (bitmap == null) {
                    android.util.Log.e("ARController",
                        "[IMAGE_DB] BitmapFactory returned null for '${anchor.imageAssetName}.jpg' — file may be corrupt")
                    continue
                }
                android.util.Log.d("ARController",
                    "[IMAGE_DB] Bitmap decoded: ${bitmap.width}x${bitmap.height}")
                android.util.Log.d("ARController",
                    "[IMAGE_DB] Configured physical width for '${anchor.id}': " +
                    "${anchor.physicalWidthMeters}m (ARCore uses width only; height follows bitmap aspect ratio)")
                db.addImage(anchor.id, bitmap, anchor.physicalWidthMeters)
                addedCount++
                android.util.Log.d("ARController",
                    "[IMAGE_DB] Added '${anchor.id}' (${anchor.physicalWidthMeters}m wide) to AR database")
            } catch (e: Exception) {
                android.util.Log.e("ARController",
                    "[IMAGE_DB] FAILED to load '${anchor.imageAssetName}.jpg' from either " +
                    "Flutter or legacy Android assets: ${e::class.java.simpleName}: ${e.message}")
            }
        }

        if (addedCount == 0) {
            android.util.Log.e("ARController", "No anchor images were loaded — check ar_anchors/ in assets")
            return
        }

        val config = Config(session)
        config.augmentedImageDatabase = db
        config.focusMode   = Config.FocusMode.AUTO
        config.updateMode  = Config.UpdateMode.LATEST_CAMERA_IMAGE
        session.configure(config)

        android.util.Log.d("ARController",
            "ARCore image database configured with $addedCount images")
    }

    // Wire up the per-frame session callbacks.
    private fun setupARSessionCallbacks() {
        // onSessionCreated can fire before we set this callback (lifecycle race when the
        // Activity is already RESUMED at PlatformView creation time).  We therefore do NOT
        // rely on it as the sole trigger for image-DB setup — the first onSessionUpdated
        // frame is the reliable fallback (see below).
        arSceneView.onSessionCreated = { session: Session ->
            android.util.Log.d("ARController",
                "[SESSION] onSessionCreated fired — pendingAnchors=${pendingAnchors?.size ?: 0}")
            capturedSession = session
            if (pendingAnchors != null) {
                android.util.Log.d("ARController",
                    "[SESSION] Applying ${pendingAnchors!!.size} queued anchors via onSessionCreated")
                applyImageDatabase(pendingAnchors!!, session)
                pendingAnchors = null
            } else {
                android.util.Log.d("ARController",
                    "[SESSION] onSessionCreated: no pending anchors yet — will apply when initializeARSession is called")
            }
        }

        // Per-frame update: process all augmented image state changes.
        arSceneView.onSessionUpdated = { session: Session, frame: Frame ->
            // CRITICAL: capture session on the very first frame.
            // This is the reliable fallback for the lifecycle race where onSessionCreated
            // fires before we register the callback above.
            if (capturedSession == null) {
                android.util.Log.d("ARController",
                    "[SESSION] First onSessionUpdated — session captured (onSessionCreated was missed)")
                capturedSession = session
                pendingAnchors?.let {
                    android.util.Log.d("ARController",
                        "[SESSION] Applying ${it.size} pending anchors from first frame")
                    applyImageDatabase(it, session)
                    pendingAnchors = null
                }
            }

            sessionUpdateCount++
            if (sessionUpdateCount == 1) {
                android.util.Log.d("ARController",
                    "[SESSION] onSessionUpdated #1 — session loop confirmed running, " +
                    "imageDB=${if (pendingAnchors == null && capturedSession != null) "CONFIGURED" else "PENDING"}")
            } else if (sessionUpdateCount % 150 == 0) {
                // ~every 5s at 30fps
                android.util.Log.d("ARController",
                    "[SESSION] onSessionUpdated #$sessionUpdateCount — still alive")
            }
            // Throttle: project world positions to screen ~10fps (every 3 frames).
            if (sessionUpdateCount % 3 == 0 && worldCoordinateManager.worldRootNode.isVisible) {
                val viewMatrix = FloatArray(16)
                val projMatrix = FloatArray(16)
                frame.camera.getViewMatrix(viewMatrix, 0)
                frame.camera.getProjectionMatrix(projMatrix, 0, 0.1f, 100f)
                val vw = arSceneView.width.toFloat()
                val vh = arSceneView.height.toFloat()
                arSceneView.post { sendOverlayUpdate(viewMatrix, projMatrix, vw, vh) }
            }

            val updatedImages = frame.getUpdatedAugmentedImages()
            for (image in updatedImages) {
                when (image.trackingState) {
                    TrackingState.TRACKING -> handleAnchorTracked(image, frame)
                    TrackingState.STOPPED  -> {
                        reportedAnchors.remove(image.name)
                        lastTrackingMethods.remove(image.name)
                        worldCoordinateManager.anchorLost(image.name)
                        sendEvent(mapOf(
                            "type" to "anchor_lost",
                            "anchor_id" to image.name
                        ))
                    }
                    else -> Unit
                }
            }
        }

        // Forward POI tap events from 3D scene to Flutter.
        // SceneView 2.2.1 uses setOnGestureListener() with named lambda parameters.
        arSceneView.setOnGestureListener(
            onSingleTapConfirmed = { _: android.view.MotionEvent, node: io.github.sceneview.node.Node? ->
                val tappedName = node?.name
                if (tappedName != null) {
                    sendEvent(mapOf("type" to "poi_tapped", "poi_id" to tappedName))
                }
            }
        )
    }

    // Apply drift correction and send anchor_detected event on first detection.
    private fun handleAnchorTracked(
        image: com.google.ar.core.AugmentedImage,
        frame: Frame
    ) {
        val trackingMethod = image.trackingMethod
        val previousTrackingMethod = lastTrackingMethods.put(image.name, trackingMethod)
        if (previousTrackingMethod != trackingMethod) {
            android.util.Log.d("ARController",
                "[TRACKING] Anchor '${image.name}' method ${previousTrackingMethod?.name ?: "NONE"} -> ${trackingMethod.name}")
        }

        if (trackingMethod != AugmentedImage.TrackingMethod.FULL_TRACKING) {
            worldCoordinateManager.anchorLost(image.name)
            return
        }

        val pose       = image.centerPose
        val cameraPose = frame.camera.pose

        val dx = pose.tx() - cameraPose.tx()
        val dy = pose.ty() - cameraPose.ty()
        val dz = pose.tz() - cameraPose.tz()
        val dist = sqrt((dx * dx + dy * dy + dz * dz).toDouble()).toFloat()

        worldCoordinateManager.applyCorrection(image.name, pose, dist)

        if (image.name !in reportedAnchors) {
            reportedAnchors.add(image.name)
            android.util.Log.d("ARController",
                "[DETECT] Anchor '${image.name}' dist=${String.format("%.2f", dist)}m " +
                "AR_pos=(${f(pose.tx())}, ${f(pose.ty())}, ${f(pose.tz())}) method=${trackingMethod.name}")
            // Log each POI's blueprint position so we can verify coordinates.
            poiNodeBuilder?.builtNodes?.forEach { node ->
                android.util.Log.d("ARController",
                    "[DETECT] POI '${node.name}' blueprint_local=(" +
                    "${f(node.position.x)}, ${f(node.position.y)}, ${f(node.position.z)})")
            }
            sendEvent(mapOf(
                "type"            to "anchor_detected",
                "anchor_id"       to image.name,
                "distance_meters" to dist.toDouble(),
                "detected_x"      to pose.tx().toDouble(),
                "detected_y"      to pose.ty().toDouble(),
                "detected_z"      to pose.tz().toDouble()
            ))
        }
    }

    // Project a 3D world position to normalized viewport coordinates.
    // Returned x/y are in [0,1] relative to the AR view so Flutter can map them
    // into its own logical-pixel canvas without depending on Android pixel density.
    // Returns null if the point is behind the camera or outside the viewport.
    private fun worldToScreen(
        worldPos: Float3,
        viewMatrix: FloatArray,
        projMatrix: FloatArray,
        viewWidth: Float,
        viewHeight: Float
    ): Pair<Float, Float>? {
        val mvp  = FloatArray(16)
        Matrix.multiplyMM(mvp, 0, projMatrix, 0, viewMatrix, 0)
        val clip = FloatArray(4)
        Matrix.multiplyMV(clip, 0, mvp, 0,
            floatArrayOf(worldPos.x, worldPos.y, worldPos.z, 1f), 0)
        if (clip[3] <= 0f) return null  // behind camera
        val ndcX = clip[0] / clip[3]
        val ndcY = clip[1] / clip[3]
        if (ndcX < -1f || ndcX > 1f || ndcY < -1f || ndcY > 1f) return null
        return Pair(
            (ndcX + 1f) / 2f,
            (1f - ndcY) / 2f   // Y flipped: NDC +1 = top, viewport +Y = down
        )
    }

    // Called on main thread (via arSceneView.post) every 3 frames when a valid world transform exists.
    // Reads current worldPositions and projects them to 2D screen coords for Flutter overlay.
    private fun sendOverlayUpdate(
        viewMatrix: FloatArray,
        projMatrix: FloatArray,
        vw: Float,
        vh: Float
    ) {
        fun ws(p: Float3) = worldToScreen(p, viewMatrix, projMatrix, vw, vh)

        val wcm    = worldCoordinateManager
        val origin = ws(wcm.worldRootNode.worldPosition)

        val axisX = ws(wcm.xAxisMarker.worldPosition)
        val axisY = ws(wcm.yAxisMarker.worldPosition)
        val axisZ = ws(wcm.zAxisMarker.worldPosition)

        val fallbackOrigin = origin ?: Pair(Float.NaN, Float.NaN)
        val fallbackAxisX = axisX ?: Pair(Float.NaN, Float.NaN)
        val fallbackAxisY = axisY ?: Pair(Float.NaN, Float.NaN)
        val fallbackAxisZ = axisZ ?: Pair(Float.NaN, Float.NaN)

        val poisList = poiNodeBuilder?.getNodePositions()
            ?.mapNotNull { (id, label, worldPos) ->
                val ss = ws(worldPos) ?: return@mapNotNull null
                mapOf("id" to id, "label" to label, "x" to ss.first, "y" to ss.second)
            } ?: emptyList()

        logPoiVisibilityTransitions(poisList.map { it["id"] as String }.toSet())

        // Deliver directly — already on main thread.
        eventSink?.success(mapOf(
            "type" to "overlay_update",
            "ox"   to fallbackOrigin.first.toDouble(),  "oy"  to fallbackOrigin.second.toDouble(),
            "xx"   to fallbackAxisX.first.toDouble(),   "xy"  to fallbackAxisX.second.toDouble(),
            "yx"   to fallbackAxisY.first.toDouble(),   "yy"  to fallbackAxisY.second.toDouble(),
            "zx"   to fallbackAxisZ.first.toDouble(),   "zy"  to fallbackAxisZ.second.toDouble(),
            "origin_visible" to (origin != null),
            "axis_x_visible" to (axisX != null),
            "axis_y_visible" to (axisY != null),
            "axis_z_visible" to (axisZ != null),
            "pois" to poisList
        ))
    }

    private fun openAnchorAsset(primaryPath: String, fallbackPath: String): InputStream {
        return try {
            context.assets.open(primaryPath)
        } catch (primaryError: Exception) {
            android.util.Log.w("ARController",
                "[IMAGE_DB] Primary Flutter asset path failed: '$primaryPath' " +
                "(${primaryError::class.java.simpleName}: ${primaryError.message}); trying legacy '$fallbackPath'")
            context.assets.open(fallbackPath)
        }
    }

    private fun logPoiVisibilityTransitions(visiblePoiIds: Set<String>) {
        val poiIds = poiNodeBuilder?.builtNodes
            ?.mapNotNull { it.name }
            ?.sorted()
            ?: return

        val changes = mutableListOf<String>()
        for (poiId in poiIds) {
            val isVisible = poiId in visiblePoiIds
            val previous = lastPoiVisibility[poiId]
            if (previous == null || previous != isVisible) {
                changes += "$poiId ${if (previous == true) 1 else 0}->${if (isVisible) 1 else 0}"
                lastPoiVisibility[poiId] = isVisible
            }
        }

        if (changes.isNotEmpty()) {
            android.util.Log.d("ARProjection",
                "[PROJECTION] POI visibility changed: ${changes.joinToString(", ")}")
        }
    }

    private fun f(v: Float) = String.format("%.3f", v)
}
