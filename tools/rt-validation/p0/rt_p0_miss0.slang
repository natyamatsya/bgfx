// Miss index 0 (primary-ray miss): contributes nothing.
struct P
{
    float v;
};

[shader("miss")]
void missMain(inout P p)
{
    p.v = 0.0;
}
