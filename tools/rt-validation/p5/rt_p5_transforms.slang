// Transforms-phase on-device module (runs on the metal_rt_pipeline_p4 host: translated
// +2z instance, AABB at OBJECT z [2,4]). The intersection shader finds the sphere in
// OBJECT space via ObjectRayOrigin/Direction -- only correct if the candidate's
// object-space ray is exact -- and the closest-hit validates the committed transforms.
// Eight 0.125 increments, exactly 1.0:
//   chit base; RayTCurrent==4.2; ObjectToWorld4x3()[3].z==+2; WorldToObject4x3()[3].z==-2;
//   ObjectRayOrigin().z==-2; ObjectRayDirection().z==+1; isect-side ObjectToWorld check
//   (via the attribute blob); miss record 1 for the away ray.
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
    p.v = 0.125;
}

[shader("closesthit")]
void closestHitMain(inout P p, in SphereAttrs attrs)
{
    float v = 0.125;
    if (abs(RayTCurrent() - 4.2) < 0.01)                 v += 0.125;
    if (abs(ObjectToWorld4x3()[3].z - 2.0) < 0.001)      v += 0.125;
    if (abs(WorldToObject4x3()[3].z + 2.0) < 0.001)      v += 0.125;
    if (abs(ObjectRayOrigin().z + 2.0) < 0.001)          v += 0.125;
    if (abs(ObjectRayDirection().z - 1.0) < 0.001)       v += 0.125;
    v += attrs.shifted;
    p.v = v;
}

// Sphere at OBJECT-space (0,0,3): findable only through the candidate's exact
// object-space ray. The attribute carries the isect-side transform check.
[shader("intersection")]
void sphereIsect()
{
    float3 c  = float3(0.0, 0.0, 3.0);
    float  r  = 0.8;
    float3 ro = ObjectRayOrigin();
    float3 rd = ObjectRayDirection();

    float3 oc = ro - c;
    float a = dot(rd, rd);
    float b = dot(oc, rd);
    float d = b*b - a*(dot(oc, oc) - r*r);

    if (d >= 0.0)
    {
        float t = (-b - sqrt(d)) / a;
        SphereAttrs attrs;
        attrs.normal  = normalize((ro + t*rd) - c);
        attrs.shifted = abs(ObjectToWorld4x3()[3].z - 2.0) < 0.001 ? 0.125 : 0.0;
        ReportHit(t, 7u, attrs);
    }
}
