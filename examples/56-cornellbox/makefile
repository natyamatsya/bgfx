#
# Copyright 2011-2026 Branimir Karadzic. All rights reserved.
# License: https://github.com/bkaradzic/bgfx/blob/master/LICENSE
#

BGFX_DIR=../..
RUNTIME_DIR=$(BGFX_DIR)/examples/runtime
BUILD_DIR=../../.build

# The shaders are authored in Slang, which shaderc compiles to SPIR-V (Vulkan, TARGET=7),
# Metal (TARGET=5) and DXIL (D3D12, TARGET=0). Metal/SPIR-V are set here; on Windows DXIL is
# added by shader.mk's prepend, so `make TARGET=0` builds the D3D12 shaders.
SHADER_TARGETS := 5 7

include $(BGFX_DIR)/scripts/shader.mk
