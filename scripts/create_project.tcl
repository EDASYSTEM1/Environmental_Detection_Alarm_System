# ============================================================================
#  scripts/create_project.tcl —— 一键生成 Vivado 工程
#
#  用法（在仓库根目录）：
#     E:\vivado\2026.1\Vivado\bin\vivado.bat -mode batch -source scripts\create_project.tcl
#  或者双击 scripts\create_project.bat
#
#  特点：用 glob 自动收文件，所以组员新增 .v 之后**不用改这个脚本**，
#        重新跑一次就自动收进来了。
#
#  生成：work\sys_proj\sys_proj.xpr （用 Vivado 打开这个工程）
# ============================================================================

set script_dir [file normalize [file dirname [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]
set proj_dir   [file join $root_dir work sys_proj]

puts "INFO: root dir = $root_dir"
puts "INFO: project  = $proj_dir"

# Nexys A7-100T 的器件型号（不要写 xc7a35t：那是小板的型号）
create_project -force sys_proj $proj_dir -part xc7a100tcsg324-1

# ---------------------------------------------------------------------------
# RTL：top/*.v（排除 *_tb.v） + common/*.v + modules/*/rtl/*.v
#
# ⚠️ 曾经踩过的坑：最早这里漏收了 top/sys_top.v，结果工程里根本没有 sys_top，
#    Vivado 就"自动"把 alarm_ctrl 选成顶层，XDC 90 个端口全部对不上、bitgen 失败。
#    所以下面除了 glob，还断言 sys_top.v 一定在列表里。
# ---------------------------------------------------------------------------
set rtl_files {}
foreach f [glob -nocomplain [file join $root_dir top *.v]] {
    if {[string match "*_tb.v" [file tail $f]]} continue
    lappend rtl_files $f
}
foreach f [glob -nocomplain [file join $root_dir common *.v]] {
    lappend rtl_files $f
}
foreach d [glob -nocomplain -type d [file join $root_dir modules *]] {
    foreach f [glob -nocomplain [file join $d rtl *.v]] {
        lappend rtl_files $f
    }
}
if {[llength $rtl_files] == 0} {
    puts "ERROR: no RTL found under top/ or common/ or modules/*/rtl/"
    exit 1
}
set has_top 0
foreach f $rtl_files {
    if {[file tail $f] eq "sys_top.v"} { set has_top 1 }
}
if {!$has_top} {
    puts "ERROR: top/sys_top.v 没被收进 RTL 列表，顶层会错，停止建工程"
    exit 1
}
puts "INFO: RTL files ([llength $rtl_files]):"
foreach f $rtl_files { puts "        [file tail $f]" }
add_files -norecurse $rtl_files

# ---------------------------------------------------------------------------
# testbench：top/*_tb.v + modules/*/sim/*.v
# ---------------------------------------------------------------------------
set tb_files {}
foreach f [glob -nocomplain [file join $root_dir top *_tb.v]] {
    lappend tb_files $f
}
foreach d [glob -nocomplain -type d [file join $root_dir modules *]] {
    foreach f [glob -nocomplain [file join $d sim *.v]] {
        lappend tb_files $f
    }
}
if {[llength $tb_files] > 0} {
    add_files -fileset sim_1 -norecurse $tb_files
    puts "INFO: testbenches ([llength $tb_files)]"
}

# ---------------------------------------------------------------------------
# 约束
# ---------------------------------------------------------------------------
set xdc_files [glob -nocomplain [file join $root_dir xdc *.xdc]]
if {[llength $xdc_files] == 0} {
    puts "ERROR: no .xdc found under xdc/"
    exit 1
}
add_files -fileset constrs_1 -norecurse $xdc_files

# ---------------------------------------------------------------------------
# 顶层设置
#
# 注意顺序：必须先 update_compile_order，再 set_property top。
# 反过来的话 Vivado 在"自动层级更新"模式下还没扫出模块树，
# 会报 CRITICAL WARNING "top module sys_top can not be validated"，
# 然后自作主张换一个顶层（很容易导致综合出来的东西不是你想要的）。
# 所以这里先把层级定下来（source_mgmt_mode None = 手动编译顺序），再设顶层。
# ---------------------------------------------------------------------------
set_property source_mgmt_mode None [current_project]
update_compile_order -fileset sources_1
set_property top sys_top [current_fileset]

if {[llength $tb_files] > 0} {
    update_compile_order -fileset sim_1
    set_property top sys_tb [get_filesets sim_1]
}

puts "INFO: project created: $proj_dir/sys_proj.xpr"
puts "INFO: 打开工程：双击 work\\sys_proj\\sys_proj.xpr"
