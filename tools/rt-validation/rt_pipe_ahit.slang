// Any-hit stage: rejects every hit on instance 0 (the front triangle), so the ray
// continues to instance 1 behind it. If any-hit is not wired, the closest hit lands on
// instance 0 instead -- distinguishable via the per-instance material.
struct Payload
{
	float hit;
};

[shader("anyhit")]
void anyHitMain(inout Payload p, in BuiltInTriangleIntersectionAttributes attribs)
{
	if (InstanceIndex() == 0)
	{
		IgnoreHit();
	}
}
