using Test

# This is a problem of the code right now. It can only set once per as 
# this variable is used in macros to generate the code at compile time.
# This implies we cannot both test gpu and cpu code here.
target = "cpu"
@testset "Powerflow" begin
    include("test_pf.jl")
    # test convergence is OK
    @test conv
    # test norm is minimized
    @test res < 1e-7
end

# Not working yet. Will check whether Ipopt and reduced method match in objective
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