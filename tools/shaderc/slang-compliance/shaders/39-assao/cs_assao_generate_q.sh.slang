// Slang port of examples/39-assao cs_assao_generate_q.sh -- the shared ASSAO body that
// the five cs_assao_generate_q{0,1,2,3,3base}.sc stages #include (each only #defines
// ASSAO_QUALITY / ASSAO_ADAPTIVE_BASE and pulls this in). Ported once here as a co-located
// library; each entry point imports it and calls generateSSAO(...) with compile-time
// quality/base constants so the same dead-code elimination (and thus resource set) that the
// stock macro constants produce is reproduced per stage. `import cs_assao_generate_q;`.
//
// Only the non-GLSL (BGFX_SHADER_LANGUAGE_SPIRV) branches are ported: shaderc compiles the
// stock .sc with `-p spirv`, which leaves BGFX_SHADER_LANGUAGE_GLSL == 0.
import bgfx_shader;   // vec/ivec/uvec/mat aliases, texture2DLod, mtxFromCols
import bgfx_compute;  // imageLoad/imageStore/imageSize

// --- uniforms (uniforms.sh) ---
public uniform float4 u_params[19];
public uniform float4 u_rect;

#define u_viewportPixelSize                 u_params[0].xy
#define u_halfViewportPixelSize             u_params[0].zw
#define u_depthUnpackConsts                 u_params[1].xy
#define u_ndcToViewMul                      u_params[2].xy
#define u_ndcToViewAdd                      u_params[2].zw
#define u_perPassFullResCoordOffset         u_params[3].xy
#define u_perPassFullResUVOffset            u_params[3].zw
#define u_viewport2xPixelSize               u_params[4].xy
#define u_viewport2xPixelSize_x_025         u_params[4].zw
#define u_effectRadius                      u_params[5].x
#define u_effectShadowStrength              u_params[5].y
#define u_effectShadowPow                   u_params[5].z
#define u_effectShadowClamp                 u_params[5].w
#define u_effectFadeOutMul                  u_params[6].x
#define u_effectFadeOutAdd                  u_params[6].y
#define u_effectHorizonAngleThreshold       u_params[6].z
#define u_effectSamplingRadiusNearLimitRec  u_params[6].w
#define u_depthPrecisionOffsetMod           u_params[7].x
#define u_negRecEffectRadius                u_params[7].y
#define u_loadCounterAvgDiv                 u_params[7].z
#define u_adaptiveSampleCountLimit          u_params[7].w
#define u_invSharpness                      u_params[8].x
#define u_passIndex                         u_params[8].y
#define u_quarterResPixelSize               u_params[8].zw
#define u_patternRotScaleMatrices(i)        u_params[9+(i)]
#define u_normalsUnpackMul                  u_params[14].x
#define u_normalsUnpackAdd                  u_params[14].y
#define u_detailAOStrength                  u_params[14].z
#define u_layer                             u_params[14].w
#define u_normalsWorldToViewspaceMatrix0    u_params[15]
#define u_normalsWorldToViewspaceMatrix1    u_params[16]
#define u_normalsWorldToViewspaceMatrix2    u_params[17]
#define u_normalsWorldToViewspaceMatrix3    u_params[18]

#define SSAO_MAX_TAPS                               32
#define SSAO_ADAPTIVE_TAP_BASE_COUNT                5
#define SSAO_ADAPTIVE_TAP_FLEXIBLE_COUNT            (SSAO_MAX_TAPS-SSAO_ADAPTIVE_TAP_BASE_COUNT)
#define SSAO_DEPTH_MIP_LEVELS                       4
#define SSAO_ENABLE_NORMAL_WORLD_TO_VIEW_CONVERSION 1

// progressive poisson-like pattern; x, y are in [-1, 1] range, .z is length( vec2(x,y) ), .w is log2( z )
#define INTELSSAO_MAIN_DISK_SAMPLE_COUNT (32)
static const vec4 g_samplePatternMain[INTELSSAO_MAIN_DISK_SAMPLE_COUNT] =
{
   { 0.78488064,  0.56661671,  1.500000, -0.126083},    { 0.26022232, -0.29575172,  1.500000, -1.064030},    { 0.10459357,  0.08372527,  1.110000, -2.730563},    {-0.68286800,  0.04963045,  1.090000, -0.498827},
   {-0.13570161, -0.64190155,  1.250000, -0.532765},    {-0.26193795, -0.08205118,  0.670000, -1.783245},    {-0.61177456,  0.66664219,  0.710000, -0.044234},    { 0.43675563,  0.25119025,  0.610000, -1.167283},
   { 0.07884444,  0.86618668,  0.640000, -0.459002},    {-0.12790935, -0.29869005,  0.600000, -1.729424},    {-0.04031125,  0.02413622,  0.600000, -4.792042},    { 0.16201244, -0.52851415,  0.790000, -1.067055},
   {-0.70991218,  0.47301072,  0.640000, -0.335236},    { 0.03277707, -0.22349690,  0.600000, -1.982384},    { 0.68921727,  0.36800742,  0.630000, -0.266718},    { 0.29251814,  0.37775412,  0.610000, -1.422520},
   {-0.12224089,  0.96582592,  0.600000, -0.426142},    { 0.11071457, -0.16131058,  0.600000, -2.165947},    { 0.46562141, -0.59747696,  0.600000, -0.189760},    {-0.51548797,  0.11804193,  0.600000, -1.246800},
   { 0.89141309, -0.42090443,  0.600000,  0.028192},    {-0.32402530, -0.01591529,  0.600000, -1.543018},    { 0.60771245,  0.41635221,  0.600000, -0.605411},    { 0.02379565, -0.08239821,  0.600000, -3.809046},
   { 0.48951152, -0.23657045,  0.600000, -1.189011},    {-0.17611565, -0.81696892,  0.600000, -0.513724},    {-0.33930185, -0.20732205,  0.600000, -1.698047},    {-0.91974425,  0.05403209,  0.600000,  0.062246},
   {-0.15064627, -0.14949332,  0.600000, -1.896062},    { 0.53180975, -0.35210401,  0.600000, -0.758838},    { 0.41487166,  0.81442589,  0.600000, -0.505648},    {-0.24106961, -0.32721516,  0.600000, -1.665244}
};

// these values can be changed (up to SSAO_MAX_TAPS) with no changes required elsewhere; values for 4th and 5th preset are ignored but array needed to avoid compilation errors
static const uint g_numTaps[5] = { 3, 5, 12, 0, 0 };

#define SSAO_TILT_SAMPLES_ENABLE_AT_QUALITY_PRESET                      (99)
#define SSAO_TILT_SAMPLES_AMOUNT                                        (0.4)
#define SSAO_HALOING_REDUCTION_ENABLE_AT_QUALITY_PRESET                 (1)
#define SSAO_HALOING_REDUCTION_AMOUNT                                   (0.6)
#define SSAO_NORMAL_BASED_EDGES_ENABLE_AT_QUALITY_PRESET                (2)
#define SSAO_NORMAL_BASED_EDGES_DOT_THRESHOLD                           (0.5)
#define SSAO_DETAIL_AO_ENABLE_AT_QUALITY_PRESET                         (1)
#define SSAO_DEPTH_MIPS_ENABLE_AT_QUALITY_PRESET                        (2)
#define SSAO_DEPTH_MIPS_GLOBAL_OFFSET                                   (-4.3)
#define SSAO_DEPTH_BASED_EDGES_ENABLE_AT_QUALITY_PRESET                 (1)
#define SSAO_REDUCE_RADIUS_NEAR_SCREEN_BORDER_ENABLE_AT_QUALITY_PRESET  (99)

// --- resources (bgfx_compute.sh macro expansions, SPIRV branch) ---
public Texture2D    s_viewspaceDepthSource               : register(t0);
public SamplerState s_viewspaceDepthSourceSampler        : register(s0);
public Texture2D    s_viewspaceDepthSourceMirror         : register(t1);
public SamplerState s_viewspaceDepthSourceMirrorSampler  : register(s1);

[[vk::image_format("rgba8")]]
public Texture2D<float4> s_normalmapSource : register(t2);

public StructuredBuffer<uint> s_loadCounter : register(t3);

public Texture2D    s_importanceMap        : register(t4);
public SamplerState s_importanceMapSampler : register(s4);

[[vk::image_format("rg8")]]
public Texture2DArray<float2> s_baseSSAO : register(t5);

[[vk::image_format("rg8")]]
public RWTexture2DArray<float2> s_target : register(u6);

// packing/unpacking for edges; 2 bits per edge mean 4 gradient values (0, 0.33, 0.66, 1) for smoother transitions!
public float PackEdges( vec4 edgesLRTB )
{
    // optimized, should be same as above
    edgesLRTB = round( saturate( edgesLRTB ) * 3.05 );
    return dot( edgesLRTB, vec4( 64.0 / 255.0, 16.0 / 255.0, 4.0 / 255.0, 1.0 / 255.0 ) ) ;
}

public vec3 NDCToViewspace( vec2 pos, float viewspaceDepth )
{
    vec3 ret;

    ret.xy = (u_ndcToViewMul * pos.xy + u_ndcToViewAdd) * viewspaceDepth;

    ret.z = viewspaceDepth;

    return ret;
}

// calculate effect radius and fit our screen sampling pattern inside it
public void CalculateRadiusParameters( const float pixCenterLength, const vec2 pixelDirRBViewspaceSizeAtCenterZ, out float pixLookupRadiusMod, out float effectRadius, out float falloffCalcMulSq )
{
    effectRadius = u_effectRadius;

    // when too close, on-screen sampling disk will grow beyond screen size; limit this to avoid closeup temporal artifacts
    const float tooCloseLimitMod = saturate( pixCenterLength * u_effectSamplingRadiusNearLimitRec ) * 0.8 + 0.2;

    effectRadius *= tooCloseLimitMod;

    // 0.85 is to reduce the radius to allow for more samples on a slope to still stay within influence
    pixLookupRadiusMod = (0.85 * effectRadius) / pixelDirRBViewspaceSizeAtCenterZ.x;

    // used to calculate falloff (both for AO samples and per-sample weights)
    falloffCalcMulSq= -1.0f / (effectRadius*effectRadius);
}

public vec4 CalculateEdges( const float centerZ, const float leftZ, const float rightZ, const float topZ, const float bottomZ )
{
    // slope-sensitive depth-based edge detection
    vec4 edgesLRTB = vec4( leftZ, rightZ, topZ, bottomZ ) - centerZ;
    vec4 edgesLRTBSlopeAdjusted = edgesLRTB + edgesLRTB.yxwz;
    edgesLRTB = min( abs( edgesLRTB ), abs( edgesLRTBSlopeAdjusted ) );
    return saturate( ( 1.3 - edgesLRTB / (centerZ * 0.040) ) );
}

public vec3 DecodeNormal( vec3 encodedNormal )
{
    vec3 normal = encodedNormal * u_normalsUnpackMul.xxx + u_normalsUnpackAdd.xxx;

#if SSAO_ENABLE_NORMAL_WORLD_TO_VIEW_CONVERSION
	normal = vec3( dot(normal, u_normalsWorldToViewspaceMatrix0.xyz),
					dot(normal, u_normalsWorldToViewspaceMatrix1.xyz),
					dot(normal, u_normalsWorldToViewspaceMatrix2.xyz));
#endif

    return normal;
}

public vec3 LoadNormal( ivec2 pos )
{
    vec3 encodedNormal = imageLoad(s_normalmapSource, pos).xyz;
    return DecodeNormal( encodedNormal );
}

public vec3 LoadNormal( ivec2 pos, ivec2 offset )
{
    vec3 encodedNormal = imageLoad(s_normalmapSource, pos + offset ).xyz;
    return DecodeNormal( encodedNormal );
}

// all vectors in viewspace
public float CalculatePixelObscurance( vec3 pixelNormal, vec3 hitDelta, float falloffCalcMulSq )
{
  float lengthSq = dot( hitDelta, hitDelta );
  float NdotD = dot(pixelNormal, hitDelta) / sqrt(lengthSq);

  float falloffMult = max( 0.0, lengthSq * falloffCalcMulSq + 1.0 );

  return max( 0, NdotD - u_effectHorizonAngleThreshold ) * falloffMult;
}

public void SSAOTapInner( const int qualityLevel, inout float obscuranceSum, inout float weightSum, const vec2 samplingUV, const float mipLevel, const vec3 pixCenterPos, const vec3 negViewspaceDir, vec3 pixelNormal, const float falloffCalcMulSq, const float weightMod, const int dbgTapIndex)
{
    // get depth at sample
    float viewspaceSampleZ = texture2DLod(s_viewspaceDepthSource, s_viewspaceDepthSourceSampler, samplingUV.xy, mipLevel ).x;

    // convert to viewspace
    vec3 hitPos = NDCToViewspace( samplingUV.xy, viewspaceSampleZ ).xyz;
    vec3 hitDelta = hitPos - pixCenterPos;

    float obscurance = CalculatePixelObscurance( pixelNormal, hitDelta, falloffCalcMulSq );
    float weight = 1.0;

    if( qualityLevel >= SSAO_HALOING_REDUCTION_ENABLE_AT_QUALITY_PRESET )
    {
        float reduct = max( 0, -hitDelta.z ); // cheaper, less correct version
        reduct = saturate( reduct * u_negRecEffectRadius + 2.0 );
        weight = SSAO_HALOING_REDUCTION_AMOUNT * reduct + (1.0 - SSAO_HALOING_REDUCTION_AMOUNT);
    }
    weight *= weightMod;
    obscuranceSum += obscurance * weight;
    weightSum += weight;
}

public void SSAOTap( const int qualityLevel, inout float obscuranceSum, inout float weightSum, const int tapIndex, const mat2 rotScale, const vec3 pixCenterPos, const vec3 negViewspaceDir, vec3 pixelNormal, const vec2 normalizedScreenPos, const float mipOffset, const float falloffCalcMulSq, float weightMod, vec2 normXY, float normXYLength)
{
    vec2  sampleOffset;
    float   samplePow2Len;

    // patterns
    {
        vec4 newSample = g_samplePatternMain[tapIndex];
        sampleOffset    = mul( rotScale, newSample.xy );
        samplePow2Len   = newSample.w;                      // precalculated, same as: samplePow2Len = log2( length( newSample.xy ) );
        weightMod *= newSample.z;
    }

    // snap to pixel center (more correct obscurance math, avoids artifacts)
    sampleOffset                    = round(sampleOffset);

    // calculate MIP based on the sample distance from the centre
    float mipLevel = ( qualityLevel < SSAO_DEPTH_MIPS_ENABLE_AT_QUALITY_PRESET )?(0):(samplePow2Len + mipOffset);

    vec2 samplingUV = sampleOffset * u_viewport2xPixelSize + normalizedScreenPos;

    SSAOTapInner( qualityLevel, obscuranceSum, weightSum, samplingUV, mipLevel, pixCenterPos, negViewspaceDir, pixelNormal, falloffCalcMulSq, weightMod, tapIndex * 2);

    // for the second tap, just use the mirrored offset
    vec2 sampleOffsetMirroredUV    = -sampleOffset;

    // tilt the second set of samples so that the disk is effectively rotated by the normal
    if( qualityLevel >= SSAO_TILT_SAMPLES_ENABLE_AT_QUALITY_PRESET )
    {
        float dotNorm = dot( sampleOffsetMirroredUV, normXY );
        sampleOffsetMirroredUV -= dotNorm * normXYLength * normXY;
        sampleOffsetMirroredUV = round(sampleOffsetMirroredUV);
    }

    // snap to pixel center (more correct obscurance math, avoids artifacts)
    vec2 samplingMirroredUV = sampleOffsetMirroredUV * u_viewport2xPixelSize + normalizedScreenPos;

    SSAOTapInner( qualityLevel, obscuranceSum, weightSum, samplingMirroredUV, mipLevel, pixCenterPos, negViewspaceDir, pixelNormal, falloffCalcMulSq, weightMod, tapIndex * 2 + 1);
}

// this function is designed to only work with half/half depth at the moment
public void GenerateSSAOShadowsInternal<let qualityLevel : int, let adaptiveBase : bool>( out float outShadowTerm, out vec4 outEdges, out float outWeight,
	const vec2 SVPos)
{
    vec2 SVPosRounded = trunc( SVPos );
    uvec2 SVPosui = uvec2( SVPosRounded ); //same as uvec2( SVPos )

    const uint numberOfTaps = (adaptiveBase)?(SSAO_ADAPTIVE_TAP_BASE_COUNT) : ( g_numTaps[qualityLevel] );
    float pixZ, pixLZ, pixTZ, pixRZ, pixBZ;

    vec4 valuesUL     = s_viewspaceDepthSourceMirror.GatherRed(s_viewspaceDepthSourceMirrorSampler, SVPosRounded * u_halfViewportPixelSize);
    vec4 valuesBR     = s_viewspaceDepthSourceMirror.GatherRed(s_viewspaceDepthSourceMirrorSampler, SVPosRounded * u_halfViewportPixelSize, ivec2( 1, 1 ));

    // get this pixel's viewspace depth
    pixZ = valuesUL.y;

    // get left right top bottom neighbouring pixels for edge detection (gets compiled out on qualityLevel == 0)
    pixLZ   = valuesUL.x;
    pixTZ   = valuesUL.z;
    pixRZ   = valuesBR.z;
    pixBZ   = valuesBR.x;

    vec2 normalizedScreenPos = SVPosRounded * u_viewport2xPixelSize + u_viewport2xPixelSize_x_025;
    vec3 pixCenterPos = NDCToViewspace( normalizedScreenPos, pixZ ); // g

    // Load this pixel's viewspace normal
    uvec2 fullResCoord = uvec2(SVPosui * 2 + u_perPassFullResCoordOffset.xy);
    vec3 pixelNormal = LoadNormal( ivec2(fullResCoord) );

    const vec2 pixelDirRBViewspaceSizeAtCenterZ = pixCenterPos.z * u_ndcToViewMul * u_viewport2xPixelSize;

    float pixLookupRadiusMod;
    float falloffCalcMulSq;

    // calculate effect radius and fit our screen sampling pattern inside it
    float effectViewspaceRadius;
    CalculateRadiusParameters( length( pixCenterPos ), pixelDirRBViewspaceSizeAtCenterZ, pixLookupRadiusMod, effectViewspaceRadius, falloffCalcMulSq );

    // calculate samples rotation/scaling
    mat2 rotScale;
    {
        // reduce effect radius near the screen edges slightly
        if( !adaptiveBase && (qualityLevel >= SSAO_REDUCE_RADIUS_NEAR_SCREEN_BORDER_ENABLE_AT_QUALITY_PRESET) )
        {
            float nearScreenBorder = min( min( normalizedScreenPos.x, 1.0 - normalizedScreenPos.x ), min( normalizedScreenPos.y, 1.0 - normalizedScreenPos.y ) );
            nearScreenBorder = saturate( 10.0 * nearScreenBorder + 0.6 );
            pixLookupRadiusMod *= nearScreenBorder;
        }

        // load & update pseudo-random rotation matrix
        uint pseudoRandomIndex = uint( SVPosRounded.y * 2 + SVPosRounded.x ) % 5;
        vec4 rs = u_patternRotScaleMatrices( pseudoRandomIndex );
        rotScale = mtxFromCols( vec2( rs.x * pixLookupRadiusMod, rs.y * pixLookupRadiusMod ), vec2( rs.z * pixLookupRadiusMod, rs.w * pixLookupRadiusMod ) );
    }

    // the main obscurance & sample weight storage
    float obscuranceSum = 0.0;
    float weightSum = 0.0;

    // edge mask for between this and left/right/top/bottom neighbour pixels
    vec4 edgesLRTB = vec4( 1.0, 1.0, 1.0, 1.0 );

    // Move center pixel slightly towards camera to avoid imprecision artifacts
    pixCenterPos *= u_depthPrecisionOffsetMod;

    if( !adaptiveBase && (qualityLevel >= SSAO_DEPTH_BASED_EDGES_ENABLE_AT_QUALITY_PRESET) )
    {
        edgesLRTB = CalculateEdges( pixZ, pixLZ, pixRZ, pixTZ, pixBZ );
    }

    // adds a more high definition sharp effect, which gets blurred out
    if( !adaptiveBase && (qualityLevel >= SSAO_DETAIL_AO_ENABLE_AT_QUALITY_PRESET) )
    {
        // disable in case of quality level 4 (reference)
        if( qualityLevel != 4 )
        {
            vec3 viewspaceDirZNormalized = vec3( pixCenterPos.xy / pixCenterPos.zz, 1.0 );
            vec3 pixLDelta  = vec3( -pixelDirRBViewspaceSizeAtCenterZ.x, 0.0, 0.0 ) + viewspaceDirZNormalized * (pixLZ - pixCenterPos.z);
            vec3 pixRDelta  = vec3( +pixelDirRBViewspaceSizeAtCenterZ.x, 0.0, 0.0 ) + viewspaceDirZNormalized * (pixRZ - pixCenterPos.z);
            vec3 pixTDelta  = vec3( 0.0, -pixelDirRBViewspaceSizeAtCenterZ.y, 0.0 ) + viewspaceDirZNormalized * (pixTZ - pixCenterPos.z);
            vec3 pixBDelta  = vec3( 0.0, +pixelDirRBViewspaceSizeAtCenterZ.y, 0.0 ) + viewspaceDirZNormalized * (pixBZ - pixCenterPos.z);

            const float rangeReductionConst         = 4.0f;
            const float modifiedFalloffCalcMulSq    = rangeReductionConst * falloffCalcMulSq;

            vec4 additionalObscurance;
            additionalObscurance.x = CalculatePixelObscurance( pixelNormal, pixLDelta, modifiedFalloffCalcMulSq );
            additionalObscurance.y = CalculatePixelObscurance( pixelNormal, pixRDelta, modifiedFalloffCalcMulSq );
            additionalObscurance.z = CalculatePixelObscurance( pixelNormal, pixTDelta, modifiedFalloffCalcMulSq );
            additionalObscurance.w = CalculatePixelObscurance( pixelNormal, pixBDelta, modifiedFalloffCalcMulSq );

            obscuranceSum += u_detailAOStrength * dot( additionalObscurance, edgesLRTB );
        }
    }

    // Sharp normals also create edges - but this adds to the cost as well
    if( !adaptiveBase && (qualityLevel >= SSAO_NORMAL_BASED_EDGES_ENABLE_AT_QUALITY_PRESET ) )
    {
        vec3 neighbourNormalL  = LoadNormal( ivec2(fullResCoord), ivec2( -2,  0 ) );
        vec3 neighbourNormalR  = LoadNormal( ivec2(fullResCoord), ivec2(  2,  0 ) );
        vec3 neighbourNormalT  = LoadNormal( ivec2(fullResCoord), ivec2(  0, -2 ) );
        vec3 neighbourNormalB  = LoadNormal( ivec2(fullResCoord), ivec2(  0,  2 ) );

        const float dotThreshold = SSAO_NORMAL_BASED_EDGES_DOT_THRESHOLD;

        vec4 normalEdgesLRTB;
        normalEdgesLRTB.x = saturate( (dot( pixelNormal, neighbourNormalL ) + dotThreshold ) );
        normalEdgesLRTB.y = saturate( (dot( pixelNormal, neighbourNormalR ) + dotThreshold ) );
        normalEdgesLRTB.z = saturate( (dot( pixelNormal, neighbourNormalT ) + dotThreshold ) );
        normalEdgesLRTB.w = saturate( (dot( pixelNormal, neighbourNormalB ) + dotThreshold ) );

        edgesLRTB *= normalEdgesLRTB;
    }

    const float globalMipOffset     = SSAO_DEPTH_MIPS_GLOBAL_OFFSET;
    float mipOffset = ( qualityLevel < SSAO_DEPTH_MIPS_ENABLE_AT_QUALITY_PRESET ) ? ( 0 ) : ( log2( pixLookupRadiusMod ) + globalMipOffset );

    // Used to tilt the second set of samples so that the disk is effectively rotated by the normal
    vec2 normXY = vec2( pixelNormal.x, pixelNormal.y );
    float normXYLength = length( normXY );
    normXY /= vec2( normXYLength, -normXYLength );
    normXYLength *= SSAO_TILT_SAMPLES_AMOUNT;

    const vec3 negViewspaceDir = -normalize( pixCenterPos );

    // standard, non-adaptive approach
    if( (qualityLevel != 3) || adaptiveBase )
    {
        for( uint i = 0; i < numberOfTaps; i++ )
        {
            SSAOTap( qualityLevel, obscuranceSum, weightSum, int(i), rotScale, pixCenterPos, negViewspaceDir, pixelNormal, normalizedScreenPos, mipOffset, falloffCalcMulSq, 1.0, normXY, normXYLength);
        }
    }
    else // if( qualityLevel == 3 ) adaptive approach
    {
        // add new ones if needed
        vec2 fullResUV = normalizedScreenPos + u_perPassFullResUVOffset.xy;
		float importance = texture2DLod(s_importanceMap, s_importanceMapSampler, fullResUV, 0.0 ).x;

        // this is to normalize SSAO_DETAIL_AO_AMOUNT across all pixel regardless of importance
        obscuranceSum *= (SSAO_ADAPTIVE_TAP_BASE_COUNT / float(SSAO_MAX_TAPS)) + (importance * SSAO_ADAPTIVE_TAP_FLEXIBLE_COUNT / float(SSAO_MAX_TAPS));

        // load existing base values
        vec2 baseValues = imageLoad(s_baseSSAO, ivec3( SVPosui, int(u_passIndex) ) ).xy;
        weightSum += baseValues.y * (float(SSAO_ADAPTIVE_TAP_BASE_COUNT) * 4.0);
        obscuranceSum += (baseValues.x) * weightSum;

        // increase importance around edges
        float edgeCount = dot( 1.0-edgesLRTB, vec4( 1.0, 1.0, 1.0, 1.0 ) );

        float avgTotalImportance = float(s_loadCounter[0]) * u_loadCounterAvgDiv;

        float importanceLimiter = saturate( u_adaptiveSampleCountLimit / avgTotalImportance );
        importance *= importanceLimiter;

        float additionalSampleCountFlt = SSAO_ADAPTIVE_TAP_FLEXIBLE_COUNT * importance;

        const float blendRange = 3.0;
        const float blendRangeInv = 1.0 / blendRange;

        additionalSampleCountFlt += 0.5;
        uint additionalSamples   = uint( additionalSampleCountFlt );
        uint additionalSamplesTo = min( SSAO_MAX_TAPS, additionalSamples + SSAO_ADAPTIVE_TAP_BASE_COUNT );

        for( uint i = SSAO_ADAPTIVE_TAP_BASE_COUNT; i < additionalSamplesTo; i++ )
        {
            additionalSampleCountFlt -= 1.0f;
            float weightMod = saturate(additionalSampleCountFlt * blendRangeInv); // slowly blend in the last few samples
            SSAOTap( qualityLevel, obscuranceSum, weightSum, int(i), rotScale, pixCenterPos, negViewspaceDir, pixelNormal, normalizedScreenPos, mipOffset, falloffCalcMulSq, weightMod, normXY, normXYLength);
        }
    }

    // early out for adaptive base - just output weight (used for the next pass)
    if( adaptiveBase )
    {
        float obscurance = obscuranceSum / weightSum;

        outShadowTerm   = obscurance;
        outEdges        = vec4(0,0,0,0);
        outWeight       = weightSum;
        return;
    }

    // calculate weighted average
    float obscurance = obscuranceSum / weightSum;

    // calculate fadeout (1 close, gradient, 0 far)
    float fadeOut = saturate( pixCenterPos.z * u_effectFadeOutMul + u_effectFadeOutAdd );

    // Reduce the SSAO shadowing if we're on the edge to remove artifacts on edges
    if( !adaptiveBase && (qualityLevel >= SSAO_DEPTH_BASED_EDGES_ENABLE_AT_QUALITY_PRESET) )
    {
        // when there's more than 2 opposite edges, start fading out the occlusion to reduce aliasing artifacts
        float edgeFadeoutFactor = saturate( (1.0 - edgesLRTB.x - edgesLRTB.y) * 0.35) + saturate( (1.0 - edgesLRTB.z - edgesLRTB.w) * 0.35 );

        fadeOut *= saturate( 1.0 - edgeFadeoutFactor );
    }

    // strength
    obscurance = u_effectShadowStrength * obscurance;

    // clamp
    obscurance = min( obscurance, u_effectShadowClamp );

    // fadeout
    obscurance *= fadeOut;

    // conceptually switch to occlusion with the meaning being visibility
    float occlusion = 1.0 - obscurance;

    // modify the gradient
    occlusion = pow( saturate( occlusion ), u_effectShadowPow );

    // outputs!
    outShadowTerm   = occlusion;    // Our final 'occlusion' term (0 means fully occluded, 1 means fully lit)
    outEdges        = edgesLRTB;    // These are used to prevent blurring across edges
    outWeight       = weightSum;
}

// Shared entry body: qualityLevel / adaptiveBase are passed as compile-time constants from
// each cs_assao_generate_q{N}.slang so specialization reproduces the stock's macro-driven
// dead-code elimination (and thus resource set) per stage.
public void generateSSAO<let qualityLevel : int, let adaptiveBase : bool>(uvec2 dtid)
{
	uvec2 dtID = dtid + uvec2(u_rect.xy);
	if (all(vec2(dtID.xy) < u_rect.zw) )
	{
		float   outShadowTerm;
		float   outWeight;
		vec4  outEdges;
		GenerateSSAOShadowsInternal<qualityLevel, adaptiveBase>( outShadowTerm, outEdges, outWeight, vec2(dtID.xy));
		vec2 out0;
		out0.x = outShadowTerm;

		if ( adaptiveBase )
		{
			out0.y = outWeight / (float(SSAO_ADAPTIVE_TAP_BASE_COUNT) * 4.0);
		}
		else
		{
			if (qualityLevel == 0)
				out0.y = PackEdges( vec4( 1, 1, 1, 1 ) ); // no edges in low quality
			else
				out0.y = PackEdges( outEdges );
		}
		imageStore(s_target, ivec3(int2(dtID.xy), int(u_layer)), out0);
	}
}
