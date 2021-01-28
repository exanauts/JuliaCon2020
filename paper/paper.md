---
title: 'ExaPF.jl: A Power Flow Solver for GPUs'
tags:
  - Julia
authors:
  - name: Michel Schanen
    orcid: 0000-0002-4164-027X
    affiliation: 1
  - name: Adrian Maldonado
    affiliation: 1
  - name: François Pacaud
    affiliation: 1
  - name: Mihai Anitescu
    affiliation: 1
affiliations:
 - name: Argonne National Laboratory
   index: 1
date: 30 September 2020
bibliography: paper.bib

---

# Summary

Solving optimal power flow is an important tool in the secure and cost
effective operation of the transmission power grids. `ExaPF.jl` aims to
implement a reduced space method for solving the optimal power flow problem (OPF)
fully on GPUs. Reduced space methods enforce the constraints, represented here by
the power flow's (PF) system of nonlinear equations, separately at each
iteration of the optimization in the reduced space. This paper describes the
API of `ExaPF.jl` for solving the power flow's nonlinear equations entirely on the GPU.
This includes the computation of the derivatives using automatic
differentiation, an iterative linear solver with a preconditioner, and a
Newton-Raphson implementation. All of these steps allow us to run the main
computational loop entirely on the GPU with no transfer from host to device.

This implementation will serve as the basis for the future OPF implementation
in the reduced space.

# Statement of Need

The current state-of-the-art for solving optimal power flow is the
interior-point method (IPM) in optimization implemented by the solver Ipopt
[@wachter2004implementation] and is the algorithm of reference
in implementations like MATPOWER [@matpower]. However, its reliance on
unstructured sparse indefinite inertia revealing direct linear solvers makes
this algorithm hard to port to GPUs. `ExaPF.jl` aims at applying a reduced
gradient method to tackle this problem, which allows us to leverage iterative
linear solvers for solving the linear systems arising in the PF.

Our final goal is a reduced method optimization solver that provides a
flexible API for models and formulations outside of the domain of OPF.

