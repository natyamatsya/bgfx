// Slang port of examples/39-assao cs_assao_load_counter_clear.sc — compute tier.
// BUFFER_WO(s_loadCounter, uint, 0) -> a read-write structured buffer; NUM_THREADS
// -> [numthreads]. The threadgroup size lives in the SPIR-V (no envelope trailer).

RWStructuredBuffer<uint> s_loadCounter : register(u0);

[shader("compute")]
[numthreads(1, 1, 1)]
void computeMain(uint3 dispatchThreadId : SV_DispatchThreadID)
{
	s_loadCounter[0] = 0;
}
