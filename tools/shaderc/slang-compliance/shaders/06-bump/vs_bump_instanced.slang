// 1-to-1 Slang port of examples/06-bump vs_bump_instanced.sc. The per-instance model matrix
// arrives in i_data0..3 on TEXCOORD31..28 (bgfx feeds them from a separate instance buffer),
// so unlike vs_bump.slang this one builds its own and uses no predefined model matrix.
// u_viewProj and u_view are auto-declared.
//
// Do not name that predefined uniform anywhere in this file, comments included:
// injectPredefinedUniforms scans the source text, so a mention is enough to have it
// declared, and it would then show up in the envelope that stock does not have.
import bgfx_shader;

struct VSInput
{
	vec3 a_position  : POSITION;
	vec4 a_normal    : NORMAL;
	vec4 a_tangent   : TANGENT;
	vec2 a_texcoord0 : TEXCOORD0;
	vec4 i_data0     : TEXCOORD31;
	vec4 i_data1     : TEXCOORD30;
	vec4 i_data2     : TEXCOORD29;
	vec4 i_data3     : TEXCOORD28;
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
	mat4 model = mtxFromCols(input.i_data0, input.i_data1, input.i_data2, input.i_data3);

	vec3 wpos = mul(model, vec4(input.a_position, 1.0) ).xyz;
	output.pos = mul(u_viewProj, vec4(wpos, 1.0) );

	vec4 normal = input.a_normal * 2.0 - 1.0;
	vec3 wnormal = mul(model, vec4(normal.xyz, 0.0) ).xyz;

	vec4 tangent = input.a_tangent * 2.0 - 1.0;
	vec3 wtangent = mul(model, vec4(tangent.xyz, 0.0) ).xyz;

	output.v_normal = wnormal;
	output.v_tangent = wtangent;
	output.v_bitangent = cross(output.v_normal, output.v_tangent) * tangent.w;

	mat3 tbn = mtxFromCols(output.v_tangent, output.v_bitangent, output.v_normal);

	output.v_wpos = wpos;

	vec3 weyepos = mul(vec4(0.0, 0.0, 0.0, 1.0), u_view).xyz;
	output.v_view = mul(weyepos - wpos, tbn);

	output.v_texcoord0 = input.a_texcoord0;
	return output;
}
