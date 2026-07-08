// Headless render of the path-traced Cornell Box (ray-query path): 3 BLASes + TLAS with
// instance transforms, N accumulated frames -> PPM; then rotated boxes -> second PPM.
// Usage: cb_gi_run <rq.bin> <out_static.ppm> <out_rotated.ppm> [frames]
#include <bgfx/bgfx.h>
#include <bx/timer.h>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cmath>
#include <vector>
#include <bx/bx.h>

static const bgfx::Memory* loadBin(const char* p){FILE*f=fopen(p,"rb");if(!f){printf("open %s fail\n",p);return 0;}fseek(f,0,2);long n=ftell(f);fseek(f,0,0);const bgfx::Memory*m=bgfx::alloc(uint32_t(n));fread(m->data,1,n,f);fclose(f);return m;}

struct Mat { float a[4], e[4], n[4]; };
struct Mesh { std::vector<float> pos; std::vector<uint16_t> idx; std::vector<Mat> mat; };
static void quad(Mesh&M,const float*a,const float*b,const float*c,const float*d,float nx,float ny,float nz,float r,float g,float bl,float er=0,float eg=0,float eb=0){
	uint16_t base=uint16_t(M.pos.size()/3);const float*v[4]={a,b,c,d};
	for(int i=0;i<4;i++){M.pos.push_back(v[i][0]);M.pos.push_back(v[i][1]);M.pos.push_back(v[i][2]);}
	uint16_t t[6]={base,uint16_t(base+1),uint16_t(base+2),base,uint16_t(base+2),uint16_t(base+3)};
	for(int i=0;i<6;i++)M.idx.push_back(t[i]);
	Mat m={{r,g,bl,0},{er,eg,eb,0},{nx,ny,nz,0}};M.mat.push_back(m);M.mat.push_back(m);
}
static void box(Mesh&M,const float*lo,const float*hi,float r,float g,float bl){
	float x0=lo[0],y0=lo[1],z0=lo[2],x1=hi[0],y1=hi[1],z1=hi[2];
	float A[3]={x0,y0,z0},B[3]={x0,y0,z1},C[3]={x0,y1,z1},D[3]={x0,y1,z0};quad(M,A,B,C,D,-1,0,0,r,g,bl);
	float E[3]={x1,y0,z1},F[3]={x1,y0,z0},G[3]={x1,y1,z0},H[3]={x1,y1,z1};quad(M,E,F,G,H,1,0,0,r,g,bl);
	float I[3]={x0,y0,z0},J[3]={x1,y0,z0},K[3]={x1,y0,z1},L[3]={x0,y0,z1};quad(M,I,J,K,L,0,-1,0,r,g,bl);
	float N[3]={x0,y1,z1},O[3]={x1,y1,z1},P[3]={x1,y1,z0},Q[3]={x0,y1,z0};quad(M,N,O,P,Q,0,1,0,r,g,bl);
	float R[3]={x1,y0,z0},S[3]={x0,y0,z0},T[3]={x0,y1,z0},U[3]={x1,y1,z0};quad(M,R,S,T,U,0,0,-1,r,g,bl);
	float V[3]={x0,y0,z1},W[3]={x1,y0,z1},X[3]={x1,y1,z1},Y[3]={x0,y1,z1};quad(M,V,W,X,Y,0,0,1,r,g,bl);
}
static void buildWalls(Mesh&M){
	float W[3]={.73f,.73f,.73f},R[3]={.65f,.05f,.05f},G[3]={.12f,.45f,.15f};
	{float a[3]={-1,-1,-1},b[3]={1,-1,-1},c[3]={1,-1,1},d[3]={-1,-1,1};quad(M,a,b,c,d,0,1,0,W[0],W[1],W[2]);}
	{float a[3]={-1,1,1},b[3]={1,1,1},c[3]={1,1,-1},d[3]={-1,1,-1};quad(M,a,b,c,d,0,-1,0,W[0],W[1],W[2]);}
	{float a[3]={-1,-1,1},b[3]={1,-1,1},c[3]={1,1,1},d[3]={-1,1,1};quad(M,a,b,c,d,0,0,-1,W[0],W[1],W[2]);}
	{float a[3]={-1,-1,-1},b[3]={-1,-1,1},c[3]={-1,1,1},d[3]={-1,1,-1};quad(M,a,b,c,d,1,0,0,R[0],R[1],R[2]);}
	{float a[3]={1,-1,1},b[3]={1,-1,-1},c[3]={1,1,-1},d[3]={1,1,1};quad(M,a,b,c,d,-1,0,0,G[0],G[1],G[2]);}
	{float a[3]={-.35f,.998f,.35f},b[3]={.35f,.998f,.35f},c[3]={.35f,.998f,-.35f},d[3]={-.35f,.998f,-.35f};quad(M,a,b,c,d,0,-1,0,0,0,0,18,18,18);}
}

static void mtxRotY(float*m,float a){memset(m,0,64);m[0]=cosf(a);m[2]=sinf(a);m[5]=1;m[8]=-sinf(a);m[10]=cosf(a);m[15]=1;}
static void mtxTrans(float*m,float x,float y,float z){memset(m,0,64);m[0]=m[5]=m[10]=m[15]=1;m[12]=x;m[13]=y;m[14]=z;}
static void mtxMul(float*r,const float*a,const float*b){float t[16];for(int i=0;i<4;i++)for(int j=0;j<4;j++){t[i*4+j]=0;for(int k=0;k<4;k++)t[i*4+j]+=a[i*4+k]*b[k*4+j];}memcpy(r,t,64);}

static bgfx::TextureHandle g_accum, g_target, g_rb, g_gbufA, g_gbufN, g_irr0, g_irr1, g_histI[2], g_histN[2], g_histM[2], g_res[2];
static uint32_t g_histIdx=0;
static bgfx::ProgramHandle g_atrous, g_temporal;
static bgfx::UniformHandle g_fparams, g_tp, g_pt;
static float g_prevAng=0; static bool g_resetHist=true;
static int g_spp=1, g_bounces=4;
static bgfx::UniformHandle g_params;
static bgfx::ProgramHandle g_prog;
static bgfx::VertexBufferHandle g_mbh;
static bgfx::AccelerationStructureHandle g_tlas;
static uint32_t g_frameIdx = 0;
static const uint32_t kW=1024,kH=1024;

static void dispatchFrame(float angle, bool reset, int mode)
{
	float params[4] = { float(g_frameIdx), reset?1.0f:0.0f, angle, float(mode) };
	bgfx::setUniform(g_params, params);
	float pt[4] = { float(g_spp), float(g_bounces), 0, 0 };
	bgfx::setUniform(g_pt, pt);
	bgfx::setAccelerationStructure(0, g_tlas);
	bgfx::setImage(1, g_accum, 0, bgfx::Access::ReadWrite, bgfx::TextureFormat::RGBA32F);
	bgfx::setImage(2, g_target, 0, bgfx::Access::Write, bgfx::TextureFormat::RGBA8);
	bgfx::setBuffer(3, g_mbh, bgfx::Access::Read);
	bgfx::setImage(4, g_gbufA, 0, bgfx::Access::Write, bgfx::TextureFormat::RGBA32F);
	bgfx::setImage(5, g_gbufN, 0, bgfx::Access::Write, bgfx::TextureFormat::RGBA32F);
	bgfx::setImage(6, g_irr0, 0, bgfx::Access::Write, bgfx::TextureFormat::RGBA32F);
	bgfx::setImage(7, g_res[g_histIdx], 0, bgfx::Access::Read, bgfx::TextureFormat::RGBA32F);
	bgfx::setImage(8, g_res[g_histIdx^1], 0, bgfx::Access::Write, bgfx::TextureFormat::RGBA32F);
	bgfx::dispatch(0, g_prog, (kW+7)/8, (kH+7)/8, 1);
	if (mode >= 2)
	{
		float tp[4] = { angle - g_prevAng, angle, g_resetHist?1.0f:0.0f, 0 };
		bgfx::setUniform(g_tp, tp);
		uint32_t nh = g_histIdx ^ 1;
		bgfx::setImage(0, g_irr0, 0, bgfx::Access::Read, bgfx::TextureFormat::RGBA32F);
		bgfx::setImage(1, g_histI[g_histIdx], 0, bgfx::Access::Read, bgfx::TextureFormat::RGBA32F);
		bgfx::setImage(2, g_histN[g_histIdx], 0, bgfx::Access::Read, bgfx::TextureFormat::RGBA32F);
		bgfx::setImage(3, g_gbufN, 0, bgfx::Access::Read, bgfx::TextureFormat::RGBA32F);
		bgfx::setImage(4, g_irr1, 0, bgfx::Access::Write, bgfx::TextureFormat::RGBA32F);
		bgfx::setImage(5, g_histI[nh], 0, bgfx::Access::Write, bgfx::TextureFormat::RGBA32F);
		bgfx::setImage(6, g_histN[nh], 0, bgfx::Access::Write, bgfx::TextureFormat::RGBA32F);
		bgfx::setImage(7, g_histM[g_histIdx], 0, bgfx::Access::Read, bgfx::TextureFormat::RGBA32F);
		bgfx::setImage(8, g_histM[nh], 0, bgfx::Access::Write, bgfx::TextureFormat::RGBA32F);
		bgfx::dispatch(1, g_temporal, (kW+7)/8, (kH+7)/8, 1);
		g_histIdx = nh;
		g_resetHist = false;

		bgfx::TextureHandle irr[2] = { g_irr0, g_irr1 };
		for (uint32_t pass = 0; pass < 4; ++pass)
		{
			bool last = pass == 3;
			float fp[4] = { float(1 << pass), last?1.0f:0.0f, 0, 0 };
			bgfx::setUniform(g_fparams, fp);
			bgfx::setImage(0, irr[(pass+1) & 1], 0, bgfx::Access::Read, bgfx::TextureFormat::RGBA32F);
			bgfx::setImage(1, irr[pass & 1], 0, bgfx::Access::Write, bgfx::TextureFormat::RGBA32F);
			bgfx::setImage(2, g_gbufN, 0, bgfx::Access::Read, bgfx::TextureFormat::RGBA32F);
			bgfx::setImage(3, g_gbufA, 0, bgfx::Access::Read, bgfx::TextureFormat::RGBA32F);
			bgfx::setImage(4, g_target, 0, bgfx::Access::Write, bgfx::TextureFormat::RGBA8);
			bgfx::dispatch(bgfx::ViewId(2+pass), g_atrous, (kW+7)/8, (kH+7)/8, 1);
		}
	}
	g_prevAng = angle;
	++g_frameIdx;
}

static void updateXf(bgfx::AccelerationStructureHandle tlas, float angle)
{
	float xf[48], rot[16], trn[16];
	memset(xf,0,sizeof(xf)); xf[0]=xf[5]=xf[10]=xf[15]=1; // identity for walls
	mtxRotY(rot, angle);  mtxTrans(trn,-0.37f,0,0.15f);  mtxMul(&xf[16],rot,trn);
	mtxRotY(rot,-angle);  mtxTrans(trn, 0.35f,0,-0.30f); mtxMul(&xf[32],rot,trn);
	bgfx::updateTlas(tlas, bgfx::copy(xf,sizeof(xf)));
}

static void readbackPPM(const char* path)
{
	bgfx::blit(7, g_rb, 0, 0, g_target);
	std::vector<uint8_t> px(kW*kH*4,0);
	uint32_t fa = bgfx::readTexture(g_rb, px.data());
	uint32_t fr = 0; while (fr < fa) fr = bgfx::frame();
	FILE*o=fopen(path,"wb"); fprintf(o,"P6\n%u %u\n255\n",kW,kH);
	for(uint32_t i=0;i<kW*kH;i++){uint8_t rgb[3]={px[i*4],px[i*4+1],px[i*4+2]};fwrite(rgb,1,3,o);}
	fclose(o); printf("wrote %s\n",path);
}


static double benchLoop(const char* name, void (*submit)(void*), void* ud)
{
	// Warm-up (pipeline creation, first-use residency), then timed steady state.
	for (int i = 0; i < 20; ++i) { submit(ud); bgfx::frame(); }
	const int64_t t0 = bx::getHPCounter();
	const int kFrames = 200;
	for (int i = 0; i < kFrames; ++i) { submit(ud); bgfx::frame(); }
	const double ms = double(bx::getHPCounter() - t0) / double(bx::getHPFrequency()) * 1000.0 / kFrames;
	printf("%-22s %8.3f ms/frame  (%.0f fps equivalent)\n", name, ms, 1000.0/ms);
	return ms;
}

struct Ctx
{
	bgfx::ProgramHandle prog;
	bgfx::TextureHandle target;
};

static void submitUber(void* ud)
{
	Ctx* c = (Ctx*)ud;
	float pr[4] = {0, 1, 0, 0};   bgfx::setUniform(g_params, pr);
	float pt[4] = {1, 4, 0, 0};   bgfx::setUniform(g_pt, pt);
	bgfx::setAccelerationStructure(0, g_tlas);
	bgfx::setImage(1, g_accum, 0, bgfx::Access::ReadWrite, bgfx::TextureFormat::RGBA32F);
	bgfx::setImage(2, c->target, 0, bgfx::Access::Write, bgfx::TextureFormat::RGBA8);
	bgfx::setBuffer(3, g_mbh, bgfx::Access::Read);
	bgfx::setImage(4, g_gbufA, 0, bgfx::Access::Write, bgfx::TextureFormat::RGBA32F);
	bgfx::setImage(5, g_gbufN, 0, bgfx::Access::Write, bgfx::TextureFormat::RGBA32F);
	bgfx::setImage(6, g_irr0, 0, bgfx::Access::Write, bgfx::TextureFormat::RGBA32F);
	bgfx::dispatch(0, c->prog, (kW+7)/8, (kH+7)/8, 1);
}

static void submitDedicated(void* ud)
{
	Ctx* c = (Ctx*)ud;
	float pr[4] = {float(kW), float(kH), 0, 0};   bgfx::setUniform(g_params, pr);
	bgfx::setAccelerationStructure(0, g_tlas);
	bgfx::setImage(1, c->target, 0, bgfx::Access::Write, bgfx::TextureFormat::RGBA8);
	bgfx::setBuffer(3, g_mbh, bgfx::Access::Read);
	bgfx::dispatch(0, c->prog, (kW+7)/8, (kH+7)/8, 1);
}

static void submitRtp(void* ud)
{
	Ctx* c = (Ctx*)ud;
	float pr[4] = {0, 1, 0, 0};   bgfx::setUniform(g_params, pr);
	bgfx::setAccelerationStructure(0, g_tlas);
	bgfx::setImage(1, c->target, 0, bgfx::Access::Write, bgfx::TextureFormat::RGBA8);
	bgfx::setBuffer(3, g_mbh, bgfx::Access::Read);
	bgfx::dispatch(0, c->prog, kW, kH, 1); // rays, not groups
}

int main(int argc, char** argv)
{
	// usage: <cs_rq.bin> <cs_rq1.bin> <rg.bin> <miss.bin> <shadow.bin> <chit.bin>
	if (argc < 7) { printf("usage: %s <uber.bin> <dedicated.bin> <rg> <miss> <shadow> <chit>\n", argv[0]); return 1; }
	bgfx::renderFrame();
	bgfx::Init init; init.type = bgfx::RendererType::Count;
	init.resolution.width = 0; init.resolution.height = 0;
	if (!bgfx::init(init)) return 1;
	if (0 == (bgfx::getCaps()->supported & BGFX_CAPS_RAY_TRACING_PIPELINE)) { printf("SKIP\n"); bgfx::shutdown(); return 0; }
	printf("renderer: %s, %ux%u, 200 frames per mode\n", bgfx::getRendererName(bgfx::getCaps()->rendererType), kW, kH);

	Mesh walls, tall, shrt;
	buildWalls(walls);
	{float lo[3]={-.25f,-1,-.25f},hi[3]={.25f,.3f,.25f}; box(tall,lo,hi,.73f,.73f,.73f);}
	{float lo[3]={-.25f,-1,-.25f},hi[3]={.25f,-.4f,.25f}; box(shrt,lo,hi,.73f,.73f,.73f);}
	bgfx::VertexLayout pl; pl.begin().add(bgfx::Attrib::Position,3,bgfx::AttribType::Float).end();
	bgfx::VertexLayout ml; ml.begin().add(bgfx::Attrib::TexCoord0,4,bgfx::AttribType::Float).add(bgfx::Attrib::TexCoord1,4,bgfx::AttribType::Float).add(bgfx::Attrib::TexCoord2,4,bgfx::AttribType::Float).end();
	Mesh* meshes[3]={&walls,&tall,&shrt};
	bgfx::AccelerationStructureHandle blas[3];
	std::vector<Mat> mats;
	for(int i=0;i<3;i++){
		Mesh&M=*meshes[i];
		bgfx::VertexBufferHandle vbv=bgfx::createVertexBuffer(bgfx::copy(M.pos.data(),uint32_t(M.pos.size()*4)),pl);
		bgfx::IndexBufferHandle ibv=bgfx::createIndexBuffer(bgfx::copy(M.idx.data(),uint32_t(M.idx.size()*2)));
		blas[i]=bgfx::createBlas(&vbv,&ibv,1);
		mats.insert(mats.end(),M.mat.begin(),M.mat.end());
	}
	g_mbh=bgfx::createVertexBuffer(bgfx::copy(mats.data(),uint32_t(mats.size()*sizeof(Mat))),ml,BGFX_BUFFER_COMPUTE_READ);
	g_tlas=bgfx::createTlas(blas,3);
	updateXf(g_tlas, 0.0f);
	bgfx::frame(); bgfx::frame();

	g_params=bgfx::createUniform("u_params",bgfx::UniformType::Vec4);
	g_pt=bgfx::createUniform("u_ptParams",bgfx::UniformType::Vec4);
	g_accum=bgfx::createTexture2D(kW,kH,false,1,bgfx::TextureFormat::RGBA32F,BGFX_TEXTURE_COMPUTE_WRITE);
	g_gbufA=bgfx::createTexture2D(kW,kH,false,1,bgfx::TextureFormat::RGBA32F,BGFX_TEXTURE_COMPUTE_WRITE);
	g_gbufN=bgfx::createTexture2D(kW,kH,false,1,bgfx::TextureFormat::RGBA32F,BGFX_TEXTURE_COMPUTE_WRITE);
	g_irr0=bgfx::createTexture2D(kW,kH,false,1,bgfx::TextureFormat::RGBA32F,BGFX_TEXTURE_COMPUTE_WRITE);
	bgfx::TextureHandle target=bgfx::createTexture2D(kW,kH,false,1,bgfx::TextureFormat::RGBA8,BGFX_TEXTURE_COMPUTE_WRITE);

	Ctx uber; uber.target=target;
	uber.prog=bgfx::createProgram(bgfx::createShader(loadBin(argv[1])),true);
	Ctx dedicated; dedicated.target=target;
	dedicated.prog=bgfx::createProgram(bgfx::createShader(loadBin(argv[2])),true);
	Ctx rtp; rtp.target=target;
	{
		bgfx::ShaderHandle miss[2]={bgfx::createShader(loadBin(argv[4])),bgfx::createShader(loadBin(argv[5]))};
		bgfx::ShaderHandle rg=bgfx::createShader(loadBin(argv[3]));
		bgfx::ShaderHandle ch=bgfx::createShader(loadBin(argv[6]));
		rtp.prog=bgfx::createRtProgram(rg,miss,2,&ch,NULL,NULL,1,NULL,0,true);
	}

	const double a=benchLoop("uber-RQ (stage-1 mode)", submitUber, &uber);
	const double b=benchLoop("dedicated-RQ", submitDedicated, &dedicated);
	const double c=benchLoop("RT pipeline (stage 5)", submitRtp, &rtp);
	printf("\nspecialization win (uber/dedicated): %.2fx\n", a/b);
	printf("dispatch-model delta (dedicated-RQ vs RT pipeline): %.2fx %s\n", (b>c?b/c:c/b), b>c?"in favor of the PIPELINE":"in favor of RAY QUERY");
	bgfx::shutdown();
	return 0;
}
