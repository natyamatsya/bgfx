// Mixed-kit phase B, procedural closest-hit module: 0.5 base + 0.25 for the analytic
// distance + the 0.25 the intersection module put in the attribute blob = 1.0.
struct P { float v; };
struct SphereAttrs
{
    float3 normal;
    float shifted;
};

[shader("closesthit")]
void closestHitMain(inout P p, in SphereAttrs attrs)
{
    p.v = 0.5;
    if (abs(RayTCurrent() - 4.2) < 0.01) p.v += 0.25;
    p.v += attrs.shifted;
}
