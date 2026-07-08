// Mixed-module kit, closest-hit module: a different resource subset (slot 3 only).
RWStructuredBuffer<float4> materials : register(u3);
struct P { float v; };

[shader("closesthit")]
void closestHitMain(inout P p, in BuiltInTriangleIntersectionAttributes a)
{
    p.v = 0.25 + materials[0].x;
}
