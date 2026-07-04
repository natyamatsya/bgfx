// 1-to-1 Slang port of examples/14-shadowvolumes fs_shadowvolume_svsideblank.sc.
import bgfx_shader;

struct V2F
{
	float4 pos : SV_Position;
	float  v_k : FOG;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	return vec4(1.0, 1.0, 1.0, 1.0);
}
