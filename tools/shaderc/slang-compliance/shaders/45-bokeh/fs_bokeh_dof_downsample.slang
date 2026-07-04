// 1-to-1 Slang port of examples/45-bokeh fs_bokeh_dof_downsample.sc.
// GetBlurSize comes from bokeh_dof.sh (import bokeh_dof); u_maxBlurSize is passed in.
import bgfx_shader;
import bokeh_dof;

Texture2D    s_color        : register(t0);
SamplerState s_colorSampler : register(s0);
Texture2D    s_depth        : register(t1);
SamplerState s_depthSampler : register(s1);

// Active extent: only u_params[3] is read, so glslang reflects u_params[4] (no reserved tail).
vec4 u_params[4];

#define u_maxBlurSize (u_params[3].x)
#define u_focusPoint  (u_params[3].y)
#define u_focusScale  (u_params[3].z)

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec2 texCoord = input.v_texcoord0.xy;

	vec3 color = texture2D(s_color, s_colorSampler, texCoord).xyz;
	float depth = texture2D(s_depth, s_depthSampler, texCoord).x;
	float blurSize = GetBlurSize(depth, u_focusPoint, u_focusScale, u_maxBlurSize);

	return vec4(color, blurSize);
}
