// 1-to-1 Slang port of examples/14-shadowvolumes fs_shadowvolume_svbacktex2.sc.
// stencilColor is defined inline in the .sc body, so it stays inline here.
// gl_FrontFacing -> SV_IsFrontFace input.
import bgfx_shader;

vec4 stencilColor(float _k)
{
	return vec4(float(abs(_k - 1.0) < 0.0001)/255.0
			  , float(abs(_k + 1.0) < 0.0001)/255.0
			  , float(abs(_k - 2.0) < 0.0001)/255.0
			  , float(abs(_k + 2.0) < 0.0001)/255.0
			  );
}

[shader("fragment")]
vec4 fragmentMain(bool gl_FrontFacing : SV_IsFrontFace) : SV_Target
{
	float k = 2.0;
	if (!gl_FrontFacing)
	{
		k = -k;
	}

	return stencilColor(k);
}
