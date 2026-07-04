// Slang shader library for bgfx.
//
// Ported from src/bgfx_shader.sh and examples/common/shaderlib.sh. Per
// docs/adr/0002-slang-shader-library-composition.md this holds the sampler
// abstraction and helper *functions* only (Slang dead-strips unused ones);
// predefined and custom uniforms are declared per-shader.
//
// Consumed with `import bgfx_shader;`. shaderc preloads every *.sh.slang in the
// include dirs as a module named after the file (minus ".sh.slang"), so the
// module name here is implicit ("bgfx_shader"). All shared symbols are `public`.

// --- GLSL-compatible type aliases ---
//
// The example shaders are written in bgfx's GLSL dialect. These aliases let a 1-to-1 port
// keep the same vec/mat spellings, so the translated body stays near-verbatim.
public typealias vec2  = float2;
public typealias vec3  = float3;
public typealias vec4  = float4;
public typealias ivec2 = int2;
public typealias ivec3 = int3;
public typealias ivec4 = int4;
public typealias uvec2 = uint2;
public typealias uvec3 = uint3;
public typealias uvec4 = uint4;
public typealias mat3  = float3x3;
public typealias mat2  = float2x2;
public typealias mat4  = float4x4;

public static const float M_PI = 3.1415926535897932384626433832795;

// --- splat + matrix construction (from bgfx_shader.sh) ---

public float rcp(float _a) { return 1.0/_a; }

public vec2 vec2_splat(float _x) { return vec2(_x, _x); }
public vec3 vec3_splat(float _x) { return vec3(_x, _x, _x); }
public vec4 vec4_splat(float _x) { return vec4(_x, _x, _x, _x); }

public uvec2 uvec2_splat(uint _x) { return uvec2(_x, _x); }
public uvec3 uvec3_splat(uint _x) { return uvec3(_x, _x, _x); }
public uvec4 uvec4_splat(uint _x) { return uvec4(_x, _x, _x, _x); }

// bgfx builds matrices from column vectors. Slang's matrix constructor is row-major (HLSL),
// so transpose to match GLSL's column-setting mat4(cols) -- i.e. bgfx's non-COLUMN_MAJOR branch.
public mat4 mtxFromCols(vec4 _0, vec4 _1, vec4 _2, vec4 _3) { return transpose(mat4(_0, _1, _2, _3) ); }
public mat3 mtxFromCols(vec3 _0, vec3 _1, vec3 _2)          { return transpose(mat3(_0, _1, _2) ); }
public mat4 mtxFromRows(vec4 _0, vec4 _1, vec4 _2, vec4 _3) { return mat4(_0, _1, _2, _3); }
public mat3 mtxFromRows(vec3 _0, vec3 _1, vec3 _2)          { return mat3(_0, _1, _2); }
public mat2 mtxFromCols(vec2 _0, vec2 _1)                   { return transpose(mat2(_0, _1) ); }
public mat2 mtxFromRows(vec2 _0, vec2 _1)                   { return mat2(_0, _1); }

// bgfx's mat4x3 (a 4x3 affine transform) is float3x4 in the HLSL/SPIR-V (non-column-major)
// world Slang emulates, and mtx accessors index the same way. These mirror bgfx_shader.sh's
// non-COLUMN_MAJOR branch (consistent with mtxFromCols above).
public typealias mat4x3 = float3x4;
public typealias mat3x3 = float3x3;
public typealias mat4x4 = float4x4;
public typealias bvec2  = bool2;
public typealias bvec3  = bool3;
public typealias bvec4  = bool4;
public mat4x3 mtxFromRows(vec4 _0, vec4 _1, vec4 _2)       { return mat4x3(_0, _1, _2); }

public vec3  mtxGetRow(mat3 _mtx, int _row)                { return vec3(_mtx[_row]); }
public vec3  mtxGetColumn(mat3 _mtx, int _col)             { return vec3(_mtx[0][_col], _mtx[1][_col], _mtx[2][_col]); }
public vec4  mtxGetRow(mat4x3 _mtx, int _row)              { return vec4(_mtx[_row]); }
public vec3  mtxGetColumn(mat4x3 _mtx, int _col)           { return vec3(_mtx[0][_col], _mtx[1][_col], _mtx[2][_col]); }
public vec4  mtxGetRow(mat4 _mtx, int _row)                { return vec4(_mtx[_row]); }
public vec4  mtxGetColumn(mat4 _mtx, int _col)             { return vec4(_mtx[0][_col], _mtx[1][_col], _mtx[2][_col], _mtx[3][_col]); }
public float mtxGetElement(mat3 _mtx, int _col, int _row)  { return _mtx[_row][_col]; }
public float mtxGetElement(mat4 _mtx, int _col, int _row)  { return _mtx[_row][_col]; }

// --- color-space helpers (from shaderlib.sh) ---

public float3 toGamma(float3 _rgb)
{
	return pow(abs(_rgb), float3(1.0 / 2.2) );
}

public float4 toGamma(float4 _rgba)
{
	return float4(toGamma(_rgba.xyz), _rgba.w);
}

public float3 toLinear(float3 _rgb)
{
	return pow(abs(_rgb), float3(2.2) );
}

public float4 toLinear(float4 _rgba)
{
	return float4(toLinear(_rgba.xyz), _rgba.w);
}

public float3 luma(float3 _rgb)
{
	return float3(dot(float3(0.2126729, 0.7151522, 0.0721750), _rgb) );
}

// --- sampler abstraction (from bgfx_shader.sh) ---
//
// bgfx's SAMPLER2D(s_tex, N) is declared per-shader as a texture + sampler pair:
//     Texture2D    s_tex        : register(tN);
//     SamplerState s_texSampler : register(sN);
// shaderc shifts those registers to bgfx's binding convention (texture at
// N+kSpirvBindShift, sampler +kSpirvSamplerShift beyond that). texture2D() and
// friends give shaders the portable sampling spelling over the pair.

public float4 texture2D(Texture2D _tex, SamplerState _sampler, float2 _uv)
{
	return _tex.Sample(_sampler, _uv);
}

public float4 texture2DLod(Texture2D _tex, SamplerState _sampler, float2 _uv, float _lod)
{
	return _tex.SampleLevel(_sampler, _uv, _lod);
}

public float4 textureCube(TextureCube _tex, SamplerState _sampler, float3 _dir)
{
	return _tex.Sample(_sampler, _dir);
}

public float4 textureCubeLod(TextureCube _tex, SamplerState _sampler, float3 _dir, float _lod)
{
	return _tex.SampleLevel(_sampler, _dir, _lod);
}

public float4 texture2DGrad(Texture2D _tex, SamplerState _sampler, float2 _uv, float2 _dpdx, float2 _dpdy)
{
	return _tex.SampleGrad(_sampler, _uv, _dpdx, _dpdy);
}

// Projective sampling (bgfx texture2DProj): divide by the last coord component.
public float4 texture2DProj(Texture2D _tex, SamplerState _sampler, float3 _coord) { return _tex.Sample(_sampler, _coord.xy * rcp(_coord.z) ); }
public float4 texture2DProj(Texture2D _tex, SamplerState _sampler, float4 _coord) { return _tex.Sample(_sampler, _coord.xy * rcp(_coord.w) ); }

// Comparison (shadow) sampling (bgfx shadow2D*), over a texture + SamplerComparisonState pair
// (bgfx SAMPLER2DSHADOW). Uses SampleCmpLevelZero to match the stock non-GLSL branch.
public float shadow2D(Texture2D _tex, SamplerComparisonState _cmp, float3 _coord)      { return _tex.SampleCmpLevelZero(_cmp, _coord.xy, _coord.z); }
public float shadow2DProj(Texture2D _tex, SamplerComparisonState _cmp, float4 _coord)  { float3 c = _coord.xyz * rcp(_coord.w); return _tex.SampleCmpLevelZero(_cmp, c.xy, c.z); }
public float4 shadow2DArray(Texture2DArray _tex, SamplerComparisonState _cmp, float4 _coord) { return float4(_tex.SampleCmpLevelZero(_cmp, _coord.xyz, _coord.w) ); }
