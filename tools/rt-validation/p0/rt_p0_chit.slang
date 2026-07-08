// Closest hit: 0.5 for the hit plus 0.25 when the reported distance matches the
// triangle at z=5 (payload roundtrip + RayTCurrent-from-context both validated).
struct P
{
    float v;
};

[shader("closesthit")]
void closestHitMain(inout P p, in BuiltInTriangleIntersectionAttributes attr)
{
    p.v = 0.5;
    if (abs(RayTCurrent() - 5.0) < 0.01)
    {
        p.v += 0.25;
    }
}
