#include <jni.h>
#include <android/log.h>
#include <cstdlib>
#include <cstring>

// stable_diffusion.h is provided by the FetchContent'd source
#include "stable_diffusion.h"

#define LOG_TAG "StableDiffusionJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// ─── Global state ─────────────────────────────────────────────────────────────
static sd_ctx_t* g_ctx = nullptr;

// JNI progress trampoline
static JavaVM*   g_jvm                 = nullptr;
static jobject   g_progress_obj        = nullptr;
static jmethodID g_on_progress_mid     = nullptr;

static void sd_log_cb(sd_log_level_t level, const char* text, void*) {
    if (level >= SD_LOG_INFO) LOGI("%s", text);
}

static void sd_progress_cb(int step, int steps, float /*time*/, void*) {
    if (!g_jvm || !g_progress_obj) return;
    JNIEnv* env = nullptr;
    bool attached = false;
    if (g_jvm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
        g_jvm->AttachCurrentThread(&env, nullptr);
        attached = true;
    }
    if (env && g_on_progress_mid)
        env->CallVoidMethod(g_progress_obj, g_on_progress_mid, (jint)step, (jint)steps);
    if (attached) g_jvm->DetachCurrentThread();
}

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
    g_jvm = vm;
    set_sd_log_callback(sd_log_cb, nullptr);
    set_sd_progress_callback(sd_progress_cb, nullptr);
    return JNI_VERSION_1_6;
}

// ─── JNI exports ──────────────────────────────────────────────────────────────

extern "C" JNIEXPORT jboolean JNICALL
Java_com_itec_override_StableDiffusionPlugin_nativeIsModelLoaded(JNIEnv*, jobject) {
    return g_ctx != nullptr ? JNI_TRUE : JNI_FALSE;
}

/**
 * Loads the model at the given path.
 * Returns true on success.
 */
extern "C" JNIEXPORT jboolean JNICALL
Java_com_itec_override_StableDiffusionPlugin_nativeLoadModel(
        JNIEnv* env, jobject, jstring model_path_j) {

    if (g_ctx) {
        free_sd_ctx(g_ctx);
        g_ctx = nullptr;
    }

    const char* path = env->GetStringUTFChars(model_path_j, nullptr);
    LOGI("Loading model: %s", path);

    g_ctx = new_sd_ctx(
        path,
        "",      // vae_path
        "",      // taesd_path
        "",      // control_net_path
        "",      // lora_model_dir
        "",      // embed_dir
        "",      // stacked_id_embed_dir
        true,    // vae_decode_only (we never encode images)
        false,   // vae_tiling
        false,   // free_params_immediately
        4,       // n_threads
        SD_TYPE_COUNT,  // SD_TYPE_COUNT = keep model's own type (already quantised)
        STD_DEFAULT_RNG,
        DEFAULT,
        false,   // keep_clip_on_cpu
        false,   // keep_control_net_cpu
        false    // keep_vae_on_cpu
    );

    env->ReleaseStringUTFChars(model_path_j, path);

    if (!g_ctx) { LOGE("new_sd_ctx failed"); return JNI_FALSE; }
    LOGI("Model loaded successfully");
    return JNI_TRUE;
}

/**
 * Generates an image.
 * Returns raw RGB bytes (width * height * 3) on success, null on failure.
 * The Kotlin caller encodes these to PNG via Android Bitmap.
 */
extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_itec_override_StableDiffusionPlugin_nativeGenerateImage(
        JNIEnv* env, jobject,
        jstring prompt_j, jstring neg_prompt_j,
        jint width, jint height,
        jint steps, jfloat cfg, jlong seed) {

    if (!g_ctx) { LOGE("No model loaded"); return nullptr; }

    const char* prompt     = env->GetStringUTFChars(prompt_j,     nullptr);
    const char* neg_prompt = env->GetStringUTFChars(neg_prompt_j, nullptr);

    LOGI("Generating %dx%d | steps=%d cfg=%.1f seed=%lld | prompt='%s'",
         width, height, steps, cfg, (long long)seed, prompt);

    sd_image_t* images = txt2img(
        g_ctx,
        prompt,
        neg_prompt,
        -1,          // clip_skip (-1 = model default)
        cfg,
        0.f,         // guidance (unused in SD 1.x)
        width,
        height,
        LCM,         // LCM sampler for 4-8 step generation
        steps,
        seed,
        1,           // batch_count
        nullptr,     // control_cond
        0.9f,        // control_strength (unused)
        20.f,        // style_strength  (unused)
        false,       // normalize_input
        ""           // input_id_images_path
    );

    env->ReleaseStringUTFChars(prompt_j,     prompt);
    env->ReleaseStringUTFChars(neg_prompt_j, neg_prompt);

    if (!images || !images[0].data) {
        LOGE("txt2img returned null");
        if (images) free(images);
        return nullptr;
    }

    const int n_bytes = (int)(images[0].width * images[0].height * images[0].channel);
    jbyteArray result = env->NewByteArray(n_bytes);
    env->SetByteArrayRegion(result, 0, n_bytes,
                            reinterpret_cast<const jbyte*>(images[0].data));

    free(images[0].data);
    free(images);

    LOGI("Generation complete (%d bytes)", n_bytes);
    return result;
}

extern "C" JNIEXPORT void JNICALL
Java_com_itec_override_StableDiffusionPlugin_nativeFreeModel(JNIEnv*, jobject) {
    if (g_ctx) {
        free_sd_ctx(g_ctx);
        g_ctx = nullptr;
    }
}
