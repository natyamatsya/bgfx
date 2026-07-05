/*
 * Copyright 2011-2026 Branimir Karadzic. All rights reserved.
 * License: https://github.com/bkaradzic/bgfx/blob/master/LICENSE
 */

#ifndef SHADERC_H_HEADER_GUARD
#define SHADERC_H_HEADER_GUARD

namespace bgfx
{
	extern bool g_verbose;
}

#include <bx/bx.h>

// HLSL compilation support:
// - Windows: Native D3DCompiler DLL
// - Linux/macOS: d3d4linux (Wine-based D3DCompiler via IPC)
#ifndef SHADERC_CONFIG_HAS_D3DCOMPILER
#	if BX_PLATFORM_WINDOWS
#		if __has_include(<d3dcompiler.h>)
#			define SHADERC_CONFIG_HAS_D3DCOMPILER 1
#		endif
#	elif BX_PLATFORM_LINUX
#		if __has_include(<d3d4linux.h>)
#			define SHADERC_CONFIG_HAS_D3DCOMPILER 1
#		endif
#	endif
// Still not?
#	ifndef SHADERC_CONFIG_HAS_D3DCOMPILER
#		define SHADERC_CONFIG_HAS_D3DCOMPILER 0
#	endif
#endif // SHADERC_CONFIG_HAS_D3DCOMPILER

// DXIL compilation support (Shader Model 6.0+):
// - Windows: Native DXC (dxcompiler.dll)
// - Linux: DXC (libdxcompiler.so) via directx-headers
// - macOS: Not supported (no DXC dynamic library available)
#ifndef SHADERC_CONFIG_HAS_DXC
#	define SHADERC_CONFIG_HAS_DXC (0  \
		|| BX_PLATFORM_WINDOWS     \
		|| BX_PLATFORM_LINUX       \
		)
#endif // SHADERC_CONFIG_HAS_DXC

#ifndef SHADERC_CONFIG_HAS_TINT
#	if __has_include(<tint/api/tint.h>)
#		define SHADERC_CONFIG_HAS_TINT 1
#	else
#		define SHADERC_CONFIG_HAS_TINT 0
#	endif
#endif

#ifndef SHADERC_CONFIG_HAS_SLANG
#	if __has_include(<slang.h>)
#		define SHADERC_CONFIG_HAS_SLANG 1
#	else
#		define SHADERC_CONFIG_HAS_SLANG 0
#	endif
#endif

#ifndef SHADERC_CONFIG_HAS_GLSLANG
#	if __has_include(<ShaderLang.h>) \
	&& __has_include(<SPIRV/SpvTools.h>)
#		define SHADERC_CONFIG_HAS_GLSLANG 1
#	else
#		define SHADERC_CONFIG_HAS_GLSLANG 0
#	endif
#endif

#ifndef SHADERC_CONFIG_HAS_GLSL_OPTIMIZER
#	if __has_include("glsl_optimizer.h")
#		define SHADERC_CONFIG_HAS_GLSL_OPTIMIZER 1
#	else
#		define SHADERC_CONFIG_HAS_GLSL_OPTIMIZER 0
#	endif
#endif

#include <bx/debug.h>
#include <bx/commandline.h>
#include <bx/endian.h>
#include <bx/string.h>
#include <bx/scanner.h>
#include <bx/hash.h>
#include <bx/file.h>
#include "../../src/vertexlayout.h"

#include <string.h>
#include <algorithm>
#include <string>
#include <vector>
#include <unordered_map>

// Compiled-shader binary "envelope" format. Frozen: bumping the version changes
// the on-disk layout consumed by src/bgfx_p.h and every renderer backend.
#define BGFX_SHADER_BIN_VERSION 11
#define BGFX_CHUNK_MAGIC_CSH BX_MAKEFOURCC('C', 'S', 'H', BGFX_SHADER_BIN_VERSION)
#define BGFX_CHUNK_MAGIC_FSH BX_MAKEFOURCC('F', 'S', 'H', BGFX_SHADER_BIN_VERSION)
#define BGFX_CHUNK_MAGIC_VSH BX_MAKEFOURCC('V', 'S', 'H', BGFX_SHADER_BIN_VERSION)

namespace bgfx
{
	extern bool g_verbose;

	// Target shading language a profile compiles to. Shared so front-ends (notably the
	// Slang front-end) can route to the right backend emitter.
	struct ShadingLang
	{
		enum Enum
		{
			ESSL,
			GLSL,
			HLSL,
			Metal,
			PSSL,
			SpirV,
			WGSL,
			Dxil,

			Count
		};
	};

	bx::StringView nextWord(bx::StringView& _parse);

	constexpr uint16_t kAccessRead  = 0x8000;
	constexpr uint16_t kAccessWrite = 0x4000;
	constexpr uint16_t kAccessMask  = 0
		| kAccessRead
		| kAccessWrite
		;

	constexpr uint8_t kUniformFragmentBit  = 0x10;
	constexpr uint8_t kUniformSamplerBit   = 0x20;
	constexpr uint8_t kUniformReadOnlyBit  = 0x40;
	constexpr uint8_t kUniformCompareBit   = 0x80;
	constexpr uint8_t kUniformMask = 0
		| kUniformFragmentBit
		| kUniformSamplerBit
		| kUniformReadOnlyBit
		| kUniformCompareBit
		;

	const char* getUniformTypeName(UniformType::Enum _enum);
	UniformType::Enum nameToUniformTypeEnum(const char* _name);

	struct Uniform
	{
		Uniform()
			: type(UniformType::Count)
			, num(0)
			, regIndex(0)
			, regCount(0)
			, texComponent(0)
			, texDimension(0)
			, texFormat(0)
		{
		}

		std::string name;
		UniformType::Enum type;
		uint8_t num;
		uint16_t regIndex;
		uint16_t regCount;
		uint8_t texComponent;
		uint8_t texDimension;
		uint16_t texFormat;
	};

	struct Options
	{
		Options();

		void dump();

		char shaderType;
		std::string platform;
		std::string profile;

		std::string	inputFilePath;
		std::string	outputFilePath;

		std::vector<std::string> includeDirs;
		std::vector<std::string> defines;
		std::vector<std::string> dependencies;

		bool disasm;
		bool raw;
		bool slang;
		bool slangNoPredefined; // Slang: don't auto-declare bgfx predefined uniforms.
		bool preprocessOnly;
		bool keepComments;
		bool depends;

		bool debugInformation;

		bool avoidFlowControl;
		bool noPreshader;
		bool partialPrecision;
		bool preferFlowControl;
		bool backwardsCompatibility;
		bool warningsAreErrors;
		bool keepIntermediate;

		bool optimize;
		uint32_t optimizationLevel;
	};

	typedef std::vector<Uniform> UniformArray;

	// Writes the uniform records of a compiled-shader envelope (count, then each
	// record: nameSize:u8, name, type:u8(|fragmentBit), num:u8, regIndex:u16,
	// regCount:u16, texComponent:u8, texDimension:u8, texFormat:u16). Returns the
	// constant-buffer size. This is the single source of truth for that byte
	// layout; the SPIR-V, WGSL and Slang backends all use it. Metal shares the same
	// record layout but a different constant-buffer size convention -- see
	// writeUniformArrayMetal below.
	inline uint16_t writeUniformArray(bx::WriterI* _shaderWriter, const UniformArray& uniforms, bool isFragmentShader)
	{
		uint16_t size = 0;

		bx::ErrorAssert err;

		uint16_t count = uint16_t(uniforms.size() );
		bx::write(_shaderWriter, count, &err);

		uint32_t fragmentBit = isFragmentShader ? kUniformFragmentBit : 0;

		for (uint16_t ii = 0; ii < count; ++ii)
		{
			const Uniform& un = uniforms[ii];

			if ( (un.type & ~kUniformMask) > UniformType::End)
			{
				size = bx::max(size, (uint16_t)(un.regIndex + un.regCount*16) );
			}

			uint8_t nameSize = (uint8_t)un.name.size();
			bx::write(_shaderWriter, nameSize, &err);
			bx::write(_shaderWriter, un.name.c_str(), nameSize, &err);
			bx::write(_shaderWriter, uint8_t(un.type | fragmentBit), &err);
			bx::write(_shaderWriter, un.num, &err);
			bx::write(_shaderWriter, un.regIndex, &err);
			bx::write(_shaderWriter, un.regCount, &err);
			bx::write(_shaderWriter, un.texComponent, &err);
			bx::write(_shaderWriter, un.texDimension, &err);
			bx::write(_shaderWriter, un.texFormat, &err);

			BX_TRACE("%s, %s, %d, %d, %d"
				, un.name.c_str()
				, getUniformTypeName(UniformType::Enum(un.type & ~kUniformMask))
				, un.num
				, un.regIndex
				, un.regCount
				);
		}
		return size;
	}

	// Metal variant of writeUniformArray. The uniform-record byte layout is identical
	// to writeUniformArray; only the returned constant-buffer size differs -- Metal sums
	// regCount*16 over every record (matching how the Metal runtime lays out its single
	// argument buffer) rather than taking max(regIndex + regCount*16). Shared by the
	// stock glslang Metal backend and the Slang Metal path so both agree byte-for-byte.
	inline uint16_t writeUniformArrayMetal(bx::WriterI* _shaderWriter, const UniformArray& uniforms, bool isFragmentShader)
	{
		uint16_t size = 0;

		bx::ErrorAssert err;

		uint16_t count = uint16_t(uniforms.size() );
		bx::write(_shaderWriter, count, &err);

		uint32_t fragmentBit = isFragmentShader ? kUniformFragmentBit : 0;

		for (uint16_t ii = 0; ii < count; ++ii)
		{
			const Uniform& un = uniforms[ii];

			size += un.regCount*16;

			uint8_t nameSize = (uint8_t)un.name.size();
			bx::write(_shaderWriter, nameSize, &err);
			bx::write(_shaderWriter, un.name.c_str(), nameSize, &err);
			bx::write(_shaderWriter, uint8_t(un.type | fragmentBit), &err);
			bx::write(_shaderWriter, un.num, &err);
			bx::write(_shaderWriter, un.regIndex, &err);
			bx::write(_shaderWriter, un.regCount, &err);
			bx::write(_shaderWriter, un.texComponent, &err);
			bx::write(_shaderWriter, un.texDimension, &err);
			bx::write(_shaderWriter, un.texFormat, &err);

			BX_TRACE("%s, %s, %d, %d, %d"
				, un.name.c_str()
				, getUniformTypeName(UniformType::Enum(un.type & ~kUniformMask))
				, un.num
				, un.regIndex
				, un.regCount
				);
		}
		return size;
	}

	// Maps a SPIR-V image format (spv::ImageFormat) to a bgfx texture format. Shared by
	// the SPIR-V and Slang backends so there is one canonical table -- new formats are
	// handled by extending this single list. Indexed by the numeric spv::ImageFormat,
	// which is the format-agnostic value both backends read from the shader.
	inline bgfx::TextureFormat::Enum imageFormatToTextureFormat(uint32_t _spvImageFormat)
	{
		static const bgfx::TextureFormat::Enum s_textureFormats[] =
		{
			bgfx::TextureFormat::Unknown,   // spv::ImageFormatUnknown = 0
			bgfx::TextureFormat::RGBA32F,   // spv::ImageFormatRgba32f = 1
			bgfx::TextureFormat::RGBA16F,   // spv::ImageFormatRgba16f = 2
			bgfx::TextureFormat::R32F,      // spv::ImageFormatR32f = 3
			bgfx::TextureFormat::RGBA8,     // spv::ImageFormatRgba8 = 4
			bgfx::TextureFormat::RGBA8S,    // spv::ImageFormatRgba8Snorm = 5
			bgfx::TextureFormat::RG32F,     // spv::ImageFormatRg32f = 6
			bgfx::TextureFormat::RG16F,     // spv::ImageFormatRg16f = 7
			bgfx::TextureFormat::RG11B10F,  // spv::ImageFormatR11fG11fB10f = 8
			bgfx::TextureFormat::R16F,      // spv::ImageFormatR16f = 9
			bgfx::TextureFormat::RGBA16,    // spv::ImageFormatRgba16 = 10
			bgfx::TextureFormat::RGB10A2,   // spv::ImageFormatRgb10A2 = 11
			bgfx::TextureFormat::RG16,      // spv::ImageFormatRg16 = 12
			bgfx::TextureFormat::RG8,       // spv::ImageFormatRg8 = 13
			bgfx::TextureFormat::R16,       // spv::ImageFormatR16 = 14
			bgfx::TextureFormat::R8,        // spv::ImageFormatR8 = 15
			bgfx::TextureFormat::RGBA16S,   // spv::ImageFormatRgba16Snorm = 16
			bgfx::TextureFormat::RG16S,     // spv::ImageFormatRg16Snorm = 17
			bgfx::TextureFormat::RG8S,      // spv::ImageFormatRg8Snorm = 18
			bgfx::TextureFormat::R16S,      // spv::ImageFormatR16Snorm = 19
			bgfx::TextureFormat::R8S,       // spv::ImageFormatR8Snorm = 20
			bgfx::TextureFormat::RGBA32I,   // spv::ImageFormatRgba32i = 21
			bgfx::TextureFormat::RGBA16I,   // spv::ImageFormatRgba16i = 22
			bgfx::TextureFormat::RGBA8I,    // spv::ImageFormatRgba8i = 23
			bgfx::TextureFormat::R32I,      // spv::ImageFormatR32i = 24
			bgfx::TextureFormat::RG32I,     // spv::ImageFormatRg32i = 25
			bgfx::TextureFormat::RG16I,     // spv::ImageFormatRg16i = 26
			bgfx::TextureFormat::RG8I,      // spv::ImageFormatRg8i = 27
			bgfx::TextureFormat::R16I,      // spv::ImageFormatR16i = 28
			bgfx::TextureFormat::R8I,       // spv::ImageFormatR8i = 29
			bgfx::TextureFormat::RGBA32U,   // spv::ImageFormatRgba32ui = 30
			bgfx::TextureFormat::RGBA16U,   // spv::ImageFormatRgba16ui = 31
			bgfx::TextureFormat::RGBA8U,    // spv::ImageFormatRgba8ui = 32
			bgfx::TextureFormat::R32U,      // spv::ImageFormatR32ui = 33
			bgfx::TextureFormat::Unknown,   // spv::ImageFormatRgb10a2ui = 34
			bgfx::TextureFormat::RG32U,     // spv::ImageFormatRg32ui = 35
			bgfx::TextureFormat::RG16U,     // spv::ImageFormatRg16ui = 36
			bgfx::TextureFormat::RG8U,      // spv::ImageFormatRg8ui = 37
			bgfx::TextureFormat::R16U,      // spv::ImageFormatR16ui = 38
			bgfx::TextureFormat::R8U,       // spv::ImageFormatR8ui = 39
			bgfx::TextureFormat::Unknown,   // spv::ImageFormatR64ui = 40
			bgfx::TextureFormat::Unknown,   // spv::ImageFormatR64i = 41
		};

		return _spvImageFormat < BX_COUNTOF(s_textureFormats)
			? s_textureFormats[_spvImageFormat]
			: bgfx::TextureFormat::Unknown
			;
	}

	void printCode(const char* _code, int32_t _line = 0, int32_t _start = 0, int32_t _end = INT32_MAX, int32_t _column = -1);
	void strReplace(char* _str, const char* _find, const char* _replace);
	int32_t writef(bx::WriterI* _writer, const char* _format, ...);
	void writeFile(const char* _filePath, const void* _data, int32_t _size);

	bool compileGLSLShader(const Options& _options, uint32_t _version, const std::string& _code, bx::WriterI* _writer, bx::WriterI* _messages);
	bool compileHLSLShader(const Options& _options, uint32_t _version, const std::string& _code, bx::WriterI* _writer, bx::WriterI* _messages);
	bool compileDxilShader(const Options& _options, uint32_t _version, const std::string& _code, bx::WriterI* _writer, bx::WriterI* _messages);
	// Appends the sampler / storage-image / storage-buffer uniform records reflected from
	// bgfx-convention SPIR-V (texture N at binding N+kSpirvBindShift, its sampler at
	// N+kSpirvBindShift+kSpirvSamplerShift -- used to detect comparison samplers). This is
	// the single source of truth for resource reflection: the SPIR-V backend and the Metal
	// backend both call it so their envelopes carry identical texture/sampler/image tables.
	void reflectSpirvResourceUniforms(const std::vector<uint32_t>& _spirv, UniformArray& _uniforms);

	bool compileMetalShader(const Options& _options, uint32_t _version, const std::string& _code, bx::WriterI* _writer, bx::WriterI* _messages);

	// Emits the Metal (MSL) body of a compiled-shader envelope -- the uniform table,
	// the compute threadgroup trailer, the MSL code blob, the vertex-attribute table
	// and the constant-buffer size -- from bgfx-convention SPIR-V (UBO at binding
	// kSpirv{Vertex,Fragment}Binding, textures at +kSpirvBindShift, samplers at
	// +kSpirvBindShift+kSpirvSamplerShift). The envelope header (magic + varying
	// hashes) is written by the caller. Shared by the stock glslang Metal backend and
	// the Slang Metal path; _spirv is consumed (moved into SPIRV-Cross).
	bool compileMetalShaderFromSpirv(const Options& _options, uint32_t _version, std::vector<uint32_t>& _spirv, const UniformArray& _uniforms, const std::vector<uint16_t>& _attrIds, bx::WriterI* _writer, bx::WriterI* _messages);
	bool compilePSSLShader(const Options& _options, uint32_t _version, const std::string& _code, bx::WriterI* _writer, bx::WriterI* _messages);
	bool compileSPIRVShader(const Options& _options, uint32_t _version, const std::string& _code, bx::WriterI* _writer, bx::WriterI* _messages);
	bool compileWgslShader(const Options& _options, uint32_t _version, const std::string& _code, bx::WriterI* _writer, bx::WriterI* _messages);
	bool compileSlangShader(const Options& _options, uint32_t _version, ShadingLang::Enum _targetLang, const std::string& _code, bx::WriterI* _writer, bx::WriterI* _messages);

	const char* getPsslPreamble();

} // namespace bgfx

#endif // SHADERC_H_HEADER_GUARD
