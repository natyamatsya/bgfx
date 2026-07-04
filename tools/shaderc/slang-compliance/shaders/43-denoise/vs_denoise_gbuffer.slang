// 1-to-1 Slang port of examples/43-denoise vs_denoise_gbuffer.sc.
// Predefined u_modelViewProj/u_model/u_invView are auto-declared; u_model[0] -> u_model.
// parameters.sh macros expanded inline against u_params:
//   u_worldToViewPrev0..3 = u_params[3..6], u_viewToProjPrev0..3 = u_params[7..10].
// Highest index used is 10, so u_params reflects at its used extent of 11.
import bgfx_shader;

float4 u_params[11];

struct VSInput
{
	vec4 a_position  : POSITION;
	vec3 a_normal    : NORMAL;
	vec2 a_texcoord0 : TEXCOORD0;
};

struct V2F
{
	vec4 pos         : SV_Position;
	vec3 v_normal    : NORMAL;
	vec2 v_texcoord0 : TEXCOORD0;
	vec4 v_texcoord1 : TEXCOORD1;
	vec4 v_texcoord2 : TEXCOORD2;
	vec4 v_texcoord3 : TEXCOORD3;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;

	// Calculate vertex position
	vec3 pos = input.a_position.xyz;
	output.pos = mul(u_modelViewProj, vec4(pos, 1.0));

	// Calculate previous frame's position
	mat4 worldToViewPrev = mtxFromCols(
		  u_params[3]
		, u_params[4]
		, u_params[5]
		, u_params[6]
		);
	mat4 viewToProjPrev = mtxFromCols(
		  u_params[7]
		, u_params[8]
		, u_params[9]
		, u_params[10]
		);

	vec3 wsPos  = mul(u_model, vec4(pos, 1.0)).xyz;
	vec3 vspPos = mul(worldToViewPrev, vec4(wsPos, 1.0)).xyz;
	vec4 pspPos = mul(viewToProjPrev, vec4(vspPos, 1.0));

	// Calculate normal, unpack
	vec3 osNormal = input.a_normal.xyz * 2.0 - 1.0;

	// Transform normal into world space
	vec3 wsNormal = mul(u_model, vec4(osNormal, 0.0)).xyz;

	output.v_normal.xyz = normalize(wsNormal);
	output.v_texcoord0 = input.a_texcoord0;

	// Store previous frame projection space position in extra texCoord attribute
	output.v_texcoord1 = pspPos;

	// Store world space view vector in extra texCoord attribute
	vec3 wsCamPos = mul(u_invView, vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 view = normalize(wsCamPos - wsPos);

	output.v_texcoord2 = vec4(wsPos, 1.0);
	output.v_texcoord3 = vec4(wsCamPos, 1.0);

	return output;
}
