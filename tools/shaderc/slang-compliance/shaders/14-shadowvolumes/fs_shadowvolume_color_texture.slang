// 1-to-1 Slang port of examples/14-shadowvolumes fs_shadowvolume_color_texture.sc.
import bgfx_shader;

vec4 u_color;

// SAMPLER2D(s_texColor, 0)
Texture2D    s_texColor        : register(t0);
SamplerState s_texColorSampler : register(s0);

struct V2F
{
	float4 pos         : SV_Position;
	float2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
float4 fragmentMain(V2F input) : SV_Target
{
	vec4 tcolor = toLinear(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0));

	if (tcolor.x < 0.1) //OK for now.
	{
		discard;
	}

	return toGamma(tcolor + u_color);
}
