// 1-to-1 Slang port of examples/28-wireframe fs_wf_wireframe.sc.
// u_params is the custom array from uniforms.sh (declared vec4[3]); this FS reads
// u_wfColor/u_wfOpacity (u_params[1]) and u_wfThickness (u_params[2]), so the active
// extent is the full 3 -- no tail padding needed.
// gl_FrontFacing -> SV_IsFrontFace input; dFdx/dFdy come from bgfx_shader_glsl_compat.
import bgfx_shader;
import bgfx_shader_glsl_compat;

float4 u_params[3];
// u_wfColor      = u_params[1].xyz
// u_wfOpacity    = u_params[1].w
// u_wfThickness  = u_params[2].y

struct V2F
{
	vec3 v_view : TEXCOORD0;
	vec3 v_bc   : TEXCOORD1;
};

[shader("fragment")]
vec4 fragmentMain(V2F input, bool gl_FrontFacing : SV_IsFrontFace) : SV_Target
{
	vec3  color   = u_params[1].xyz;
	float opacity = u_params[1].w;
	float thickness = u_params[2].y;

	if (gl_FrontFacing) { opacity *= 0.5; }

	vec3 fw = abs(dFdx(input.v_bc)) + abs(dFdy(input.v_bc));
	vec3 val = smoothstep(vec3_splat(0.0), fw*thickness, input.v_bc);
	float edge = min(min(val.x, val.y), val.z); // Gets to 0.0 around the edges.

	vec4 rgba = vec4(color, (1.0-edge)*opacity);
	return rgba;
}
