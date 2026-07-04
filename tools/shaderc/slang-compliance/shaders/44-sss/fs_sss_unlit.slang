// 1-to-1 Slang port of examples/44-sss fs_sss_unlit.sc.
// MRT G-buffer: gl_FragData[0]/[1] -> a struct of SV_Target0/SV_Target1.
// parameters.sh is included but no u_params macro is referenced, so u_params is
// dead-stripped and not declared.
import bgfx_shader;
import normal_encoding; // NormalEncode

struct V2F
{
	vec4 pos         : SV_Position;
	vec3 v_normal    : NORMAL;
	vec2 v_texcoord0 : TEXCOORD0;
	vec4 v_texcoord1 : TEXCOORD1;
};

struct GBuffer
{
	vec4 gbuffer0 : SV_Target0;
	vec4 gbuffer1 : SV_Target1;
};

[shader("fragment")]
GBuffer fragmentMain(V2F input)
{
	vec3 albedo = vec3_splat(1.0);

	// get vertex normal
	vec3 normal = normalize(input.v_normal);
	float roughness = 1.0;

	vec3 bufferNormal = NormalEncode(normal);

	GBuffer output;
	// write data to alpha channel of color buffer to signify different handling
	// while lighting/shading these pixels in the gbuffer combine pass
	output.gbuffer0 = vec4(toGamma(albedo), 0.0);
	output.gbuffer1 = vec4(bufferNormal, roughness);
	return output;
}
