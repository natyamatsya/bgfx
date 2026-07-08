// Miss index 1: reached only by the deliberately-missing second ray.
struct P
{
    float v;
};

[shader("miss")]
void missMain1(inout P p)
{
    p.v = 0.25;
}
