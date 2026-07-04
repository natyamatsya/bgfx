// 1-to-1 Slang port of examples/27-terrain vs_terrain_height_texture.sc.
// Predefined u_modelViewProj is auto-declared; use directly.
import bgfx_shader;

Texture2D    s_heightTexture        : register(t0);
SamplerState s_heightTextureSampler : register(s0);

struct VSInput
{
	vec3 a_position  : POSITION;
	vec2 a_texcoord0 : TEXCOORD0;
};

struct V2F
{
	vec4 pos         : SV_Position;
	vec2 v_texcoord0 : TEXCOORD0;
	vec3 v_position  : TEXCOORD1;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	output.v_texcoord0 = input.a_texcoord0;
	output.v_position = input.a_position.xyz;
	output.v_position.y = texture2DLod(s_heightTexture, s_heightTextureSampler, input.a_texcoord0, 0).x * 255.0;

	output.pos = mul(u_modelViewProj, vec4(output.v_position.xyz, 1.0));
	return output;
}
