// P1 on-device module: all five stages compiled TOGETHER, per the design doc's
// separate-compilation caveat -- the raygen kernel receives the `slang_rtIsect`
// intersection function table binding only when anyhit/intersection entry points are
// present in the same module. The host (metal_rt_pipeline_p1.cpp) loads each stage
// function by name from the one library.
//
// Phase A (procedural sphere): sphereIsect reports the analytic entry with a custom
// hit kind and user attributes; closestHitMain validates distance (+0.25), hit kind
// (+0.25) and the attribute blob (+0.25) on top of the 0.25 base = exactly 1.0.
// Phase B (anyhit): anyHitMain writes 0.5 of payload evidence and rejects the
// candidate -- DXR requires the write to persist for ignored hits, so exactly 0.5.
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

    P p;
    p.v = 0.0;
    TraceRay(scene, RAY_FLAG_NONE, 0xff, 0, 1, 0, rd, p);

    target[px] = float4(p.v, p.v, p.v, 1.0);
}

[shader("miss")]
void missMain(inout P p)
{
}

[shader("closesthit")]
void closestHitMain(inout P p, in SphereAttrs attrs)
{
    p.v = 0.25;
    if (abs(RayTCurrent() - 4.2) < 0.01) p.v += 0.25;
    if (HitKind() == 7u) p.v += 0.25;
    p.v += attrs.shifted;
}

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
        attrs.shifted = 0.25;
        ReportHit(t, 7u, attrs);
    }
}

[shader("anyhit")]
void anyHitMain(inout P p, in BuiltInTriangleIntersectionAttributes attrs)
{
    p.v += 0.5;
    IgnoreHit();
}
