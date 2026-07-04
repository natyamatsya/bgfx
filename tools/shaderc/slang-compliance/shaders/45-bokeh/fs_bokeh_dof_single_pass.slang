// 1-to-1 Slang port of examples/45-bokeh fs_bokeh_dof_single_pass.sc.
// USE_PACKED_COLOR_AND_BLUR is unset here, so DepthOfField is called with usePacked=false
// and samples both s_color and s_depth.
import bgfx_shader;
import bokeh_dof;

Texture2D    s_color        : register(t0);
SamplerState s_colorSampler : register(s0);
Texture2D    s_depth        : register(t1);
SamplerState s_depthSampler : register(s1);

// Active extent: highest read index is u_params[3], so glslang reflects u_params[4].
vec4 u_params[4];

#define u_lobeRotation		(u_params[0].w)
#define u_frameIdx			(u_params[0].z)
#define u_lobeCount			(u_params[2].y)
#define u_lobeRadiusMin		(u_params[2].z)
#define u_lobeRadiusDelta2x	(u_params[2].w)
#define u_maxBlurSize		(u_params[3].x)
#define u_focusPoint		(u_params[3].y)
#define u_focusScale		(u_params[3].z)
#define u_radiusScale		(u_params[3].w)

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec2 texCoord = input.v_texcoord0.xy;

	vec3 outColor = DepthOfField(
		s_color, s_colorSampler,
		s_depth, s_depthSampler,
		texCoord, u_focusPoint, u_focusScale,
		u_maxBlurSize, u_radiusScale, u_frameIdx,
		u_lobeCount, u_lobeRadiusMin, u_lobeRadiusDelta2x, u_lobeRotation,
		u_viewRect, u_viewTexel, false).xyz;

	// this pass is writing directly out to backbuffer, convert from linear to gamma
	outColor = toGamma(outColor);

	return vec4(outColor, 1.0);
}
