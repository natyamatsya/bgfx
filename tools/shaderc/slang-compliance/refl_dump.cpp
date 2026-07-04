// refl_dump — a debug tool that prints the Slang reflection structure of a shader
// as shaderc_slang.cpp sees it (same target, matrix layout, and bind shifts). Use it
// to understand how uniforms/textures/samplers are laid out when the compliance
// runner reports an envelope mismatch.
//
// Build (needs the vendored headers + libslang and its companion dylibs):
//   clang++ -std=c++17 -I ../../3rdparty/slang/include refl_dump.cpp -o refl_dump \
//     -L ../../tools/bin/darwin -lslang -Wl,-rpath,../../tools/bin/darwin
// Run (companions must be resolvable, e.g. from a Slang release lib/ dir):
//   DYLD_LIBRARY_PATH=/path/to/slang/lib ./refl_dump <shader.slang> <entryPoint> <vertex|fragment|compute>
#include <slang.h>
#include <slang-com-ptr.h>
#include <cstdio>
#include <fstream>
#include <sstream>
using namespace slang;

static const char* kindName(TypeReflection::Kind k) {
    switch (k) {
        case TypeReflection::Kind::Struct:         return "Struct";
        case TypeReflection::Kind::ConstantBuffer: return "ConstantBuffer";
        case TypeReflection::Kind::Resource:       return "Resource";
        case TypeReflection::Kind::SamplerState:   return "SamplerState";
        case TypeReflection::Kind::Scalar:         return "Scalar";
        case TypeReflection::Kind::Vector:         return "Vector";
        case TypeReflection::Kind::Matrix:         return "Matrix";
        case TypeReflection::Kind::Array:          return "Array";
        case TypeReflection::Kind::ParameterBlock: return "ParameterBlock";
        default:                                   return "?";
    }
}

static void dumpVar(const char* tag, VariableLayoutReflection* vl, int depth) {
    if (!vl) { printf("%*s%s: <null>\n", depth*2, "", tag); return; }
    TypeLayoutReflection* tl = vl->getTypeLayout();
    TypeReflection::Kind k = tl->getKind();
    const char* name = vl->getName();
    unsigned set     = (unsigned)vl->getBindingSpace(SLANG_PARAMETER_CATEGORY_DESCRIPTOR_TABLE_SLOT);
    unsigned binding = (unsigned)vl->getOffset(SLANG_PARAMETER_CATEGORY_DESCRIPTOR_TABLE_SLOT);
    unsigned uoff    = (unsigned)vl->getOffset(SLANG_PARAMETER_CATEGORY_UNIFORM);
    const char* typeName = tl->getType() ? tl->getType()->getName() : NULL;
    const char* sem = vl->getSemanticName();
    printf("%*s%s name=%-18s kind=%-14s type=%-20s sem=%s:%u set=%u binding=%u uniformOffset=%u\n",
        depth*2, "", tag, name?name:"(null)", kindName(k), typeName?typeName:"",
        sem?sem:"", (unsigned)vl->getSemanticIndex(), set, binding, uoff);
    if (k == TypeReflection::Kind::Resource) {
        TypeReflection* t = tl->getType();
        printf("%*s    resourceShape=0x%x resultType=%s\n", depth*2, "",
            (unsigned)t->getResourceShape(),
            t->getResourceResultType() ? kindName(t->getResourceResultType()->getKind()) : "?");
    }
    if (k == TypeReflection::Kind::Struct || k == TypeReflection::Kind::ConstantBuffer || k == TypeReflection::Kind::ParameterBlock) {
        TypeLayoutReflection* st = (k == TypeReflection::Kind::Struct) ? tl : tl->getElementTypeLayout();
        if (st && st->getKind() == TypeReflection::Kind::Struct) {
            unsigned fc = st->getFieldCount();
            for (unsigned i = 0; i < fc; ++i) dumpVar("field", st->getFieldByIndex(i), depth+1);
        }
    }
}

int main(int argc, char** argv) {
    if (argc < 4) { fprintf(stderr, "usage: refl_dump <shader.slang> <entryPoint> <vertex|fragment|compute>\n"); return 2; }
    std::ifstream f(argv[1]); std::stringstream ss; ss << f.rdbuf(); std::string src = ss.str();
    const char* stage = argv[3];
    const int32_t uboBinding = (stage[0] == 'f') ? 1 : 0; // fragment UBO at binding 1, else 0

    Slang::ComPtr<IGlobalSession> g; createGlobalSession(g.writeRef());
    TargetDesc t = {}; t.format = SLANG_SPIRV; t.profile = g->findProfile("spirv_1_5");
    // Same bind shifts as shaderc_slang.cpp (Kind: UAV=0, Sampler=1, SRV=2, CBV=3).
    CompilerOptionEntry sh[4] = {};
    sh[0].name=CompilerOptionName::VulkanBindShiftAll; sh[0].value.intValue0=3; sh[0].value.intValue1=uboBinding; // b
    sh[1].name=CompilerOptionName::VulkanBindShiftAll; sh[1].value.intValue0=2; sh[1].value.intValue1=2;          // t
    sh[2].name=CompilerOptionName::VulkanBindShiftAll; sh[2].value.intValue0=1; sh[2].value.intValue1=18;         // s
    sh[3].name=CompilerOptionName::VulkanBindShiftAll; sh[3].value.intValue0=0; sh[3].value.intValue1=2;          // u
    SessionDesc sd = {}; sd.targets=&t; sd.targetCount=1;
    sd.defaultMatrixLayoutMode=SLANG_MATRIX_LAYOUT_COLUMN_MAJOR;
    sd.compilerOptionEntries=sh; sd.compilerOptionEntryCount=4;
    Slang::ComPtr<ISession> s; g->createSession(sd, s.writeRef());

    Slang::ComPtr<IBlob> d;
    IModule* m = s->loadModuleFromSourceString("sh", argv[1], src.c_str(), d.writeRef());
    if (d && d->getBufferSize()) fprintf(stderr, "%.*s\n", (int)d->getBufferSize(), (const char*)d->getBufferPointer());
    if (!m) return 1;
    Slang::ComPtr<IEntryPoint> ep;
    if (SLANG_FAILED(m->findEntryPointByName(argv[2], ep.writeRef())) || !ep) { fprintf(stderr, "entry point '%s' not found\n", argv[2]); return 1; }
    IComponentType* comps[] = { m, ep.get() };
    Slang::ComPtr<IComponentType> comp, lk;
    s->createCompositeComponentType(comps, 2, comp.writeRef(), d.writeRef());
    comp->link(lk.writeRef(), d.writeRef());
    ProgramLayout* pl = lk->getLayout(0, d.writeRef());
    if (!pl) { fprintf(stderr, "no layout\n"); return 1; }
    // Usage gating (glslang live-uniform parity): is the global cbuffer live?
    Slang::ComPtr<IMetadata> meta;
    lk->getEntryPointMetadata(0, 0, meta.writeRef(), d.writeRef());
    if (meta) {
        VariableLayoutReflection* gv = pl->getGlobalParamsVarLayout();
        unsigned b = (unsigned)gv->getOffset(SLANG_PARAMETER_CATEGORY_DESCRIPTOR_TABLE_SLOT);
        bool used = false;
        meta->isParameterLocationUsed(SLANG_PARAMETER_CATEGORY_DESCRIPTOR_TABLE_SLOT, 0, b, used);
        // Note: isParameterLocationUsed is unreliable once -fvk-*-shift is applied
        // (it reports 0 for live cbuffers); shaderc_slang.cpp gates on the SPIR-V
        // instead. Shown here only as a reflection data point.
        printf("=== metadata: global DESCRIPTOR_TABLE_SLOT binding=%u used=%d (unreliable under shifts) ===\n", b, used);
    }
    printf("=== getGlobalParamsVarLayout ===\n");
    dumpVar("global", pl->getGlobalParamsVarLayout(), 0);
    printf("=== getParameterCount = %u ===\n", pl->getParameterCount());
    for (unsigned i = 0; i < pl->getParameterCount(); ++i) dumpVar("param", pl->getParameterByIndex(i), 1);
    return 0;
}
