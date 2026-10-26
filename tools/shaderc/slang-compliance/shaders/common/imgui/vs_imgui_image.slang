// 1-to-1 Slang port of examples/common/imgui vs_imgui_image.sc. Predefined u_viewProj is
// auto-declared.
import bgfx_shader;

struct VSInput
{
	vec2 a_position  : POSITION;
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
	output.pos         = mul(u_viewProj, vec4(input.a_position.xy, 0.0, 1.0) );
	output.v_texcoord0 = input.a_texcoord0;
	return output;
}
