// Slang port of examples/39-assao cs_assao_generate_q3.sc. The stock file only #defines
// ASSAO_QUALITY 3 / ASSAO_ADAPTIVE_BASE false and #includes cs_assao_generate_q.sh; the whole
// body lives in the co-located cs_assao_generate_q library. Passing quality/base as compile-time
// constants reproduces the stock's macro-driven specialization (resource set) per stage.
import bgfx_shader;
import cs_assao_generate_q;

[shader("compute")]
[numthreads(8, 8, 1)]
void computeMain(uint3 dispatchThreadId : SV_DispatchThreadID)
{
	generateSSAO<3, false>(uvec2(dispatchThreadId.xy));
}
