// Slang port of examples/39-assao cs_assao_postprocess_importance_map_a.sc.
// IMAGE2D_WO(r8) target + SAMPLER2D importanceMap; texture2DLod (library), mix (glsl_compat).
import bgfx_shader;
import bgfx_shader_glsl_compat; // mix
import bgfx_compute;

uniform float4 u_params[9];

[[vk::image_format("r8")]]
RWTexture2D<float> s_target : register(u0);

Texture2D    s_importanceMap        : register(t1);
SamplerState s_importanceMapSampler : register(s1);

// Shaders below only needed for adaptive quality level
static const float cSmoothenImportance = 1.0;

[shader("compute")]
[numthreads(8, 8, 1)]
void computeMain(uint3 dispatchThreadId : SV_DispatchThreadID)
{
	uvec2 dtID = uvec2(dispatchThreadId.xy);

	uvec2 dim = uvec2(imageSize(s_target).xy);
	if (all(dtID.xy < dim) )
	{
		uvec2 pos = uvec2(dtID.xy);
		vec2 inUV = (dtID.xy+vec2(0.5,0.5)) * u_params[8].zw;

		float centre = texture2DLod(s_importanceMap, s_importanceMapSampler, inUV, 0.0 ).x;

		vec2 halfPixel = u_params[8].zw * 0.5f;

		vec4 vals;
		vals.x = texture2DLod(s_importanceMap, s_importanceMapSampler, inUV + vec2( -halfPixel.x * 3, -halfPixel.y ), 0.0 ).x;
		vals.y = texture2DLod(s_importanceMap, s_importanceMapSampler, inUV + vec2( +halfPixel.x, -halfPixel.y * 3 ), 0.0 ).x;
		vals.z = texture2DLod(s_importanceMap, s_importanceMapSampler, inUV + vec2( +halfPixel.x * 3, +halfPixel.y ), 0.0 ).x;
		vals.w = texture2DLod(s_importanceMap, s_importanceMapSampler, inUV + vec2( -halfPixel.x, +halfPixel.y * 3 ), 0.0 ).x;

		float avgVal = dot( vals, vec4( 0.25, 0.25, 0.25, 0.25 ) );
		vals.xy = max( vals.xy, vals.zw );
		float maxVal = max( centre, max( vals.x, vals.y ) );

		imageStore(s_target, ivec2(dtID.xy), mix( maxVal, avgVal, cSmoothenImportance ));
	}
}
