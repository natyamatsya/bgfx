// 1-to-1 Slang port of examples/51-gpufont vs_slug.sc — reference vertex shader for
// the Slug algorithm (Copyright 2017, Eric Lengyel, MIT License).
// Predefined u_modelViewProj / u_viewRect are auto-declared; u_params is custom.
import bgfx_shader;
import bgfx_shader_glsl_compat;

uniform float4 u_params;

struct VSInput
{
	vec4 a_position  : POSITION;
	vec4 a_texcoord0 : TEXCOORD0;
	vec4 a_texcoord1 : TEXCOORD1;
};

struct V2F
{
	vec4 pos         : SV_Position;
	vec2 v_texcoord0 : TEXCOORD0;
	nointerpolation vec4 v_banding : TEXCOORD1;
	nointerpolation vec4 v_glyph   : TEXCOORD2;
};

void slugUnpack(vec4 _bnd, vec2 _bits, out vec4 _outBanding, out vec4 _outGlyph)
{
	uvec2 g = floatBitsToUint(_bits);
	_outGlyph   = vec4(g.x & 0xffffu, g.x >> 16u, g.y & 0xffffu, g.y >> 16u);
	_outBanding = _bnd;
}

vec2 slugDilate(vec2 _pos, vec2 _normal, vec2 _tex, vec4 _jac, vec2 _dim, out vec2 _outPos)
{
	vec2 n = normalize(_normal);

	vec4 pClip = mul(u_modelViewProj, vec4(_pos, 0.0, 1.0) );
	vec4 nClip = mul(u_modelViewProj, vec4(n, 0.0, 0.0) );

	float s = pClip.w;
	float t = nClip.w;

	float u = (s * nClip.x - t * pClip.x) * _dim.x;
	float v = (s * nClip.y - t * pClip.y) * _dim.y;

	float s2 = s * s;
	float st = s * t;
	float uv = u * u + v * v;
	vec2  d  = _normal * (s2 * (st + sqrt(uv) ) / (uv - st * st) );

	_outPos = _pos + d;
	return vec2(_tex.x + dot(d, _jac.xy), _tex.y + dot(d, _jac.zw) );
}

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;

	vec2 p;
	vec4 jacobian = vec4(u_params.w, 0.0, 0.0, u_params.w);

	// Apply dynamic dilation to vertex position. Returns new em-space sample position.

	vec2 pos    = input.a_position.xy;
	vec2 normal = input.a_position.zw;
	vec2 uv     = input.a_texcoord0.xy;
	vec2 bits   = input.a_texcoord0.zw;

	output.v_texcoord0 = slugDilate(pos, normal, uv, jacobian, u_viewRect.zw, p);

	// Apply MVP matrix to dilated vertex position.

	output.pos = mul(u_modelViewProj, vec4(p, 0.0, 1.0) );

	// Unpack or pass through remaining vertex data.

	slugUnpack(input.a_texcoord1, bits, output.v_banding, output.v_glyph);

	return output;
}
