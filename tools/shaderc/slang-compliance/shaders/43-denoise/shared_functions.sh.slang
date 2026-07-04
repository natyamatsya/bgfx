// Slang port of examples/43-denoise shared_functions.sh -- the reprojection helpers
// shared by the temporal and txaa passes. `import shared_functions;`.
//
// GetTexCoordPreviousNoJitter is pure and unchanged. GetTexCoordPrevious references the
// custom uniform jitter (u_jitterCurr/u_jitterPrev = u_params[0]) and the predefined
// u_viewTexel in the stock body; a library module cannot see those uniforms, so (as with
// 41-tess terrain_common) they are passed in as arguments. No resources are declared here,
// so importing this leaves the reflection envelope unchanged.
import bgfx_shader;

public vec2 GetTexCoordPreviousNoJitter(vec2 texCoord, vec2 velocity)
{
	vec2 texCoordPrev = texCoord - velocity;
	return texCoordPrev;
}

public vec2 GetTexCoordPrevious(vec2 texCoord, vec2 velocity, vec2 jitterDelta, vec2 viewTexel)
{
	vec2 texCoordPrev = texCoord - velocity;

	// jitterDelta = (u_jitterCurr - u_jitterPrev); viewTexel = u_viewTexel.xy
	texCoordPrev += jitterDelta * viewTexel;

	return texCoordPrev;
}
