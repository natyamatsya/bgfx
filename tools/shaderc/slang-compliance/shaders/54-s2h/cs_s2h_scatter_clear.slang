// Slang port of examples/54-s2h/cs_s2h_scatter_clear.sc.
import bgfx_shader;
import bgfx_compute;

[[vk::image_format("rgba8")]]
RWTexture2D<vec4> s_scatterColor : register(u0);

vec4 u_s2hScatterSize;

struct CSInput
{
	uint3 gl_GlobalInvocationID : SV_DispatchThreadID;
};

[shader("compute")]
[numthreads(8, 8, 1)]
void computeMain(CSInput input)
{
	ivec2 pixel = ivec2(input.gl_GlobalInvocationID.xy);
	if (pixel.x < int(u_s2hScatterSize.x) && pixel.y < int(u_s2hScatterSize.y) )
	{
		imageStore(s_scatterColor, pixel, vec4(0.40, 0.70, 0.40, 1.0) );
	}
}
