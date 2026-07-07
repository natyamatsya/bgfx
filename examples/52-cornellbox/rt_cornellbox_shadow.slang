// Shadow miss (index 1) of the RT-pipeline stage: reached only when the closest-hit
// stage's shadow ray finds nothing between the surface and the light.
import "cornellbox.sh";

[shader("miss")]
void shadowMissMain(inout RtShadowPayload p)
{
	p.lit = 1.0;
}
