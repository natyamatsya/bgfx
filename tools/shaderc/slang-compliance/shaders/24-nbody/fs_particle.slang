// 1-to-1 Slang port of examples/24-nbody fs_particle.sc.
// Shades a billboarded particle with a soft radial falloff, tinting by the color factor
// carried in v_texCoord.z. Per-stage port (not combined with vs_particle): this stage has a
// smaller uniform footprint than the VS. mix() comes from bgfx_shader_glsl_compat.
import bgfx_shader;
import bgfx_shader_glsl_compat;

// uniforms.sh: uniform vec4 u_params[3]; this stage reads only u_params[1], so glslang
// reflects (and reserves) the active extent [2] here -- no reserved tail padding.
float4 u_params[2];

// #define u_particleIntensity u_params[1].x
// #define u_particlePower     u_params[1].w

struct V2F
{
	vec3 v_texCoord : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec3 color = mix(vec3(0.1f, 0.8f, 0.2f), 0.5 *  vec3(0.3, 0.25, 0.05), input.v_texCoord.z);
	float f = u_params[1].x * pow(max(1.0 - length(input.v_texCoord.xy), 0.0), u_params[1].w);
	return vec4(color * f, 1.0);
}
