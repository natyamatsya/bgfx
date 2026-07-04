// 1-to-1 Slang port of examples/14-shadowvolumes vs_shadowvolume_svfront.sc.
// Predefined u_modelViewProj is auto-declared; use it directly.
import bgfx_shader;

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
	output.pos = mul(u_modelViewProj, vec4(input.a_position, 1.0));
	return output;
}
