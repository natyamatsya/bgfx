// 1-to-1 Slang port of examples/14-shadowvolumes fs_shadowvolume_svsidetex.sc.
// stencilColor is defined inline in the .sc body, so it stays inline here.
// gl_FrontFacing -> SV_IsFrontFace input.
import bgfx_shader;

vec4 u_svparams;
// u_dfail = u_svparams.y

vec4 stencilColor(float _k)
{
	return vec4(float(abs(_k - 1.0) < 0.0001)/255.0
			  , float(abs(_k + 1.0) < 0.0001)/255.0
			  , float(abs(_k - 2.0) < 0.0001)/255.0
			  , float(abs(_k + 2.0) < 0.0001)/255.0
			  );
}

struct V2F
{
	float4 pos : SV_Position;
	float  v_k : FOG;
};

[shader("fragment")]
vec4 fragmentMain(V2F input, bool gl_FrontFacing : SV_IsFrontFace) : SV_Target
{
	float k = input.v_k;

	if (!gl_FrontFacing)
		k = -k;

	if (u_svparams.y == 0.0)
		k = -k;

	return stencilColor(k);
}
