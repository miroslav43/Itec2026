package com.itec.override

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.opengl.GLUtils
import android.opengl.Matrix
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import android.view.View
import com.google.ar.core.*
import com.google.ar.core.exceptions.CameraNotAvailableException
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
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

    companion object {
        private const val TAG = "ArPosterView"
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
        // Poster overlay shaders — renders textured quad in AR space
        private const val POSTER_VS = """
            attribute vec4 a_Pos;
            attribute vec2 a_TexCoord;
            uniform mat4 u_MVP;
            varying vec2 v_TexCoord;
            void main() { gl_Position = u_MVP * a_Pos; v_TexCoord = a_TexCoord; }
        """
        private const val POSTER_FS = """
            precision mediump float;
            uniform sampler2D u_Texture;
            varying vec2 v_TexCoord;
            void main() { gl_FragColor = texture2D(u_Texture, v_TexCoord); }
        """
        // Normalised 1×1 quad in XZ plane (scaled by extentX / extentZ per draw)
        // Triangle-strip order: TL TR BL BR
        // x, y, z, u, v
        private val QUAD_VERTS = floatArrayOf(
            -0.5f, 0f, -0.5f,  0f, 0f,
             0.5f, 0f, -0.5f,  1f, 0f,
            -0.5f, 0f,  0.5f,  0f, 1f,
             0.5f, 0f,  0.5f,  1f, 1f
        )
    }

    private val glView = GLSurfaceView(context)
    private var session: Session? = null
    private var eventSink: EventChannel.EventSink? = null
    private val eventQueue = mutableListOf<String>()   // buffered until onListen fires
    private val mainHandler = Handler(Looper.getMainLooper())

    // All volatile so background thread sees latest values
    @Volatile private var surfaceReady    = false
    @Volatile private var sessionSpawned = false  // guard against double-spawn
    @Volatile private var sessionReady   = false
    @Volatile private var cameraTextureId = -1    // must be volatile: read by background thread
    @Volatile private var pendingIds: List<String>? = null
    @Volatile private var pendingWidths: Map<String, Double>? = null
    @Volatile private var pendingTexturePaths: Map<String, String> = emptyMap()  // posterId -> file path

    private val trackedNames = mutableSetOf<String>()
    private var viewportW = 1
    private var viewportH = 1
    private var displayRotation = 0
    private var lastHeartbeatMs = 0L
    private var lastCameraStateName = ""

    private var bgProgram = 0
    private var bgPosHandle = 0
    private var bgTexCoordHandle = 0
    private var bgTextureHandle = 0
    private var texCoordsBuffer: FloatBuffer
    private val ndcBuffer: FloatBuffer
    private val ndcCoords       = floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f)
    private val defaultTexCoords = floatArrayOf( 0f,  1f, 1f,  1f,  0f, 0f, 1f, 0f)

    // Poster overlay GL state
    private var posterProgram  = 0
    private var pPosHandle     = 0
    private var pTexHandle     = 0
    private var pMvpHandle     = 0
    private var pSamplerHandle = 0
    private val posterTextures = mutableMapOf<String, Int>()   // posterId -> GL texId
    @Volatile private var pendingBitmaps: Map<String, Bitmap>? = null
    private val quadBuffer: FloatBuffer = ByteBuffer
        .allocateDirect(QUAD_VERTS.size * 4)
        .order(ByteOrder.nativeOrder()).asFloatBuffer()
        .also { it.put(QUAD_VERTS).rewind() }

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
        val eventChannel  = EventChannel(messenger, "com.itec.override/ar_events")

        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                eventSink = sink
                Log.d(TAG, "EventChannel onListen — flushing ${eventQueue.size} queued event(s)")
                // Flush events that fired before the listener was attached
                eventQueue.forEach { sink.success(it) }
                eventQueue.clear()
            }
            override fun onCancel(args: Any?) {
                eventSink = null
                Log.d(TAG, "EventChannel listener cancelled")
            }
        })

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    // Receive only IDs — images loaded natively from flutter_assets/
                    val ids          = call.argument<List<String>>("posterIds") ?: emptyList()
                    val widths       = call.argument<Map<String, Double>>("widths") ?: emptyMap()
                    @Suppress("UNCHECKED_CAST")
                    val texturePaths = (call.argument<Map<*, *>>("texturePaths") as? Map<String, String>) ?: emptyMap()
                    Log.d(TAG, "initialize: ${ids.size} poster(s): $ids  customTextures=${texturePaths.keys}")
                    pendingIds           = ids
                    pendingWidths        = widths
                    pendingTexturePaths  = texturePaths
                    result.success(null)   // return immediately — no data to transfer
                    maybeSpawnSession()
                }
                "dispose" -> {
                    Log.d(TAG, "dispose")
                    sessionReady = false
                    session?.pause(); session?.close(); session = null
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ── Session spawn guard ───────────────────────────────────────────────────

    private fun maybeSpawnSession() {
        if (!surfaceReady)          { Log.d(TAG, "maybeSpawnSession: surface not ready"); return }
        if (pendingIds == null)     { Log.d(TAG, "maybeSpawnSession: ids not set");       return }
        if (sessionSpawned)         { Log.d(TAG, "maybeSpawnSession: already spawned");   return }
        sessionSpawned = true
        Log.d(TAG, "maybeSpawnSession: launching session thread")
        spawnSessionThread()
    }

    // ── Session creation (background thread) ─────────────────────────────────

    private fun spawnSessionThread() {
        val ids          = pendingIds          ?: emptyList()
        val widths       = pendingWidths       ?: emptyMap()
        val texturePaths = pendingTexturePaths  // posterId -> file path (empty = all use assets)
        val texId  = cameraTextureId       // volatile read — valid because surfaceReady is true
        val vW     = viewportW
        val vH     = viewportH
        val rot    = displayRotation

        Log.d(TAG, "spawnSessionThread: texId=$texId  viewport=${vW}x${vH}  rot=$rot  ids=$ids")

        if (texId == -1) {
            Log.e(TAG, "spawnSessionThread: texId is -1, aborting (surface not created yet?)")
            sessionSpawned = false
            return
        }

        Thread {
            try {
                Log.d(TAG, "Thread: creating ARCore Session")
                val s  = Session(context)
                val db = AugmentedImageDatabase(s)
                var loaded = 0

                val savedBitmaps = mutableMapOf<String, Bitmap>()

                for (id in ids) {
                    val assetPath = "flutter_assets/assets/posters/$id.png"
                    try {
                        val stream = context.assets.open(assetPath)
                        val raw    = BitmapFactory.decodeStream(stream)
                        stream.close()
                        if (raw == null) { Log.w(TAG, "  [$id] decode returned null"); continue }

                        // Scale to 512px wide for ARCore tracking DB
                        val dbBmp: Bitmap = if (raw.width > 512) {
                            val h = (512f * raw.height / raw.width).toInt()
                            Bitmap.createScaledBitmap(raw, 512, h, true)
                        } else raw

                        val physW = (widths[id] ?: 0.4).toFloat()
                        db.addImage(id, dbBmp, physW)   // tracking always uses reference asset
                        loaded++
                        Log.d(TAG, "  [$id] added to DB OK — ${dbBmp.width}x${dbBmp.height} physW=${physW}m")

                        // GL texture: use per-poster cached battle canvas if available
                        val filePath = texturePaths[id]
                        if (filePath != null) {
                            try {
                                val fileBmp = BitmapFactory.decodeFile(filePath)
                                if (fileBmp != null) {
                                    savedBitmaps[id] = fileBmp
                                    Log.d(TAG, "  [$id] GL texture from file: $filePath")
                                } else {
                                    savedBitmaps[id] = dbBmp
                                    Log.w(TAG, "  [$id] GL texture file null, using asset")
                                }
                            } catch (e: Exception) {
                                savedBitmaps[id] = dbBmp
                                Log.w(TAG, "  [$id] GL texture file error: ${e.message}, using asset")
                            }
                        } else {
                            savedBitmaps[id] = dbBmp   // no custom texture — use asset
                        }

                    } catch (e: Exception) {
                        Log.e(TAG, "  [$id] FAILED: ${e.message}")
                    }
                }

                pendingBitmaps = savedBitmaps   // will be uploaded on GL thread in onDrawFrame

                Log.d(TAG, "Thread: DB has $loaded/${ids.size} images")

                val config = Config(s).apply {
                    updateMode             = Config.UpdateMode.LATEST_CAMERA_IMAGE
                    focusMode              = Config.FocusMode.AUTO
                    augmentedImageDatabase = db
                }
                s.configure(config)
                s.setCameraTextureName(texId)
                s.setDisplayGeometry(rot, vW, vH)
                s.resume()

                session      = s
                sessionReady = true
                Log.d(TAG, "Thread: session STARTED — $loaded images ready for tracking")

                mainHandler.post {
                    sendEvent(JSONObject().apply {
                        put("type", "ar_ready")
                        put("imagesLoaded", loaded)
                    })
                }
            } catch (e: Exception) {
                Log.e(TAG, "Thread FAILED: ${e.javaClass.simpleName}: ${e.message}")
                sessionSpawned = false
                mainHandler.post {
                    sendEvent(JSONObject().apply {
                        put("type", "ar_error")
                        put("message", "${e.javaClass.simpleName}: ${e.message}")
                    })
                }
            }
        }.start()
    }

    private fun sendEvent(json: JSONObject) {
        val str = json.toString()
        val sink = eventSink
        if (sink != null) {
            sink.success(str)
        } else {
            // Listener not yet attached — queue for flush in onListen
            Log.d(TAG, "sendEvent queued (no sink yet): $str")
            eventQueue.add(str)
        }
    }

    // ── GL Renderer ──────────────────────────────────────────────────────────

    override fun onSurfaceCreated(gl: GL10, config: EGLConfig) {
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        cameraTextureId  = createOesTexture()
        bgProgram        = buildProgram(VERTEX_SHADER, FRAGMENT_SHADER)
        bgPosHandle      = GLES20.glGetAttribLocation(bgProgram, "a_Pos")
        bgTexCoordHandle = GLES20.glGetAttribLocation(bgProgram, "a_TexCoord")
        bgTextureHandle  = GLES20.glGetUniformLocation(bgProgram, "sTexture")
        // Poster overlay program
        posterProgram  = buildProgram(POSTER_VS, POSTER_FS)
        pPosHandle     = GLES20.glGetAttribLocation(posterProgram, "a_Pos")
        pTexHandle     = GLES20.glGetAttribLocation(posterProgram, "a_TexCoord")
        pMvpHandle     = GLES20.glGetUniformLocation(posterProgram, "u_MVP")
        pSamplerHandle = GLES20.glGetUniformLocation(posterProgram, "u_Texture")
        Log.d(TAG, "onSurfaceCreated: cameraTextureId=$cameraTextureId  posterProgram=$posterProgram")
        // Do NOT set surfaceReady here — viewport dims are 0 until onSurfaceChanged
    }

    override fun onSurfaceChanged(gl: GL10, width: Int, height: Int) {
        viewportW       = width
        viewportH       = height
        displayRotation = context.display?.rotation ?: Surface.ROTATION_0
        GLES20.glViewport(0, 0, width, height)
        session?.setDisplayGeometry(displayRotation, width, height)
        Log.d(TAG, "onSurfaceChanged: ${width}x${height}  rot=$displayRotation")
        if (!surfaceReady) {
            surfaceReady = true
            maybeSpawnSession()
        }
    }

    override fun onDrawFrame(gl: GL10) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
        if (!sessionReady) return
        val s = session ?: return

        // Upload any poster bitmaps that arrived from the background thread
        pendingBitmaps?.let { bitmaps ->
            pendingBitmaps = null
            for ((id, bmp) in bitmaps) {
                val tId = uploadTexture(bmp)
                posterTextures[id] = tId
                Log.d(TAG, "GL texture uploaded for '$id' -> texId=$tId")
            }
        }

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
                outBuf.rewind(); texCoordsBuffer = outBuf; ndcBuffer.rewind()
            }

            drawBackground()

            val camera       = frame.camera
            val camState     = camera.trackingState
            val camStateName = camState.name

            // Heartbeat: send camera tracking state every 2 seconds
            val now = System.currentTimeMillis()
            if (camStateName != lastCameraStateName || now - lastHeartbeatMs > 2000L) {
                lastCameraStateName = camStateName
                lastHeartbeatMs     = now
                mainHandler.post {
                    sendEvent(JSONObject().apply {
                        put("type",  "camera_state")
                        put("state", camStateName)
                    })
                }
            }

            // Build view/proj only when camera is TRACKING (needed for 3D pose)
            val proj: FloatArray?
            val view: FloatArray?
            if (camState == TrackingState.TRACKING) {
                proj = FloatArray(16); camera.getProjectionMatrix(proj, 0, 0.01f, 100f)
                view = FloatArray(16); camera.getViewMatrix(view, 0)
            } else {
                proj = null; view = null
            }

            // Process trackables regardless of camera state
            for (img in frame.getUpdatedTrackables(AugmentedImage::class.java)) {
                val name   = img.name
                val state  = img.trackingState
                val method = img.trackingMethod
                Log.d(TAG, "AugImg[$name] state=$state method=$method ext=${img.extentX}x${img.extentZ} cam=$camStateName")

                when (state) {
                    TrackingState.TRACKING -> {
                        // Render GL quad directly on the poster plane — correct perspective automatically
                        if (proj != null && view != null) {
                            val texId = posterTextures[name]
                            if (texId != null) {
                                renderPosterQuad(img.centerPose, img.extentX, img.extentZ, texId, view, proj)
                            } else {
                                Log.w(TAG, "  TRACKING but no GL texture yet for '$name'")
                            }
                        }
                        val isNew = trackedNames.add(name)
                        Log.d(TAG, "  -> TRACKING (GL quad rendered)")
                        mainHandler.post {
                            sendEvent(JSONObject().apply {
                                put("type",     if (isNew) "detected" else "updated")
                                put("posterId", name)
                            })
                        }
                    }
                    TrackingState.PAUSED -> {
                        Log.d(TAG, "  -> PAUSED (seen, not yet 3D-tracked)")
                        trackedNames.add(name)
                        mainHandler.post {
                            sendEvent(JSONObject().apply {
                                put("type",     "image_paused")
                                put("posterId", name)
                            })
                        }
                    }
                    TrackingState.STOPPED -> {
                        if (trackedNames.remove(name)) {
                            Log.d(TAG, "  -> STOPPED lost $name")
                            mainHandler.post {
                                sendEvent(JSONObject().apply {
                                    put("type",     "lost")
                                    put("posterId", name)
                                })
                            }
                        }
                    }
                }
            }
        } catch (e: CameraNotAvailableException) {
            Log.e(TAG, "CameraNotAvailable: ${e.message}")
            sessionReady = false
        } catch (e: Exception) {
            Log.e(TAG, "onDrawFrame error: ${e.message}")
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
        val model = FloatArray(16); pose.toMatrix(model, 0)
        val vp    = FloatArray(16); Matrix.multiplyMM(vp,  0, projMat, 0, viewMat, 0)
        val mvp   = FloatArray(16); Matrix.multiplyMM(mvp, 0, vp,      0, model,   0)

        val hx = extX / 2f; val hz = extZ / 2f
        val corners = arrayOf(
            floatArrayOf(-hx, 0f, -hz, 1f),
            floatArrayOf( hx, 0f, -hz, 1f),
            floatArrayOf( hx, 0f,  hz, 1f),
            floatArrayOf(-hx, 0f,  hz, 1f)
        )
        val screen = corners.map { c ->
            val clip = FloatArray(4); Matrix.multiplyMV(clip, 0, mvp, 0, c, 0)
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
        val widthPx  = sqrt((dx0*dx0 + dy0*dy0).toDouble()).toFloat()
        val heightPx = sqrt((dx1*dx1 + dy1*dy1).toDouble()).toFloat()
        val angle    = Math.toDegrees(atan2(dy0.toDouble(), dx0.toDouble())).toFloat()
        return floatArrayOf(cx, cy, widthPx, heightPx, angle)
    }

    // ── Poster rendering helpers ──────────────────────────────────────────────

    private fun uploadTexture(bmp: Bitmap): Int {
        val ids = IntArray(1)
        GLES20.glGenTextures(1, ids, 0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, ids[0])
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S,     GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T,     GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bmp, 0)
        return ids[0]
    }

    private fun renderPosterQuad(
        pose: Pose, extX: Float, extZ: Float,
        texId: Int, viewMat: FloatArray, projMat: FloatArray
    ) {
        if (extX <= 0f || extZ <= 0f) return

        // Build MVP: scale the unit quad by extents, then apply pose transform
        val scale = FloatArray(16); Matrix.setIdentityM(scale, 0)
        Matrix.scaleM(scale, 0, extX, 1f, extZ)
        val model = FloatArray(16); pose.toMatrix(model, 0)
        val scaledModel = FloatArray(16); Matrix.multiplyMM(scaledModel, 0, model, 0, scale, 0)
        val vp  = FloatArray(16); Matrix.multiplyMM(vp,  0, projMat, 0, viewMat,     0)
        val mvp = FloatArray(16); Matrix.multiplyMM(mvp, 0, vp,      0, scaledModel, 0)

        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        GLES20.glEnable(GLES20.GL_DEPTH_TEST)
        GLES20.glDepthMask(true)

        GLES20.glUseProgram(posterProgram)
        GLES20.glUniformMatrix4fv(pMvpHandle, 1, false, mvp, 0)

        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texId)
        GLES20.glUniform1i(pSamplerHandle, 0)

        val stride = 5 * 4  // 5 floats × 4 bytes per vertex
        quadBuffer.rewind()
        GLES20.glEnableVertexAttribArray(pPosHandle)
        GLES20.glVertexAttribPointer(pPosHandle, 3, GLES20.GL_FLOAT, false, stride, quadBuffer)
        quadBuffer.position(3)
        GLES20.glEnableVertexAttribArray(pTexHandle)
        GLES20.glVertexAttribPointer(pTexHandle, 2, GLES20.GL_FLOAT, false, stride, quadBuffer)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

        GLES20.glDisableVertexAttribArray(pPosHandle)
        GLES20.glDisableVertexAttribArray(pTexHandle)
        GLES20.glDepthMask(false)
        GLES20.glDisable(GLES20.GL_BLEND)
        quadBuffer.rewind()
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
        GLES20.glShaderSource(sh, src); GLES20.glCompileShader(sh)
        val status = IntArray(1)
        GLES20.glGetShaderiv(sh, GLES20.GL_COMPILE_STATUS, status, 0)
        if (status[0] == 0) Log.e(TAG, "Shader error: ${GLES20.glGetShaderInfoLog(sh)}")
        return sh
    }

    private fun buildProgram(vs: String, fs: String): Int {
        val prog = GLES20.glCreateProgram()
        GLES20.glAttachShader(prog, compileShader(GLES20.GL_VERTEX_SHADER,   vs))
        GLES20.glAttachShader(prog, compileShader(GLES20.GL_FRAGMENT_SHADER, fs))
        GLES20.glLinkProgram(prog)
        return prog
    }

    override fun getView(): View = glView

    override fun dispose() {
        Log.d(TAG, "dispose: cleaning up")
        sessionReady = false; glView.onPause()
        session?.pause(); session?.close(); session = null
    }
}
