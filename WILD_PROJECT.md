# Wild Project

A **Wild Project** is a research or engineering project developed with deliberately minimal exposure to modern solution methods during its formative stage.

The project may freely use ancient, classical, or textbook-level foundations such as Newton's method, Gaussian elimination, Fourier analysis, Chebyshev approximation, classical finite differences, elementary continuum mechanics, and similarly fundamental techniques.

Modern state-of-the-art methods, recent papers, contemporary solver architectures, specialized frameworks, and implementation patterns are intentionally excluded or kept to a minimum while the project's core structure is being invented.

The purpose is not to reject modern research. The purpose is to prevent premature methodological anchoring from flattening an independent technical path before it has had a chance to develop.

## Principles

1. **Classical foundations are unrestricted.**  
   Fundamental mathematics, physics, numerical methods, and textbook algorithms may be used freely as raw building blocks.

2. **Modern methodological influence is minimized during invention.**  
   Recent architectures and state-of-the-art solutions should not be used as templates for the core design.

3. **Modern methods return after the core is formed.**  
   Once the project's independent structure has stabilized, contemporary research may be introduced for prior-art checking, adversarial comparison, validation, benchmarking, and selective improvement.

A Wild Project is therefore not an anti-literature project. It is an **independent-invention-first project**.

## Typical workflow

```text
Classical foundations
        |
        v
independent structural invention
        |
        v
implementation
        |
        v
empirical failure and revision
        |
        v
stabilization of the core idea
        |
        v
modern prior-art search
        |
        v
adversarial comparison
        |
        v
retain, generalize, or reject external techniques
without flattening the original technical peak
```

## Defining rule

> **Modern methods may challenge a Wild Project after its core is born, but should not design the core before it is born.**

## Scope inside Wheelchair

For Wheelchair, Wild Project discipline means that classical foundations may enter freely, while modern language, compiler, HPC, solver, and runtime architectures should not become default design templates during formation of a new structural idea.

The purpose is to preserve independent structural invention, especially where conventional control-flow, memory, synchronization, or execution assumptions might prematurely collapse Wheelchair back toward an ordinary sequential or von-Neumann-shaped implementation.

After an idea has stabilized, modern work may be introduced as an adversary, prior-art check, or source of selectively generalizable techniques. External methods should be adopted only when they can be integrated without erasing a proven technical peak or reintroducing hidden serial structure.
