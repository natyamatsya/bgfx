// 1-to-1 Slang port of examples/18-ibl fs_ibl_skybox.sc.
// toLinear/toFilmic/fixCubeLookup and textureCube/textureCubeLod come from the central
// libraries (import bgfx_shader / shaderlib).
// u_params is the custom array from examples/18-ibl/uniforms.sh:
//   u_exposure = u_params[4].z, u_bgType = u_params[4].w.
// Only [4] is read, so the active count is 5; the reserved tail (elements [5..11],
// 7*vec4) is reproduced by an unused padding member so the UBO size stays 12*vec4.
import bgfx_shader;
import shaderlib;

TextureCube  s_texCube           : register(t0);
SamplerState s_texCubeSampler    : register(s0);
TextureCube  s_texCubeIrr        : register(t1);
SamplerState s_texCubeIrrSampler : register(s1);

float4 u_params[5];
struct ParamsTailPad { vec4 _unused[7]; };
ParamsTailPad _paramsTailPad;

struct V2F
{
	vec3 v_dir : TEXCOORD1;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec3 dir = normalize(input.v_dir);

	vec4 color;
	if (u_params[4].w == 7.0) // u_bgType
	{
		color = toLinear(textureCube(s_texCubeIrr, s_texCubeIrrSampler, dir));
	}
	else
	{
		float lod = u_params[4].w; // u_bgType
		dir = fixCubeLookup(dir, lod, 256.0);
		color = toLinear(textureCubeLod(s_texCube, s_texCubeSampler, dir, lod));
	}
	color *= exp2(u_params[4].z); // u_exposure

	return toFilmic(color);
}
