using LinearAlgebra
using Random
using SparseArrays
using Test
using TimerOutputs
using CUDA

# This is a problem of the code right now. It can only set once per as
# this variable is used in macros to generate the code at compile time.
# This implies we cannot both test gpu and cpu code here.
target = "cpu"
using ExaPF

@testset "Powerflow residuals and Jacobian" begin
    # read data
    datafile = joinpath(dirname(@__FILE__), "case14.raw")
    data = Parse.parse_raw(datafile)
    BUS_B, BUS_AREA, BUS_VM, BUS_VA, BUS_NVHI, BUS_NVLO, BUS_EVHI,
    BUS_EVLO, BUS_TYPE = Parse.idx_bus()
    bus = data["BUS"]
    nbus = size(bus, 1)

    # obtain V0 from raw data
    V = Array{Complex{Float64}}(undef, nbus)
    T = Vector
    for i in 1:nbus
        V[i] = bus[i, BUS_VM]*exp(1im * pi/180 * bus[i, BUS_VA])
    end

    # form Y matrix
    Ybus, Yf_br, Yt_br, Yf_tr, Yt_tr = PowerSystem.makeYbus(data);

    Vm = abs.(V)
    Va = angle.(V)
    bus = data["BUS"]
    gen = data["GENERATOR"]
    load = data["LOAD"]
    nbus = size(bus, 1)
    ngen = size(gen, 1)
    nload = size(load, 1)

    ybus_re, ybus_im = ExaPF.Spmat{T}(Ybus)
    SBASE = data["CASE IDENTIFICATION"][1]
    Sbus = PowerSystem.assembleSbus(gen, load, SBASE, nbus)
    pbus = real(Sbus)
    qbus = imag(Sbus)

    ref, pv, pq = PowerSystem.bustypeindex(bus, gen)
    npv = size(pv, 1);
    npq = size(pq, 1);

    # First compute a reference value for resisual computed at V
    F♯ = ExaPF.residualFunction(V, Ybus, Sbus, pv, pq)

    @testset "Residual polar" begin
        F = zeros(Float64, npv + 2*npq)
        # residual_polar! uses only binary types as this function is meant
        # to be deported on the GPU
        ExaPF.residualFunction_polar!(F, Vm, Va,
            ybus_re.nzval, ybus_re.colptr, ybus_re.rowval,
            ybus_im.nzval, ybus_im.colptr, ybus_im.rowval,
            pbus, qbus, pv, pq, nbus)
        @test F ≈ F♯
    end
end

@testset "Wrapping of iterative solvers" begin
    n, m = 32, 32
    # Add a diagonal term for conditionning
    A = randn(n, m) + 15I
    x♯ = randn(m)
    b = A * x♯
    # Careful: all algorithms work with sparse matrix
    As = sparse(A)
    precond = ExaPF.Precondition.Preconditioner(As, 2)
    to = TimerOutputs.TimerOutput()

    @testset "BICGSTAB" begin
        # Need to update preconditioner before resolution
        ExaPF.Precondition.update(As, precond, to)
        P = precond.P
        x_sol, n_iters = ExaPF.Iterative.bicgstab(As, b, P, zeros(m), to)
        @test n_iters <= m
        @test x_sol ≈ x♯
    end
    @testset "Interface for iterative algorithm ($algo)" for algo in [
        "bicgstab", "bicgstab_ref", "gmres"]
        x_sol = zeros(m)
        n_iters = ExaPF.Iterative.ldiv!(x_sol, As, b, algo, precond, to)
        @test n_iters <= m
        @test x_sol ≈ x♯
    end
end

@testset "Powerflow CPU" begin
    # Include code to run power flow equation
    include(joinpath(dirname(@__FILE__), "..", "examples", "pf.jl"))
    datafile = joinpath(dirname(@__FILE__), "case14.raw")

    # Direct solver
    nblocks = 8
    # Note: Reference BICGSTAB in IterativeSolvers
    @testset "Powerflow solver $precond" for precond in ["default", "gmres", "bicgstab_ref", "bicgstab"]
        sol, has_conv, res = pf(datafile, nblocks, precond)
        @test has_conv
        @test res < 1e-6
    end
end

## TODO: This throws warnings because the cpu version ran before.
if has_cuda_gpu()
    target = "cuda"
    @testset "Powerflow GPU" begin
        # Include code to run power flow equation
        include(joinpath(dirname(@__FILE__), "..", "examples", "pf.jl"))
        datafile = joinpath(dirname(@__FILE__), "case14.raw")
        # BICGSTAB
        sol, conv, res = pf(datafile, 2, "bicgstab")
        @test conv
        @test res < 1e-6
        # DIRECT
        sol, conv, res = pf(datafile)
        @test conv
        @test res < 1e-6
    end
end

# # Not working yet. Will check whether Ipopt and reduced method match in objective
# @testset "rgm_3bus" begin
#    include("../scripts/rgm_3bus.jl")
#    @show red_cost = cfun(xk, uk, p)
#    include("../scripts/ipopt.jl")
#    @show ipopt_cost = cfun(xk, uk, p)
#    gap = abs(red_cost - ipopt_cost)
#    println("gap = abs(red_cost - ipopt_cost): $gap = abs($red_cost - $ipopt_cost)")
#    @test gap ≈ 0.0
# end

# @testset "rgm_3bus_ref" begin
#    include("../scripts/rgm_3bus_ref.jl")
#    @show red_cost = cfun(xk, uk, p)
#    include("../scripts/ipopt_ref.jl")
#    @show ipopt_cost = cfun(xk, uk, p)
#    gap = abs(red_cost - ipopt_cost)
#    println("gap = abs(red_cost - ipopt_cost): $gap = abs($red_cost - $ipopt_cost)")
#    @test gap ≈ 0.0
# end
