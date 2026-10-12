// Slang port of examples/54-s2h/fs_s2h_debug_zoom.sc -- the magnifier panel.
// u_viewRect is a bgfx predefined uniform, so it is used without being declared.
import bgfx_shader;
import bgfx_shader_glsl_compat; // mix
#include "s2h_bgfx.h" // s2h_getPixelCoord

Texture2D    s_quadPostColor        : register(t0);
SamplerState s_quadPostColorSampler : register(s0);

vec4 u_s2hMouse;

struct V2F
{
	vec4 pos         : SV_Position;
	vec4 v_color0    : COLOR0;
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec2 pixel = s2h_getPixelCoord(input.pos.xy);
	vec2 resolution = u_viewRect.zw;
	vec2 mouse = u_s2hMouse.xy;
	vec3 color = texture2D(s_quadPostColor, s_quadPostColorSampler, input.v_texcoord0).rgb;
	vec2 panelLocal = pixel - mouse - vec2(24.0f, 24.0f);
	if (panelLocal.x >= 0.0f && panelLocal.y >= 0.0f && panelLocal.x < 160.0f && panelLocal.y < 160.0f)
	{
		vec2 sourcePixel = floor(mouse - vec2(8.0f, 8.0f) + panelLocal / 10.0f);
		color = texture2D(s_quadPostColor, s_quadPostColorSampler, (sourcePixel + 0.5f) / resolution).rgb;
		vec2 cell = frac(panelLocal / 10.0f);
		if (cell.x < 0.08f || cell.y < 0.08f) color = vec3(0.0f, 0.0f, 0.0f);
	}
	float crosshair = 1.0f - smoothstep(0.0f, 1.0f, min(abs(pixel.x - mouse.x), abs(pixel.y - mouse.y) ) );
	color = mix(color, vec3(1.0f, 1.0f, 1.0f), crosshair);
	return vec4(color, 1.0f);
}
