// Dedicated stage-1 kernel: the "Simple RT" image as a STANDALONE ray-query compute
// shader -- the specialization benchmark counterpart to (a) the four-stage uber-kernel
// (cs_cornellbox_rq, mode 0) and (b) the RT-pipeline stage (rt_cornellbox_*). Same
// lighting as both; compiled through the same Slang -> SPIR-V -> SPIRV-Cross route as
// the uber-kernel so the comparison isolates kernel specialization, not toolchain.
import bgfx_shader;
import bgfx_compute;
import "cornellbox.sh";

uniform RaytracingAccelerationStructure scene : register(t0);
RWTexture2D<float4> s_target : register(u1);

struct Material
{
	float4 albedo;
	float4 emission;
	float4 normal;
};
RWStructuredBuffer<Material> materials : register(u3);

// x,y = resolution, z = box rotation angle, w = unused.
uniform float4 u_params;

bool occludedRq(float3 origin, float3 dir, float dist)
{
	RayQuery<RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH> q;
	RayDesc rd;
	rd.Origin = origin;
	rd.Direction = dir;
	rd.TMin = 1e-3;
	rd.TMax = dist - kShadowBias;
	q.TraceRayInline(scene, RAY_FLAG_NONE, 0xff, rd);
	while (q.Proceed())
	{
		if (q.CandidateType() == CANDIDATE_NON_OPAQUE_TRIANGLE)
			q.CommitNonOpaqueTriangleHit();
	}
	return q.CommittedStatus() == COMMITTED_TRIANGLE_HIT;
}

[shader("compute")]
[numthreads(8, 8, 1)]
void computeMain(uint3 dtid : SV_DispatchThreadID)
{
	uint2 px = dtid.xy;
	uint2 dim = uint2(u_params.xy);
	if (any(px >= dim)) return;

	RayDesc rd;
	rd.Origin    = kEye;
	rd.Direction = primaryRay(float2(px), float2(0.5, 0.5), float2(dim));
	rd.TMin      = 1e-3;
	rd.TMax      = 1000.0;

	RayQuery<RAY_FLAG_NONE> q;
	q.TraceRayInline(scene, RAY_FLAG_NONE, 0xff, rd);
	while (q.Proceed())
	{
		if (q.CandidateType() == CANDIDATE_NON_OPAQUE_TRIANGLE)
			q.CommitNonOpaqueTriangleHit();
	}

	float3 color = float3(0.02, 0.02, 0.02);
	if (q.CommittedStatus() == COMMITTED_TRIANGLE_HIT)
	{
		uint matIdx = q.CommittedInstanceIndex()*12 + q.CommittedPrimitiveIndex();
		Material m = materials[matIdx];
		float3 emission = m.emission.xyz;
		if (dot(emission, emission) > 0.0)
		{
			color = emission;
		}
		else
		{
			float3 n = m.normal.xyz;
			uint inst = q.CommittedInstanceIndex();
			if (inst == 1u) n = rotY(n,  u_params.z);
			if (inst == 2u) n = rotY(n, -u_params.z);

			float3 hitP = rd.Origin + rd.Direction * q.CommittedRayT();
			float3 toLight = kLightCenter - hitP;
			float dist = length(toLight);
			float3 wi = toLight / dist;
			float ndotl = max(0.0, dot(n, wi));
			float3 albedo = m.albedo.xyz;
			color = albedo * 0.12;
			if (ndotl > 0.0 && !occludedRq(hitP + n*kShadowBias, wi, dist))
			{
				color += albedo * kLightEmission * (ndotl / (dist*dist)) * 0.15;
			}
		}
	}
	s_target[px] = float4(tonemap(color), 1.0);
}
