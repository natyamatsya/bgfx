// 1-to-1 Slang port of examples/15-shadowmaps-simple fs_sms_mesh.sc
// (#define SHADOW_PACKED_DEPTH 0 + #include "fs_sms_shadow.sh"): the lit mesh pass that
// samples the shadow map with a hardware compare sampler2DShadow. The shared lit/PCF/
// hardShadow helpers live in the co-located library fs_sms_shadow.sh.slang.
import bgfx_shader;
import fs_sms_shadow; // lit, PCF (SamplerComparisonState overload)

uniform vec4 u_lightPos;

// SAMPLER2DSHADOW(s_shadowMap, 0)
Texture2D              s_shadowMap        : register(t0);
SamplerComparisonState s_shadowMapSampler : register(s0);

struct V2F
{
	vec3 v_view        : TEXCOORD0;
	vec4 v_shadowcoord : TEXCOORD1;
	vec3 v_normal      : NORMAL;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	float shadowMapBias = 0.005;
	vec3 color = vec3_splat(1.0);

	vec3 v  = input.v_view;
	vec3 vd = -normalize(v);
	vec3 n  = input.v_normal;
	vec3 l  = u_lightPos.xyz;
	vec3 ld = -normalize(l);

	vec2 lc = lit(ld, n, vd, 1.0);

	vec2 texelSize = vec2_splat(1.0/512.0);
	float visibility = PCF(s_shadowMap, s_shadowMapSampler, input.v_shadowcoord, shadowMapBias, texelSize);

	vec3 ambient = 0.1 * color;
	vec3 brdf = (lc.x + lc.y) * color * visibility;

	vec3 final = toGamma(abs(ambient + brdf) );
	return vec4(final, 1.0);
}
