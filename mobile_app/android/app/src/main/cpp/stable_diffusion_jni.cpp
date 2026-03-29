#include <jni.h>
#include <android/log.h>
#include <cstdlib>
#include <cstring>

#include "stable-diffusion.h"

#define LOG_TAG "StableDiffusionJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// ─── Global state ─────────────────────────────────────────────────────────────
static sd_ctx_t* g_ctx = nullptr;

static void sd_log_cb(enum sd_log_level_t level, const char* text, void*) {
    if (level >= SD_LOG_INFO) LOGI("%s", text);
}

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
    (void)vm;
    sd_set_log_callback(sd_log_cb, nullptr);
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

    sd_ctx_params_t ctx_params;
    sd_ctx_params_init(&ctx_params);
    ctx_params.model_path = path;
    ctx_params.vae_decode_only = true;
    ctx_params.n_threads = 4;
    ctx_params.wtype = SD_TYPE_COUNT;
    ctx_params.rng_type = STD_DEFAULT_RNG;
    ctx_params.sampler_rng_type = STD_DEFAULT_RNG;

    g_ctx = new_sd_ctx(&ctx_params);

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

    sd_img_gen_params_t img_params;
    sd_img_gen_params_init(&img_params);
    img_params.prompt = prompt;
    img_params.negative_prompt = neg_prompt;
    img_params.clip_skip = -1;
    img_params.width = width;
    img_params.height = height;
    img_params.batch_count = 1;
    img_params.seed = seed;
    img_params.sample_params.sample_steps = steps;
    img_params.sample_params.guidance.txt_cfg = cfg;
    img_params.sample_params.sample_method = sd_get_default_sample_method(g_ctx);
    img_params.sample_params.scheduler = sd_get_default_scheduler(g_ctx, img_params.sample_params.sample_method);

    sd_image_t* images = generate_image(g_ctx, &img_params);

    env->ReleaseStringUTFChars(prompt_j,     prompt);
    env->ReleaseStringUTFChars(neg_prompt_j, neg_prompt);

    if (!images || !images[0].data) {
        LOGE("generate_image returned null");
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
