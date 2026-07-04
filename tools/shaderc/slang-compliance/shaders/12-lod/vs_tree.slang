// 1-to-1 Slang port of examples/12-lod vs_tree.sc (per-stage; the FS declares its own
// sampler/uniform set). Predefined u_modelViewProj / u_modelView are auto-declared.
import bgfx_shader;

struct VSInput
{
	vec3 a_position  : POSITION;
	vec3 a_normal    : NORMAL;
	vec2 a_texcoord0 : TEXCOORD0;
};

struct V2F
{
	vec4 pos         : SV_Position;
	vec3 v_normal    : NORMAL;
	vec2 v_texcoord0 : TEXCOORD0;
	vec3 v_pos       : TEXCOORD1;
	vec3 v_view      : TEXCOORD2;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	vec3 pos = input.a_position;

	vec3 normal = input.a_normal.xyz*2.0 - 1.0;

	V2F output;
	output.pos = mul(u_modelViewProj, vec4(pos, 1.0) );
	output.v_pos = output.pos.xyz/output.pos.w;
	output.v_view = mul(u_modelView, vec4(pos, 1.0) ).xyz;

	output.v_normal = mul(u_modelView, vec4(normal, 0.0) ).xyz;
	output.v_texcoord0 = input.a_texcoord0;
	return output;
}
