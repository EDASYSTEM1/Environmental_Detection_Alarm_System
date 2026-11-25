# ============================================================================
#  tools/hw_program.tcl -- 把 bitstream/top.bit 下载进 FPGA
#  （由 tools/program_board.bat 调用；成功时打印 PROGRAM_OK）
#
#  流程：启动/连接 hw_server → 打开 target → 刷新器件 → 下载 bit
# ============================================================================
set script_dir [file normalize [file dirname [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]
set bit_file   [file join $root_dir bitstream top.bit]

if {![file exists $bit_file]} {
    puts "ERROR: 找不到比特流：$bit_file"
    puts "       先跑 scripts/build_bitstream.bat"
    exit 1
}

open_hw_manager

puts "INFO: 连接 / 启动 hw_server ..."
if {[catch {connect_hw_server} err]} {
    if {[catch {connect_hw_server -url localhost:3121} err2]} {
        puts "ERROR: 连不上 hw_server：$err2"
        puts "       检查：USB 是否插在板子的 PROG/UART 口、板子是否上电、Vivado 是否占用了目标"
        exit 1
    }
}
puts "INFO: hw_server = [get_hw_servers]"

puts "INFO: 打开 hw_target ..."
if {[catch {open_hw_target} err]} {
    puts "ERROR: 打不开 hw_target：$err"
    exit 1
}

set dev [lindex [get_hw_devices] 0]
if {$dev eq ""} {
    puts "ERROR: 没找到器件（JTAG 链不通）"
    exit 1
}
current_hw_device $dev
puts "INFO: device = $dev"

if {[catch {refresh_hw_device -update_hw_probes false $dev} err]} {
    puts "ERROR: refresh_hw_device 失败：$err"
    exit 1
}

puts "INFO: 正在下载 $bit_file ..."
set_property PROGRAM.FILE $bit_file $dev
if {[catch {program_hw_devices $dev} err]} {
    puts "ERROR: program_hw_devices 失败：$err"
    exit 1
}

puts "PROGRAM_OK"
catch { close_hw_target }
catch { close_hw_manager }
