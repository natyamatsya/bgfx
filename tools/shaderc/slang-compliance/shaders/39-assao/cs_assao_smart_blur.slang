// Slang port of examples/39-assao cs_assao_smart_blur.sc — edge-sensitive blur.
// IMAGE2D_ARRAY_WO(rg8) target, SAMPLER2DARRAY input; textureGather -> GatherRed,
// texelFetch -> .Load. UnpackEdges/AddSample/SampleBlurred kept inline. Non-GLSL branch.
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

// unpacking for edges; 2 bits per edge mean 4 gradient values (0, 0.33, 0.66, 1) for smoother transitions!
vec4 UnpackEdges( float _packedVal )
{
    uint packedVal = uint(_packedVal * 255.5);
    vec4 edgesLRTB;
    edgesLRTB.x = float((packedVal >> 6) & 0x03) / 3.0;
    edgesLRTB.y = float((packedVal >> 4) & 0x03) / 3.0;
    edgesLRTB.z = float((packedVal >> 2) & 0x03) / 3.0;
    edgesLRTB.w = float((packedVal >> 0) & 0x03) / 3.0;

    return saturate( edgesLRTB + u_params[8].x );
}

// ********************************************************************************************************
// Pixel shader that does smart blurring (to avoid bleeding)

void AddSample( float ssaoValue, float edgeValue, inout float sum, inout float sumWeight )
{
    float weight = edgeValue;

    sum += (weight * ssaoValue);
    sumWeight += weight;
}

vec2 SampleBlurred( ivec2 inPos, vec2 coord )
{
    float packedEdges   = s_blurInput.Load( ivec4(inPos.xy, 0, 0) ).y;
    vec4 edgesLRTB    = UnpackEdges( packedEdges );

    vec4 valuesUL     = s_blurInput.GatherRed(s_blurInputSampler, vec3(coord - u_params[0].zw * 0.5, 0.0));
    vec4 valuesBR     = s_blurInput.GatherRed(s_blurInputSampler, vec3(coord + u_params[0].zw * 0.5, 0.0));

    float ssaoValue     = valuesUL.y;
    float ssaoValueL    = valuesUL.x;
    float ssaoValueT    = valuesUL.z;
    float ssaoValueR    = valuesBR.z;
    float ssaoValueB    = valuesBR.x;

    float sumWeight = 0.5f;
    float sum = ssaoValue * sumWeight;

    AddSample( ssaoValueL, edgesLRTB.x, sum, sumWeight );
    AddSample( ssaoValueR, edgesLRTB.y, sum, sumWeight );

    AddSample( ssaoValueT, edgesLRTB.z, sum, sumWeight );
    AddSample( ssaoValueB, edgesLRTB.w, sum, sumWeight );

    float ssaoAvg = sum / sumWeight;

    ssaoValue = ssaoAvg;

    return vec2( ssaoValue, packedEdges );
}

[shader("compute")]
[numthreads(8, 8, 1)]
void computeMain(uint3 dispatchThreadId : SV_DispatchThreadID)
{
	uvec2 dtID = uvec2(dispatchThreadId.xy) + uvec2(u_rect.xy);
	if (all(vec2(dtID.xy) < u_rect.zw) )
	{
		vec2 inUV = (dtID.xy+vec2(0.5,0.5)) * u_params[0].zw;
	    imageStore(s_target, ivec3(int2(dtID.xy), int(u_params[14].w)), SampleBlurred( ivec2(dtID.xy), inUV ));
	}
}
