// P0 end-to-end raygen: two traces per pixel — the primary ray hits the triangle
// (closest-hit contributes 0.5 + 0.25 for the validated distance), a second ray points
// away and lands in miss shader INDEX 1 (+0.25, proving miss-record indexing). Exactly
// 1.0 only when the whole compiler<->runtime contract works.
uniform RaytracingAccelerationStructure scene : register(t0);
RWTexture2D<float4> target : register(u1);

struct P
{
    float v;
};

[shader("raygeneration")]
void rayGenMain()
{
    uint2 px = DispatchRaysIndex().xy;

    RayDesc rd;
    rd.Origin    = float3(0, 0, 0);
    rd.Direction = float3(0, 0, 1);
    rd.TMin      = 0.0;
    rd.TMax      = 100.0;

    P p;
    p.v = 0.0;
    TraceRay(scene, RAY_FLAG_NONE, 0xff, 0, 1, 0, rd, p);

    RayDesc rdUp;
    rdUp.Origin    = float3(0, 0, 0);
    rdUp.Direction = float3(0, 1, 0);
    rdUp.TMin      = 0.0;
    rdUp.TMax      = 100.0;

    P p2;
    p2.v = 0.0;
    TraceRay(scene, RAY_FLAG_NONE, 0xff, 0, 1, 1, rdUp, p2);

    float v = p.v + p2.v;
    target[px] = float4(v, v, v, 1.0);
}
