// Miss stage of the RT-pipeline smoke test.
struct Payload
{
	float hit;
};

[shader("miss")]
void missMain(inout Payload p)
{
	p.hit = 0.0;
}
