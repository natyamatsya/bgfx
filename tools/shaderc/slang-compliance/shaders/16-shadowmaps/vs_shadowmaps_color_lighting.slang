// 1-to-1 Slang port of examples/16-shadowmaps/vs_shadowmaps_color_lighting.sc
import bgfx_shader;

float4x4 u_lightMtx;
float4   u_params1; // u_shadowMapOffset = u_params1.y

struct VSInput
{
	vec3 a_position : POSITION;
	vec4 a_normal   : NORMAL;
};

struct V2F
{
	vec4 pos          : SV_Position;
	vec3 v_normal     : NORMAL;
	vec3 v_view       : TEXCOORD5;
	vec4 v_shadowcoord : TEXCOORD6;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	output.pos = mul(u_modelViewProj, vec4(input.a_position, 1.0) );

	vec4 normal = input.a_normal * 2.0 - 1.0;
	output.v_normal = normalize(mul(u_modelView, vec4(normal.xyz, 0.0) ).xyz);
	output.v_view = mul(u_modelView, vec4(input.a_position, 1.0)).xyz;

	vec3 posOffset = input.a_position + normal.xyz * u_params1.y;
	output.v_shadowcoord = mul(u_lightMtx, vec4(posOffset, 1.0) );
	return output;
}
