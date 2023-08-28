if {[file isdirectory work]} { vdel -all -lib work }
vlib work
vmap work work


# conv2d tb not use data from tensorflow, the data is defined in tb

vcom -work work ../rtl/components/reg.vhd
vcom -work work ../rtl/components/mac.vhd
vcom -work work ../rtl/arrays/conv2d_v2.vhd
vcom -work work ../tb/rtl/tb2d_v2_rtl.vhd

vsim -voptargs=+acc=lprn -t ns work.tb

do wave2d.do
run 3000 ns



 
