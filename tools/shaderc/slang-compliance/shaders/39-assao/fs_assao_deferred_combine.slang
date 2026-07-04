// Slang port of examples/39-assao fs_assao_deferred_combine.sc.
// SAMPLER2D s_color/s_normal/s_ao + custom u_combineParams[2]; gl_FragColor -> SV_Target.
import bgfx_shader;

Texture2D    s_color        : register(t0);
SamplerState s_colorSampler : register(s0);
Texture2D    s_normal        : register(t1);
SamplerState s_normalSampler : register(s1);
Texture2D    s_ao        : register(t2);
SamplerState s_aoSampler : register(s2);

uniform float4 u_combineParams[2];

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec2 tc0 = input.v_texcoord0 * u_combineParams[1].xy + u_combineParams[1].zw;
	vec3 albedoColor = vec3(1.0,1.0,1.0);
	if (u_combineParams[0].x > 0.0)
	{
		albedoColor = texture2D(s_color, s_colorSampler, tc0).rgb;
	}

	float light = 1.0;
	if (u_combineParams[0].x > 0.0)
	{
		vec3 n  = texture2D(s_normal, s_normalSampler, tc0).xyz;
		// Expand out normal
		n = n*2.0-1.0;
		vec3 l = normalize(vec3(-0.8,0.75,-1.0));
		light = max(0.0,dot(n,l)) * 1.2+ 0.3;
	}

	float ao = 1.0;
	if ( u_combineParams[0].y > 0.0)
	{
		ao = texture2D(s_ao, s_aoSampler, tc0).x;
	}

	return vec4(albedoColor * light * ao, 1.0f);
}
