// 1-to-1 Slang port of examples/44-sss fs_screen_space_shadows.sc.
// Ray-marched contact shadows. u_params referenced up to index 11 (u_viewToProj3),
// so the array reflects at its used extent (12). gl_FragCoord -> SV_Position input field.
// NDCToViewspace / ShadertoyNoise are inline in the stock .sc body -> stay inline.
import bgfx_shader;

Texture2D    s_depth        : register(t0);
SamplerState s_depthSampler : register(s0);

// parameters.sh macros expanded inline against u_params:
//   u_frameIdx=[0].x u_shadowRadius=[0].y u_shadowSteps=[0].z u_useNoiseOffset=[0].w
//   u_contactShadowsMode=[1].z u_useScreenSpaceRadius=[1].w
//   u_ndcToViewMul=[2].xy u_ndcToViewAdd=[2].zw u_lightPosition=[3].xyz
//   u_viewToProj0..3=[8..11]
float4 u_params[12];

#define DEPTH_EPSILON	1e-4

// from assao sample, cs_assao_prepare_depths.sc
vec3 NDCToViewspace( vec2 pos, float viewspaceDepth )
{
	vec3 ret;

	ret.xy = (u_params[2].xy * pos.xy + u_params[2].zw) * viewspaceDepth;

	ret.z = viewspaceDepth;

	return ret;
}

float ShadertoyNoise (vec2 uv) {
	return frac(sin(dot(uv.xy, vec2(12.9898,78.233))) * 43758.5453123);
}

struct V2F
{
	vec4 gl_FragCoord : SV_Position;
	vec2 v_texcoord0  : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec2 texCoord = input.v_texcoord0;
	float linearDepth = texture2D(s_depth, s_depthSampler, texCoord).x;
	vec3 viewSpacePosition = NDCToViewspace(texCoord, linearDepth);

	vec3 lightStep = normalize(u_params[3].xyz - viewSpacePosition);

	// screen space radius not usable directly. convert value given in pixels,
	// to world units. this is important later when comparing depth in world units
	float radius = u_params[0].y;
	if (0.0 < u_params[1].w)
	{
		// is there a better way to do this calculation?
		float radiusTexCoordX = u_params[0].y * u_viewTexel.x + texCoord.x;
		float radiusPositionX = u_params[2].x * radiusTexCoordX + u_params[2].z;
		radius = abs(radiusPositionX * linearDepth - viewSpacePosition.x);
	}
	lightStep *= (radius / u_params[0].z);

	vec3 samplePosition = viewSpacePosition;
	float random = ShadertoyNoise(input.gl_FragCoord.xy + vec2(314.0, 159.0)*u_params[0].x);
	float initialOffset = (0.0 < u_params[0].w) ? (0.5+random) : 1.0;
	samplePosition += initialOffset * lightStep;

	mat4 viewToProj = mtxFromCols(
		  u_params[8]
		, u_params[9]
		, u_params[10]
		, u_params[11]
		);

	float occluded = 0.0;
	float softOccluded = 0.0;
	float firstHit = u_params[0].z;
	for (int i = 0; i < int(u_params[0].z); ++i, samplePosition += lightStep)
	{
		vec3 psSamplePosition = mul(viewToProj, vec4(samplePosition, 1.0)).xyw;
		psSamplePosition.xy *= (1.0/psSamplePosition.z);

		vec2 sampleCoord = psSamplePosition.xy * 0.5 + 0.5;
		sampleCoord.y = 1.0 - sampleCoord.y;

		// using texture2Dlod because dx9 compiler doesn't like
		// gradient instructions within this loop
		float sampleDepth = texture2DLod(s_depth, s_depthSampler, sampleCoord, 0).x;

		float delta = (samplePosition.z - sampleDepth);
		if (DEPTH_EPSILON < delta && delta < radius)
		{
			firstHit = min(firstHit, float(i));
			// for hard, soft occlusion
			occluded += 1.0;
			// for very soft occlusion
			softOccluded += saturate(radius - delta);
		}
	}

	float shadow;
	if (1.5 < u_params[1].z)
	{
		// very soft occlusion, includes distance falloff above
		shadow = softOccluded * (1.0 - (firstHit / u_params[0].z));
		shadow = 1.0 - saturate(shadow);
		shadow = shadow*shadow;
	}
	else if (0.5 < u_params[1].z)
	{
		// soft occlusion
		shadow = occluded * (1.0 - (firstHit / u_params[0].z));
		shadow = 1.0 - saturate(shadow);
		shadow = shadow*shadow;
	}
	else // == 0
	{
		// hard occlusion
		shadow = 0.0 < occluded ? 0.0 : 1.0;
	}

	return vec4_splat(shadow);
}
