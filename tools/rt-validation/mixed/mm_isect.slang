// Mixed-kit phase B, intersection module: reads its sphere FROM A GLOBAL (slot 6)
// through the C3 trailing-parameter path -- the first on-device exercise of
// intersection-stage globals. Reports with attrs carrying +0.25.
StructuredBuffer<float4> spheres : register(t6);

struct SphereAttrs
{
    float3 normal;
    float shifted;
};

[shader("intersection")]
void sphereIsect()
{
    float4 sph = spheres[0];
    float3 c = sph.xyz;
    float  r = sph.w;
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
        attrs.normal = normalize((ro + t*rd) - c);
        attrs.shifted = 0.25;
        ReportHit(t, 7u, attrs);
    }
}
