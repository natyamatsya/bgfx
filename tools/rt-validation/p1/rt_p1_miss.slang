// Miss contributes nothing; every phase's expected value comes from hit-path
// features so a silent miss is always distinguishable.
struct P
{
    float v;
};

[shader("miss")]
void missMain(inout P p)
{
}
