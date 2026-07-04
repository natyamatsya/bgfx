// Slang port of examples/39-assao cs_assao_apply.sc.
// IMAGE2D_WO(r8) target + SAMPLER2DARRAY finalSSAO; texelFetch -> .Load, texture2DArrayLod
// -> .SampleLevel. UnpackEdges kept inline (defined in the .sc body). Non-GLSL branch.
import bgfx_shader;
import bgfx_compute;

uniform float4 u_params[9];
// stock uniforms.sh declares u_params[19] then u_rect; glslang reflects u_params at its used
// extent (9) but reserves the full [19] in $Globals, so u_rect keeps byte offset 304 and the UBO
// size stays 320. Reproduce the reserved tail with a struct member (not reflected as a uniform).
struct ParamsTailPad { float4 _unused[10]; };
ParamsTailPad _paramsTailPad;
uniform float4 u_rect;

[[vk::image_format("r8")]]
RWTexture2D<float> s_target : register(u0);

Texture2DArray s_finalSSAO        : register(t1);
SamplerState   s_finalSSAOSampler : register(s1);

// unpacking for edges; 2 bits per edge mean 4 gradient values (0, 0.33, 0.66, 1) for smoother transitions!
vec4 UnpackEdges( float _packedVal )
{
    uint packedVal = uint(_packedVal * 255.5);
    vec4 edgesLRTB;
    edgesLRTB.x = float((packedVal >> 6) & 0x03) / 3.0;
    edgesLRTB.y = float((packedVal >> 4) & 0x03) / 3.0;
    edgesLRTB.z = float((packedVal >> 2) & 0x03) / 3.0;
    edgesLRTB.w = float((packedVal >> 0) & 0x03) / 3.0;

    return saturate( edgesLRTB + u_params[8].x );
}

[shader("compute")]
[numthreads(8, 8, 1)]
void computeMain(uint3 dispatchThreadId : SV_DispatchThreadID)
{
	uvec2 dtID = uvec2(dispatchThreadId.xy) + uvec2(u_rect.xy);
	if (all(vec2(dtID.xy) < u_rect.zw) )
	{
		float ao;
		uvec2 pixPos     = uvec2(dtID.xy);
		uvec2 pixPosHalf = pixPos / uvec2(2, 2);

		// calculate index in the four deinterleaved source array texture
		int mx = (int(pixPos.x) % 2);
		int my = (int(pixPos.y) % 2);
		int ic = mx + my * 2;       // center index
		int ih = (1-mx) + my * 2;   // neighbouring, horizontal
		int iv = mx + (1-my) * 2;   // neighbouring, vertical
		int id = (1-mx) + (1-my)*2; // diagonal

		vec2 centerVal = s_finalSSAO.Load( ivec4(ivec2(pixPosHalf), ic, 0) ).xy;

		ao = centerVal.x;

	#if 1   // change to 0 if you want to disable last pass high-res blur (for debugging purposes, etc.)
		vec4 edgesLRTB = UnpackEdges( centerVal.y );

		// convert index shifts to sampling offsets
		float fmx   = float(mx);
		float fmy   = float(my);

		// in case of an edge, push sampling offsets away from the edge (towards pixel center)
		float fmxe  = (edgesLRTB.y - edgesLRTB.x);
		float fmye  = (edgesLRTB.w - edgesLRTB.z);

		// calculate final sampling offsets and sample using bilinear filter
		vec2  uvH = (dtID.xy + vec2( fmx + fmxe - 0.5, 0.5 - fmy ) ) * 0.5 * u_params[0].zw;
		float   aoH = s_finalSSAO.SampleLevel(s_finalSSAOSampler, vec3( uvH, float(ih) ), 0 ).x;
		vec2  uvV = (dtID.xy + vec2( 0.5 - fmx, fmy - 0.5 + fmye ) ) * 0.5 * u_params[0].zw;
		float   aoV = s_finalSSAO.SampleLevel(s_finalSSAOSampler, vec3( uvV, float(iv) ), 0 ).x;
		vec2  uvD = (dtID.xy + vec2( fmx - 0.5 + fmxe, fmy - 0.5 + fmye ) ) * 0.5 * u_params[0].zw;
		float   aoD = s_finalSSAO.SampleLevel(s_finalSSAOSampler, vec3( uvD, float(id) ), 0 ).x;

		// reduce weight for samples near edge - if the edge is on both sides, weight goes to 0
		vec4 blendWeights;
		blendWeights.x = 1.0;
		blendWeights.y = (edgesLRTB.x + edgesLRTB.y) * 0.5;
		blendWeights.z = (edgesLRTB.z + edgesLRTB.w) * 0.5;
		blendWeights.w = (blendWeights.y + blendWeights.z) * 0.5;

		// calculate weighted average
		float blendWeightsSum   = dot( blendWeights, vec4( 1.0, 1.0, 1.0, 1.0 ) );
		ao = dot( vec4( ao, aoH, aoV, aoD ), blendWeights ) / blendWeightsSum;
	#endif

		ao = pow(ao,1.0/2.2);

		imageStore(s_target, ivec2(dtID.xy), ao);
	}
}
