// Slang port of examples/37-gpudrivenrendering fs_gdr_instanced_indirect_rendering.sc.
// Looks up the instance's material colour by the flat material id and, for translucent
// materials, renders a 1-in-2 dithered-alpha pattern via gl_FragCoord (SV_Position).
import bgfx_shader;

float4 u_color[32];

struct V2F
{
	float4 fragCoord                   : SV_Position; // gl_FragCoord
	nointerpolation float v_materialID : TEXCOORD0;
};

[shader("fragment")]
float4 fragmentMain(V2F input) : SV_Target
{
	float4 color = u_color[uint(input.v_materialID)];

	if (color.w < 1.0f)
	{
		//render dithered alpha
		if ( (int(input.fragCoord.x) % 2) == (int(input.fragCoord.y) % 2) )
		{
			discard;
		}
	}

	return float4(color.xyz, 1.0);
}
