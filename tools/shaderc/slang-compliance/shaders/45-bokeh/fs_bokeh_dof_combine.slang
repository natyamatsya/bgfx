// 1-to-1 Slang port of examples/45-bokeh fs_bokeh_dof_combine.sc.
// Stock includes parameters.sh but never reads u_params, so it is not declared here.
import bgfx_shader;
import bgfx_shader_glsl_compat; // mix

Texture2D    s_color              : register(t0);
SamplerState s_colorSampler       : register(s0);
Texture2D    s_blurredColor       : register(t1);
SamplerState s_blurredColorSampler : register(s1);

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec2 texCoord = input.v_texcoord0.xy;
	vec4 color = texture2D(s_color, s_colorSampler, texCoord);
	vec4 dofColorSize = texture2D(s_blurredColor, s_blurredColorSampler, texCoord);
	vec3 dofColor = dofColorSize.xyz;
	float sampleSize = dofColorSize.w;

	float m = saturate(sampleSize-1.0);
	color.xyz = mix(color.xyz, dofColor, m);

	// this pass is writing directly out to backbuffer, convert from linear to gamma
	color.xyz = toGamma(color.xyz);

	return color;
}
