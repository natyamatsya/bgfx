// P1 on-device raygen: one primary ray per pixel into the scene; every payload
// contribution is additive so the readback pins each P1 feature separately.
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

    target[px] = float4(p.v, p.v, p.v, 1.0);
}
