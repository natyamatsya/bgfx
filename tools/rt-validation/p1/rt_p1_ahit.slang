// Anyhit: writes payload evidence, then rejects the candidate. DXR requires
// payload writes to persist for ignored hits, so phase B expects exactly 0.5:
// the write survived AND the reject forced a miss (0.25 = anyhit never ran,
// chit hit instead; 0.75 = write survived but the reject did not).
struct P
{
    float v;
};

[shader("anyhit")]
void anyHitMain(inout P p, in BuiltInTriangleIntersectionAttributes attrs)
{
    p.v += 0.5;
    IgnoreHit();
}
