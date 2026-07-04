// 1-to-1 Slang port of examples/49-hextile vs_hextile.sc. Predefined u_model/u_viewProj
// are auto-declared; u_model[0] -> u_model (single matrix).
import bgfx_shader;

struct VSInput
{
	vec3 a_position  : POSITION;
	vec2 a_texcoord0 : TEXCOORD0;
};

struct V2F
{
	vec4 pos         : SV_Position;
	vec3 v_position  : TEXCOORD1;
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	vec3 vp = mul(u_model, vec4(input.a_position.xyz, 1.0) ).xyz;
	output.v_position = vp;
	output.v_texcoord0 = mul(u_model, vec4(input.a_texcoord0.xy, 1.0, 1.0) ).xy;
	output.pos = mul(u_viewProj, vec4(vp.xyz, 1.0) );
	return output;
}
