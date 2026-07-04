// 1-to-1 Slang port of examples/38-bloom fs_upsample.sc.
// 9-tap dual-filter upsample kernel; scaled by u_intensity.x.
import bgfx_shader;

Texture2D    s_tex        : register(t0);
SamplerState s_texSampler : register(s0);

vec4 u_pixelSize;
vec4 u_intensity;

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec2 halfpixel = u_pixelSize.xy;
	vec2 uv = input.v_texcoord0.xy;

	vec4 sum = vec4_splat(0.0);

	sum += (2.0 / 16.0) * texture2D(s_tex, s_texSampler, uv + vec2(-halfpixel.x,  0.0) );
	sum += (2.0 / 16.0) * texture2D(s_tex, s_texSampler, uv + vec2( 0.0,          halfpixel.y) );
	sum += (2.0 / 16.0) * texture2D(s_tex, s_texSampler, uv + vec2( halfpixel.x,  0.0) );
	sum += (2.0 / 16.0) * texture2D(s_tex, s_texSampler, uv + vec2( 0.0,         -halfpixel.y) );

	sum += (1.0 / 16.0) * texture2D(s_tex, s_texSampler, uv + vec2(-halfpixel.x, -halfpixel.y) );
	sum += (1.0 / 16.0) * texture2D(s_tex, s_texSampler, uv + vec2(-halfpixel.x,  halfpixel.y) );
	sum += (1.0 / 16.0) * texture2D(s_tex, s_texSampler, uv + vec2( halfpixel.x, -halfpixel.y) );
	sum += (1.0 / 16.0) * texture2D(s_tex, s_texSampler, uv + vec2( halfpixel.x,  halfpixel.y) );

	sum += (4.0 / 16.0) * texture2D(s_tex, s_texSampler, uv);

	return u_intensity.x * sum;
}
