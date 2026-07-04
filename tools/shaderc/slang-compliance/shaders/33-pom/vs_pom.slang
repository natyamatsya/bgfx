// 1-to-1 Slang port of examples/33-pom vs_pom.sc (per-stage). Predefined
// u_model / u_viewProj are auto-declared; u_norm_mtx / u_light_pos are custom.
import bgfx_shader;

float4x4 u_norm_mtx;
float4   u_light_pos;

struct VSInput
{
	vec3 a_position  : POSITION;
	vec3 a_tangent   : TANGENT;
	vec3 a_bitangent : BITANGENT;
	vec2 a_texcoord0 : TEXCOORD0;
};

struct V2F
{
	vec4 pos            : SV_Position;
	vec2 v_texcoord0    : TEXCOORD0;
	vec3 v_ts_light_pos : TEXCOORD1;
	vec3 v_ts_view_pos  : TEXCOORD2;
	vec3 v_ts_frag_pos  : TEXCOORD3;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;

	vec3 wpos = mul(u_model, vec4(input.a_position, 1.0) ).xyz;
	output.pos = mul(u_viewProj, vec4(wpos, 1.0) );

	vec3 tangent   = input.a_tangent   * 2.0 - 1.0;
	vec3 bitangent = input.a_bitangent * 2.0 - 1.0;
	vec3 normal    = cross(tangent, bitangent);

	vec3 t = normalize(mul(u_norm_mtx, vec4(tangent,   0.0) ).xyz);
	vec3 b = normalize(mul(u_norm_mtx, vec4(bitangent, 0.0) ).xyz);
	vec3 n = normalize(mul(u_norm_mtx, vec4(normal,    0.0) ).xyz);
	mat3 tbn = mtxFromCols(t, b, n);

	output.v_ts_light_pos = mul(u_light_pos.xyz, tbn);
	// Our camera is always at the origin
	output.v_ts_view_pos  = mul(vec3_splat(0.0), tbn);
	output.v_ts_frag_pos  = mul(wpos,            tbn);

	output.v_texcoord0 = input.a_texcoord0;
	return output;
}
