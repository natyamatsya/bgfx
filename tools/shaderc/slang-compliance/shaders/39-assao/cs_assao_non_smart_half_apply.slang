// Slang port of examples/39-assao cs_assao_non_smart_half_apply.sc.
// edge-ignorant blur & apply, skipping half pixels in checkerboard pattern. texture2DArrayLod -> .SampleLevel.
import bgfx_shader;
import bgfx_compute;

uniform float4 u_params[1];
// stock uniforms.sh declares u_params[19] then u_rect; glslang reflects u_params at its used
// extent (1) but reserves the full [19] in $Globals, so u_rect keeps byte offset 304 and the UBO
// size stays 320. Reproduce the reserved tail with a struct member (not reflected as a uniform).
struct ParamsTailPad { float4 _unused[18]; };
ParamsTailPad _paramsTailPad;
uniform float4 u_rect;

[[vk::image_format("r8")]]
RWTexture2D<float> s_target : register(u0);

Texture2DArray s_finalSSAO        : register(t1);
SamplerState   s_finalSSAOSampler : register(s1);

[shader("compute")]
[numthreads(8, 8, 1)]
void computeMain(uint3 dispatchThreadId : SV_DispatchThreadID)
{
	uvec2 dtID = uvec2(dispatchThreadId.xy) + uvec2(u_rect.xy);
	if (all(vec2(dtID.xy) < u_rect.zw) )
	{
		vec2 inUV = (dtID.xy+vec2(0.5,0.5)) * u_params[0].xy;
		float a = s_finalSSAO.SampleLevel(s_finalSSAOSampler, vec3( inUV.xy, 0 ), 0.0 ).x;
		float d = s_finalSSAO.SampleLevel(s_finalSSAOSampler, vec3( inUV.xy, 3 ), 0.0 ).x;
		float avg = (a+d) * 0.5;
		avg = pow(avg,1.0/2.2);
		imageStore(s_target, ivec2(dtID.xy), avg);
	}
}
