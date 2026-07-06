// Deforms the smoke test's triangle: each thread moves one vertex +100 in x, taking the
// geometry off the test ray's path. Exercises BGFX_BUFFER_COMPUTE_WRITE vertex buffers as
// refit sources (bgfx::updateBlas).
import bgfx_shader;
import bgfx_compute;

RWStructuredBuffer<float> vertices : register(u0); // xyz per vertex, tightly packed

[shader("compute")]
[numthreads(3, 1, 1)]
void computeMain(uint3 id : SV_DispatchThreadID)
{
	vertices[id.x*3 + 0] += 100.0;
}
