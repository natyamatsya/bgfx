// Slang port of examples/37-gpudrivenrendering cs_gdr_occlude_props.sc.
// Per-instance occlusion culling against the hi-Z pyramid: projects each instance's world
// AABB to screen, picks a hi-Z mip, samples the 4 corner depths and, if the box's nearest
// depth is <= the sampled max depth, marks the instance visible and bumps its drawcall's
// instance count (atomicAdd). u_viewProj is a predefined uniform (auto-provided).
import bgfx_compute;
import bgfx_shader;

Texture2D    s_texOcclusionDepth        : register(t0); // SAMPLER2D(s_texOcclusionDepth, 0)
SamplerState s_texOcclusionDepthSampler : register(s0);

StructuredBuffer<float4>   instanceDataIn          : register(t1); // BUFFER_RO(instanceDataIn, vec4, 1)
RWStructuredBuffer<uint>   drawcallInstanceCount   : register(u2); // BUFFER_RW(drawcallInstanceCount, uint, 2)
RWStructuredBuffer<bool>   instancePredicates      : register(u3); // BUFFER_WO(instancePredicates, bool, 3)

uniform float4 u_inputRTSize;
uniform float4 u_cullingConfig;

[shader("compute")]
[numthreads(64, 1, 1)]
void computeMain(uint3 dispatchThreadId : SV_DispatchThreadID)
{
	bool predicate = false;

	//make sure that we not processing more instances than available
	if (dispatchThreadId.x < uint(u_cullingConfig.x) )
	{
		//get the bounding box for this instance
		float4 bboxMin = instanceDataIn[2 * dispatchThreadId.x];
		float3 bboxMax = instanceDataIn[2 * dispatchThreadId.x + 1].xyz;

		int drawcallID = int(bboxMin.w);

		//Adapted from http://blog.selfshadow.com/publications/practical-visibility/
		float3 bboxSize = bboxMax.xyz - bboxMin.xyz;

		float3 boxCorners[8] = {
			bboxMin.xyz,
			bboxMin.xyz + float3(bboxSize.x, 0, 0),
			bboxMin.xyz + float3(0, bboxSize.y, 0),
			bboxMin.xyz + float3(0, 0, bboxSize.z),
			bboxMin.xyz + float3(bboxSize.xy, 0),
			bboxMin.xyz + float3(0, bboxSize.yz),
			bboxMin.xyz + float3(bboxSize.x, 0, bboxSize.z),
			bboxMin.xyz + bboxSize.xyz
		};
		float minZ = 1.0;
		float2 minXY = float2(1.0, 1.0);
		float2 maxXY = float2(0.0, 0.0);

		[unroll]
		for (int i = 0; i < 8; i++)
		{
			//transform World space aaBox to NDC
			float4 clipPos = mul( u_viewProj, float4(boxCorners[i], 1) );

			clipPos.z = max(clipPos.z, 0);

			clipPos.xyz = clipPos.xyz / clipPos.w;

			clipPos.xy = clamp(clipPos.xy, -1, 1);
			clipPos.xy = clipPos.xy * float2(0.5, -0.5) + float2(0.5, 0.5);

			minXY = min(clipPos.xy, minXY);
			maxXY = max(clipPos.xy, maxXY);

			minZ = saturate(min(minZ, clipPos.z));
		}

		float4 boxUVs = float4(minXY, maxXY);

		// Calculate hi-Z buffer mip
		int2 size = int2( (maxXY - minXY) * u_inputRTSize.xy);
		float mip = ceil(log2(float(max(size.x, size.y))));

		mip = clamp(mip, 0, u_cullingConfig.z);

		// Texel footprint for the lower (finer-grained) level
		float level_lower = max(mip - 1, 0);
		float2 scale = vec2_splat(exp2(-level_lower) );
		float2 a = floor(boxUVs.xy*scale);
		float2 b = ceil(boxUVs.zw*scale);
		float2 dims = b - a;

		// Use the lower level if we only touch <= 2 texels in both dimensions
		if (dims.x <= 2 && dims.y <= 2)
			mip = level_lower;

		//load depths from high z buffer
		float4 depth =
		{
			texture2DLod(s_texOcclusionDepth, s_texOcclusionDepthSampler, boxUVs.xy, mip).x,
			texture2DLod(s_texOcclusionDepth, s_texOcclusionDepthSampler, boxUVs.zy, mip).x,
			texture2DLod(s_texOcclusionDepth, s_texOcclusionDepthSampler, boxUVs.xw, mip).x,
			texture2DLod(s_texOcclusionDepth, s_texOcclusionDepthSampler, boxUVs.zw, mip).x,
		};

		//find the max depth
		float maxDepth = max( max(depth.x, depth.y), max(depth.z, depth.w) );

		if ( minZ <= maxDepth )
		{
			predicate = true;

			//increase instance count for this particular prop type
			InterlockedAdd(drawcallInstanceCount[ drawcallID ], 1); // atomicAdd
		}
	}

	instancePredicates[dispatchThreadId.x] = predicate;
}
