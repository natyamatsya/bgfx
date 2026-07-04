// 1-to-1 Slang port of examples/16-shadowmaps/vs_shadowmaps_color_lighting_csm.sc
import bgfx_shader;

float4   u_params1; // u_shadowMapOffset = u_params1.y
float4x4 u_shadowMapMtx0;
float4x4 u_shadowMapMtx1;
float4x4 u_shadowMapMtx2;
float4x4 u_shadowMapMtx3;
// u_model, u_modelView, u_modelViewProj are predefined (auto-provided).

struct VSInput
{
	vec3 a_position : POSITION;
	vec4 a_normal   : NORMAL;
};

struct V2F
{
	vec4 pos        : SV_Position;
	vec4 v_position : TEXCOORD7;
	vec3 v_normal   : NORMAL;
	vec3 v_view     : TEXCOORD5;
	vec4 v_texcoord1 : TEXCOORD1;
	vec4 v_texcoord2 : TEXCOORD2;
	vec4 v_texcoord3 : TEXCOORD3;
	vec4 v_texcoord4 : TEXCOORD4;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	output.pos = mul(u_modelViewProj, vec4(input.a_position, 1.0) );

	vec4 normal = input.a_normal * 2.0 - 1.0;
	output.v_normal = normalize(mul(u_modelView, vec4(normal.xyz, 0.0) ).xyz);
	output.v_view = mul(u_modelView, vec4(input.a_position, 1.0)).xyz;

	vec4 posOffset = vec4(input.a_position + normal.xyz * u_params1.y, 1.0);
	output.v_position = mul(u_modelView, posOffset);

	vec4 wpos = vec4(mul(u_model, posOffset).xyz, 1.0);
	output.v_texcoord1 = mul(u_shadowMapMtx0, wpos);
	output.v_texcoord2 = mul(u_shadowMapMtx1, wpos);
	output.v_texcoord3 = mul(u_shadowMapMtx2, wpos);
	output.v_texcoord4 = mul(u_shadowMapMtx3, wpos);
	return output;
}
