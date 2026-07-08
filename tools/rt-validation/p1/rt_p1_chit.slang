// Closest hit for the procedural sphere: 0.25 base + 0.25 for the analytic
// distance (4.2) + 0.25 for the custom hit kind (7) + the 0.25 the intersection
// shader put in the attribute blob = exactly 1.0 when everything works.
struct P
{
    float v;
};

struct SphereAttrs
{
    float3 normal;
    float shifted;
};

[shader("closesthit")]
void closestHitMain(inout P p, in SphereAttrs attrs)
{
    p.v = 0.25;
    if (abs(RayTCurrent() - 4.2) < 0.01) p.v += 0.25;
    if (HitKind() == 7u) p.v += 0.25;
    p.v += attrs.shifted;
}
