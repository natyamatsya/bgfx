// Slang port of examples/39-assao cs_assao_non_smart_blur.sc.
// edge-ignorant blur in x and y directions, 9 pixels touched. IMAGE2D_ARRAY_WO(rg8) target,
// SAMPLER2DARRAY input; texture2DArrayLod -> .SampleLevel. Non-GLSL branch.
import bgfx_shader;
import bgfx_compute;

uniform float4 u_params[15];
// stock uniforms.sh declares u_params[19] then u_rect; glslang reflects u_params at its used
// extent (15) but reserves the full [19] in $Globals, so u_rect keeps byte offset 304 and the UBO
// size stays 320. Reproduce the reserved tail with a struct member (not reflected as a uniform).
struct ParamsTailPad { float4 _unused[4]; };
ParamsTailPad _paramsTailPad;
uniform float4 u_rect;

[[vk::image_format("rg8")]]
RWTexture2DArray<float2> s_target : register(u0);

Texture2DArray s_blurInput        : register(t1);
SamplerState   s_blurInputSampler : register(s1);

[shader("compute")]
[numthreads(8, 8, 1)]
void computeMain(uint3 dispatchThreadId : SV_DispatchThreadID)
{
	uvec2 dtID = uvec2(dispatchThreadId.xy) + uvec2(u_rect.xy);
	if (all(vec2(dtID.xy) < u_rect.zw) )
	{
		vec2 inUV = (dtID.xy+vec2(0.5,0.5)) * u_params[0].zw;
		vec2 halfPixel = u_params[0].zw * 0.5f;

		vec2 centre = s_blurInput.SampleLevel(s_blurInputSampler, vec3(inUV, 0.0), 0.0 ).xy;

		vec4 vals;
		vals.x = s_blurInput.SampleLevel(s_blurInputSampler, vec3(inUV + vec2( -halfPixel.x * 3, -halfPixel.y ),0.0) , 0.0 ).x;
		vals.y = s_blurInput.SampleLevel(s_blurInputSampler, vec3(inUV + vec2( +halfPixel.x, -halfPixel.y * 3 ),0.0) , 0.0 ).x;
		vals.z = s_blurInput.SampleLevel(s_blurInputSampler, vec3(inUV + vec2( -halfPixel.x, +halfPixel.y * 3 ),0.0) , 0.0 ).x;
		vals.w = s_blurInput.SampleLevel(s_blurInputSampler, vec3(inUV + vec2( +halfPixel.x * 3, +halfPixel.y ),0.0) , 0.0 ).x;

		imageStore(s_target, ivec3(int2(dtID.xy),int(u_params[14].w)), vec2(dot( vals, (0.2).xxxx ) + centre.x * 0.2, centre.y));
	}
}
