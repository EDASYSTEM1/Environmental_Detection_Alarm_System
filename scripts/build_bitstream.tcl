# ============================================================================
#  scripts/build_bitstream.tcl —— 综合 + 实现 + 生成 bit/bin（全自动）
#
#  用法：
#     E:\vivado\2026.1\Vivado\bin\vivado.bat -mode batch -source scripts\build_bitstream.tcl
#  或者双击 scripts\build_bitstream.bat
#
#  前置：先跑过 scripts/create_project.tcl（工程不存在会报错退出）
#
#  产物：
#     bitstream\top.bit   下载到 FPGA（JTAG，掉电丢失）
#     bitstream\top.bin   给 QSPI Flash 用（本机烧不进去，见 README）
#     reports\utilization.rpt / timing_summary.rpt
# ============================================================================

set script_dir [file normalize [file dirname [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]
set proj_file  [file join $root_dir work sys_proj sys_proj.xpr]
set bit_dir    [file join $root_dir bitstream]

if {![file exists $proj_file]} {
    puts "ERROR: 工程不存在：$proj_file"
    puts "       先跑 scripts/create_project.tcl"
    exit 1
}

open_project $proj_file

# ---------------------------------------------------------------------------
# 综合
# ---------------------------------------------------------------------------
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "INFO: synth status = $synth_status"
if {[string first "Complete" $synth_status] < 0} {
    puts "ERROR: 综合失败，看 work/sys_proj/sys_proj.runs/synth_1 下的日志"
    exit 1
}

# ---------------------------------------------------------------------------
# 实现 + bit
# ---------------------------------------------------------------------------
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "INFO: impl status = $impl_status"
if {[string first "Complete" $impl_status] < 0} {
    puts "ERROR: 实现失败，看 work/sys_proj/sys_proj.runs/impl_1 下的日志"
    exit 1
}

# ---------------------------------------------------------------------------
# 时序检查 + 报告
# ---------------------------------------------------------------------------
file mkdir [file join $root_dir reports]
open_run impl_1
set wns "N/A"
set whs "N/A"
catch { set wns [get_property STATS.WNS [get_runs impl_1]] }
catch { set whs [get_property STATS.WHS [get_runs impl_1]] }
puts "INFO: timing WNS = $wns ns, WHS = $whs ns"
report_utilization        -file [file join $root_dir reports utilization.rpt]
report_timing_summary     -file [file join $root_dir reports timing_summary.rpt]
close_design

# ---------------------------------------------------------------------------
# 拷贝 bit + 生成 QSPI 镜像
# ---------------------------------------------------------------------------
file mkdir $bit_dir
set impl_dir [get_property DIRECTORY [get_runs impl_1]]
set src_bit  [file join $impl_dir top.bit]
file copy -force $src_bit [file join $bit_dir top.bit]
puts "INFO: wrote $bit_dir/top.bit"

write_cfgmem -force -format BIN -interface SPIx4 -size 16 \
    -loadbit "up 0x00000000 $src_bit" \
    [file join $bit_dir top.bin]
puts "INFO: wrote $bit_dir/top.bin"

puts "BUILD_DONE"
