// 1-to-1 Slang port of examples/31-rsm fs_rsm_shadow.sc.
// Writes the reflective shadow map: rgb = light-sphere color (u_tint), a = light-sphere
// radius (-view.z). Single MRT target. gl_FragCoord -> SV_Position input; u_viewTexel
// is auto-provided.
import bgfx_shader;

uniform vec4 u_tint;

struct V2F
{
	vec4 gl_FragCoord : SV_Position;
	vec3 v_normal     : NORMAL;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec2 texCoord = input.gl_FragCoord.xy * u_viewTexel.xy;

	vec4 fragColor;
	fragColor.xyz = u_tint.xyz;         // Color of light sphere
	fragColor.w = -input.v_normal.z;    // Radius of light sphere
	return fragColor;
}
