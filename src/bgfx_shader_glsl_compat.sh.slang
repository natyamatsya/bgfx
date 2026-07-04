// GLSL builtin compatibility for Slang.
//
// Slang uses the HLSL spellings natively (lerp/frac/ddx/atan2/...); these wrappers give the
// GLSL spellings the bgfx example shaders use, so a ported .sc body stays verbatim. The set
// is just the builtins Slang does NOT already provide -- frac, saturate, ddx/ddy, fwidth,
// atan2 are native and need no wrapper here.
//
// Standalone (no imports): the signatures use the HLSL vector types, and the bgfx_shader
// aliases (vec3 = float3, ...) resolve to those, so a caller may spell the argument either
// way. Consumed with `import bgfx_shaders_glsl_compat;`.

// --- derivatives (GLSL dFdx/dFdy -> HLSL ddx/ddy) ---
public float  dFdx(float  _v) { return ddx(_v); }
public float2 dFdx(float2 _v) { return ddx(_v); }
public float3 dFdx(float3 _v) { return ddx(_v); }
public float4 dFdx(float4 _v) { return ddx(_v); }
public float  dFdy(float  _v) { return ddy(_v); }
public float2 dFdy(float2 _v) { return ddy(_v); }
public float3 dFdy(float3 _v) { return ddy(_v); }
public float4 dFdy(float4 _v) { return ddy(_v); }

// --- mix (GLSL) -> lerp (HLSL) ---
public float  mix(float  _a, float  _b, float  _t) { return lerp(_a, _b, _t); }
public float2 mix(float2 _a, float2 _b, float  _t) { return lerp(_a, _b, _t); }
public float3 mix(float3 _a, float3 _b, float  _t) { return lerp(_a, _b, _t); }
public float4 mix(float4 _a, float4 _b, float  _t) { return lerp(_a, _b, _t); }
public float2 mix(float2 _a, float2 _b, float2 _t) { return lerp(_a, _b, _t); }
public float3 mix(float3 _a, float3 _b, float3 _t) { return lerp(_a, _b, _t); }
public float4 mix(float4 _a, float4 _b, float4 _t) { return lerp(_a, _b, _t); }

// --- mod (GLSL) -> a - b*floor(a/b) ---
public float  mod(float  _a, float  _b) { return _a - _b*floor(_a/_b); }
public float2 mod(float2 _a, float2 _b) { return _a - _b*floor(_a/_b); }
public float3 mod(float3 _a, float3 _b) { return _a - _b*floor(_a/_b); }
public float4 mod(float4 _a, float4 _b) { return _a - _b*floor(_a/_b); }

// --- component-wise comparisons (GLSL) -> operators (HLSL) ---
public bool2 lessThan(float2 _a, float2 _b) { return _a < _b; }
public bool3 lessThan(float3 _a, float3 _b) { return _a < _b; }
public bool4 lessThan(float4 _a, float4 _b) { return _a < _b; }
public bool2 lessThanEqual(float2 _a, float2 _b) { return _a <= _b; }
public bool3 lessThanEqual(float3 _a, float3 _b) { return _a <= _b; }
public bool4 lessThanEqual(float4 _a, float4 _b) { return _a <= _b; }
public bool2 greaterThan(float2 _a, float2 _b) { return _a > _b; }
public bool3 greaterThan(float3 _a, float3 _b) { return _a > _b; }
public bool4 greaterThan(float4 _a, float4 _b) { return _a > _b; }
public bool2 greaterThanEqual(float2 _a, float2 _b) { return _a >= _b; }
public bool3 greaterThanEqual(float3 _a, float3 _b) { return _a >= _b; }
public bool4 greaterThanEqual(float4 _a, float4 _b) { return _a >= _b; }

// --- mix bool-select form: mix(a, b, cond) picks b where cond is true (GLSL) ---
public float2 mix(float2 _a, float2 _b, bool2 _t) { return lerp(_a, _b, float2(_t) ); }
public float3 mix(float3 _a, float3 _b, bool3 _t) { return lerp(_a, _b, float3(_t) ); }
public float4 mix(float4 _a, float4 _b, bool4 _t) { return lerp(_a, _b, float4(_t) ); }

// --- bit reinterpretation (GLSL) -> HLSL asuint/asint/asfloat ---
public uint   floatBitsToUint(float  _v) { return asuint(_v); }
public uint2  floatBitsToUint(float2 _v) { return asuint(_v); }
public uint3  floatBitsToUint(float3 _v) { return asuint(_v); }
public uint4  floatBitsToUint(float4 _v) { return asuint(_v); }
public int    floatBitsToInt(float  _v)  { return asint(_v); }
public int2   floatBitsToInt(float2 _v)  { return asint(_v); }
public int3   floatBitsToInt(float3 _v)  { return asint(_v); }
public int4   floatBitsToInt(float4 _v)  { return asint(_v); }
public float  uintBitsToFloat(uint  _v)  { return asfloat(_v); }
public float2 uintBitsToFloat(uint2 _v)  { return asfloat(_v); }
public float3 uintBitsToFloat(uint3 _v)  { return asfloat(_v); }
public float4 uintBitsToFloat(uint4 _v)  { return asfloat(_v); }
public float  intBitsToFloat(int  _v)    { return asfloat(_v); }
public float2 intBitsToFloat(int2 _v)    { return asfloat(_v); }
public float3 intBitsToFloat(int3 _v)    { return asfloat(_v); }
public float4 intBitsToFloat(int4 _v)    { return asfloat(_v); }

// --- inversesqrt (GLSL) -> rsqrt (HLSL) ---
public float  inversesqrt(float  _v) { return rsqrt(_v); }
public float2 inversesqrt(float2 _v) { return rsqrt(_v); }
public float3 inversesqrt(float3 _v) { return rsqrt(_v); }
public float4 inversesqrt(float4 _v) { return rsqrt(_v); }

// --- notEqual (GLSL) -> componentwise != (equal/fract are native in Slang) ---
public bool2 notEqual(float2 _a, float2 _b) { return _a != _b; }
public bool3 notEqual(float3 _a, float3 _b) { return _a != _b; }
public bool4 notEqual(float4 _a, float4 _b) { return _a != _b; }
