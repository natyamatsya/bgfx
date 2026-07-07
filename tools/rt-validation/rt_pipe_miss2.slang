// Second miss stage (index 1) of the RT-pipeline smoke test: reached only by the
// closest-hit shader's secondary ray.
struct Payload
{
	float hit;
};

[shader("miss")]
void missMain2(inout Payload p)
{
	p.hit = 0.25;
}
