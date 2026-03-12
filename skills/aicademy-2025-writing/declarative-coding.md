# Intro
The paradigm behind my approach to coding is Declarative coding. See "thinking like a distribution" (ublue/bluebuild).
This has really shaped how i view building software. 

You start with a recipe/map/specification, then rely on cloud services/workflows to implement the recipe in a containerized environment.

I have the same philosophy as bluebuild versus Nix: no need to "control the universe". The spec is in english. Treat codebases as scaffold, not the cathedral. 
Parametric design > 1 equation, all shapes

We stand in the middleground (same as how bluebuild is between nixos full declarative; and stable LTS releases). Reduce amount of variability and frequency of change.
With LLMs we move away from full-declarative because we may not have the same outcomes (probabilistic/stochastic). For example: Why reinvent shadcn components every time? See how Vercel handles it.
