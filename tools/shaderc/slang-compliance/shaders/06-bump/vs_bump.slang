// 1-to-1 Slang port of examples/06-bump vs_bump.sc. Predefined u_model/u_viewProj/u_view
// are auto-declared; u_model[0] -> u_model (single matrix).
import bgfx_shader;

struct VSInput
{
	vec3 a_position  : POSITION;
	vec4 a_normal    : NORMAL;
	vec4 a_tangent   : TANGENT;
	vec2 a_texcoord0 : TEXCOORD0;
};

struct V2F
{
	vec4 pos         : SV_Position;
	vec3 v_wpos      : TEXCOORD1;
	vec3 v_view      : TEXCOORD2;
	vec3 v_normal    : NORMAL;
	vec3 v_tangent   : TANGENT;
	vec3 v_bitangent : BINORMAL;
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	vec3 wpos = mul(u_model, vec4(input.a_position, 1.0) ).xyz;
	output.v_wpos = wpos;
	output.pos = mul(u_viewProj, vec4(wpos, 1.0) );
	vec4 normal = input.a_normal * 2.0 - 1.0;
	vec4 tangent = input.a_tangent * 2.0 - 1.0;
	vec3 wnormal = mul(u_model, vec4(normal.xyz, 0.0) ).xyz;
	vec3 wtangent = mul(u_model, vec4(tangent.xyz, 0.0) ).xyz;
	output.v_normal = normalize(wnormal);
	output.v_tangent = normalize(wtangent);
	output.v_bitangent = cross(output.v_normal, output.v_tangent) * tangent.w;
	mat3 tbn = mtxFromCols(output.v_tangent, output.v_bitangent, output.v_normal);
	vec3 weyepos = mul(vec4(0.0, 0.0, 0.0, 1.0), u_view).xyz;
	output.v_view = mul(weyepos - wpos, tbn);
	output.v_texcoord0 = input.a_texcoord0;
	return output;
}
