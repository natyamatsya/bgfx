// 1-to-1 Slang port of examples/44-sss vs_sss_gbuffer.sc.
// Predefined u_modelViewProj/u_model are auto-declared; u_model[0] -> u_model.
// parameters.sh is included by the stock shader but no u_params macro is referenced,
// so u_params is dead-stripped and not declared here.
import bgfx_shader;

struct VSInput
{
	vec4 a_position  : POSITION;
	vec2 a_texcoord0 : TEXCOORD0;
	vec3 a_normal    : NORMAL;
};

struct V2F
{
	vec4 pos         : SV_Position;
	vec3 v_normal    : NORMAL;
	vec2 v_texcoord0 : TEXCOORD0;
	vec4 v_texcoord1 : TEXCOORD1;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;

	// Calculate vertex position
	vec3 pos = input.a_position.xyz;
	output.pos = mul(u_modelViewProj, vec4(pos, 1.0));

	// Calculate normal, unpack
	vec3 osNormal = input.a_normal.xyz * 2.0 - 1.0;

	// Transform normal into world space
	vec3 wsNormal = mul(u_model, vec4(osNormal, 0.0)).xyz;
	output.v_normal.xyz = normalize(wsNormal);

	output.v_texcoord0 = input.a_texcoord0;

	// Pass through world space position
	vec3 wsPos  = mul(u_model, vec4(pos, 1.0)).xyz;
	output.v_texcoord1 = vec4(wsPos, 1.0);

	return output;
}
