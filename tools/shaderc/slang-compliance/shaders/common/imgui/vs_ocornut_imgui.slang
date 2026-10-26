// 1-to-1 Slang port of examples/common/imgui vs_ocornut_imgui.sc. Predefined u_viewProj is
// auto-declared.
import bgfx_shader;

struct VSInput
{
	vec2 a_position  : POSITION;
	vec4 a_color0    : COLOR0;
	vec2 a_texcoord0 : TEXCOORD0;
};

struct V2F
{
	vec4 pos         : SV_Position;
	vec4 v_color0    : COLOR0;
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	vec4 pos = mul(u_viewProj, vec4(input.a_position.xy, 0.0, 1.0) );
	output.pos         = vec4(pos.x, pos.y, 0.0, 1.0);
	output.v_texcoord0 = input.a_texcoord0;
	output.v_color0    = input.a_color0;
	return output;
}
