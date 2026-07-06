import bgfx_shader;
import bgfx_compute;

uniform RaytracingAccelerationStructure scene : register(t0);
RWTexture2D<float4> s_target : register(u1);

[shader("compute")]
[numthreads(8, 8, 1)]
void computeMain(uint3 dtid : SV_DispatchThreadID)
{
    RayDesc rd;
    rd.Origin = float3(0, 0, 0);
    rd.Direction = float3(0, 0, 1);
    rd.TMin = 0.0;
    rd.TMax = 1000.0;

    RayQuery<RAY_FLAG_NONE> q;
    q.TraceRayInline(scene, RAY_FLAG_NONE, 0xff, rd);
    q.Proceed();

    float hit = (q.CommittedStatus() == COMMITTED_TRIANGLE_HIT) ? 1.0 : 0.0;
    imageStore(s_target, ivec2(dtid.xy), float4(hit, hit, hit, 1.0));
}
