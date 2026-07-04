/*
 * Copyright 2011-2026 Branimir Karadzic. All rights reserved.
 * License: https://github.com/bkaradzic/bgfx/blob/master/LICENSE
 */

#include "shaderc.h"

#if SHADERC_CONFIG_HAS_SLANG

#include <slang.h>
#include <slang-com-ptr.h>

#include "../../src/shader.h" // kSpirv* binding-shift constants (shared with shaderc_spirv.cpp)
#include <spirv.hpp>          // spv::Op / spv::Decoration / spv::MagicNumber

#include <bx/os.h>            // bx::dlopen/dlsym/dlclose
#include <bx/filepath.h>      // bx::FilePath, bx::Dir
#include <bx/file.h>          // bx::DirectoryReader, bx::FileReader
#include <bx/readerwriter.h>  // bx::write
#include <bx/hash.h>          // bx::HashMurmur2A
#include <bx/string.h>

#include <string>
#include <vector>
#include <algorithm>

namespace bgfx
{
	// Slang is loaded dynamically at runtime (like DXC in shaderc_dxil.cpp), so it
	// stays an optional backend and its bundled glslang/spirv-tools never collide
	// with bgfx's own. Compilation uses the COM vtable through a single dlsym'd
	// factory; reflection uses the Slang C API through dlsym'd pointers, because
	// slang.h's C++ reflection wrappers are inline forwarders that would otherwise
	// require link-time symbols. See docs/adr/0001-slang-reflection-source.md.

	// C reflection handles are opaque typedefs in slang.h; slang::ProgramLayout* et
	// al. cast to them (that is exactly what the inline wrappers do).
	typedef SlangResult (*PFN_slang_createGlobalSession)(SlangInt apiVersion, slang::IGlobalSession** outGlobalSession);

	// A move-only dlopen handle: it closes on destruction (so the compiler's early returns
	// are leak-free with no manual unload) and transfers ownership when load() returns the
	// table by value.
	struct SlangHandle
	{
		void* ptr = NULL;

		SlangHandle() = default;
		~SlangHandle() { if (NULL != ptr) { bx::dlclose(ptr); } }
		SlangHandle(SlangHandle&& _rhs) noexcept : ptr(_rhs.ptr) { _rhs.ptr = NULL; }
		SlangHandle& operator=(SlangHandle&& _rhs) noexcept { bx::swap(ptr, _rhs.ptr); return *this; }
		SlangHandle(const SlangHandle&) = delete;
		SlangHandle& operator=(const SlangHandle&) = delete;
	};

	struct SlangDll
	{
		SlangHandle dll; // the only owning member -- makes SlangDll move-only, copy deleted

		PFN_slang_createGlobalSession createGlobalSession = NULL;

		// --- reflection C API (signatures derived from slang.h inline wrappers) ---
		unsigned                       (*Reflection_GetParameterCount)(SlangReflection*) = NULL;
		SlangReflectionVariableLayout* (*Reflection_getGlobalParamsVarLayout)(SlangReflection*) = NULL;
		SlangUInt                      (*Reflection_getEntryPointCount)(SlangReflection*) = NULL;
		SlangReflectionEntryPoint*     (*Reflection_getEntryPointByIndex)(SlangReflection*, SlangUInt) = NULL;

		SlangStage                     (*EntryPoint_getStage)(SlangReflectionEntryPoint*) = NULL;
		char const*                    (*EntryPoint_getName)(SlangReflectionEntryPoint*) = NULL;
		SlangReflectionVariableLayout* (*EntryPoint_getVarLayout)(SlangReflectionEntryPoint*) = NULL;
		SlangReflectionVariableLayout* (*EntryPoint_getResultVarLayout)(SlangReflectionEntryPoint*) = NULL;

		SlangReflectionVariable*       (*VariableLayout_GetVariable)(SlangReflectionVariableLayout*) = NULL;
		SlangReflectionTypeLayout*     (*VariableLayout_GetTypeLayout)(SlangReflectionVariableLayout*) = NULL;
		size_t                         (*VariableLayout_GetOffset)(SlangReflectionVariableLayout*, SlangParameterCategory) = NULL;
		char const*                    (*VariableLayout_GetSemanticName)(SlangReflectionVariableLayout*) = NULL;

		char const*                    (*Variable_GetName)(SlangReflectionVariable*) = NULL;

		SlangTypeKind                  (*TypeLayout_getKind)(SlangReflectionTypeLayout*) = NULL;
		SlangReflectionType*           (*TypeLayout_GetType)(SlangReflectionTypeLayout*) = NULL;
		unsigned                       (*TypeLayout_GetFieldCount)(SlangReflectionTypeLayout*) = NULL;
		SlangReflectionVariableLayout* (*TypeLayout_GetFieldByIndex)(SlangReflectionTypeLayout*, unsigned) = NULL;
		SlangReflectionTypeLayout*     (*TypeLayout_GetElementTypeLayout)(SlangReflectionTypeLayout*) = NULL;

		SlangTypeKind                  (*Type_GetKind)(SlangReflectionType*) = NULL;
		SlangScalarType                (*Type_GetScalarType)(SlangReflectionType*) = NULL;
		unsigned                       (*Type_GetRowCount)(SlangReflectionType*) = NULL;
		unsigned                       (*Type_GetColumnCount)(SlangReflectionType*) = NULL;
		size_t                         (*Type_GetElementCount)(SlangReflectionType*, SlangReflection*) = NULL;
		SlangResourceShape             (*Type_GetResourceShape)(SlangReflectionType*) = NULL;
		SlangReflectionType*           (*Type_GetResourceResultType)(SlangReflectionType*) = NULL;
		const char*                    (*Type_GetName)(SlangReflectionType*) = NULL;
		SlangResourceAccess            (*Type_GetResourceAccess)(SlangReflectionType*) = NULL;
	};

	// Binds a dlsym'd Slang C-API entry point into _member. Fn (the exact function-pointer
	// type) is deduced from the member, so the void* -> typed-pointer cast stays local and
	// type-checked instead of living in a macro. False, with a message, if the symbol is missing.
	template<typename Fn>
	static bool bindSymbol(Fn& _member, void* _dll, const char* _symbol, bx::WriterI* _messageWriter)
	{
		bx::ErrorIgnore err;
		_member = (Fn)bx::dlsym(_dll, _symbol);
		if (NULL == _member)
		{
			bx::write(_messageWriter, &err, "Error: Symbol '%s' not found in Slang library.\n", _symbol);
			return false;
		}

		return true;
	}

	static SlangDll load(bx::WriterI* _messageWriter)
	{
		SlangDll slang;
		bx::ErrorIgnore err;

		const char* slangDllName =
#if BX_PLATFORM_WINDOWS
			"slang.dll"
#elif BX_PLATFORM_OSX
			"libslang.dylib"
#elif BX_PLATFORM_LINUX
			"libslang.so"
#else
			"libslang"
#endif // BX_PLATFORM_
			;

		bx::FilePath slangDll = bx::FilePath(bx::Dir::Executable).getPath();
		slangDll.join(slangDllName);

		slang.dll.ptr = bx::dlopen(slangDll.getCPtr() );
		if (NULL == slang.dll.ptr)
		{
			// Fall back to the system loader search path (LD_LIBRARY_PATH / rpath).
			slang.dll.ptr = bx::dlopen(slangDllName);
		}

		if (NULL == slang.dll.ptr)
		{
			bx::write(_messageWriter, &err, "Error: Unable to open Slang shader compiler '%s'.\n", slangDllName);
			return SlangDll{};
		}

		auto bind = [&](auto& _member, const char* _symbol)
		{
			return bindSymbol(_member, slang.dll.ptr, _symbol, _messageWriter);
		};

		const bool ok =
			   bind(slang.createGlobalSession,                 "slang_createGlobalSession")
			&& bind(slang.Reflection_GetParameterCount,        "spReflection_GetParameterCount")
			&& bind(slang.Reflection_getGlobalParamsVarLayout, "spReflection_getGlobalParamsVarLayout")
			&& bind(slang.Reflection_getEntryPointCount,       "spReflection_getEntryPointCount")
			&& bind(slang.Reflection_getEntryPointByIndex,     "spReflection_getEntryPointByIndex")
			&& bind(slang.EntryPoint_getStage,                 "spReflectionEntryPoint_getStage")
			&& bind(slang.EntryPoint_getName,                  "spReflectionEntryPoint_getName")
			&& bind(slang.EntryPoint_getVarLayout,             "spReflectionEntryPoint_getVarLayout")
			&& bind(slang.EntryPoint_getResultVarLayout,       "spReflectionEntryPoint_getResultVarLayout")
			&& bind(slang.VariableLayout_GetVariable,          "spReflectionVariableLayout_GetVariable")
			&& bind(slang.VariableLayout_GetTypeLayout,        "spReflectionVariableLayout_GetTypeLayout")
			&& bind(slang.VariableLayout_GetOffset,            "spReflectionVariableLayout_GetOffset")
			&& bind(slang.VariableLayout_GetSemanticName,      "spReflectionVariableLayout_GetSemanticName")
			&& bind(slang.Variable_GetName,                    "spReflectionVariable_GetName")
			&& bind(slang.TypeLayout_getKind,                  "spReflectionTypeLayout_getKind")
			&& bind(slang.TypeLayout_GetType,                  "spReflectionTypeLayout_GetType")
			&& bind(slang.TypeLayout_GetFieldCount,            "spReflectionTypeLayout_GetFieldCount")
			&& bind(slang.TypeLayout_GetFieldByIndex,          "spReflectionTypeLayout_GetFieldByIndex")
			&& bind(slang.TypeLayout_GetElementTypeLayout,     "spReflectionTypeLayout_GetElementTypeLayout")
			&& bind(slang.Type_GetKind,                        "spReflectionType_GetKind")
			&& bind(slang.Type_GetScalarType,                  "spReflectionType_GetScalarType")
			&& bind(slang.Type_GetRowCount,                    "spReflectionType_GetRowCount")
			&& bind(slang.Type_GetColumnCount,                 "spReflectionType_GetColumnCount")
			&& bind(slang.Type_GetElementCount,                "spReflectionType_GetElementCount")
			&& bind(slang.Type_GetResourceShape,               "spReflectionType_GetResourceShape")
			&& bind(slang.Type_GetResourceResultType,          "spReflectionType_GetResourceResultType")
			&& bind(slang.Type_GetName,                        "spReflectionType_GetName")
			&& bind(slang.Type_GetResourceAccess,              "spReflectionType_GetResourceAccess")
			;

		if (!ok)
		{
			return SlangDll{};
		}

		return slang;
	}

	// Maps a Slang vertex-input semantic name to a bgfx attribute. The envelope
	// uniform writer is shared: see writeUniformArray in shaderc.h.
	static const char* s_attribNameSlang[] =
	{
		"a_position", "a_normal", "a_tangent", "a_bitangent",
		"a_color0", "a_color1", "a_color2", "a_color3",
		"a_indices", "a_weight",
		"a_texcoord0", "a_texcoord1", "a_texcoord2", "a_texcoord3",
		"a_texcoord4", "a_texcoord5", "a_texcoord6", "a_texcoord7",
		"a_texcoord8", "a_texcoord9", "a_texcoord10", "a_texcoord11",
		"a_texcoord12", "a_texcoord13", "a_texcoord14", "a_texcoord15",
	};
	static_assert(bgfx::Attrib::Count == BX_COUNTOF(s_attribNameSlang) );

	static bgfx::Attrib::Enum toAttribEnumSlang(const bx::StringView& _name)
	{
		for (uint8_t ii = 0; ii < Attrib::Count; ++ii)
		{
			if (0 == bx::strCmp(s_attribNameSlang[ii], _name) )
			{
				return bgfx::Attrib::Enum(ii);
			}
		}
		return bgfx::Attrib::Count;
	}

	// Reproduce parseInOut's hash (shaderc.cpp:1075) over a set of varying names so a Slang
	// VS and FS that share varyings produce matching output/input hashes. Takes the names by
	// value: it sorts them to hash order-independently, without disturbing the caller's list.
	static uint32_t hashVaryings(std::vector<std::string> _names)
	{
		if (_names.empty() )
		{
			return 0;
		}

		std::sort(_names.begin(), _names.end() );

		bx::HashMurmur2A murmur;
		murmur.begin();
		for (const std::string& name : _names)
		{
			murmur.add(name.c_str(), (uint32_t)name.size() );
		}
		return murmur.end();
	}

	// Collect leaf varying field names (excluding system-value semantics like
	// SV_Position) from a struct type layout.
	static void collectVaryings(const SlangDll& _slang, SlangReflectionTypeLayout* _tl, SlangParameterCategory _category, std::vector<std::string>& _out)
	{
		if (NULL == _tl)
		{
			return;
		}

		SlangTypeKind kind = _slang.TypeLayout_getKind(_tl);
		if (SLANG_TYPE_KIND_STRUCT == kind)
		{
			unsigned fieldCount = _slang.TypeLayout_GetFieldCount(_tl);
			for (unsigned ii = 0; ii < fieldCount; ++ii)
			{
				SlangReflectionVariableLayout* field = _slang.TypeLayout_GetFieldByIndex(_tl, ii);
				collectVaryings(_slang, _slang.VariableLayout_GetTypeLayout(field), _category, _out);

				const char* semantic = _slang.VariableLayout_GetSemanticName(field);
				if (NULL != semantic
				&&  0 == bx::strCmpI(bx::StringView(semantic, 3), "SV_") )
				{
					continue;
				}

				SlangReflectionVariable* var = _slang.VariableLayout_GetVariable(field);
				const char* name = _slang.Variable_GetName(var);
				if (NULL != name
				&&  SLANG_TYPE_KIND_STRUCT != _slang.TypeLayout_getKind(_slang.VariableLayout_GetTypeLayout(field) ) )
				{
					_out.push_back(name);
				}
			}
		}
	}

	// Map a scalar/vector/matrix field to a bgfx UniformType record.
	static bool toUniform(const SlangDll& _slang, SlangReflectionVariableLayout* _field, Uniform& _un)
	{
		SlangReflectionTypeLayout* tl = _slang.VariableLayout_GetTypeLayout(_field);
		SlangTypeKind kind = _slang.TypeLayout_getKind(tl);

		uint8_t num = 1;
		if (SLANG_TYPE_KIND_ARRAY == kind)
		{
			SlangReflectionType* arrType = _slang.TypeLayout_GetType(tl);
			num = (uint8_t)_slang.Type_GetElementCount(arrType, NULL);
			tl  = _slang.TypeLayout_GetElementTypeLayout(tl);
			kind = _slang.TypeLayout_getKind(tl);
		}

		SlangReflectionType* type = _slang.TypeLayout_GetType(tl);

		_un.num = num;
		_un.regIndex = (uint16_t)_slang.VariableLayout_GetOffset(_field, SLANG_PARAMETER_CATEGORY_UNIFORM);
		_un.texComponent = 0;
		_un.texDimension = 0;
		_un.texFormat = 0;

		switch (kind)
		{
		case SLANG_TYPE_KIND_MATRIX:
			{
				unsigned rows = _slang.Type_GetRowCount(type);
				if (3 == rows)
				{
					_un.type = UniformType::Mat3;
					_un.regCount = uint16_t(num*3);
				}
				else
				{
					_un.type = UniformType::Mat4;
					_un.regCount = uint16_t(num*4);
				}
			}
			return true;

		case SLANG_TYPE_KIND_VECTOR:
		case SLANG_TYPE_KIND_SCALAR:
			_un.type = UniformType::Vec4;
			_un.regCount = num;
			return true;

		default:
			break;
		}

		return false;
	}

	// Maps a Slang texture resource shape to a bgfx texture dimension. False if the shape
	// is not a texture (a buffer, etc.). Shared by the sampler and storage-image mappings.
	static bool toTextureDimension(SlangResourceShape _shape, bgfx::TextureDimension::Enum& _dim)
	{
		switch (_shape & SLANG_RESOURCE_BASE_SHAPE_MASK)
		{
		case SLANG_TEXTURE_1D:   _dim = bgfx::TextureDimension::Dimension1D; break;
		case SLANG_TEXTURE_2D:   _dim = (_shape & SLANG_TEXTURE_ARRAY_FLAG) ? bgfx::TextureDimension::Dimension2DArray : bgfx::TextureDimension::Dimension2D; break;
		case SLANG_TEXTURE_3D:   _dim = bgfx::TextureDimension::Dimension3D; break;
		case SLANG_TEXTURE_CUBE: _dim = (_shape & SLANG_TEXTURE_ARRAY_FLAG) ? bgfx::TextureDimension::DimensionCubeArray : bgfx::TextureDimension::DimensionCube; break;
		default: return false;
		}

		return true;
	}

	// The bgfx component type of a texture/image element (its result scalar: float/int/uint).
	static bgfx::TextureComponentType::Enum toTextureComponent(const SlangDll& _slang, SlangReflectionType* _type)
	{
		SlangReflectionType* resultType = _slang.Type_GetResourceResultType(_type);
		if (NULL != resultType)
		{
			switch (_slang.Type_GetScalarType(resultType) )
			{
			case SLANG_SCALAR_TYPE_INT32:  return bgfx::TextureComponentType::Int;
			case SLANG_SCALAR_TYPE_UINT32: return bgfx::TextureComponentType::Uint;
			default: break;
			}
		}

		return bgfx::TextureComponentType::Float;
	}

	static uint32_t spirvImageFormatForName(slang::IBlob* _spirv, const char* _name); // defined below

	// Map a Slang texture Resource field to a bgfx sampler uniform record, matching
	// shaderc_spirv.cpp's SPIRV-Cross sampled-image reflection. Returns false for
	// non-texture resources (storage buffers/images -- a later tier). The envelope
	// regIndex is the texture's SPIR-V binding: its logical register + kSpirvBindShift.
	static bool toSamplerUniform(const SlangDll& _slang, SlangReflectionVariableLayout* _field, Uniform& _un, slang::IBlob* _spirv, const char* _name)
	{
		SlangReflectionTypeLayout* tl   = _slang.VariableLayout_GetTypeLayout(_field);
		SlangReflectionType*       type = _slang.TypeLayout_GetType(tl);

		// Write-accessible textures are storage images (RWTexture) -> toStorageUniform.
		const SlangResourceAccess access = _slang.Type_GetResourceAccess(type);
		if (SLANG_RESOURCE_ACCESS_READ_WRITE == access
		||  SLANG_RESOURCE_ACCESS_WRITE == access)
		{
			return false;
		}

		bgfx::TextureDimension::Enum dim;
		if (!toTextureDimension(_slang.Type_GetResourceShape(type), dim) )
		{
			return false; // structured/byte-address buffer or storage image -- not this tier
		}

		_un.type         = UniformType::Enum(UniformType::Sampler | kUniformSamplerBit);
		_un.num          = 0;
		_un.regIndex     = 0; // set by the caller from the SPIR-V binding
		_un.regCount     = 0;
		_un.texComponent = textureComponentTypeToId(toTextureComponent(_slang, type) );
		_un.texDimension = textureDimensionToId(dim);
		// A plain sampled texture (SAMPLER2D) has SPIR-V image format Unknown; a read-only
		// formatted image (bgfx IMAGE2D_RO -> a formatted sampled image) carries its storage
		// format there. Reflect whichever the SPIR-V shows, matching stock shaderc.
		_un.texFormat    = uint16_t(imageFormatToTextureFormat(spirvImageFormatForName(_spirv, _name) ) );
		return true;
	}

	// A texture's sampler is a comparison (shadow) sampler if the sibling field named
	// "<texture>Sampler" is a SamplerComparisonState (bgfx's SAMPLER2DSHADOW). Matches
	// shaderc_spirv.cpp's compare detection; the record then carries kUniformCompareBit.
	static bool isCompareSampler(const SlangDll& _slang, SlangReflectionTypeLayout* _structTl, const char* _textureName)
	{
		std::string samplerName = _textureName;
		samplerName += "Sampler";

		const unsigned fieldCount = _slang.TypeLayout_GetFieldCount(_structTl);
		for (unsigned ii = 0; ii < fieldCount; ++ii)
		{
			SlangReflectionVariableLayout* field = _slang.TypeLayout_GetFieldByIndex(_structTl, ii);
			SlangReflectionVariable*       var   = _slang.VariableLayout_GetVariable(field);
			const char*                    name  = _slang.Variable_GetName(var);
			if (NULL != name
			&&  0 == bx::strCmp(name, samplerName.c_str() ) )
			{
				SlangReflectionType* type = _slang.TypeLayout_GetType(_slang.VariableLayout_GetTypeLayout(field) );
				const char* typeName = _slang.Type_GetName(type);
				return NULL != typeName
					&& 0 == bx::strCmp(typeName, "SamplerComparisonState");
			}
		}
		return false;
	}

	// Map a Slang storage-buffer Resource field (StructuredBuffer / ByteAddressBuffer,
	// bgfx's BUFFER_RO/WO/RW) to a bgfx storage uniform record, matching
	// shaderc_spirv.cpp's storage_buffers reflection: type End (| ReadOnly for a
	// read-only buffer), regCount = the StorageBuffer descriptor id. Returns false for
	// sampled textures (handled by toSamplerUniform) and storage images (a later tier).
	static bool toStorageUniform(const SlangDll& _slang, SlangReflectionVariableLayout* _field, Uniform& _un, slang::IBlob* _spirv, const char* _name)
	{
		SlangReflectionType* type = _slang.TypeLayout_GetType(_slang.VariableLayout_GetTypeLayout(_field) );
		const SlangResourceShape shape = _slang.Type_GetResourceShape(type);
		const unsigned base = shape & SLANG_RESOURCE_BASE_SHAPE_MASK;
		const bool readOnly = SLANG_RESOURCE_ACCESS_READ == _slang.Type_GetResourceAccess(type);

		_un.num          = 0;
		_un.regIndex     = 0; // set by the caller from the SPIR-V binding
		_un.type         = UniformType::Enum(UniformType::End | (readOnly ? kUniformReadOnlyBit : 0) );
		_un.texComponent = 0;
		_un.texDimension = 0;
		_un.texFormat    = 0;

		// Storage buffer (StructuredBuffer / ByteAddressBuffer).
		if (SLANG_STRUCTURED_BUFFER == base
		||  SLANG_BYTE_ADDRESS_BUFFER == base)
		{
			_un.regCount = descriptorTypeToId(bgfx::DescriptorType::StorageBuffer);
			return true;
		}

		// Storage image (RWTexture): a texture-shaped resource that toSamplerUniform did not
		// take. Component/dimension come from Slang reflection; the format is read from the
		// SPIR-V and mapped through bgfx's shared table.
		bgfx::TextureDimension::Enum dim;
		if (!toTextureDimension(shape, dim) )
		{
			return false;
		}

		_un.regCount     = descriptorTypeToId(bgfx::DescriptorType::StorageImage);
		_un.texComponent = textureComponentTypeToId(toTextureComponent(_slang, type) );
		_un.texDimension = textureDimensionToId(dim);
		_un.texFormat    = uint16_t(imageFormatToTextureFormat(spirvImageFormatForName(_spirv, _name) ) );
		return true;
	}

	// A *.sh.slang library, read into memory before loading so the loads can be ordered by
	// dependency (see preloadSlangLibraries) rather than by include-dir/file order.
	struct SlangLibrary
	{
		std::string moduleName; // file name minus ".sh.slang" -- the name `import` resolves to
		std::string path;
		std::string source;
		std::vector<std::string> imports; // module names this library `import`s
	};

	// Collects the module names a library `import`s (including `__exported import`), so the
	// preloader can order loads by dependency. Scans per line and only treats an `import` that
	// begins the line (after optional whitespace / `__exported`) as a statement, so the word
	// "import" inside a comment or string does not register a bogus -- possibly self -- dependency.
	static void parseSlangImports(const std::string& _source, std::vector<std::string>& _out)
	{
		auto isIdent = [](char _ch)
		{
			return ('a' <= _ch && _ch <= 'z')
			    || ('A' <= _ch && _ch <= 'Z')
			    || ('0' <= _ch && _ch <= '9')
			    ||  '_' == _ch;
		};
		auto skipSpace = [](const std::string& _s, size_t _p, size_t _end)
		{
			while (_p < _end && (' ' == _s[_p] || '\t' == _s[_p]) ) { ++_p; }
			return _p;
		};

		const std::string kExported = "__exported";
		const std::string kImport   = "import";
		for (size_t pos = 0; pos < _source.size(); )
		{
			const size_t eol     = _source.find('\n', pos);
			const size_t lineEnd = (std::string::npos == eol) ? _source.size() : eol;

			size_t beg = skipSpace(_source, pos, lineEnd);
			if (0 == _source.compare(beg, kExported.size(), kExported) )
			{
				beg = skipSpace(_source, beg + kExported.size(), lineEnd);
			}

			if (0 == _source.compare(beg, kImport.size(), kImport)
			&&  (beg + kImport.size() >= lineEnd || !isIdent(_source[beg + kImport.size()]) ) )
			{
				const size_t nameBeg = skipSpace(_source, beg + kImport.size(), lineEnd);
				size_t nameEnd = nameBeg;
				while (nameEnd < lineEnd && isIdent(_source[nameEnd]) ) { ++nameEnd; }
				if (nameEnd > nameBeg)
				{
					_out.push_back(_source.substr(nameBeg, nameEnd - nameBeg) );
				}
			}

			pos = (std::string::npos == eol) ? _source.size() : eol + 1;
		}
	}

	// Appends every *.sh.slang found in _dir to _libraries.
	static void collectSlangLibraries(const std::string& _dir, std::vector<SlangLibrary>& _libraries)
	{
		bx::DirectoryReader dirReader;
		if (!bx::open(&dirReader, _dir.c_str() ) )
		{
			return;
		}

		bx::Error scanErr;
		while (scanErr.isOk() )
		{
			bx::FileInfo fi;
			bx::read(&dirReader, fi, &scanErr);

			if (!scanErr.isOk()
			||  bx::FileType::File != fi.type)
			{
				continue;
			}

			// DirectoryReader yields the bare entry name; join it onto the dir.
			const bx::StringView fileName = fi.filePath.getFileName();
			if (!bx::hasSuffix(fileName, ".sh.slang") )
			{
				continue;
			}

			bx::FilePath fullPath(_dir.c_str() );
			fullPath.join(fileName);

			bx::FileReader fr;
			if (!bx::open(&fr, fullPath) )
			{
				continue;
			}

			SlangLibrary lib;
			const int32_t size = (int32_t)bx::getSize(&fr);
			lib.source.resize(size);
			bx::read(&fr, &lib.source[0], size, bx::ErrorAssert{});
			bx::close(&fr);

			lib.moduleName.assign(fileName.getPtr(), fileName.getTerm() );
			lib.moduleName.resize(lib.moduleName.size() - bx::strLen(".sh.slang") );
			lib.path = fullPath.getCPtr();
			parseSlangImports(lib.source, lib.imports);

			_libraries.push_back(lib);
		}

		bx::close(&dirReader);
	}

	// Preload every *.sh.slang in the include dirs as a Slang module named after the file
	// (minus ".sh.slang"), so shaders can `import bgfx_shader;` etc. Slang resolves imports by
	// module name, decoupled from the filename (see docs/adr/0002-slang-shader-library-composition.md).
	//
	// Loads are ordered by dependency: a library is loaded only once every *.sh.slang it imports
	// has already been loaded, so it compiles cleanly on the first attempt. Slang does not cleanly
	// recompile a module whose first compile failed (a failed load poisons the module name), so a
	// load-and-retry scheme does NOT work for a library that imports another library's types --
	// hence the explicit ordering. This keeps preloading independent of the include-dir order and
	// of the dependency DAG's shape.
	static void preloadSlangLibraries(slang::ISession* _session, const std::vector<std::string>& _includeDirs, bx::WriterI* _messageWriter)
	{
		bx::Error err;  // library diagnostics to _messageWriter (must not assert)

		std::vector<SlangLibrary> pending;
		for (const std::string& dir : _includeDirs)
		{
			collectSlangLibraries(dir, pending);
		}

		auto contains = [](const std::vector<std::string>& _v, const std::string& _s)
		{
			for (const std::string& e : _v) { if (e == _s) { return true; } }
			return false;
		};

		// Only imports that name one of our own libraries gate ordering; an `import` of a Slang
		// builtin/stdlib module is not something we preload and is ignored here.
		std::vector<std::string> known;
		for (const SlangLibrary& lib : pending)
		{
			known.push_back(lib.moduleName);
		}
		std::vector<std::string> loaded;

		for (bool progress = true; progress && !pending.empty(); )
		{
			progress = false;
			for (size_t ii = 0; ii < pending.size(); )
			{
				// Defer until every imported library has been loaded.
				bool depsReady = true;
				for (const std::string& imp : pending[ii].imports)
				{
					if (contains(known, imp)
					&&  !contains(loaded, imp) )
					{
						depsReady = false;
						break;
					}
				}

				if (!depsReady)
				{
					++ii;
					continue;
				}

				Slang::ComPtr<slang::IBlob> libDiag;
				_session->loadModuleFromSourceString(
					  pending[ii].moduleName.c_str()
					, pending[ii].path.c_str()
					, pending[ii].source.c_str()
					, libDiag.writeRef()
					);

				if (NULL != libDiag
				&&  0 != libDiag->getBufferSize() )
				{
					bx::write(_messageWriter, libDiag->getBufferPointer(), (int32_t)libDiag->getBufferSize(), &err);
				}

				// Mark loaded whether or not it compiled: a failed load will not recompile, and
				// its dependents should proceed (and surface their own errors) rather than hang.
				loaded.push_back(pending[ii].moduleName);
				pending.erase(pending.begin() + ii);
				progress = true;
			}
		}

		// Whatever is still pending sits behind an import cycle (or an import that never loaded);
		// load it once more so its diagnostics reach the user instead of silently vanishing.
		for (const SlangLibrary& lib : pending)
		{
			Slang::ComPtr<slang::IBlob> libDiag;
			_session->loadModuleFromSourceString(lib.moduleName.c_str(), lib.path.c_str(), lib.source.c_str(), libDiag.writeRef() );
			if (NULL != libDiag
			&&  0 != libDiag->getBufferSize() )
			{
				bx::write(_messageWriter, libDiag->getBufferPointer(), (int32_t)libDiag->getBufferSize(), &err);
			}
		}
	}

	// --- Minimal SPIR-V readers ------------------------------------------------------
	// The reflection needs a few facts the Slang API does not expose reliably (resource
	// bindings, storage-image formats); these read them from the emitted SPIR-V. In a
	// SPIR-V instruction the first word packs (wordCount<<16 | opcode); the operands that
	// follow are indexed from 0 below (i.e. operand k is words[insn + 1 + k]).

	// Validates the blob and yields its instruction words. False if it is not SPIR-V.
	static bool spirvWords(slang::IBlob* _spirv, const uint32_t*& _words, size_t& _count)
	{
		if (NULL == _spirv)
		{
			return false;
		}

		_words = (const uint32_t*)_spirv->getBufferPointer();
		_count = _spirv->getBufferSize() / sizeof(uint32_t);
		return _count >= 5
			&& spv::MagicNumber == _words[0]
			;
	}

	// Visits each SPIR-V instruction, calling _fn(opcode, operands, numOperands) until it
	// returns true or the stream ends. operands[k] is the instruction's k-th operand (the
	// words after the packed opcode/word-count word); numOperands excludes that word too.
	template<typename Fn>
	static void spirvForEach(const uint32_t* _words, size_t _count, Fn _fn)
	{
		for (size_t ii = 5; ii < _count; )
		{
			const uint32_t wordCount = _words[ii] >> 16;
			if (0 == wordCount)
			{
				break;
			}

			if (_fn(uint16_t(_words[ii] & 0xffff), &_words[ii+1], wordCount - 1) )
			{
				break;
			}

			ii += wordCount;
		}
	}

	// The result id named by an OpName equal to _name, or 0.
	static uint32_t spirvIdForName(const uint32_t* _words, size_t _count, const char* _name)
	{
		uint32_t id = 0;
		spirvForEach(_words, _count, [&](uint16_t _op, const uint32_t* _operands, uint32_t _numOperands)
		{
			// OpName: operand 0 = target id, operand 1.. = the name string.
			if (spv::Op::OpName == _op
			&&  _numOperands >= 2
			&&  0 == bx::strCmp( (const char*)&_operands[1], _name) )
			{
				id = _operands[0];
				return true;
			}
			return false;
		});
		return id;
	}

	// The operand at _resultIndex of the first _opcode instruction whose operand at
	// _matchIndex equals _matchValue, or 0.
	static uint32_t spirvFindOperand(const uint32_t* _words, size_t _count, uint16_t _opcode, uint32_t _matchIndex, uint32_t _matchValue, uint32_t _resultIndex)
	{
		uint32_t result = 0;
		spirvForEach(_words, _count, [&](uint16_t _op, const uint32_t* _operands, uint32_t _numOperands)
		{
			if (_opcode == _op
			&&  _matchIndex  < _numOperands
			&&  _resultIndex < _numOperands
			&&  _operands[_matchIndex] == _matchValue)
			{
				result = _operands[_resultIndex];
				return true;
			}
			return false;
		});
		return result;
	}

	// True if the SPIR-V binds anything at descriptor binding _binding (used to detect a
	// dead-stripped -- hence unused -- uniform block or resource).
	static bool spirvHasBinding(slang::IBlob* _spirv, uint32_t _binding)
	{
		const uint32_t* words;
		size_t count;
		if (!spirvWords(_spirv, words, count) )
		{
			return false;
		}

		bool found = false;
		spirvForEach(words, count, [&](uint16_t _op, const uint32_t* _operands, uint32_t _numOperands)
		{
			// OpDecorate: operand 0 = target id, 1 = decoration, 2 = value.
			if (spv::Op::OpDecorate == _op
			&&  _numOperands >= 3
			&&  spv::Decoration::DecorationBinding == _operands[1]
			&&  _binding == _operands[2])
			{
				found = true;
				return true;
			}
			return false;
		});
		return found;
	}

	// The descriptor binding of the OpVariable named _name, or UINT32_MAX. Resource
	// bindings are read from the SPIR-V by name because the reflection's
	// DESCRIPTOR_TABLE_SLOT offset is unreliable for multiple resources; absence also
	// serves as the live/dead-strip check.
	static uint32_t spirvBindingForName(slang::IBlob* _spirv, const char* _name)
	{
		const uint32_t* words;
		size_t count;
		if (!spirvWords(_spirv, words, count) )
		{
			return UINT32_MAX;
		}

		const uint32_t id = spirvIdForName(words, count, _name);
		if (0 == id)
		{
			return UINT32_MAX;
		}

		// OpDecorate id Binding <value>.
		uint32_t binding = UINT32_MAX;
		spirvForEach(words, count, [&](uint16_t _op, const uint32_t* _operands, uint32_t _numOperands)
		{
			if (spv::Op::OpDecorate == _op
			&&  _numOperands >= 3
			&&  id == _operands[0]
			&&  spv::Decoration::DecorationBinding == _operands[1])
			{
				binding = _operands[2];
				return true;
			}
			return false;
		});
		return binding;
	}

	// The spv::ImageFormat of the storage-image OpVariable named _name (0/ImageFormatUnknown
	// if none). Read from the SPIR-V so the format is taken format-agnostically and mapped
	// through bgfx's own table -- no Slang-specific format list to maintain.
	static uint32_t spirvImageFormatForName(slang::IBlob* _spirv, const char* _name)
	{
		const uint32_t* words;
		size_t count;
		if (!spirvWords(_spirv, words, count) )
		{
			return 0;
		}

		// Chase the type graph from the named variable down to the image's Format operand:
		//   OpName        _name                  -> the variable's result id
		//   OpVariable    result id == variable  -> operand 0: its pointer type
		//   OpTypePointer result id == pointer    -> operand 2: the pointee image type
		//   OpTypeImage   result id == image      -> operand 7: the Format
		const uint32_t varId     = spirvIdForName(words, count, _name);
		const uint32_t ptrType   = 0 != varId     ? spirvFindOperand(words, count, spv::Op::OpVariable,    1, varId,     0) : 0;
		const uint32_t imageType = 0 != ptrType   ? spirvFindOperand(words, count, spv::Op::OpTypePointer, 0, ptrType,   2) : 0;
		return                     0 != imageType ? spirvFindOperand(words, count, spv::Op::OpTypeImage,   0, imageType, 7) : 0;
	}

	// Creates a SPIR-V session configured for bgfx: column-major matrices and the bgfx
	// binding convention (UBO at _uboBinding; textures/samplers/images shifted per
	// src/shader.h). Returns null on failure. See the -fvk-*-shift notes in the code.
	// Forwards Slang's compiler diagnostics (warnings/errors), if any, to the message writer.
	static void writeDiagnostics(bx::WriterI* _messageWriter, slang::IBlob* _diagnostics)
	{
		if (NULL != _diagnostics
		&&  0 != _diagnostics->getBufferSize() )
		{
			bx::Error err;
			bx::write(_messageWriter, _diagnostics->getBufferPointer(), (int32_t)_diagnostics->getBufferSize(), &err);
		}
	}

	static Slang::ComPtr<slang::ISession> createSlangSession(slang::IGlobalSession* _global, int32_t _uboBinding, bx::WriterI* _messageWriter)
	{
		slang::TargetDesc target = {};
		target.format  = SLANG_SPIRV;
		target.profile = _global->findProfile("spirv_1_5");
		// bgfx runs its own spirv-opt; skip Slang's (its optimizer lives in the
		// slang-glslang companion we intentionally do not vendor).
		target.flags = 0;

		slang::SessionDesc sd = {};
		sd.targets     = &target;
		sd.targetCount = 1;
		// Matrix layout must match bgfx's convention or every matrix is transposed. bgfx's
		// stock GLSL->SPIR-V path decorates uniform matrices RowMajor, and shaders use
		// mul(M, v). Slang's layout-mode naming is INVERTED relative to the SPIR-V storage
		// decoration: COLUMN_MAJOR emits SPIR-V RowMajor (the match we want).
		sd.defaultMatrixLayoutMode = SLANG_MATRIX_LAYOUT_COLUMN_MAJOR;

		// Reproduce bgfx's SPIR-V binding convention (cf. shaderc_spirv.cpp setShiftBinding):
		// UBO at _uboBinding, textures +kSpirvBindShift, samplers +kSpirvBindShift+kSpirvSamplerShift,
		// images/RW buffers +kSpirvBindShift. The register-class "kind" values are Slang's
		// HLSLToVulkanLayoutOptions::Kind (NOT SlangParameterCategory); VulkanBindShiftAll
		// takes intValue0=kind, intValue1=shift across all descriptor sets.
		enum { SlangKindUav = 0, SlangKindSampler = 1, SlangKindSrv = 2, SlangKindCbv = 3 };
		const struct { int32_t kind; int32_t shift; } shifts[] =
		{
			{ SlangKindCbv,     _uboBinding                             },
			{ SlangKindSrv,     kSpirvBindShift                         },
			{ SlangKindSampler, kSpirvBindShift + kSpirvSamplerShift    },
			{ SlangKindUav,     kSpirvBindShift                         },
		};
		slang::CompilerOptionEntry bindShifts[BX_COUNTOF(shifts)] = {};
		for (uint32_t ii = 0; ii < BX_COUNTOF(shifts); ++ii)
		{
			bindShifts[ii].name = slang::CompilerOptionName::VulkanBindShiftAll;
			bindShifts[ii].value.intValue0 = shifts[ii].kind;
			bindShifts[ii].value.intValue1 = shifts[ii].shift;
		}
		sd.compilerOptionEntries    = bindShifts;
		sd.compilerOptionEntryCount = BX_COUNTOF(bindShifts);

		Slang::ComPtr<slang::ISession> session;
		if (SLANG_FAILED(_global->createSession(sd, session.writeRef() ) )
		||  !session)
		{
			bx::Error err;
			bx::write(_messageWriter, &err, "Error: Slang createSession failed.\n");
			return Slang::ComPtr<slang::ISession>();
		}

		return session;
	}

	// Human-readable Slang stage name, for diagnostics.
	static const char* stageName(SlangStage _stage)
	{
		switch (_stage)
		{
		case SLANG_STAGE_VERTEX:         return "vertex";
		case SLANG_STAGE_HULL:           return "hull";
		case SLANG_STAGE_DOMAIN:         return "domain";
		case SLANG_STAGE_GEOMETRY:       return "geometry";
		case SLANG_STAGE_FRAGMENT:       return "fragment";
		case SLANG_STAGE_COMPUTE:        return "compute";
		case SLANG_STAGE_RAY_GENERATION: return "raygeneration";
		case SLANG_STAGE_INTERSECTION:   return "intersection";
		case SLANG_STAGE_ANY_HIT:        return "anyhit";
		case SLANG_STAGE_CLOSEST_HIT:    return "closesthit";
		case SLANG_STAGE_MISS:           return "miss";
		case SLANG_STAGE_CALLABLE:       return "callable";
		case SLANG_STAGE_MESH:           return "mesh";
		case SLANG_STAGE_AMPLIFICATION:  return "amplification";
		default:                         return "unknown";
		}
	}

	// Finds, composes and links the entry point whose stage matches _stage, yielding its
	// linked component, program layout and entry-point reflection. If none matches, writes a
	// diagnostic naming the entry points the module *does* define -- Slang has stages (ray
	// tracing, mesh, geometry, tessellation, ...) that bgfx does not map -- and returns false.
	static bool selectEntryPoint(const SlangDll& _slang, slang::ISession* _session, slang::IModule* _module, SlangStage _stage,
		Slang::ComPtr<slang::IComponentType>& _linked, SlangReflection*& _layout, SlangReflectionEntryPoint*& _epReflect, bx::WriterI* _messageWriter)
	{
		Slang::ComPtr<slang::IBlob> diagnostics;
		bx::Error err;
		std::string found; // "<name> [<stage>], ..." accumulated for the not-found message
		bool matched = false;

		const SlangInt32 definedCount = _module->getDefinedEntryPointCount();
		for (SlangInt32 ii = 0; ii < definedCount; ++ii)
		{
			Slang::ComPtr<slang::IEntryPoint> entryPoint;
			if (SLANG_FAILED(_module->getDefinedEntryPoint(ii, entryPoint.writeRef() ) )
			||  !entryPoint)
			{
				continue;
			}

			slang::IComponentType* components[] = { _module, entryPoint.get() };
			Slang::ComPtr<slang::IComponentType> composed;
			if (SLANG_FAILED(_session->createCompositeComponentType(components, 2, composed.writeRef(), diagnostics.writeRef() ) ) )
			{
				continue;
			}

			Slang::ComPtr<slang::IComponentType> candidate;
			if (SLANG_FAILED(composed->link(candidate.writeRef(), diagnostics.writeRef() ) ) )
			{
				continue;
			}

			slang::ProgramLayout* candidateLayout = candidate->getLayout(0, diagnostics.writeRef() );
			if (NULL == candidateLayout)
			{
				continue;
			}

			// Cross from the C++ layout wrapper to the C reflection handle once, here; every
			// consumer uses the dlsym'd C API, so they take the C handles directly.
			SlangReflection* reflect = (SlangReflection*)candidateLayout;
			if (0 == _slang.Reflection_getEntryPointCount(reflect) )
			{
				continue;
			}

			SlangReflectionEntryPoint* candidateEp = _slang.Reflection_getEntryPointByIndex(reflect, 0);
			const SlangStage stage = _slang.EntryPoint_getStage(candidateEp);
			const char* name = _slang.EntryPoint_getName(candidateEp);

			if (_stage == stage)
			{
				if (!matched)
				{
					_linked    = candidate;
					_layout    = reflect;
					_epReflect = candidateEp;
					matched    = true;
				}
				else
				{
					// A second entry point of the requested stage; the first one is used.
					bx::write(_messageWriter, &err, "Warning: multiple %s entry points; using the first, ignoring '%s'.\n", stageName(_stage), (NULL != name) ? name : "?");
				}

				continue;
			}

			// Not the requested stage; remember it for the not-found diagnostic below.
			found += found.empty() ? "" : ", ";
			found += (NULL != name) ? name : "?";
			found += " [";
			found += stageName(stage);
			found += "]";
		}

		if (matched)
		{
			return true;
		}

		if (found.empty() )
		{
			bx::write(_messageWriter, &err, "Error: the Slang module defines no entry points (mark one with [shader(\"vertex\"|\"fragment\"|\"compute\")]).\n");
		}
		else
		{
			bx::write(_messageWriter, &err, "Error: no %s entry point in the Slang module. It defines: %s.\n", stageName(_stage), found.c_str() );
			bx::write(_messageWriter, &err, "Note: bgfx shaderc maps only vertex, fragment and compute shaders.\n");
		}

		return false;
	}

	// Warns that a live global parameter has a type bgfx does not map (ray-tracing
	// acceleration structures, subpass inputs, nested-struct uniforms, ...). It is dropped
	// from the envelope, so surfacing it here avoids a silent mis-bind at runtime.
	static void warnUnsupportedGlobal(bx::WriterI* _messageWriter, const SlangDll& _slang, SlangReflectionVariableLayout* _field, const char* _name)
	{
		SlangReflectionType* type = _slang.TypeLayout_GetType(_slang.VariableLayout_GetTypeLayout(_field) );
		const char* typeName = _slang.Type_GetName(type);
		bx::Error err;
		bx::write(_messageWriter, &err
			, "Warning: ignoring unsupported Slang global '%s' (%s) -- not mapped to a bgfx uniform/sampler/buffer.\n"
			, _name
			, (NULL != typeName) ? typeName : "unknown type"
			);
	}

	// Reflects the live global uniforms, samplers and storage resources into _uniforms,
	// warning about live globals whose type bgfx does not map.
	static void reflectUniforms(const SlangDll& _slang, SlangReflection* _reflect, slang::IBlob* _spirv, int32_t _uboBinding, UniformArray& _uniforms, bx::WriterI* _messageWriter)
	{
		SlangReflectionVariableLayout* globalVar = _slang.Reflection_getGlobalParamsVarLayout(_reflect);
		if (NULL == globalVar)
		{
			return;
		}

		SlangReflectionTypeLayout* globalTl = _slang.VariableLayout_GetTypeLayout(globalVar);
		SlangTypeKind globalKind = _slang.TypeLayout_getKind(globalTl);

		// Loose uniforms, textures and samplers all appear as fields of one struct:
		// either the element of the global constant buffer (when uniforms exist) or the
		// global params struct itself (texture-only shaders).
		SlangReflectionTypeLayout* structTl =
			  (SLANG_TYPE_KIND_CONSTANT_BUFFER == globalKind || SLANG_TYPE_KIND_PARAMETER_BLOCK == globalKind)
			? _slang.TypeLayout_GetElementTypeLayout(globalTl)
			: globalTl
			;

		if (NULL == structTl
		||  SLANG_TYPE_KIND_STRUCT != _slang.TypeLayout_getKind(structTl) )
		{
			return;
		}

		// bgfx serializes only live uniforms/samplers (glslang parity). Slang keeps unused
		// globals in the reflection, and IMetadata::isParameterLocationUsed is unreliable
		// once -fvk-*-shift is applied, so gate each field on the generated SPIR-V: an unused
		// UBO or texture is dead-stripped from the entry point. Loose uniforms share the
		// stage's UBO binding; each texture has its own (logical register + kSpirvBindShift).
		const bool uboUsed = spirvHasBinding(_spirv, (uint32_t)_uboBinding);

		const unsigned fieldCount = _slang.TypeLayout_GetFieldCount(structTl);
		for (unsigned ii = 0; ii < fieldCount; ++ii)
		{
			SlangReflectionVariableLayout* field = _slang.TypeLayout_GetFieldByIndex(structTl, ii);
			SlangTypeKind fieldKind = _slang.TypeLayout_getKind(_slang.VariableLayout_GetTypeLayout(field) );

			// Samplers are folded into their paired texture record.
			if (SLANG_TYPE_KIND_SAMPLER_STATE == fieldKind)
			{
				continue;
			}

			Uniform un;
			SlangReflectionVariable* var = _slang.VariableLayout_GetVariable(field);
			const char* name = _slang.Variable_GetName(var);
			if (NULL == name)
			{
				continue;
			}
			un.name = name;

			if (SLANG_TYPE_KIND_RESOURCE == fieldKind)
			{
				// Binding (and liveness) come from the SPIR-V by name.
				const uint32_t binding = spirvBindingForName(_spirv, name);
				if (UINT32_MAX == binding)
				{
					continue;
				}

				if (toSamplerUniform(_slang, field, un, _spirv, name) )
				{
					un.regIndex = uint16_t(binding);
					if (isCompareSampler(_slang, structTl, name) )
					{
						un.type = UniformType::Enum(un.type | kUniformCompareBit);
					}
					_uniforms.push_back(un);
				}
				else if (toStorageUniform(_slang, field, un, _spirv, name) )
				{
					un.regIndex = uint16_t(binding);
					_uniforms.push_back(un);
				}
				else
				{
					// Live resource we do not map (acceleration structure, subpass input, ...).
					warnUnsupportedGlobal(_messageWriter, _slang, field, name);
				}
			}
			else if (uboUsed)
			{
				// A live cbuffer member: a scalar/vector/matrix uniform, or a type we do not map.
				if (toUniform(_slang, field, un) )
				{
					_uniforms.push_back(un);
				}
				else
				{
					warnUnsupportedGlobal(_messageWriter, _slang, field, name);
				}
			}
		}
	}

	// Collects the vertex-input attribute ids, ordered by SPIR-V input location so index N
	// in the envelope corresponds to location N (which is what the renderers assume).
	static void collectAttributes(const SlangDll& _slang, SlangReflectionEntryPoint* _epReflect, std::vector<uint16_t>& _attrIds)
	{
		if (NULL == _epReflect)
		{
			return;
		}

		SlangReflectionVariableLayout* epVar = _slang.EntryPoint_getVarLayout(_epReflect);
		SlangReflectionTypeLayout* epTl = (NULL != epVar) ? _slang.VariableLayout_GetTypeLayout(epVar) : NULL;
		if (NULL == epTl
		||  SLANG_TYPE_KIND_STRUCT != _slang.TypeLayout_getKind(epTl) )
		{
			return;
		}

		std::vector<std::pair<uint32_t, uint16_t> > located;

		const unsigned paramCount = _slang.TypeLayout_GetFieldCount(epTl);
		for (unsigned ii = 0; ii < paramCount; ++ii)
		{
			SlangReflectionVariableLayout* param = _slang.TypeLayout_GetFieldByIndex(epTl, ii);
			SlangReflectionTypeLayout* paramTl = _slang.VariableLayout_GetTypeLayout(param);

			// A vertex input parameter is typically a struct (VSInput).
			if (SLANG_TYPE_KIND_STRUCT != _slang.TypeLayout_getKind(paramTl) )
			{
				continue;
			}

			const unsigned inFieldCount = _slang.TypeLayout_GetFieldCount(paramTl);
			for (unsigned jj = 0; jj < inFieldCount; ++jj)
			{
				SlangReflectionVariableLayout* inField = _slang.TypeLayout_GetFieldByIndex(paramTl, jj);
				SlangReflectionVariable* inVar = _slang.VariableLayout_GetVariable(inField);
				const char* inName = _slang.Variable_GetName(inVar);

				bgfx::Attrib::Enum attr = (NULL != inName)
					? toAttribEnumSlang(bx::StringView(inName) )
					: bgfx::Attrib::Count
					;

				uint32_t location = (uint32_t)_slang.VariableLayout_GetOffset(inField, SLANG_PARAMETER_CATEGORY_VARYING_INPUT);
				uint16_t id = bgfx::Attrib::Count != attr
					? bgfx::attribToId(attr)
					: uint16_t(UINT16_MAX)
					;
				located.push_back(std::make_pair(location, id) );
			}
		}

		std::sort(located.begin(), located.end() );
		for (size_t ii = 0; ii < located.size(); ++ii)
		{
			_attrIds.push_back(located[ii].second);
		}
	}

	// Computes the inter-stage varying hashes (matching parseInOut so a VS output hash
	// equals the paired FS input hash).
	static void computeVaryingHashes(const SlangDll& _slang, SlangReflectionEntryPoint* _epReflect, char _shaderType, uint32_t& _inputHash, uint32_t& _outputHash)
	{
		if (NULL == _epReflect)
		{
			return;
		}

		if ('v' == _shaderType)
		{
			std::vector<std::string> outs;
			SlangReflectionVariableLayout* resultVar = _slang.EntryPoint_getResultVarLayout(_epReflect);
			if (NULL != resultVar)
			{
				collectVaryings(_slang, _slang.VariableLayout_GetTypeLayout(resultVar), SLANG_PARAMETER_CATEGORY_VARYING_OUTPUT, outs);
			}
			_outputHash = hashVaryings(outs);
		}
		else if ('f' == _shaderType)
		{
			std::vector<std::string> ins;
			SlangReflectionVariableLayout* epVar = _slang.EntryPoint_getVarLayout(_epReflect);
			if (NULL != epVar)
			{
				collectVaryings(_slang, _slang.VariableLayout_GetTypeLayout(epVar), SLANG_PARAMETER_CATEGORY_VARYING_INPUT, ins);
			}
			_inputHash = hashVaryings(ins);
		}
	}

	// Writes the compiled-shader envelope (header + uniform table + code + attribute table
	// + cbuffer size), matching the layout shaderc.cpp / the SPIR-V backend produce.
	static void writeEnvelope(bx::WriterI* _writer, char _shaderType, const UniformArray& _uniforms, slang::IBlob* _spirv, const std::vector<uint16_t>& _attrIds, uint32_t _inputHash, uint32_t _outputHash)
	{
		bx::ErrorAssert err;

		if ('f' == _shaderType)
		{
			bx::write(_writer, BGFX_CHUNK_MAGIC_FSH, &err);
			bx::write(_writer, _inputHash, &err);
			bx::write(_writer, uint32_t(0), &err);
		}
		else if ('v' == _shaderType)
		{
			bx::write(_writer, BGFX_CHUNK_MAGIC_VSH, &err);
			bx::write(_writer, uint32_t(0), &err);
			bx::write(_writer, _outputHash, &err);
		}
		else
		{
			bx::write(_writer, BGFX_CHUNK_MAGIC_CSH, &err);
			bx::write(_writer, uint32_t(0), &err);
			bx::write(_writer, _outputHash, &err);
		}

		uint16_t size = writeUniformArray(_writer, _uniforms, 'f' == _shaderType);

		uint32_t shaderSize = (uint32_t)_spirv->getBufferSize();
		bx::write(_writer, shaderSize, &err);
		bx::write(_writer, _spirv->getBufferPointer(), shaderSize, &err);
		uint8_t nul = 0;
		bx::write(_writer, nul, &err);

		uint8_t numAttr = (uint8_t)_attrIds.size();
		bx::write(_writer, numAttr, &err);
		for (uint8_t ii = 0; ii < numAttr; ++ii)
		{
			bx::write(_writer, _attrIds[ii], &err);
		}

		bx::write(_writer, size, &err);
	}

	static bool isIdentChar(char _ch)
	{
		return '_' == _ch
			|| (_ch >= 'a' && _ch <= 'z')
			|| (_ch >= 'A' && _ch <= 'Z')
			|| (_ch >= '0' && _ch <= '9')
			;
	}

	// True if _name occurs in _code as a whole identifier (not a substring of a
	// longer one -- e.g. u_modelView must not match inside u_modelViewProj).
	static bool referencesIdentifier(const std::string& _code, const std::string& _name)
	{
		for (size_t pos = _code.find(_name); std::string::npos != pos; pos = _code.find(_name, pos + _name.size() ) )
		{
			const size_t end = pos + _name.size();
			if ((0 == pos             || !isIdentChar(_code[pos - 1]) )
			&&  (end >= _code.size()  || !isIdentChar(_code[end]) ) )
			{
				return true;
			}
		}

		return false;
	}

	// True if _code already declares _name as `<type> _name` -- so auto-provide can
	// skip it and not collide with a hand-written declaration.
	static bool declaresIdentifier(const std::string& _code, const std::string& _name)
	{
		for (size_t pos = _code.find(_name); std::string::npos != pos; pos = _code.find(_name, pos + _name.size() ) )
		{
			const size_t end = pos + _name.size();
			const bool bounded = (0 == pos            || !isIdentChar(_code[pos - 1]) )
			                  && (end >= _code.size() || !isIdentChar(_code[end]) );
			if (!bounded)
			{
				continue;
			}

			// Read the identifier token immediately preceding _name (skipping spaces/tabs).
			size_t back = pos;
			while (back > 0 && (' ' == _code[back - 1] || '\t' == _code[back - 1]) ) { --back; }
			const size_t tokEnd = back;
			while (back > 0 && isIdentChar(_code[back - 1]) ) { --back; }
			const std::string prev = _code.substr(back, tokEnd - back);

			if ("float"    == prev || "float2"   == prev || "float3"   == prev || "float4" == prev
			||  "float3x3" == prev || "float4x4" == prev)
			{
				return true;
			}
		}

		return false;
	}

	// Maps a bgfx_shader.sh scalar/matrix uniform type to its Slang spelling; NULL for
	// anything that is not a loose predefined uniform (samplers etc. are handled elsewhere).
	static const char* toSlangUniformType(const std::string& _glslType)
	{
		if ("vec2" == _glslType) { return "float2";   }
		if ("vec3" == _glslType) { return "float3";   }
		if ("vec4" == _glslType) { return "float4";   }
		if ("mat3" == _glslType) { return "float3x3"; }
		if ("mat4" == _glslType) { return "float4x4"; }
		return NULL;
	}

	struct PredefinedDecl
	{
		std::string name;
		std::string decl; // Slang declaration, e.g. "float4x4 u_modelViewProj;"
	};

	// Reads bgfx's predefined uniforms straight from bgfx_shader.sh -- the same file the .sc
	// path uses -- so the auto-provided set and its canonical declaration order (which fixes
	// the $Globals offsets) stay in sync with bgfx automatically, instead of being duplicated
	// here. Each top-level `uniform <type> u_name[array]?;` becomes a Slang declaration; an
	// array uniform (u_model[BGFX_CONFIG_MAX_BONES]) collapses to a single element -- Slang
	// cannot strip unused elements, and the stock compiler reflects a u_model[0] use as a
	// single matrix. Returns empty if bgfx_shader.sh is not on the include path.
	static std::vector<PredefinedDecl> readPredefinedUniforms(const std::vector<std::string>& _includeDirs)
	{
		std::string source;
		for (const std::string& dir : _includeDirs)
		{
			bx::FilePath path(dir.c_str() );
			path.join("bgfx_shader.sh");

			bx::FileReader fr;
			if (bx::open(&fr, path) )
			{
				const int32_t size = (int32_t)bx::getSize(&fr);
				source.resize(size);
				bx::read(&fr, &source[0], size, bx::ErrorAssert{});
				bx::close(&fr);
				break;
			}
		}

		std::vector<PredefinedDecl> predefined;
		for (size_t pos = 0; pos < source.size(); )
		{
			const size_t eol  = source.find('\n', pos);
			const std::string line = source.substr(pos, (std::string::npos == eol ? source.size() : eol) - pos);
			pos = (std::string::npos == eol) ? source.size() : eol + 1;

			// Match a top-level `uniform <type> u_<name> ...` declaration.
			const size_t kw = line.find_first_not_of(" \t");
			if (std::string::npos == kw
			||  0 != line.compare(kw, 8, "uniform ") )
			{
				continue;
			}

			const size_t typeBeg   = kw + 8;
			const size_t typeEnd   = line.find_first_of(" \t", typeBeg);
			const char*  slangType = toSlangUniformType(line.substr(typeBeg, typeEnd - typeBeg) );
			if (NULL == slangType)
			{
				continue;
			}

			const size_t nameBeg = line.find_first_not_of(" \t", typeEnd);
			size_t nameEnd = (std::string::npos == nameBeg) ? line.size() : nameBeg;
			while (nameEnd < line.size() && isIdentChar(line[nameEnd]) ) { ++nameEnd; }
			const std::string name = line.substr(nameBeg, nameEnd - nameBeg);
			if (name.size() < 2 || 'u' != name[0] || '_' != name[1])
			{
				continue;
			}

			PredefinedDecl pd;
			pd.name = name;
			pd.decl = std::string(slangType) + " " + name + ";"; // any array size dropped -> single element
			predefined.push_back(pd);
		}

		return predefined;
	}

	// Auto-declare the bgfx predefined uniforms a Slang shader references, in bgfx_shader.sh's
	// canonical order so their $Globals offsets match the stock compiler by construction. Only
	// the referenced ones are emitted (unused ones would bloat the envelope, since Slang does
	// not strip UBO members); a hand-written declaration of a name suppresses its injection.
	static std::string injectPredefinedUniforms(const std::string& _code, const std::vector<std::string>& _includeDirs)
	{
		const std::vector<PredefinedDecl> predefined = readPredefinedUniforms(_includeDirs);

		std::string preamble;
		for (const PredefinedDecl& pd : predefined)
		{
			if (referencesIdentifier(_code, pd.name)
			&&  !declaresIdentifier(_code, pd.name) )
			{
				preamble += pd.decl;
				preamble += "\n";
			}
		}

		if (preamble.empty() )
		{
			return _code;
		}

		// Reset the line counter so diagnostics point at the user's source lines.
		return preamble + "#line 1\n" + _code;
	}

	bool compileSlangShader(const Options& _options, uint32_t _version, const std::string& _code, bx::WriterI* _shaderWriter, bx::WriterI* _messageWriter)
	{
		BX_UNUSED(_version);
		bx::Error messageErr;      // diagnostics to _messageWriter (must not assert)

		SlangDll slang = load(_messageWriter);
		if (NULL == slang.dll.ptr)
		{
			return false;
		}

		Slang::ComPtr<slang::IGlobalSession> global;
		if (SLANG_FAILED(slang.createGlobalSession(SLANG_API_VERSION, global.writeRef() ) )
		||  !global)
		{
			bx::write(_messageWriter, &messageErr, "Error: Slang createGlobalSession failed.\n");
			return false;
		}

		const SlangStage targetStage =
			  'v' == _options.shaderType ? SLANG_STAGE_VERTEX
			: 'f' == _options.shaderType ? SLANG_STAGE_FRAGMENT
			:                              SLANG_STAGE_COMPUTE
			;

		const int32_t uboBinding = ('f' == _options.shaderType) ? kSpirvFragmentBinding : kSpirvVertexBinding;

		Slang::ComPtr<slang::ISession> session = createSlangSession(global, uboBinding, _messageWriter);
		if (!session)
		{
			return false;
		}

		// Make the bgfx Slang shader libraries (*.sh.slang) importable.
		preloadSlangLibraries(session, _options.includeDirs, _messageWriter);

		// Unless disabled, auto-declare the bgfx predefined uniforms the shader uses
		// (u_modelViewProj, ...) so authors need not restate bgfx's internal layout.
		const std::string code = _options.slangNoPredefined
			? _code
			: injectPredefinedUniforms(_code, _options.includeDirs)
			;

		Slang::ComPtr<slang::IBlob> diagnostics;
		slang::IModule* module = session->loadModuleFromSourceString(
			  "bgfx_slang"
			, _options.inputFilePath.c_str()
			, code.c_str()
			, diagnostics.writeRef()
			);

		writeDiagnostics(_messageWriter, diagnostics);

		if (NULL == module)
		{
			return false;
		}

		Slang::ComPtr<slang::IComponentType> linked;
		SlangReflection* layout = NULL;
		SlangReflectionEntryPoint* epReflect = NULL;
		if (!selectEntryPoint(slang, session, module, targetStage, linked, layout, epReflect, _messageWriter) )
		{
			return false;
		}

		// Generate SPIR-V for the selected entry point.
		Slang::ComPtr<slang::IBlob> spirvBlob;
		if (SLANG_FAILED(linked->getEntryPointCode(0, 0, spirvBlob.writeRef(), diagnostics.writeRef() ) )
		||  !spirvBlob)
		{
			writeDiagnostics(_messageWriter, diagnostics);
			return false;
		}

		UniformArray uniforms;
		reflectUniforms(slang, layout, spirvBlob, uboBinding, uniforms, _messageWriter);

		std::vector<uint16_t> attrIds;
		if ('v' == _options.shaderType)
		{
			collectAttributes(slang, epReflect, attrIds);
		}

		uint32_t inputHash  = 0;
		uint32_t outputHash = 0;
		computeVaryingHashes(slang, epReflect, _options.shaderType, inputHash, outputHash);

		writeEnvelope(_shaderWriter, _options.shaderType, uniforms, spirvBlob, attrIds, inputHash, outputHash);

		return true;
	}

} // namespace bgfx

#else

#include <bx/readerwriter.h>

namespace bgfx
{
	bool compileSlangShader(const Options& _options, uint32_t _version, const std::string& _code, bx::WriterI* _shaderWriter, bx::WriterI* _messageWriter)
	{
		BX_UNUSED(_options, _version, _code, _shaderWriter);
		bx::write(_messageWriter, bx::ErrorIgnore{}, "Slang shader support is not compiled in (vendor 3rdparty/slang to enable).\n");
		return false;
	}

} // namespace bgfx

#endif // SHADERC_CONFIG_HAS_SLANG
