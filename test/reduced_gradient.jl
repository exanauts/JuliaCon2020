# Verify reduced gradient
using Test
using ExaPF
using FiniteDiff
using ForwardDiff
using LinearAlgebra

import ExaPF: ParseMAT, PowerSystem, IndexSet

@testset "RGM Optimal Power flow 9 bus case" begin
    datafile = "test/case9.m"
    pf = PowerSystem.PowerNetwork(datafile, 1)
    # retrieve initial state of network
    pbus = real.(pf.sbus)
    qbus = imag.(pf.sbus)
    vmag = abs.(pf.vbus)
    vang = angle.(pf.vbus)
    x = ExaPF.PowerSystem.get_x(pf, vmag, vang, pbus, qbus)
    u = ExaPF.PowerSystem.get_u(pf, vmag, vang, pbus, qbus)
    p = ExaPF.PowerSystem.get_p(pf, vmag, vang, pbus, qbus)

    # solve power flow
    xk, g, Jx, Ju, convergence = ExaPF.solve(pf, x, u, p)
    ∇gₓ = Jx(pf, xk, u, p)
    ∇gᵤ = Ju(pf, xk, u, p)

    c = ExaPF.cost_function(pf, xk, u, p)
    ∇fₓ, ∇fᵤ = ExaPF.cost_gradients(pf, xk, u, p)

    # Test gradients
    # We need uk here for the closure
    uk = copy(u)
    cost_x = x_ -> ExaPF.cost_function(pf, x_, uk, p; V=eltype(x_))
    cost_u = u_ -> ExaPF.cost_function(pf, xk, u_, p; V=eltype(u_))

    dCdx_fd = FiniteDiff.finite_difference_gradient(cost_x, xk)
    dCdx_ad = ForwardDiff.gradient(cost_x, xk)
    dCdu_fd = FiniteDiff.finite_difference_gradient(cost_u, u)
    dCdu_ad = ForwardDiff.gradient(cost_u, u)

    @test isapprox(∇fₓ, dCdx_fd)
    @test isapprox(∇fᵤ, dCdu_fd)
    @test isapprox(∇fₓ, dCdx_ad)
    @test isapprox(∇fᵤ, dCdu_ad)

    # residual function
    ybus_re, ybus_im = ExaPF.Spmat{Vector}(pf.Ybus)
    function g2(pf, x, u, p)
        eval_g = similar(x)
        nbus = length(pbus)
        Vm, Va, pbus, qbus = PowerSystem.retrieve_physics(pf, x, u, p)
        ExaPF.residualFunction_polar!(
            eval_g, Vm, Va,
            ybus_re, ybus_im,
            pbus, qbus, pf.pv, pf.pq, nbus
        )
        return eval_g
    end
    g_x = x_ -> g2(pf, x_, uk, p)
    ∇gₓ_fd = FiniteDiff.finite_difference_jacobian(g_x, xk)
    # This function should return the same matrix as ∇gₓ, but it
    # appears that is not the case
    @test_broken isapprox(∇gₓ_fd, ∇gₓ)

    g_u = u_ -> g2(pf, xk, u_, p)
    ∇gᵤ_fd = FiniteDiff.finite_difference_jacobian(g_u, uk)
    # However, it appears that the Jacobian wrt u is correct
    @test isapprox(∇gᵤ_fd, ∇gᵤ)

    # evaluate cost
    c = ExaPF.cost_function(pf, xk, uk, p)
    ## ADJOINT
    # lamba calculation
    λk  = -(∇gₓ) \ ∇fₓ
    grad_adjoint = ∇fᵤ + ∇gᵤ' * λk
    ## DIRECT
    S = - inv(Array(∇gₓ))' * ∇gᵤ
    grad_direct = ∇fᵤ + S' * ∇fₓ
    @test isapprox(grad_adjoint, grad_direct)

    function reduced_cost(u_)
        # Ensure we remain in the manifold
        x_, g, _, _, convergence = ExaPF.solve(pf, xk, u_, p, tol=1e-14)
        return ExaPF.cost_function(pf, x_, u_, p)
    end

    grad_fd = FiniteDiff.finite_difference_gradient(reduced_cost, uk)
    # At the end, we are unable to compute the reduced gradient
    @test_broken is_approx(grad_fd, grad_adjoint)
end
