// 1-to-1 Slang port of examples/28-wireframe fs_wf_mesh.sc.
// u_params is the custom array from examples/28-wireframe/uniforms.sh (declared vec4[3]).
// This FS reads u_wfColor/u_wfOpacity (u_params[1]) and u_drawEdges/u_wfThickness
// (u_params[2]), so the active extent is the full 3 -- no tail padding needed.
// evalSh is defined inline in the .sc body, so it stays inline here.
// dFdx/dFdy come from bgfx_shader_glsl_compat (Slang lacks the GLSL builtins); mix too.
import bgfx_shader;
import bgfx_shader_glsl_compat;

float4 u_params[3];
// u_wfColor      = u_params[1].xyz
// u_wfOpacity    = u_params[1].w
// u_drawEdges    = u_params[2].x
// u_wfThickness  = u_params[2].y

vec3 evalSh(vec3 _dir)
{
#	define k01 0.2820947918 // sqrt( 1/PI)/2
#	define k02 0.4886025119 // sqrt( 3/PI)/2
#	define k03 1.0925484306 // sqrt(15/PI)/2
#	define k04 0.3153915652 // sqrt( 5/PI)/4
#	define k05 0.5462742153 // sqrt(15/PI)/4

	vec3 shEnv[9];
	shEnv[0] = vec3( 0.967757057878229854,  0.976516067990363390,  0.891218272348969998); /* Band 0 */
	shEnv[1] = vec3(-0.384163503608655643, -0.423492289131209787, -0.425532726148547868); /* Band 1 */
	shEnv[2] = vec3( 0.055906294587354334,  0.056627436881069373,  0.069969936396987467);
	shEnv[3] = vec3( 0.120985157386215209,  0.119297994074027414,  0.117111965829213599);
	shEnv[4] = vec3(-0.176711633774331106, -0.170331404095516392, -0.151345020570876621); /* Band 2 */
	shEnv[5] = vec3(-0.124682114349692147, -0.119340785411183953, -0.096300354204368860);
	shEnv[6] = vec3( 0.001852378550138503, -0.032592784164597745, -0.088204495001329680);
	shEnv[7] = vec3( 0.296365482782109446,  0.281268696656263029,  0.243328223888495510);
	shEnv[8] = vec3(-0.079826665303240341, -0.109340956251195970, -0.157208859664677764);

	vec3 nn = _dir.zxy;

	float sh[9];
	sh[0] =  k01;
	sh[1] = -k02*nn.y;
	sh[2] =  k02*nn.z;
	sh[3] = -k02*nn.x;
	sh[4] =  k03*nn.y*nn.x;
	sh[5] = -k03*nn.y*nn.z;
	sh[6] =  k04*(3.0*nn.z*nn.z-1.0);
	sh[7] = -k03*nn.x*nn.z;
	sh[8] =  k05*(nn.x*nn.x-nn.y*nn.y);

	vec3 rgb = vec3_splat(0.0);
	rgb += shEnv[0] * sh[0] * 1.0;
	rgb += shEnv[1] * sh[1] * 2.0/2.5;
	rgb += shEnv[2] * sh[2] * 2.0/2.5;
	rgb += shEnv[3] * sh[3] * 2.0/2.5;
	rgb += shEnv[4] * sh[4] * 1.0/2.5;
	rgb += shEnv[5] * sh[5] * 0.5;
	rgb += shEnv[6] * sh[6] * 0.5;
	rgb += shEnv[7] * sh[7] * 0.5;
	rgb += shEnv[8] * sh[8] * 0.5;

	return rgb;
}

struct V2F
{
	vec3 v_view   : TEXCOORD0;
	vec3 v_bc     : TEXCOORD1;
	vec3 v_normal : NORMAL;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec3 nn = normalize(input.v_normal);
	vec3 col = evalSh(nn);

	if (0.0 != u_params[2].x)
	{
		vec3  wfColor   = u_params[1].xyz;
		float wfOpacity = u_params[1].w;
		float thickness = u_params[2].y;

		vec3 fw = abs(dFdx(input.v_bc)) + abs(dFdy(input.v_bc));
		vec3 val = smoothstep(vec3_splat(0.0), fw*thickness, input.v_bc);
		float edge = min(min(val.x, val.y), val.z); // Gets to 0.0 when close to edges.

		vec3 edgeCol = mix(col, wfColor, wfOpacity);
		col = mix(edgeCol, col, edge);
	}

	vec4 fragColor;
	fragColor.xyz = col;
	fragColor.w = 1.0;
	return fragColor;
}
