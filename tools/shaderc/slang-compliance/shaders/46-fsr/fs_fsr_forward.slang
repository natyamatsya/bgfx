// 1-to-1 Slang port of examples/46-fsr fs_fsr_forward.sc.
// cotangentFrame is defined inline in the stock body, so it stays inline here.
import bgfx_shader;
import bgfx_shader_glsl_compat; // dFdx / dFdy

Texture2D    s_albedo        : register(t0);
SamplerState s_albedoSampler : register(s0);
Texture2D    s_normal        : register(t1);
SamplerState s_normalSampler : register(s1);

// struct ModelUniforms
vec4 u_modelParams[2];

#define u_color         (u_modelParams[0].xyz)
#define u_lightPosition (u_modelParams[1].xyz)

// http://www.thetenthplanet.de/archives/1180
// "followup: normal mapping without precomputed tangents"
mat3 cotangentFrame(vec3 N, vec3 p, vec2 uv)
{
	// get edge vectors of the pixel triangle
	vec3 dp1 = dFdx(p);
	vec3 dp2 = dFdy(p);
	vec2 duv1 = dFdx(uv);
	vec2 duv2 = dFdy(uv);

	// solve the linear system
	vec3 dp2perp = cross(dp2, N);
	vec3 dp1perp = cross(N, dp1);
	vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
	vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;

	// construct a scale-invariant frame
	float invMax = rsqrt(max(dot(T,T), dot(B,B)));
	return mtxFromCols(T*invMax, B*invMax, N);
}

struct V2F
{
	vec3 v_normal    : NORMAL;
	vec2 v_texcoord0 : TEXCOORD0;
	vec4 v_texcoord1 : TEXCOORD1;
	vec4 v_texcoord2 : TEXCOORD2;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec3 albedo = toLinear(texture2D(s_albedo, s_albedoSampler, input.v_texcoord0).xyz);

	// get vertex normal
	vec3 normal = normalize(input.v_normal);

	// get normal map normal, unpack, and calculate z
	vec3 normalMap;
	normalMap.xy = texture2D(s_normal, s_normalSampler, input.v_texcoord0).xy;
	normalMap.xy = normalMap.xy * 2.0 - 1.0;
	normalMap.z = sqrt(1.0 - dot(normalMap.xy, normalMap.xy));

	// swap x and y, because the brick texture looks flipped, don't copy this...
	normalMap.xy = -normalMap.yx;

	// perturb geometry normal by normal map
	vec3 pos = input.v_texcoord1.xyz; // contains world space pos
	mat3 TBN = cotangentFrame(normal, pos, input.v_texcoord0);
	vec3 bumpedNormal = normalize(mul(TBN, normalMap));

	vec3 light = (u_lightPosition - pos);
	light = normalize(light);

	float NdotL = saturate(dot(bumpedNormal, light));
	float diffuse = NdotL * 1.0;

	vec3 V = input.v_texcoord2.xyz; // contains view vector
	vec3 H = normalize(V+light);
	float NdotH = saturate(dot(bumpedNormal, H));
	float specular = 5.0 * pow(NdotH, 256);
	float ambient = 0.1;

	float lightAmount = ambient + diffuse;
	vec3 color = u_color * albedo * lightAmount + specular;

	// leave color in linear space for better dof filter result

	return vec4(color, 1.0);
}
