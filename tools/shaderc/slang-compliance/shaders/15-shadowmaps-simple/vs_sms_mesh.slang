// 1-to-1 Slang port of examples/15-shadowmaps-simple vs_sms_mesh.sc.
// Predefined u_modelViewProj/u_modelView are auto-declared; u_lightMtx is custom.
import bgfx_shader;

uniform float4x4 u_lightMtx;

struct VSInput
{
	vec3 a_position : POSITION;
	vec4 a_normal   : NORMAL;
};

struct V2F
{
	vec4 pos           : SV_Position;
	vec3 v_view        : TEXCOORD0;
	vec4 v_shadowcoord : TEXCOORD1;
	vec3 v_normal      : NORMAL;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	output.pos = mul(u_modelViewProj, vec4(input.a_position, 1.0) );

	vec4 normal = input.a_normal * 2.0 - 1.0;
	output.v_normal = normalize(mul(u_modelView, vec4(normal.xyz, 0.0) ).xyz);
	output.v_view = mul(u_modelView, vec4(input.a_position, 1.0)).xyz;

	const float shadowMapOffset = 0.001;
	vec3 posOffset = input.a_position + normal.xyz * shadowMapOffset;
	output.v_shadowcoord = mul(u_lightMtx, vec4(posOffset, 1.0) );
	return output;
}
