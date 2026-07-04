// 1-to-1 Slang port of examples/36-sky vs_sky_landscape.sc.
// u_modelViewProj / u_model are auto-provided predefined uniforms.
import bgfx_shader;

struct VSInput
{
	vec3 a_position  : POSITION;
	vec4 a_normal    : NORMAL;
	vec2 a_texcoord0 : TEXCOORD0;
};

struct V2F
{
	vec4 pos         : SV_Position;
	vec3 v_normal    : NORMAL;
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;

	output.pos = mul(u_modelViewProj, vec4(input.a_position, 1.0));

	vec3 normal = input.a_normal.xyz * 2.0 - 1.0;
	output.v_normal = mul(u_model, vec4(normal, 0.0)).xyz;

	output.v_texcoord0 = input.a_texcoord0;

	return output;
}
