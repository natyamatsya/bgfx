// Slang port of examples/39-assao vs_assao_gbuffer.sc — gbuffer VS.
// Predefined u_modelViewProj and u_model (single float4x4; stock u_model[0]) are auto-declared.
import bgfx_shader;

struct VSInput
{
	vec4 a_position  : POSITION;
	vec3 a_normal    : NORMAL;
	vec2 a_texcoord0 : TEXCOORD0;
};

struct V2F
{
	vec4 pos        : SV_Position;
	vec3 v_normal    : NORMAL;
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;

	// Calculate vertex position
	vec3 pos = input.a_position.xyz;
	output.pos = mul(u_modelViewProj, vec4(pos, 1.0) );

	// Calculate normal.  Note that compressed normal is stored in the vertices
	vec3 normalObjectSpace = input.a_normal.xyz*2.0+-1.0; // Normal is stored in [0,1], remap to [-1,1].

	// Transform normal into world space.
	vec3 normalWorldSpace = mul(u_model, vec4(normalObjectSpace, 0.0) ).xyz;
	// Normalize to remove (uniform...) scaling, however, recompress
	output.v_normal.xyz = normalize(normalWorldSpace)*0.5+0.5;

	output.v_texcoord0 = input.a_texcoord0 * 16.0;

	return output;
}
