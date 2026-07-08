// P4 on-device module: world- vs object-space semantics under a NON-IDENTITY instance
// transform (the P4 fix -- identity scenes never noticed), plus
// RAY_FLAG_SKIP_CLOSEST_HIT_SHADER. Additive values:
//   trace 1 (translated sphere instance): chit base +0.125, world-space t==4.2 +0.125,
//     hit kind 7 +0.125, attribute blob +0.125                          = +0.5
//   trace 2 (same ray, SKIP_CLOSEST_HIT_SHADER): payload marker survives = +0.25
//   trace 3 (away ray, miss record 1)                                   = +0.25
//   total: exactly 1.0
uniform RaytracingAccelerationStructure scene : register(t0);
RWTexture2D<float4> target : register(u1);

struct P
{
    float v;
};

struct SphereAttrs
{
    float3 normal;
    float shifted;
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

    float v = 0.0;

    P p;
    p.v = 0.0;
    TraceRay(scene, RAY_FLAG_NONE, 0xff, 0, 1, 0, rd, p);
    v += p.v;

    P p2;
    p2.v = 0.125;
    TraceRay(scene, RAY_FLAG_SKIP_CLOSEST_HIT_SHADER, 0xff, 0, 1, 0, rd, p2);
    if (p2.v == 0.125) v += 0.25; // closest-hit dispatch suppressed, marker intact

    RayDesc away;
    away.Origin    = float3(0, 0, 0);
    away.Direction = float3(0, 1, 0);
    away.TMin      = 0.0;
    away.TMax      = 100.0;

    P p3;
    p3.v = 0.0;
    TraceRay(scene, RAY_FLAG_NONE, 0xff, 0, 1, 1, away, p3);
    v += p3.v;

    target[px] = float4(v, v, v, 1.0);
}

[shader("miss")]
void missMain(inout P p)
{
}

[shader("miss")]
void shadowMiss(inout P p)
{
    p.v = 0.25;
}

[shader("closesthit")]
void closestHitMain(inout P p, in SphereAttrs attrs)
{
    float v = 0.125;
    if (abs(RayTCurrent() - 4.2) < 0.01) v += 0.125;
    if (HitKind() == 7u) v += 0.125;
    v += attrs.shifted;
    p.v = v;
}

// The sphere lives at WORLD (0,0,5): under the host's +2z instance translation the
// object-space ray differs, so this test fails if WorldRayOrigin/Direction still
// aliased Metal's object-space [[origin]]/[[direction]] (the pre-P4 bug).
[shader("intersection")]
void sphereIsect()
{
    float3 c  = float3(0.0, 0.0, 5.0);
    float  r  = 0.8;
    float3 ro = WorldRayOrigin();
    float3 rd = WorldRayDirection();

    float3 oc = ro - c;
    float a = dot(rd, rd);
    float b = dot(oc, rd);
    float d = b*b - a*(dot(oc, oc) - r*r);

    if (d >= 0.0)
    {
        float t = (-b - sqrt(d)) / a;
        SphereAttrs attrs;
        attrs.normal  = normalize((ro + t*rd) - c);
        attrs.shifted = 0.125;
        ReportHit(t, 7u, attrs);
    }
}
