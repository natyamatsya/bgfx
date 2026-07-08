// Mixed-module kit, miss module: a HANDLER reading loose uniforms (the blocking-finding
// case -- the uniforms header entry) plus its own hoisted resource at slot 4.
uniform float4 u_params;
StructuredBuffer<float4> skyColors : register(t4);
struct P { float v; };

[shader("miss")]
void missMain(inout P p)
{
    p.v = u_params.x + skyColors[0].x;
}
