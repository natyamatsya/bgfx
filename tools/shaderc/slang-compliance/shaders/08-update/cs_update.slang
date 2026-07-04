// 1-to-1 Slang port of examples/08-update cs_update.sc.
// IMAGE2D_ARRAY_WO(s_texColor, rgba8, 0) -> RWTexture2DArray write storage image;
// NUM_THREADS(16,16,1) -> [numthreads]; fills each cube face with an animated color.
import bgfx_compute;
import bgfx_shader;

// IMAGE2D_ARRAY_WO(s_texColor, rgba8, 0)
[[vk::image_format("rgba8")]]
RWTexture2DArray<vec4> s_texColor : register(u0);

uniform vec4 u_time;

[shader("compute")]
[numthreads(16, 16, 1)]
void computeMain(uint3 gl_GlobalInvocationID : SV_DispatchThreadID)
{
	vec3 colors[] =
	{
		vec3(1.0, 0.0, 0.0),
		vec3(1.0, 1.0, 0.0),
		vec3(1.0, 0.0, 1.0),
		vec3(0.0, 1.0, 0.0),
		vec3(0.0, 1.0, 1.0),
		vec3(0.0, 0.0, 1.0),
	};

	for (int face = 0; face < 6; face++)
	{
		vec3 color = colors[face] * 0.75 + sin(u_time.x * 4.0) * 0.25;
		ivec3 dest = ivec3(gl_GlobalInvocationID.xy, face);
		imageStore(s_texColor, dest, vec4(color, 1.0) );
	}
}
