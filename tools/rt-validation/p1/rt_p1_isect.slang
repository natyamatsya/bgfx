// Intersection shader: analytic sphere (centre (0,0,5), r=0.8) inside the AABB;
// reports the entry point with a custom hit kind and a user attribute struct.
struct SphereAttrs
{
    float3 normal;
    float shifted;
};

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
