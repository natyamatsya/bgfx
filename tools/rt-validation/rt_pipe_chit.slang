// Closest-hit stage of the RT-pipeline smoke test (triangle hit group).
struct Payload
{
	float hit;
};

[shader("closesthit")]
void closestHitMain(inout Payload p, in BuiltInTriangleIntersectionAttributes attribs)
{
	p.hit = 1.0;
}
