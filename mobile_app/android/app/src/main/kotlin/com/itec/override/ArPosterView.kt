package com.itec.override

import android.content.Context
import android.graphics.BitmapFactory
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.opengl.Matrix
import android.os.Handler
import android.os.Looper
import android.view.Surface
import android.view.View
import com.google.ar.core.*
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.google.ar.core.exceptions.UnavailableException
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.atan2
import kotlin.math.sqrt

class ArPosterView(
    private val context: Context,
    messenger: BinaryMessenger
) : PlatformView, GLSurfaceView.Renderer {

    private val glView = GLSurfaceView(context)
    private var session: Session? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Thread-safe flags
    @Volatile private var surfaceReady = false
    @Volatile private var sessionReady = false
    @Volatile private var pendingImages: Map<String, ByteArray>? = null
    @Volatile private var pendingWidths: Map<String, Double>? = null

    // Tracking state
    private val trackedNames = mutableSetOf<String>()
    private var viewportW = 1
    private var viewportH = 1
    private var displayRotation = 0

    // Background renderer state
    private var bgProgram = 0
    private var bgPosHandle = 0
    private var bgTexCoordHandle = 0
    private var bgTextureHandle = 0
    private var cameraTextureId = -1
    private var texCoordsBuffer: FloatBuffer
    private val ndcBuffer: FloatBuffer

    private val ndcCoords = floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f)
    private val defaultTexCoords = floatArrayOf(0f, 1f, 1f, 1f, 0f, 0f, 1f, 0f)

    init {
        ndcBuffer = ByteBuffer.allocateDirect(ndcCoords.size * 4)
            .order(ByteOrder.nativeOrder()).asFloatBuffer()
        ndcBuffer.put(ndcCoords).rewind()

        texCoordsBuffer = ByteBuffer.allocateDirect(defaultTexCoords.size * 4)
            .order(ByteOrder.nativeOrder()).asFloatBuffer()
        texCoordsBuffer.put(defaultTexCoords).rewind()

        glView.setEGLContextClientVersion(2)
        glView.setEGLConfigChooser(8, 8, 8, 8, 16, 0)
        glView.setRenderer(this)
        glView.renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY

        val methodChannel = MethodChannel(messenger, "com.itec.override/ar_method")
        val eventChannel = EventChannel(messenger, "com.itec.override/ar_events")

        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink) { eventSink = sink }
            override fun onCancel(args: Any?) { eventSink = null }
        })

        methodChannel.setMethodCallHandler { call, result -> onMethodCall(call, result) }
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                pendingImages = call.argument<Map<String, ByteArray>>("images")
                pendingWidths = call.argument<Map<String, Double>>("widths")
                // If GL surface is already ready, kick off session creation now
                if (surfaceReady) spawnSessionThread()
                result.success(null)
            }
            "dispose" -> {
                sessionReady = false
                session?.pause()
                session?.close()
                session = null
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ── Session creation on a background thread ───────────────────────────────
    // Heavy work (Session ctor + DB compilation) must NOT block the GL or main thread.

    private fun spawnSessionThread() {
        val images = pendingImages ?: emptyMap()
        val widths = pendingWidths ?: emptyMap()
        val texId  = cameraTextureId
        if (texId == -1) return

        Thread {
            try {
                val s = Session(context)
                val db = AugmentedImageDatabase(s)
                for ((name, bytes) in images) {
                    try {
                        val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: continue
                        val physW = (widths[name] ?: 0.4).toFloat()
                        db.addImage(name, bmp, physW)
                    } catch (_: Exception) { /* low-feature image — skip */ }
                }

                val config = Config(s).apply {
                    updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                    focusMode  = Config.FocusMode.AUTO
                    augmentedImageDatabase = db
                }
                s.configure(config)
                // setCameraTextureName MUST be called before resume()
                s.setCameraTextureName(texId)
                s.setDisplayGeometry(displayRotation, viewportW, viewportH)
                s.resume()

                session      = s
                sessionReady = true
                mainHandler.post {
                    eventSink?.success(
                        JSONObject().apply { put("type", "ar_ready") }.toString()
                    )
                }
            } catch (e: Exception) {
                val msg = e.message ?: e.javaClass.simpleName
                mainHandler.post {
                    eventSink?.success(
                        JSONObject().apply {
                            put("type", "ar_error")
                            put("message", msg)
                        }.toString()
                    )
                }
            }
        }.start()
    }

    // ── GL Renderer ──────────────────────────────────────────────────────────

    override fun onSurfaceCreated(gl: GL10, config: EGLConfig) {
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        cameraTextureId = createOesTexture()
        bgProgram       = buildProgram(VERTEX_SHADER, FRAGMENT_SHADER)
        bgPosHandle     = GLES20.glGetAttribLocation(bgProgram, "a_Pos")
        bgTexCoordHandle= GLES20.glGetAttribLocation(bgProgram, "a_TexCoord")
        bgTextureHandle = GLES20.glGetUniformLocation(bgProgram, "sTexture")
        // Don't set surfaceReady here — viewport dims not available until onSurfaceChanged
    }

    override fun onSurfaceChanged(gl: GL10, width: Int, height: Int) {
        viewportW = width
        viewportH = height
        GLES20.glViewport(0, 0, width, height)
        displayRotation = context.display?.rotation ?: Surface.ROTATION_0
        session?.setDisplayGeometry(displayRotation, width, height)
        // First time we have valid viewport dimensions — safe to start session
        if (!surfaceReady) {
            surfaceReady = true
            if (pendingImages != null) spawnSessionThread()
        }
    }

    override fun onDrawFrame(gl: GL10) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
        if (!sessionReady) return
        val s = session ?: return

        try {
            s.setCameraTextureName(cameraTextureId)
            val frame = s.update()

            if (frame.hasDisplayGeometryChanged()) {
                val outBuf = ByteBuffer.allocateDirect(defaultTexCoords.size * 4)
                    .order(ByteOrder.nativeOrder()).asFloatBuffer()
                frame.transformCoordinates2d(
                    Coordinates2d.OPENGL_NORMALIZED_DEVICE_COORDINATES, ndcBuffer,
                    Coordinates2d.TEXTURE_NORMALIZED, outBuf
                )
                outBuf.rewind()
                texCoordsBuffer = outBuf
                ndcBuffer.rewind()
            }

            drawBackground()

            val camera = frame.camera
            if (camera.trackingState != TrackingState.TRACKING) return

            val proj = FloatArray(16)
            camera.getProjectionMatrix(proj, 0, 0.01f, 100f)
            val view = FloatArray(16)
            camera.getViewMatrix(view, 0)

            for (img in frame.getUpdatedTrackables(AugmentedImage::class.java)) {
                val name = img.name
                when (img.trackingState) {
                    TrackingState.TRACKING -> {
                        val sc = projectPosterToScreen(img.centerPose, img.extentX, img.extentZ, view, proj)
                        val isNew = trackedNames.add(name)
                        val event = JSONObject().apply {
                            put("type", if (isNew) "detected" else "updated")
                            put("posterId", name)
                            put("cx", sc[0])
                            put("cy", sc[1])
                            put("widthPx", sc[2])
                            put("heightPx", sc[3])
                            put("angle", sc[4])
                        }
                        mainHandler.post { eventSink?.success(event.toString()) }
                    }
                    TrackingState.STOPPED -> {
                        if (trackedNames.remove(name)) {
                            mainHandler.post {
                                eventSink?.success(
                                    JSONObject().apply {
                                        put("type", "lost")
                                        put("posterId", name)
                                    }.toString()
                                )
                            }
                        }
                    }
                    else -> {}
                }
            }
        } catch (_: CameraNotAvailableException) {
            sessionReady = false
        }
    }

    private fun drawBackground() {
        GLES20.glDisable(GLES20.GL_DEPTH_TEST)
        GLES20.glDepthMask(false)
        GLES20.glUseProgram(bgProgram)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, cameraTextureId)
        GLES20.glEnableVertexAttribArray(bgPosHandle)
        GLES20.glVertexAttribPointer(bgPosHandle, 2, GLES20.GL_FLOAT, false, 0, ndcBuffer)
        GLES20.glEnableVertexAttribArray(bgTexCoordHandle)
        GLES20.glVertexAttribPointer(bgTexCoordHandle, 2, GLES20.GL_FLOAT, false, 0, texCoordsBuffer)
        GLES20.glUniform1i(bgTextureHandle, 0)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(bgPosHandle)
        GLES20.glDisableVertexAttribArray(bgTexCoordHandle)
        GLES20.glDepthMask(true)
        GLES20.glEnable(GLES20.GL_DEPTH_TEST)
    }

    // ── Projection ────────────────────────────────────────────────────────────

    private fun projectPosterToScreen(
        pose: Pose, extX: Float, extZ: Float,
        viewMat: FloatArray, projMat: FloatArray
    ): FloatArray {
        val model = FloatArray(16)
        pose.toMatrix(model, 0)

        val vp  = FloatArray(16)
        val mvp = FloatArray(16)
        Matrix.multiplyMM(vp,  0, projMat, 0, viewMat, 0)
        Matrix.multiplyMM(mvp, 0, vp,      0, model,   0)

        val hx = extX / 2f
        val hz = extZ / 2f

        val corners = arrayOf(
            floatArrayOf(-hx, 0f, -hz, 1f),
            floatArrayOf( hx, 0f, -hz, 1f),
            floatArrayOf( hx, 0f,  hz, 1f),
            floatArrayOf(-hx, 0f,  hz, 1f)
        )

        val screen = corners.map { c ->
            val clip = FloatArray(4)
            Matrix.multiplyMV(clip, 0, mvp, 0, c, 0)
            val w = clip[3]
            floatArrayOf(
                ((clip[0] / w + 1f) / 2f) * viewportW,
                ((1f - clip[1] / w) / 2f) * viewportH
            )
        }

        val cx = screen.sumOf { it[0].toDouble() }.toFloat() / 4f
        val cy = screen.sumOf { it[1].toDouble() }.toFloat() / 4f

        val dx0 = screen[1][0] - screen[0][0]; val dy0 = screen[1][1] - screen[0][1]
        val dx1 = screen[3][0] - screen[0][0]; val dy1 = screen[3][1] - screen[0][1]
        val widthPx  = sqrt((dx0 * dx0 + dy0 * dy0).toDouble()).toFloat()
        val heightPx = sqrt((dx1 * dx1 + dy1 * dy1).toDouble()).toFloat()
        val angle    = Math.toDegrees(atan2(dy0.toDouble(), dx0.toDouble())).toFloat()

        return floatArrayOf(cx, cy, widthPx, heightPx, angle)
    }

    // ── GL helpers ────────────────────────────────────────────────────────────

    private fun createOesTexture(): Int {
        val ids = IntArray(1)
        GLES20.glGenTextures(1, ids, 0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, ids[0])
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        return ids[0]
    }

    private fun compileShader(type: Int, src: String): Int {
        val sh = GLES20.glCreateShader(type)
        GLES20.glShaderSource(sh, src)
        GLES20.glCompileShader(sh)
        return sh
    }

    private fun buildProgram(vs: String, fs: String): Int {
        val prog = GLES20.glCreateProgram()
        GLES20.glAttachShader(prog, compileShader(GLES20.GL_VERTEX_SHADER, vs))
        GLES20.glAttachShader(prog, compileShader(GLES20.GL_FRAGMENT_SHADER, fs))
        GLES20.glLinkProgram(prog)
        return prog
    }

    override fun getView(): View = glView

    override fun dispose() {
        sessionReady = false
        glView.onPause()
        session?.pause()
        session?.close()
        session = null
    }

    companion object {
        private const val VERTEX_SHADER = """
            attribute vec4 a_Pos;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord;
            void main() { gl_Position = a_Pos; v_TexCoord = a_TexCoord; }
        """
        private const val FRAGMENT_SHADER = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            uniform samplerExternalOES sTexture;
            varying vec2 v_TexCoord;
            void main() { gl_FragColor = texture2D(sTexture, v_TexCoord); }
        """
    }
}
