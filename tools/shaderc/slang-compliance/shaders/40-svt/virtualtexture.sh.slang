// Slang port of examples/40-svt/virtualtexture.sh -- the shared sparse-virtual-texturing
// resources + sampling helpers included by fs_vt_mip.sc and fs_vt_unlit.sc. `import virtualtexture;`.
//
// Modularity notes:
//   * virtualtexture.sh is a separate #include'd .sh file, so it is ported once here with each
//     helper public. Both fs shaders include it identically, so the u_vt_settings_1/2 loose
//     uniforms and the two samplers are fully-used, fixed-layout resources -- they live here as
//     public declarations (Slang dead-strips whatever an importer never touches).
//   * import does NOT carry preprocessor macros across module boundaries, so the #define aliases
//     are re-declared in the entry shaders that reference them directly (see fs_vt_mip.slang).
import bgfx_shader;
import bgfx_shader_glsl_compat; // dFdx, dFdy

public vec4 u_vt_settings_1;
public vec4 u_vt_settings_2;

#define VirtualTextureSize u_vt_settings_1.x
#define AtlasScale         u_vt_settings_1.y
#define BorderScale        u_vt_settings_1.z
#define BorderOffset       u_vt_settings_1.w

#define MipBias            u_vt_settings_2.x
#define PageTableSize      u_vt_settings_2.y

// SAMPLER2D(s_vt_page_table, 0)
public Texture2D    s_vt_page_table        : register(t0);
public SamplerState s_vt_page_tableSampler : register(s0);
// SAMPLER2D(s_vt_texture_atlas, 1)
public Texture2D    s_vt_texture_atlas        : register(t1);
public SamplerState s_vt_texture_atlasSampler : register(s1);

// This function estimates mipmap levels
public float MipLevel( vec2 uv, float size )
{
   vec2 dx = dFdx( uv * size );
   vec2 dy = dFdy( uv * size );
   float d = max( dot( dx, dx ), dot( dy, dy ) );

   return max( 0.5 * log2( d ), 0 );
}

// This function samples the page table and returns the page's
// position and mip level.
public vec3 SampleTable( vec2 uv, float mip )
{
   vec2 offset = fract( uv * PageTableSize ) / PageTableSize;
   return texture2DLod( s_vt_page_table, s_vt_page_tableSampler, uv - offset, mip ).xyz;
}

// This functions samples from the texture atlas and returns the final color
public vec4 SampleAtlas( vec3 page, vec2 uv )
{
   float mipsize = exp2( floor( page.z * 255.0 + 0.5 ) );

   uv = fract( uv * PageTableSize / mipsize );

   uv *= BorderScale;
   uv += BorderOffset;

   vec2 offset = floor( page.xy * 255.0 + 0.5 );

   return texture2D( s_vt_texture_atlas, s_vt_texture_atlasSampler, ( offset + uv ) * AtlasScale );
}

// Ugly brute force trilinear, look up twice and mix
public vec4 VirtualTextureTrilinear( vec2 uv )
{
   float miplevel = MipLevel( uv, VirtualTextureSize );
   miplevel = clamp( miplevel, 0.0, log2( PageTableSize )-1.0 );

   float mip1     = floor( miplevel );
   float mip2    = mip1 + 1.0;
   float mipfrac  = miplevel - mip1;

   vec3 page1 = SampleTable( uv, mip1 );
   vec3 page2 = SampleTable( uv, mip2 );

   vec4 sample1 = SampleAtlas( page1, uv );
   vec4 sample2 = SampleAtlas( page2, uv );

   return mix( sample1, sample2, mipfrac );
}

// Simple bilinear
public vec4 VirtualTexture( vec2 uv )
{
   float mip = floor( MipLevel( uv, VirtualTextureSize ) );
   mip = clamp( mip, 0, log2( PageTableSize ) );

   vec3 page = SampleTable( uv, mip );
   return SampleAtlas( page, uv );
}
