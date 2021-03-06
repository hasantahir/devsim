# Copyright 2013 Devsim LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# solid state resistor ssac
circuit_element -name V1 -n1 topbias -n2 0 -acreal 1.0

## basically just a resistor
proc printCurrents {} {
    set deviceList [get_device_list]
    foreach device $deviceList \
    {
#	puts $device
	set contactList [get_contact_list -device $device]
#	puts "help $contactList"
	foreach cname $contactList \
	{
#	    puts $cname
	    set ecurr [get_contact_current -contact $cname -equation ElectronContinuityEquation -device $device]
	    #set hcurr [get_contact_current -contact $cname -equation HoleContinuityEquation -device $device]
	    set hcurr 0
	    set tcurr [expr {$ecurr+$hcurr}]                                        
	    puts [format "Device: %s Contact: %s\n\tElectron %s\n\tHole %s\n\tTotal %s" $device $cname $ecurr $hcurr $tcurr]
	}
    }
}

set device MyDevice
set region MyRegion

####
#### Meshing
####
create_2d_mesh -mesh dog
add_2d_mesh_line -mesh dog -dir x -pos 0 -ps 1e-6
#add_2d_mesh_line -mesh dog -dir x -pos 0.5e-5 -ps 1e-6
add_2d_mesh_line -mesh dog -dir x -pos 1e-5 -ps 1e-6

add_2d_mesh_line -mesh dog -dir y -pos 0 -ps 1e-6
add_2d_mesh_line -mesh dog -dir y -pos 1e-5 -ps 1e-6

add_2d_mesh_line -mesh dog -dir x -pos -1e-8 -ps 1e-8
add_2d_mesh_line -mesh dog -dir x -pos 1.001e-5 -ps 1e-8

add_2d_region    -mesh dog -material Si -region $region
add_2d_region    -mesh dog -material Si -region air1 -xl -1e-8 -xh 0
add_2d_region    -mesh dog -material Si -region air2 -xl 1.0e-5 -xh 1.001e-5

add_2d_contact   -mesh dog -name top -region $region -xl 0 -xh 0 -bloat 1e-10 -material metal
add_2d_contact   -mesh dog -name bot -region $region -xl 1e-5 -xh 1e-5 -bloat 1e-10 -material metal

finalize_mesh -mesh dog
create_device -mesh dog -device $device
###


####
#### Constants
####

set_parameter -device $device -region $region -name "Permittivity"     -value [expr 11.1*8.85e-14]
set_parameter -device $device -region $region -name "ElectronCharge"   -value 1.6e-19
set_parameter -device $device -region $region -name "IntrinsicDensity" -value 1.0e10
set_parameter -device $device -region $region -name "ThermalVoltage"   -value 0.0259

set_parameter -device $device -region $region -name "mu_n" -value 400
set_parameter -device $device -region $region -name "mu_p" -value 200

####
#### Potential
####

node_solution -device $device -region $region -name Potential
edge_from_node_model -device $device -region $region -node_model Potential


####
#### NetDoping
####

node_model -device $device -region $region -name NetDoping -equation "1.0e17;"

####
#### IntrinsicElectrons
####
node_model -device $device -region $region -name "IntrinsicElectrons"           -equation "NetDoping;"
node_model -device $device -region $region -name "IntrinsicElectrons:Potential" -equation  "diff(IntrinsicDensity*exp(Potential/ThermalVoltage), Potential);"

####
#### IntrinsicCharge
####
node_model -device $device -region $region -name "IntrinsicCharge"           -equation "-IntrinsicElectrons + NetDoping;"
node_model -device $device -region $region -name "IntrinsicCharge:Potential" -equation "-IntrinsicElectrons:Potential;"


####
#### ElectricField
####

edge_model -device $device -region $region -name ElectricField -equation "(Potential@n0 - Potential@n1)*EdgeInverseLength;"
edge_model -device $device -region $region -name "ElectricField:Potential@n0" -equation "EdgeInverseLength;"
edge_model -device $device -region $region -name "ElectricField:Potential@n1" -equation "-EdgeInverseLength;"

####
#### PotentialEdgeFlux
####

edge_model -device $device -region $region -name PotentialEdgeFlux -equation "Permittivity*ElectricField;"
edge_model -device $device -region $region -name PotentialEdgeFlux:Potential@n0 -equation "diff(Permittivity*ElectricField, Potential@n0);"
edge_model -device $device -region $region -name PotentialEdgeFlux:Potential@n1 -equation "-PotentialEdgeFlux:Potential@n0;"

####
#### PotentialEquation
####

equation -device $device -region $region -name PotentialEquation -variable_name Potential -node_model "" \
    -edge_model "PotentialEdgeFlux" -time_node_model "" -variable_update log_damp 

#set_parameter -name topbias -value 0.0
set_parameter -name bottombias -value 0.0


####
#### Potential contact equations
####

set conteq "Permittivity*ElectricField;"

node_model -device $device -region $region -name "topnode_model"           -equation "Potential - topbias;"
node_model -device $device -region $region -name "topnode_model:Potential" -equation "1;"
node_model -device $device -region $region -name "topnode_model:topbias" -equation "-1;"
edge_model -device $device -region $region -name "contactcharge_edge_top"  -equation $conteq
#
node_model -device $device -region $region -name "bottomnode_model"           -equation "Potential - bottombias;"
node_model -device $device -region $region -name "bottomnode_model:Potential" -equation "1;"
edge_model -device $device -region $region -name "contactcharge_edge_bottom"  -equation $conteq

contact_equation -device $device -contact "top" -name "PotentialEquation" -variable_name Potential \
			-node_model topnode_model -edge_model "" \
			-node_charge_model "" -edge_charge_model "contactcharge_edge_top" \
			-node_current_model ""   -edge_current_model "" -circuit_node "topbias"

contact_equation -device $device -contact "bot" -name "PotentialEquation" -variable_name Potential \
			-node_model bottomnode_model -edge_model "" \
			-node_charge_model "" -edge_charge_model "contactcharge_edge_bottom" \
			-node_current_model ""   -edge_current_model ""

####
#### Initial DC Solution
####
#catch {solve -type dc} foo
#puts $foo
solve -type dc -absolute_error 1.0 -relative_error 1e-10 -maximum_iterations 30

#print_node_values -device $device -region $region -name Potential
#print_node_values -device $device -region $region -name IntrinsicElectrons

####
#### Electrons
####
node_solution        -device $device -region $region -name Electrons
edge_from_node_model -device $device -region $region -node_model Electrons

#print_node_values -device $device -region $region -name IntrinsicElectrons
set_node_values -device $device -region $region -name Electrons -init_from IntrinsicElectrons
#print_node_values -device $device -region $region -name Electrons

####
#### PotentialNodeCharge
####
node_model -device $device -region $region -name "PotentialNodeCharge"           -equation "-ElectronCharge*(-Electrons + NetDoping);"
node_model -device $device -region $region -name "PotentialNodeCharge:Electrons" -equation "+ElectronCharge;"

####
#### PotentialEquation modified for carriers present
####
equation -device $device -region $region -name PotentialEquation -variable_name Potential -node_model "PotentialNodeCharge" \
    -edge_model "PotentialEdgeFlux" -time_node_model "" -variable_update default


####
#### vdiff, Bern01, Bern10
####
edge_model -device $device -region $region -name "vdiff"              -equation "(Potential@n0 - Potential@n1)/ThermalVoltage;"
edge_model -device $device -region $region -name "vdiff:Potential@n0"  -equation "ThermalVoltage^(-1);"
edge_model -device $device -region $region -name "vdiff:Potential@n1"  -equation "-ThermalVoltage^(-1);"
edge_model -device $device -region $region -name "Bern01"             -equation "B(vdiff);"
edge_model -device $device -region $region -name "Bern01:Potential@n0" -equation "dBdx(vdiff)*vdiff:Potential@n0;"
edge_model -device $device -region $region -name "Bern01:Potential@n1" -equation "dBdx(vdiff)*vdiff:Potential@n1;"
edge_model -device $device -region $region -name "Bern10"             -equation "B(-vdiff);"
edge_model -device $device -region $region -name "Bern10:Potential@n0" -equation "-dBdx(-vdiff)*vdiff:Potential@n0;"
edge_model -device $device -region $region -name "Bern10:Potential@n1" -equation "-dBdx(-vdiff)*vdiff:Potential@n1;"

####
#### Electron Current
####
set Jn       "ElectronCharge*mu_n*EdgeInverseLength*ThermalVoltage*(Electrons@n1*Bern10 - Electrons@n0*Bern01)";
set dJndn0   "simplify(diff( $Jn, Electrons@n0));";
set dJndn1   "simplify(diff( $Jn, Electrons@n1));";
set dJndpot0 "simplify(diff( $Jn, Potential@n0));";
set dJndpot1 "simplify(diff( $Jn, Potential@n1));";
edge_model -device $device -region $region -name "ElectronCurrent"             -equation "$Jn;"
edge_model -device $device -region $region -name "ElectronCurrent:Electrons@n0" -equation $dJndn0
edge_model -device $device -region $region -name "ElectronCurrent:Electrons@n1" -equation $dJndn1
edge_model -device $device -region $region -name "ElectronCurrent:Potential@n0" -equation $dJndpot0
edge_model -device $device -region $region -name "ElectronCurrent:Potential@n1" -equation $dJndpot1

set NCharge "-ElectronCharge * Electrons"
set dNChargedn "-ElectronCharge"

node_model -device $device -region $region -name "NCharge" -equation "$NCharge;"
node_model -device $device -region $region -name "NCharge:Electrons" -equation "$dNChargedn;"


####
#### Electron Continuity Equation
####
equation -device $device -region $region -name ElectronContinuityEquation -variable_name Electrons \
	 -edge_model "ElectronCurrent" -time_node_model "NCharge" -variable_update "positive"

####
#### Electron Continuity Contact Equation
####
node_model -device $device -region $region -name "celec" -equation "0.5*(NetDoping+(NetDoping^2 + 4 * IntrinsicDensity^2)^(0.5));"
node_model -device $device -region $region -name "topnodeelectrons"           -equation "Electrons - celec;"
node_model -device $device -region $region -name "topnodeelectrons:Electrons" -equation "1.0;"
edge_model -device $device -region $region -name "topnodeelectroncurrent"     -equation "ElectronCurrent;"
edge_model -device $device -region $region -name "topnodeelectroncurrent:Electrons@n0"     -equation "ElectronCurrent:Electrons@n0;"
edge_model -device $device -region $region -name "topnodeelectroncurrent:Electrons@n1"     -equation "ElectronCurrent:Electrons@n1;"
edge_model -device $device -region $region -name "topnodeelectroncurrent:Potential@n0"     -equation "ElectronCurrent:Potential@n0;"
edge_model -device $device -region $region -name "topnodeelectroncurrent:Potential@n1"     -equation "ElectronCurrent:Potential@n1;"

contact_equation -device $device -contact "top" -name "ElectronContinuityEquation" -variable_name Electrons \
			-node_model "topnodeelectrons" \
			-edge_current_model "topnodeelectroncurrent" \
			-circuit_node "topbias"
contact_equation -device $device -contact "bot" -name "ElectronContinuityEquation" -variable_name Electrons \
			-node_model "topnodeelectrons" \
			-edge_current_model "topnodeelectroncurrent"


foreach {v} {0.0 1e-3} {
#set_parameter -name "topbias" -value $v
circuit_alter -name V1 -value $v
solve -type dc -absolute_error 1.0e10 -relative_error 1e-7 -maximum_iterations 30
#catch {solve -type dc} foo
#puts $foo

printCurrents
}
#solve -type dc -absolute_error 1.0 -relative_error 1e-10 -maximum_iterations 30
solve -type dc -absolute_error 1.0e10 -relative_error 1e-7 -maximum_iterations 30
solve -type dc -absolute_error 1.0e10 -relative_error 1e-7 -maximum_iterations 30
solve -type dc -absolute_error 1.0e10 -relative_error 1e-7 -maximum_iterations 30
solve -type dc -absolute_error 1.0e10 -relative_error 1e-7 -maximum_iterations 30

solve -type noise -frequency 1e5 -output_node V1.I
#print_node_values -device $device -region $region -name V1.I_ElectronContinuityEquation_real
#print_node_values -device $device -region $region -name V1.I_ElectronContinuityEquation_imag
#print_node_values -device $device -region $region -name V1.I_ElectronContinuityEquation_real_gradx
#print_node_values -device $device -region $region -name V1.I_ElectronContinuityEquation_imag_gradx

#node_model -device $device -region $region -name "noise" -equation "V1.I_ElectronContinuityEquation_real_gradx^2;"
set rvx "V1.I_ElectronContinuityEquation_real_gradx"
set ivx "V1.I_ElectronContinuityEquation_imag_gradx"
set rvy "V1.I_ElectronContinuityEquation_real_grady"
set ivy "V1.I_ElectronContinuityEquation_imag_grady"

node_model -device $device -region $region -name "noisesource" -equation "4*ElectronCharge^2 * ThermalVoltage * mu_n * Electrons;"

node_model -device $device -region $region -name "vfield" -equation "($rvx*$rvx+$ivx*$ivx) + ($rvy*$rvy+$ivy*$ivy);"

node_model -device $device -region $region -name "noise" -equation "vfield * noisesource * NodeVolume;"
#node_model -device $device -region $region -name "noise2" -equation "sum(noise);"

#print_node_values -device $device -region $region -name noisesource
#print_node_values -device $device -region $region -name vfield
proc sum list {
  set sum 0
  foreach i $list {
      set sum [expr {$sum+$i}]
  }
  set sum
}
set x [sum [get_node_model_values -device $device -region $region -name noise]]
puts $x

#print_edge_values -device $device -region $region -name ElectricField

#foreach {f} {0 1 1e2 1e3 1e4 1e5 1e6 1e7 1e8 1e9 1e10 1e11 1e12} {
#solve -type ac -frequency $f
#}
#
#foreach x [get_circuit_node_list] {
#    foreach y [get_circuit_solution_list] {
#	foreach z [get_circuit_node_value -node $x -solution $y] {
#	    puts "$x\t$y\t$z";
#	}
#    }
#}

write_devices -file noise_res_2d.flps -type floops
#write_devices -file noise_res_2d -type vtk

#puts [get_edge_model_list -device $device -region $region]
#puts [get_edge_values -device $device -region $region -name unitx]
