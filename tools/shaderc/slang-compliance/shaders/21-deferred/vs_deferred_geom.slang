// 1-to-1 Slang port of examples/21-deferred vs_deferred_geom.sc.
// Predefined u_model/u_viewProj/u_view are auto-declared; u_model[0] -> u_model.
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
	output.pos = mul(u_viewProj, vec4(wpos, 1.0) );

	vec4 normal = input.a_normal * 2.0 - 1.0;
	vec3 wnormal = mul(u_model, vec4(normal.xyz, 0.0) ).xyz;

	vec4 tangent = input.a_tangent * 2.0 - 1.0;
	vec3 wtangent = mul(u_model, vec4(tangent.xyz, 0.0) ).xyz;

	vec3 viewNormal = normalize(mul(u_view, vec4(wnormal, 0.0) ).xyz);
	vec3 viewTangent = normalize(mul(u_view, vec4(wtangent, 0.0) ).xyz);
	vec3 viewBitangent = cross(viewNormal, viewTangent) * tangent.w;
	mat3 tbn = mtxFromCols(viewTangent, viewBitangent, viewNormal);

	output.v_wpos = wpos;

	vec3 view = mul(u_view, vec4(wpos, 0.0) ).xyz;
	output.v_view = mul(view, tbn);

	output.v_normal    = viewNormal;
	output.v_tangent   = viewTangent;
	output.v_bitangent = viewBitangent;

	output.v_texcoord0 = input.a_texcoord0;
	return output;
}
