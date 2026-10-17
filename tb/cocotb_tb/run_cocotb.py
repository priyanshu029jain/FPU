import os
import sys
from pathlib import Path
from cocotb_tools.runner import get_runner

def run_fpu_cocotb():
    proj_dir = Path(__file__).resolve().parent.parent.parent
    
    verilog_sources = [
        proj_dir / "component" / "param_adder_sub.v",
        proj_dir / "component" / "param_multiplier.v",
        proj_dir / "component" / "barrel_shifter.v",
        proj_dir / "component" / "leading_zero_detector.v",
        proj_dir / "component" / "input_convertor.v",
        proj_dir / "component" / "output_convertor.v",
        proj_dir / "rtl" / "FPU_adder.v",
        proj_dir / "rtl" / "FPU_multiplier.v",
        proj_dir / "rtl" / "FPU_division.v",
        proj_dir / "rtl" / "FPU_mac.v",
        proj_dir / "rtl" / "FPU_top.v",
    ]
    
    # Use Icarus Verilog runner
    runner = get_runner("icarus")
    
    build_dir = proj_dir / "sim_build_cocotb"
    
    print("=" * 80)
    print("  BUILDING COCOTB SIMULATION BINARY WITH ICARUS VERILOG")
    print("=" * 80)
    
    runner.build(
        sources=verilog_sources,
        hdl_toplevel="FPU_top",
        build_dir=build_dir,
        build_args=["-g2012"],
        always=True,
    )
    
    print("\n" + "=" * 80)
    print("  EXECUTING COCOTB REGRESSION SUITE (4,000+ TEST VECTORS)")
    print("=" * 80)
    
    runner.test(
        hdl_toplevel="FPU_top",
        test_module="test_fpu_cocotb",
        test_dir=Path(__file__).resolve().parent,
        build_dir=build_dir,
        waves=False,
    )

if __name__ == "__main__":
    run_fpu_cocotb()
