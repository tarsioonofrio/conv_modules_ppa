if {[file isdirectory work]} { vdel -all -lib work }
vlib work
vmap work work

vcom -work work ../rtl/components/reg.vhd
vcom -work work ../rtl/components/mac.vhd
vcom -work work ../rtl/arrays/systolic2d1stride.vhd
vcom -work work ../tb/rtl/tbsystolic2d_v2_rtl.vhd

vsim -voptargs=+acc=lprn -t ns work.tb 
log -r /*
do wavesystolic2d.do
add wave sim:/tb/DUT/en_reg
add wave sim:/tb/DUT/cont_iterations
add wave sim:/tb/DUT/change_line
#onfinish exit
#onbreak exit
run -all
#exit



 
