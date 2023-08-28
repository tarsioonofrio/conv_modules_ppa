if {[file isdirectory work]} { vdel -all -lib work }
vlib work
vmap work work

vcom -work work ../apps/stride1/tensorflow.vhd
vcom -work work ../rtl/components/reg.vhd
vcom -work work ../rtl/components/mac.vhd
vcom -work work ../rtl/arrays/conv1ds1.vhd
vcom -work work ../tb/rtl/tb1d_rtl.vhd

vsim -voptargs=+acc=lprn -t ns work.tb -f ../apps/stride1/generic_file.txt
log -r /*

do wave1d.do
#onfinish exit
#onbreak exit
run -all
#exit


 
