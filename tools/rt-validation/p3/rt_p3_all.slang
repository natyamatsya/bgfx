// P3 on-device module (all stages together): the SS11-question-1 gate -- TraceRay from a
// closest-hit shader (recursion depth 2) plus every other P2/P3 mechanism, each with a
// distinct additive value so the readback pins them separately:
//   raygen:  2x CallShader                                  +0.250
//   chit:    base                                           +0.125
//            materials[0].x via slang_RTGlobals             +0.125
//            nested TraceRay -> shadow miss (record idx 1)  +0.125
//            RayTCurrent() AFTER the nested trace == 5.0    +0.125  (snapshot)
//            PrimitiveIndex() AFTER the nested trace == 0   +0.125  (snapshot)
//            CallShader from a handler                      +0.125
//   total: exactly 1.0
uniform RaytracingAccelerationStructure scene : register(t0);
RWTexture2D<float4> target : register(u1);
StructuredBuffer<float4> materials : register(t2);

struct P
{
    float v;
};

struct ShadowP
{
    float lit;
};

struct CallData
{
    float add;
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

    CallData cd;
    cd.add = 0.0;
    CallShader(0, cd);
    CallShader(0, cd);

    float v = p.v + cd.add;
    target[px] = float4(v, v, v, 1.0);
}

[shader("miss")]
void missMain(inout P p)
{
}

[shader("miss")]
void shadowMiss(inout ShadowP sp)
{
    sp.lit = 0.125;
}

[shader("closesthit")]
void closestHitMain(inout P p, in BuiltInTriangleIntersectionAttributes attrs)
{
    float v = 0.125;
    v += materials[0].x; // 0.125, through the slang_RTGlobals argument buffer

    RayDesc up;
    up.Origin    = WorldRayOrigin() + WorldRayDirection() * RayTCurrent();
    up.Direction = float3(0, 1, 0);
    up.TMin      = 0.01;
    up.TMax      = 100.0;

    ShadowP sp;
    sp.lit = 0.0;
    TraceRay(scene, RAY_FLAG_NONE, 0xff, 0, 1, 1, up, sp); // depth 2
    v += sp.lit;

    if (abs(RayTCurrent() - 5.0) < 0.01) v += 0.125; // snapshot survived the nested trace
    if (PrimitiveIndex() == 0u)          v += 0.125; // snapshot survived the nested trace

    CallData cd;
    cd.add = 0.0;
    CallShader(0, cd);
    v += cd.add;

    p.v = v;
}

[shader("callable")]
void shadeCallable(inout CallData cd)
{
    cd.add += 0.125;
}
