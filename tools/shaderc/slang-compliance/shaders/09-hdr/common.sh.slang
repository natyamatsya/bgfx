// Slang port of examples/09-hdr/common.sh -- the example-local (non-shaderlib) helpers
// shared by the 09-hdr shaders. `import common;`.
//
// The uniforms and `#define u_time u_tonemap.w` from the stock common.sh are NOT ported
// here: uniforms are declared per-shader (each shader uses a different u_offset extent),
// so hoisting them into a shared module would change the reflected UBO layout. Only the
// reusable functions live here; the SPIR-V dead-strip gate keeps unused ones out of an
// importer's envelope.
import bgfx_shader;

public float reinhard(float _x)
{
	return _x / (_x + 1.0);
}

public vec3 reinhard(vec3 _x)
{
	return _x / (_x + 1.0);
}

public float reinhard2(float _x, float _whiteSqr)
{
	return (_x * (1.0 + _x/_whiteSqr) ) / (1.0 + _x);
}

public vec3 reinhard2(vec3 _x, float _whiteSqr)
{
	return (_x * (1.0 + _x/_whiteSqr) ) / (1.0 + _x);
}

// blur9() adapted to the (Texture2D, SamplerState) sampling-pair convention: the stock
// common.sh takes a sampler2D; here the texture and its paired sampler are passed
// explicitly and sampled via texture2D(_tex, _sampler, _uv).
public vec4 blur9(Texture2D _tex, SamplerState _sampler, vec2 _uv0, vec4 _uv1, vec4 _uv2, vec4 _uv3, vec4 _uv4)
{
	const float _BLUR9_WEIGHT_0 = 1.0;
	const float _BLUR9_WEIGHT_1 = 0.9;
	const float _BLUR9_WEIGHT_2 = 0.55;
	const float _BLUR9_WEIGHT_3 = 0.18;
	const float _BLUR9_WEIGHT_4 = 0.1;
	const float _BLUR9_NORMALIZE = (_BLUR9_WEIGHT_0+2.0*(_BLUR9_WEIGHT_1+_BLUR9_WEIGHT_2+_BLUR9_WEIGHT_3+_BLUR9_WEIGHT_4) );

	vec4 blur;
	blur  = texture2D(_tex, _sampler, _uv0)*(_BLUR9_WEIGHT_0/_BLUR9_NORMALIZE);
	blur += texture2D(_tex, _sampler, _uv1.xy)*(_BLUR9_WEIGHT_1/_BLUR9_NORMALIZE);
	blur += texture2D(_tex, _sampler, _uv1.zw)*(_BLUR9_WEIGHT_1/_BLUR9_NORMALIZE);
	blur += texture2D(_tex, _sampler, _uv2.xy)*(_BLUR9_WEIGHT_2/_BLUR9_NORMALIZE);
	blur += texture2D(_tex, _sampler, _uv2.zw)*(_BLUR9_WEIGHT_2/_BLUR9_NORMALIZE);
	blur += texture2D(_tex, _sampler, _uv3.xy)*(_BLUR9_WEIGHT_3/_BLUR9_NORMALIZE);
	blur += texture2D(_tex, _sampler, _uv3.zw)*(_BLUR9_WEIGHT_3/_BLUR9_NORMALIZE);
	blur += texture2D(_tex, _sampler, _uv4.xy)*(_BLUR9_WEIGHT_4/_BLUR9_NORMALIZE);
	blur += texture2D(_tex, _sampler, _uv4.zw)*(_BLUR9_WEIGHT_4/_BLUR9_NORMALIZE);
	return blur;
}
