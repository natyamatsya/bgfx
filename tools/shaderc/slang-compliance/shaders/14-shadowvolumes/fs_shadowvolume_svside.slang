// 1-to-1 Slang port of examples/14-shadowvolumes fs_shadowvolume_svside.sc.
// gl_FrontFacing -> SV_IsFrontFace input.
import bgfx_shader;

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
	{
		k = -k;
	}

	return vec4( float(abs(k - 1.0) < 0.0001)/255.0
			, float(abs(k + 1.0) < 0.0001)/255.0
			, float(abs(k - 2.0) < 0.0001)/255.0
			, float(abs(k + 2.0) < 0.0001)/255.0
			);
}
