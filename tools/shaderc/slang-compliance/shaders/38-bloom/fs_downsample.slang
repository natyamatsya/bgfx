// 1-to-1 Slang port of examples/38-bloom fs_downsample.sc.
// 13-tap dual-filter downsample kernel.
import bgfx_shader;

Texture2D    s_tex        : register(t0);
SamplerState s_texSampler : register(s0);

// pixel size of the target texture.
vec4 u_pixelSize;

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec2 halfpixel = 0.5 * vec2(u_pixelSize.x, u_pixelSize.y);
	vec2 oneepixel = 1.0 * vec2(u_pixelSize.x, u_pixelSize.y);

	vec2 uv = input.v_texcoord0.xy;

	vec4 sum = vec4(0.0, 0.0, 0.0, 0.0);

	sum += (4.0/32.0) * texture2D(s_tex, s_texSampler, uv).rgba;

	sum += (4.0/32.0) * texture2D(s_tex, s_texSampler, uv + vec2(-halfpixel.x, -halfpixel.y) );
	sum += (4.0/32.0) * texture2D(s_tex, s_texSampler, uv + vec2(+halfpixel.x, +halfpixel.y) );
	sum += (4.0/32.0) * texture2D(s_tex, s_texSampler, uv + vec2(+halfpixel.x, -halfpixel.y) );
	sum += (4.0/32.0) * texture2D(s_tex, s_texSampler, uv + vec2(-halfpixel.x, +halfpixel.y) );

	sum += (2.0/32.0) * texture2D(s_tex, s_texSampler, uv + vec2(+oneepixel.x, 0.0) );
	sum += (2.0/32.0) * texture2D(s_tex, s_texSampler, uv + vec2(-oneepixel.x, 0.0) );
	sum += (2.0/32.0) * texture2D(s_tex, s_texSampler, uv + vec2(0.0, +oneepixel.y) );
	sum += (2.0/32.0) * texture2D(s_tex, s_texSampler, uv + vec2(0.0, -oneepixel.y) );

	sum += (1.0/32.0) * texture2D(s_tex, s_texSampler, uv + vec2(+oneepixel.x, +oneepixel.y) );
	sum += (1.0/32.0) * texture2D(s_tex, s_texSampler, uv + vec2(-oneepixel.x, +oneepixel.y) );
	sum += (1.0/32.0) * texture2D(s_tex, s_texSampler, uv + vec2(+oneepixel.x, -oneepixel.y) );
	sum += (1.0/32.0) * texture2D(s_tex, s_texSampler, uv + vec2(-oneepixel.x, -oneepixel.y) );

	return sum;
}
