
using ExaPF
using FiniteDiff
using ForwardDiff
using LinearAlgebra
using LinearOperators
using LineSearches
using Printf
using KernelAbstractions
using UnicodePlots
using Statistics

reldiff(a, b) = abs(a - b) / max(1, a)

function ls(algo, nlp, uk::Vector{Float64}, obj, grad::Vector{Float64})
    nᵤ = length(grad)
    s = copy(-grad)
    function Lalpha(alpha)
        u_ = uk .+ alpha.*s
        ExaPF.update!(nlp, u_)
        return ExaPF.objective(nlp, u_)
    end
    function grad_Lalpha(alpha)
        g_ = zeros(nᵤ)
        u_ = uk .+ alpha .* s
        ExaPF.update!(nlp, u_)
        ExaPF.gradient!(nlp, g_, u_)
        return dot(g_, s)
    end
    function Lgrad_Lalpha(alpha)
        g_ = zeros(nᵤ)
        u_ = uk .+ alpha .* s
        ExaPF.update!(nlp, u_)
        ExaPF.gradient!(nlp, g_, u_)
        phi = ExaPF.objective(nlp, u_)
        dphi = dot(g_, s)
        return (phi, dphi)
    end
    dL_0 = dot(s, grad)
    alpha, obj = algo(Lalpha, grad_Lalpha, Lgrad_Lalpha, 0.0002, obj, dL_0)
    return alpha
end

# sample along descent line and find minimum.
function sample_ls(nlp, uk, d, alpha_m; sample_max=30)
    alpha = 0.0
    function cost_a(a)
        ud = uk + a*d
        ExaPF.update!(nlp, ud)
        return ExaPF.objective(nlp, ud)
    end

    alpha_vec = collect(range(0.1*alpha_m, stop=alpha_m, length=sample_max))
    f_vec = zeros(sample_max)

    for i=1:sample_max
        a = alpha_vec[i]
        f_vec[i] = cost_a(a)
    end

    (val, ind) = findmin(f_vec)

    return alpha_vec[ind]
end

# reduced gradient method
function dommel_method(datafile; bfgs=false, iter_max=200, itout_max=1,
                       feasible_start=false)

    # Load problem.
    pf = ExaPF.PowerSystem.PowerNetwork(datafile, 1)
    polar = PolarForm(pf, CPU())

    x0 = ExaPF.initial(polar, State())
    p = ExaPF.initial(polar, Parameters())
    if feasible_start
        prob = run_reduced_ipopt(datafile; hessian=false, feasible=true)
        uk = prob.x
    else
        uk = ExaPF.initial(polar, Control())
    end
    u0 = copy(uk)
    wk = copy(uk)
    u_prev = copy(uk)

    buffer = ExaPF.get(polar, ExaPF.PhysicalState())
    constraints = Function[ExaPF.state_constraint, ExaPF.power_constraints]
    nlp = ExaPF.ReducedSpaceEvaluator(polar, x0, uk, p; constraints=constraints,
                                      ε_tol=1e-10)
    # Init a penalty evaluator with initial penalty c₀
    c0 = 10.0
    pen = ExaPF.PenaltyEvaluator(nlp, c₀=c0)
    ωtol = 1 / c0

    # initialize arrays
    grad = similar(uk)
    fill!(grad, 0)
    grad_prev = copy(grad)
    obj_prev = Inf

    cost_history = Float64[]
    grad_history = Float64[]

    ls_algo = BackTracking()
    if bfgs
        H = InverseLBFGSOperator(Float64, length(uk), 50, scaling=true)
        α0 = 1e-5
    else
        H = I
        α0 = 1e-7
    end

    for i_out in 1:itout_max
        iter = 1
        # uk .= u0
        converged = false
        αi = α0
        @printf("%6s %8s %4s %4s\n", "iter", "obj", "∇f", "αₗₛ")
        # Inner iteration: projected gradient algorithm
        n_iter = 0
        for i in 1:iter_max
            n_iter += 1
            # solve power flow and compute gradients
            nlp.x .= x0
            ExaPF.update!(pen, uk)

            # evaluate cost
            c = ExaPF.objective(pen, uk)
            # Evaluate cost of problem without penalties
            c_ref = ExaPF.objective(pen.nlp, uk)
            ExaPF.gradient!(pen, grad, uk)

            # compute control step
            step = sample_ls(pen, uk, -grad, αi; sample_max=10)
            wk .= uk .- step * H * grad
            ExaPF.project_constraints!(pen.nlp, uk, wk)

            # Stopping criteration: uₖ₊₁ - uₖ
            ## Dual infeasibility
            norm_grad = norm(uk .- u_prev, Inf)
            ## Primal infeasibility
            inf_pr = ExaPF.primal_infeasibility(pen.nlp, pen.cons)

            # check convergence
            if (iter%100 == 0)
                @printf("%6d %.6e %.3e %.2e %.2e %.2e\n", iter, c, c - c_ref, norm_grad, inf_pr, step)
            end
            iter += 1
            push!(grad_history, norm_grad)
            push!(cost_history, c)
            if bfgs
                push!(H, step * H * grad, grad .- grad_prev)
            end
            grad_prev .= grad
            u_prev .= uk
            # Check whether we have converged nicely
            if (norm_grad < ωtol
                || (iter >= 4 && reldiff(c, mean(cost_history[end-2:end])) < 1e-5)
               )
                converged = true
                break
            end
        end
        # Update penalty term, according to Nocedal & Wright §17.1 (p.501)
        # Safeguard: update nicely the penalty if previously we failed to converge
        η = converged ? 10.0 : 2.0
        ωtol *= 1 / η
        ωtol = max(ωtol, 1e-5)
        inf_pr = ExaPF.primal_infeasibility(pen.nlp, pen.cons)
        @printf("#Outer %d %-4d %.3e %.3e \n",
                i_out, n_iter, ExaPF.objective(pen.nlp, uk), inf_pr)
        ExaPF.update_penalty!(pen; η=η)
    end
    # uncomment to plot cost evolution
    plt = lineplot(cost_history, title = "Cost history", width=80);
    println(plt)

    ExaPF.sanity_check(nlp, uk, pen.cons)

    return cost_history
end

datafile = joinpath(dirname(@__FILE__), "..", "test", "data", "case57.m")
#
ch = dommel_method(datafile; bfgs=false, itout_max=10, feasible_start=false,
                   iter_max=1000)
