# Verify solutions against matpower results
using Test
using ExaPF

import ExaPF: ParseMAT, PowerSystem, IdxSet

@testset "Power flow 9 bus case" begin
    datafile = "test/case9.m"
    pf = PowerSystem.PowerNetwork(datafile, 1)
    x = ExaPF.PowerSystem.get_x(pf)
    u = ExaPF.PowerSystem.get_u(pf)
    p = ExaPF.PowerSystem.get_p(pf)

    ExaPF.solve(pf, x, u, p)

    # test impedance matrix entries
    @test isapprox(real(pf.Ybus[1, 1]), 0.0)
    @test isapprox(imag(pf.Ybus[1, 1]), -17.3611111)

    #c = ExaPF.cost(pf, x, u, p)
end
