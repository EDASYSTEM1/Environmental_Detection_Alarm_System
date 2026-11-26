# vivado -mode batch -source scripts/project.tcl -tclargs build
set root [file normalize [file join [file dirname [info script]] ..]]
set name env_vga_tf
set xpr [file join $root $name.xpr]
if {[file exists $xpr]} {
    open_project $xpr
} else {
    create_project $name $root -part xc7a100tcsg324-1
}
set_property target_language Verilog [current_project]
set_property default_lib xil_defaultlib [current_project]
foreach {fileset patterns} {sources_1 {rtl/*.v rtl/base/*.v} constrs_1 {xdc/*.xdc} sim_1 {sim/*.v}} {
    foreach pat $patterns {
        foreach f [glob -nocomplain [file join $root $pat]] {
            if {![llength [get_files -quiet $f]]} {add_files -norecurse -fileset $fileset $f}
        }
    }
}
set_property top env_vga_tf_top [get_filesets sources_1]
set_property top tb_env_top [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
if {[lindex $argv 0] eq "build"} {
    set reports [file join $root reports]
    file mkdir $reports
    if {[get_property PROGRESS [get_runs synth_1]] ne "0%"} {reset_run synth_1}
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed"}
    launch_runs impl_1 -to_step write_bitstream -jobs 4
    wait_on_run impl_1
    if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation failed"}
    open_run impl_1
    report_timing_summary -file [file join $reports timing_summary.rpt]
    report_utilization -file [file join $reports utilization.rpt]
    report_drc -file [file join $reports drc.rpt]
    set setup [get_property SLACK [get_timing_paths -setup -max_paths 1]]
    set hold [get_property SLACK [get_timing_paths -hold -max_paths 1]]
    puts "DESIGN_TIMING setup=$setup hold=$hold"
    if {$setup < 0 || $hold < 0} {error "Timing constraints not met"}
    file mkdir [file join $root bitstream]
    file copy -force [file join [get_property DIRECTORY [get_runs impl_1]] env_vga_tf_top.bit] [file join $root bitstream env_vga_tf.bit]
    puts "BUILD_OK"
}
close_project
