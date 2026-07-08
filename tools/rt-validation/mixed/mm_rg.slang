// Mixed-module kit, raygen module -- compiled SEPARATELY from the handlers (the
// point of the runtime contract). Slots mode 8. v = chit(0.5) + missA(0.25) + u_params.y(0.25) = 1.0.
uniform RaytracingAccelerationStructure scene : register(t0);
RWTexture2D<float4> target : register(u1);
uniform float4 u_params;
struct P { float v; };

[shader("raygeneration")]
void rayGenMain()
{
    uint2 px = DispatchRaysIndex().xy;
    RayDesc rd;
    rd.Origin = float3(0,0,0); rd.Direction = float3(0,0,1); rd.TMin = 0.0; rd.TMax = 100.0;
    P p1; p1.v = 0.0;
    TraceRay(scene, RAY_FLAG_NONE, 0xff, 0, 1, 0, rd, p1);
    RayDesc up;
    up.Origin = float3(0,0,0); up.Direction = float3(0,1,0); up.TMin = 0.0; up.TMax = 100.0;
    P p2; p2.v = 0.0;
    TraceRay(scene, RAY_FLAG_NONE, 0xff, 0, 1, 0, up, p2);
    float v = p1.v + p2.v + u_params.y;
    target[px] = float4(v, v, v, 1.0);
}
