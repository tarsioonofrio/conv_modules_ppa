if {[file isdirectory work]} { vdel -all -lib work }
vlib work
vmap work work

vcom -work work ../apps/tensorflow.vhd
vcom -work work ../rtl/components/reg.vhd
vcom -work work ../rtl/components/mac.vhd
vcom -work work ../rtl/arrays/systolic2d.vhd
vcom -work work ../tb/rtl/tbsystolic2d_rtl.vhd

vsim -voptargs=+acc=lprn -t ns work.tb -f ../apps/generic_file.txt

do wavesystolic2d.do
onfinish exit
onbreak exit
run -all
exit



 
