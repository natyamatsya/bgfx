// 1-to-1 Slang port of examples/45-bokeh fs_bokeh_dof_debug.sc.
// GetCircleOfConfusion comes from bokeh_dof.sh (import bokeh_dof).
import bgfx_shader;
import bgfx_shader_glsl_compat; // mix
import bokeh_dof;

Texture2D    s_color        : register(t0);
SamplerState s_colorSampler : register(s0);
Texture2D    s_depth        : register(t1);
SamplerState s_depthSampler : register(s1);

// Active extent: only u_params[3] is read, so glslang reflects u_params[4] (no reserved tail).
vec4 u_params[4];

#define u_focusPoint (u_params[3].y)
#define u_focusScale (u_params[3].z)

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec2 texCoord = input.v_texcoord0.xy;

	// desaturate color to make tinted color stand out
	vec3 color = texture2D(s_color, s_colorSampler, texCoord).xyz;
	color = toGamma(color);
	color = vec3_splat(dot(color, vec3(0.33, 0.34, 0.33)));

	// get circle of confusion from depth
	float depth = texture2D(s_depth, s_depthSampler, texCoord).x;
	float circleOfConfusion = GetCircleOfConfusion(depth, u_focusPoint, u_focusScale);

	// apply tint color to debug where blur applied
	vec3 tintColor;
	if (circleOfConfusion < 0.0)
	{
		// tint foreground orange
		tintColor = vec3(187.0, 61.0, 7.0) / 255.0;
	}
	else
	{
		// tint background blue
		tintColor = vec3(11.0, 89.0, 138.0) / 255.0;
	}
	tintColor *= color;
	color = mix(color, tintColor, abs(circleOfConfusion));

	return vec4(color, 1.0);
}
