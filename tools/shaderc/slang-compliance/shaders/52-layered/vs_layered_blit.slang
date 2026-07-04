// Slang port of examples/52-layered/vs_layered_blit.sc. Passthrough for the
// fullscreen blit that resolves the texture array to the backbuffer.
import bgfx_shader;

struct VSInput
{
	vec3 a_position  : POSITION;
	vec2 a_texcoord0 : TEXCOORD0;
};

struct V2F
{
	vec4 pos         : SV_Position;
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	output.pos         = vec4(input.a_position, 1.0);
	output.v_texcoord0 = input.a_texcoord0;
	return output;
}
