# Cross-compile stable-diffusion.cpp + sd_native_bridge for iOS (device or simulator).
# Invoked by build_sd_ios.sh — not part of the Xcode compile graph directly.
cmake_minimum_required(VERSION 3.22.1)
project(sd_ios_core LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Caller sets: CMAKE_OSX_SYSROOT, CMAKE_OSX_ARCHITECTURES, CMAKE_OSX_DEPLOYMENT_TARGET
set(SD_CUBLAS OFF CACHE BOOL "" FORCE)
set(SD_HIPBLAS OFF CACHE BOOL "" FORCE)
set(SD_METAL OFF CACHE BOOL "" FORCE)
set(SD_VULKAN OFF CACHE BOOL "" FORCE)
set(SD_FLASH_ATTN OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

include(FetchContent)
# Only ggml is required; skip optional server UI submodule (clone failures in CI / long paths).
FetchContent_Declare(
  stable_diffusion_cpp
  GIT_REPOSITORY https://github.com/leejet/stable-diffusion.cpp.git
  GIT_TAG master
  GIT_SHALLOW TRUE
  GIT_SUBMODULES ggml
)
FetchContent_MakeAvailable(stable_diffusion_cpp)

set(SD_BRIDGE_DIR "${CMAKE_CURRENT_LIST_DIR}/../../cpp/sd_bridge")

add_library(sd_ios_merged STATIC
  ${SD_BRIDGE_DIR}/sd_native_bridge.cpp
)

target_include_directories(sd_ios_merged PRIVATE
  ${SD_BRIDGE_DIR}
  ${stable_diffusion_cpp_SOURCE_DIR}
  ${stable_diffusion_cpp_SOURCE_DIR}/include
)

target_link_libraries(sd_ios_merged PUBLIC stable-diffusion)
