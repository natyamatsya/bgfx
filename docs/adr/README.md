# Architecture Decision Records

This directory holds Architecture Decision Records (ADRs) — short documents capturing a significant
architectural decision, its context, and its consequences. Format follows
[Michael Nygard's template](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions).

ADRs are immutable once **Accepted**: to change a decision, add a new ADR that supersedes the old one
(mark the old one `Superseded by ADR-NNNN`).

## Index

| ADR | Title | Status |
|-----|-------|--------|
| [0001](0001-slang-reflection-source.md) | Reflection source for Slang integration: dlsym'd Slang C reflection API | Accepted |
| [0002](0002-slang-shader-library-composition.md) | Slang shader library composition: uniforms per-shader, library provides samplers + helpers | Accepted (predefined-uniform part amended by 0003) |
| [0003](0003-slang-auto-provide-predefined-uniforms.md) | Slang: auto-provide bgfx predefined uniforms | Accepted |
