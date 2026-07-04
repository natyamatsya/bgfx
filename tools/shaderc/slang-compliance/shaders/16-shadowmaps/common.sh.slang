// Slang port of examples/16-shadowmaps/common.sh -- the shared lighting, attenuation and
// shadow-filtering helpers (#included by every 16-shadowmaps shader). Ported once as a
// co-located library; `import common;`.
//
// The stock helpers take a `sampler2D`; in Slang a sampled texture is a (Texture2D,
// SamplerState) pair, so every sampler-taking helper takes both. The math is a verbatim
// translation of common.sh.
import bgfx_shader;              // vec2/3/4, vec2_splat, texture2D, texture2DLod
import shaderlib;               // unpackRgbaToFloat, unpackHalfFloat, packHalfFloat, packFloatToRgba
import bgfx_shader_glsl_compat; // mix, greaterThan, lessThan

static const int BLOCKER_SEARCH_NUM_SAMPLES = 16;
static const int PCF_LOD_OFFSET_NUM_SAMPLES  = 16;

public vec2 sampleVogelDisk(int index, int sampleCount)
{
    const float goldenAngle = 2.39996323; // radians
    float i = float(index);
    float r = sqrt((i + 0.5) / float(sampleCount));
    float a = i * goldenAngle;
    return vec2(cos(a), sin(a)) * r;
}

public vec2 samplePoisson(int index)
{
	return sampleVogelDisk(index, 10);
}

public float linstep(float _edge0, float _edge1, float _x)
{
	return clamp((_x-_edge0)/(_edge1-_edge0), 0.0, 1.0);
}

public float attenuation(float _dist, vec3 _attn)
{
	return 1.0 / ( _attn.x                  //const
				 + _attn.y * _dist          //linear
				 + _attn.z * _dist * _dist  //quadrantic
				 );
}

public float spot(float _ldotsd, float _inner, float _outer)
{
	float inner = cos(radians(_inner));
	float outer = cos(radians(min(_outer, _inner - 0.001)));
	float spot = clamp((_ldotsd - inner) / (outer - inner), 0.0, 1.0);
	return spot;
}

public vec2 lit(vec3 _ld, vec3 _n, vec3 _vd, float _exp)
{
	//diff
	float ndotl = dot(_n, _ld);

	//spec
	vec3 r = 2.0*ndotl*_n - _ld; // reflect(_ld, _n);
	float rdotv = dot(r, _vd);
	float spec = step(0.0, ndotl) * pow(max(0.0, rdotv), _exp) * (2.0 + _exp)/8.0;

	return max(vec2(ndotl, spec), 0.0);
}

public struct Light
{
	public vec3 l;
	public vec3 ld;
	public float attn;
};

public Light evalLight(vec3 _v, vec4 _l, vec3 _spotDirection, float _spotInner, float _spotOuter, vec3 _attnParams)
{
	Light light;

	//directional
	light.l    = _l.xyz;
	light.ld   = -normalize(light.l);
	light.attn = 1.0;

	if (0.0 != _l.w) //point or spot
	{
		light.l  = _l.xyz - _v;
		light.ld = normalize(light.l);

		float ldotsd = max(0.0, dot(-light.ld, normalize(_spotDirection)));
		float falloff = spot(ldotsd, _spotOuter, _spotInner);
		light.attn = attenuation(length(light.l), _attnParams) * mix(falloff, 1.0, step(90, _spotOuter));
	}

	return light;
}

public float texcoordInRange(vec2 _texcoord)
{
	bool inRange = all(greaterThan(_texcoord, vec2_splat(0.0)))
				&& all(lessThan   (_texcoord, vec2_splat(1.0)))
				 ;

	return float(inRange);
}

// Rotate a 2D sample by a precomputed sin/cos pair.
// _sincos = vec2(sin(angle), cos(angle))
public vec2 rotateSample(vec2 _sample, vec2 _sincos)
{
    return vec2(_sample.x * _sincos.y - _sample.y * _sincos.x,
                _sample.x * _sincos.x + _sample.y * _sincos.y);
}

// Interleaved gradient noise for per-pixel Poisson disk rotation.
public float interleavedGradientNoise(vec2 _screenPos)
{
    vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
    return frac(magic.z * frac(dot(_screenPos, magic.xy)));
}

public float hardShadowLod(Texture2D _sampler, SamplerState _samp, float lod, vec4 _shadowCoord, float _bias)
{
    vec2 texCoord = _shadowCoord.xy/_shadowCoord.w;

    bool outside = any(greaterThan(texCoord, vec2_splat(1.0)))
                || any(lessThan   (texCoord, vec2_splat(0.0)))
                 ;

    if (outside)
    {
        return 1.0;
    }

    float receiver = (_shadowCoord.z-_bias)/_shadowCoord.w;
    float occluder = unpackRgbaToFloat(texture2DLod(_sampler, _samp, texCoord, lod) );

    float visibility = step(receiver, occluder);
    return visibility;
}

public float hardShadow(Texture2D _sampler, SamplerState _samp, vec4 _shadowCoord, float _bias)
{
    return hardShadowLod(_sampler, _samp, 0.0, _shadowCoord, _bias);
}


// _diskRotation = vec2(sin(angle), cos(angle)) for per-pixel Poisson disk rotation.
// Pass vec2(0.0, 1.0) for no rotation (identity).
public float PCFLodOffset(Texture2D _sampler, SamplerState _samp, float lod, vec2 offset, vec4 _shadowCoord, float _bias, vec2 _texelSize, vec2 _diskRotation)
{
    float result = 0.0;

    for ( int i = 0; i < PCF_LOD_OFFSET_NUM_SAMPLES; ++i )
    {
        vec2 jitteredOffset = rotateSample(samplePoisson(i), _diskRotation) * offset;
        result += hardShadowLod(_sampler, _samp, lod, _shadowCoord + vec4(jitteredOffset, 0.0, 0.0), _bias);
    }
    return result / float(PCF_LOD_OFFSET_NUM_SAMPLES);
}

public float PCFLod(Texture2D _sampler, SamplerState _samp, float lod, vec2 filterRadius, vec4 _shadowCoord, float _bias, vec4 _pcfParams, vec2 _texelSize, vec2 _diskRotation)
{
    vec2 offset = filterRadius * _pcfParams.zw * _texelSize * _shadowCoord.w;

    return PCFLodOffset(_sampler, _samp, lod, offset, _shadowCoord, _bias, _texelSize, _diskRotation);
}

public float PCF(Texture2D _sampler, SamplerState _samp, vec4 _shadowCoord, float _bias, vec4 _pcfParams, vec2 _texelSize, vec2 fragCoord)
{
    // Per-pixel Poisson disk rotation from shadow map texel coordinates
    vec2 noiseCoord = fragCoord;
    float angle = interleavedGradientNoise(noiseCoord) * 6.283185;
    vec2 diskRotation = vec2(sin(angle), cos(angle));
    return PCFLod(_sampler, _samp, 0.0, vec2(2.0, 2.0), _shadowCoord, _bias, _pcfParams, _texelSize, diskRotation);
}

public float VSM(Texture2D _sampler, SamplerState _samp, vec4 _shadowCoord, float _bias, float _depthMultiplier, float _minVariance)
{
	vec2 texCoord = _shadowCoord.xy/_shadowCoord.w;

	bool outside = any(greaterThan(texCoord, vec2_splat(1.0)))
				|| any(lessThan   (texCoord, vec2_splat(0.0)))
				 ;

	if (outside)
	{
		return 1.0;
	}

	float receiver = (_shadowCoord.z-_bias)/_shadowCoord.w * _depthMultiplier;
	vec4 rgba = texture2D(_sampler, _samp, texCoord);
	vec2 occluder = vec2(unpackHalfFloat(rgba.rg), unpackHalfFloat(rgba.ba)) * _depthMultiplier;

	if (receiver < occluder.x)
	{
		return 1.0;
	}

	float variance = max(occluder.y - (occluder.x*occluder.x), _minVariance);
	float d = receiver - occluder.x;

	float visibility = variance / (variance + d*d);

	return visibility;
}

public float ESM(Texture2D _sampler, SamplerState _samp, vec4 _shadowCoord, float _bias, float _depthMultiplier)
{
	vec2 texCoord = _shadowCoord.xy/_shadowCoord.w;

	bool outside = any(greaterThan(texCoord, vec2_splat(1.0)))
				|| any(lessThan   (texCoord, vec2_splat(0.0)))
				 ;

	if (outside)
	{
		return 1.0;
	}

	float receiver = (_shadowCoord.z-_bias)/_shadowCoord.w;
	float occluder = unpackRgbaToFloat(texture2D(_sampler, _samp, texCoord) );

	float visibility = clamp(exp(_depthMultiplier * (occluder-receiver) ), 0.0, 1.0);

	return visibility;
}

static const float _BLUR9_NORMALIZE = (1.0+2.0*(0.9+0.55+0.18+0.1));
static const float BLUR9_WEIGHT_0 = 1.0 /_BLUR9_NORMALIZE;
static const float BLUR9_WEIGHT_1 = 0.9 /_BLUR9_NORMALIZE;
static const float BLUR9_WEIGHT_2 = 0.55/_BLUR9_NORMALIZE;
static const float BLUR9_WEIGHT_3 = 0.18/_BLUR9_NORMALIZE;
static const float BLUR9_WEIGHT_4 = 0.1 /_BLUR9_NORMALIZE;

public vec4 blur9(Texture2D _sampler, SamplerState _samp, vec2 _uv0, vec4 _uv1, vec4 _uv2, vec4 _uv3, vec4 _uv4)
{
	float blur;
	blur  = unpackRgbaToFloat(texture2D(_sampler, _samp, _uv0)    * BLUR9_WEIGHT_0);
	blur += unpackRgbaToFloat(texture2D(_sampler, _samp, _uv1.xy) * BLUR9_WEIGHT_1);
	blur += unpackRgbaToFloat(texture2D(_sampler, _samp, _uv1.zw) * BLUR9_WEIGHT_1);
	blur += unpackRgbaToFloat(texture2D(_sampler, _samp, _uv2.xy) * BLUR9_WEIGHT_2);
	blur += unpackRgbaToFloat(texture2D(_sampler, _samp, _uv2.zw) * BLUR9_WEIGHT_2);
	blur += unpackRgbaToFloat(texture2D(_sampler, _samp, _uv3.xy) * BLUR9_WEIGHT_3);
	blur += unpackRgbaToFloat(texture2D(_sampler, _samp, _uv3.zw) * BLUR9_WEIGHT_3);
	blur += unpackRgbaToFloat(texture2D(_sampler, _samp, _uv4.xy) * BLUR9_WEIGHT_4);
	blur += unpackRgbaToFloat(texture2D(_sampler, _samp, _uv4.zw) * BLUR9_WEIGHT_4);
	return packFloatToRgba(blur);
}

public vec4 blur9VSM(Texture2D _sampler, SamplerState _samp, vec2 _uv0, vec4 _uv1, vec4 _uv2, vec4 _uv3, vec4 _uv4)
{
	vec2 blur;
	vec4 val;
	val = texture2D(_sampler, _samp, _uv0) * BLUR9_WEIGHT_0;
	blur = vec2(unpackHalfFloat(val.rg), unpackHalfFloat(val.ba));
	val = texture2D(_sampler, _samp, _uv1.xy) * BLUR9_WEIGHT_1;
	blur += vec2(unpackHalfFloat(val.rg), unpackHalfFloat(val.ba));
	val = texture2D(_sampler, _samp, _uv1.zw) * BLUR9_WEIGHT_1;
	blur += vec2(unpackHalfFloat(val.rg), unpackHalfFloat(val.ba));
	val = texture2D(_sampler, _samp, _uv2.xy) * BLUR9_WEIGHT_2;
	blur += vec2(unpackHalfFloat(val.rg), unpackHalfFloat(val.ba));
	val = texture2D(_sampler, _samp, _uv2.zw) * BLUR9_WEIGHT_2;
	blur += vec2(unpackHalfFloat(val.rg), unpackHalfFloat(val.ba));
	val = texture2D(_sampler, _samp, _uv3.xy) * BLUR9_WEIGHT_3;
	blur += vec2(unpackHalfFloat(val.rg), unpackHalfFloat(val.ba));
	val = texture2D(_sampler, _samp, _uv3.zw) * BLUR9_WEIGHT_3;
	blur += vec2(unpackHalfFloat(val.rg), unpackHalfFloat(val.ba));
	val = texture2D(_sampler, _samp, _uv4.xy) * BLUR9_WEIGHT_4;
	blur += vec2(unpackHalfFloat(val.rg), unpackHalfFloat(val.ba));
	val = texture2D(_sampler, _samp, _uv4.zw) * BLUR9_WEIGHT_4;
	blur += vec2(unpackHalfFloat(val.rg), unpackHalfFloat(val.ba));

	return vec4(packHalfFloat(blur.x), packHalfFloat(blur.y));
}


// Returns vec3(avgBlockerDepth, closestBlockerDepth, blockerRatio)
public vec3 findBlocker(Texture2D _sampler, SamplerState _samp, vec4 _shadowCoord, vec2 _searchSize, float _bias, vec2 _diskRotation)
{
    int blockerCount = 0;
    float avgBlockerDepth = 0.0;
    float closestBlockerDepth = 0.0;
    vec2 texCoord = _shadowCoord.xy / _shadowCoord.w;
    float receiverDepth = (_shadowCoord.z / _shadowCoord.w) - _bias;

    // Search around the shadow coordinate to find blockers
    for( int i = 0; i < BLOCKER_SEARCH_NUM_SAMPLES; ++i )
    {
        vec2 offset = rotateSample(samplePoisson(i), _diskRotation) * _searchSize;
        float shadowMapDepth = unpackRgbaToFloat(texture2D(_sampler, _samp, texCoord + offset));
        if (shadowMapDepth < receiverDepth)
        {
            avgBlockerDepth += shadowMapDepth;
            closestBlockerDepth = max(closestBlockerDepth, shadowMapDepth);
            blockerCount++;
        }
    }

    // Calculate average blocker depth
    if (blockerCount > 0)
    {
        avgBlockerDepth /= float(blockerCount);
    }
    else
    {
        avgBlockerDepth = -1.0; // No blockers found
    }

    float blockerRatio = float(blockerCount) / float(BLOCKER_SEARCH_NUM_SAMPLES);
    return vec3(avgBlockerDepth, closestBlockerDepth, blockerRatio);
}



public float PCSS(Texture2D _sampler, SamplerState _samp, vec4 _shadowCoord, float _bias, vec4 _pcssParams, vec2 _texelSize, vec2 fragCoord)
{
    // Blocker search radius in UV space (~10 texels on 1024 map).
    float searchRadiusUV = 0.01;

    // Penumbra scale.
    float penumbraScaleX = _pcssParams.z;
    float penumbraScaleY = _pcssParams.w;

    // Maximum filter radius in UV space (~50 texels on 1024 map).
    float maxFilterRadius = 0.25;

    // Per-pixel Poisson disk rotation (Interleaved Gradient Noise)
    vec2 noiseCoord = fragCoord;
    float noise = interleavedGradientNoise(noiseCoord);
    float rotationAngle = noise * 6.283185;
    vec2 diskRotation = vec2(sin(rotationAngle), cos(rotationAngle));

    // Receiver depth in normalized shadow map space
    float receiverDepth = (_shadowCoord.z / _shadowCoord.w) - _bias;

    // Step 1: Blocker Search
    vec3 blockerResult = findBlocker(_sampler, _samp, _shadowCoord, vec2(searchRadiusUV, searchRadiusUV), _bias, diskRotation);
    float avgBlockerDepth = blockerResult.x;
    float blockerRatio = blockerResult.z;

    if (avgBlockerDepth < -0.99)
    {
        return 1.0;
    }

    // Step 2: Penumbra Estimation (standard PCSS, Fernando 2005)
    float penumbraWidth = penumbraScaleX * max(0.0, receiverDepth - avgBlockerDepth) / avgBlockerDepth;
    float penumbraHeight = penumbraScaleY * max(0.0, receiverDepth - avgBlockerDepth) / avgBlockerDepth;
    float filterRadiusU = clamp(penumbraWidth, 0.0, maxFilterRadius);
    float filterRadiusV = clamp(penumbraHeight, 0.0, maxFilterRadius);

    // Step 3: Percentage-Closer Filtering
    float visibility = PCFLodOffset(_sampler, _samp, 0.0, vec2(filterRadiusU, filterRadiusV), _shadowCoord, _bias, _texelSize, diskRotation);

    // Step 4: Edge fade based on blocker ratio
    float edgeFade = smoothstep(0.0, 0.25, blockerRatio);
    visibility = mix(1.0, visibility, edgeFade);

    return visibility;
}
