cmake_minimum_required(VERSION 3.22.1)
project(stable_diffusion_jni)

# ─── Download stable-diffusion.cpp source at configure time ──────────────────
include(FetchContent)
FetchContent_Declare(
    stable_diffusion_cpp
    GIT_REPOSITORY https://github.com/leejet/stable-diffusion.cpp.git
    GIT_TAG        master
    GIT_SHALLOW    TRUE
)

# Build options: disable everything we don't need on Android
set(SD_CUBLAS     OFF CACHE BOOL "" FORCE)
set(SD_HIPBLAS    OFF CACHE BOOL "" FORCE)
set(SD_METAL      OFF CACHE BOOL "" FORCE)
set(SD_VULKAN     OFF CACHE BOOL "" FORCE)
set(SD_FLASH_ATTN OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

FetchContent_MakeAvailable(stable_diffusion_cpp)

# ─── Our JNI glue ────────────────────────────────────────────────────────────
add_library(stable_diffusion_jni SHARED stable_diffusion_jni.cpp)

target_include_directories(stable_diffusion_jni PRIVATE
    ${stable_diffusion_cpp_SOURCE_DIR}
    ${stable_diffusion_cpp_SOURCE_DIR}/include
)

target_link_libraries(stable_diffusion_jni
    stable-diffusion   # target exported by stable-diffusion.cpp's CMakeLists
    android
    log
)
