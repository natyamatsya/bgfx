// Radiance miss (index 0) of the RT-pipeline stage: the open front's background.
import "cornellbox.sh";

[shader("miss")]
void missMain(inout RtPipePayload p)
{
	p.color = float3(0.02, 0.02, 0.02);
}
