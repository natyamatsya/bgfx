#
# Copyright 2011-2026 Branimir Karadzic. All rights reserved.
# License: https://github.com/bkaradzic/bgfx/blob/master/LICENSE
#

BGFX_DIR=../..
RUNTIME_DIR=$(BGFX_DIR)/examples/runtime
BUILD_DIR=../../.build

# The shaders are authored in Slang, which shaderc currently compiles to SPIR-V (Vulkan,
# TARGET=7) and Metal (TARGET=5). Restrict the shader build to those backends.
SHADER_TARGETS := 5 7

include $(BGFX_DIR)/scripts/shader.mk
