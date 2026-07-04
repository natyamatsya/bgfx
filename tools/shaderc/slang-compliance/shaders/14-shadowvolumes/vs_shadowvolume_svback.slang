// 1-to-1 Slang port of examples/14-shadowvolumes vs_shadowvolume_svback.sc.
// Predefined u_modelViewProj is auto-declared; use it directly.
import bgfx_shader;

vec4 u_virtualLightPos_extrusionDist;
// u_virtualLightPos   = u_virtualLightPos_extrusionDist.xyz
// u_extrusionDistance = u_virtualLightPos_extrusionDist.w

struct VSInput
{
	vec3 a_position : POSITION;
};

struct V2F
{
	vec4 pos : SV_Position;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	vec3 pos = input.a_position;

	vec3 toLight = pos - u_virtualLightPos_extrusionDist.xyz;
	pos += normalize(toLight) * u_virtualLightPos_extrusionDist.w;

	output.pos = mul(u_modelViewProj, vec4(pos, 1.0));
	return output;
}
