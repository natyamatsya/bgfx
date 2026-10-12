// Slang port of examples/54-s2h/fs_s2h_generate_user_font.sc.
// The stock file notes it is a port of ShaderToHuman-bgfx Features/GenUserFont_example.hlsl.
import bgfx_shader;
import bgfx_shader_glsl_compat; // mix, mod
#include "s2h_bgfx.h"
#include "s2h/s2h.hlsl"

vec4 u_s2hTime;

struct V2F
{
	vec4 pos         : SV_Position;
	vec4 v_color0    : COLOR0;
	vec2 v_texcoord0 : TEXCOORD0;
};

vec3 myMod(vec3 _x, vec3 _period)
{
	return frac(_x / _period) * _period;
}

vec3 hsb2rgb(vec3 _color)
{
	vec3 rgb = saturate(abs(myMod(_color.x * 6.0f + vec3(0.0f, 4.0f, 2.0f), vec3(6.0f, 6.0f, 6.0f) ) - 3.0f) - 1.0f);
	rgb = rgb * rgb * (3.0f - 2.0f * rgb);
	return _color.z * mix(vec3(1.0f, 1.0f, 1.0f), rgb, _color.y);
}

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec2 pixelPosition = floor(s2h_getPixelCoord(input.pos.xy) );
	ContextGather ui;
	s2h_init(ui, vec2(mod(pixelPosition.x, 8.0f), pixelPosition.y) );

	ui.textColor.rgb = hsb2rgb(vec3(u_s2hTime.x + (pixelPosition.x + pixelPosition.y) / 16.0f * 0.1f, 1.0f, 1.0f) );
	uint character = uint(pixelPosition.x / 8.0f) + _SPACE;
	s2h_printTxt(ui, character);

	return vec4(ui.dstColor.rgb, 1.0f);
}
