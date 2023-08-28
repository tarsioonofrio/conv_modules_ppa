from imports import tensorflow
from imports import lib

# CNN Inputs
filter_channel   = [16,8,3,1]
filter_dimension = [3,3,3,3]
stride_h         = [2,1,2,1]
stride_w         = [2,1,2,1]
n_epochs         = 10

# HW Inputs
MEM_SIZE     = 10 
INPUT_SIZE   = 8
CARRY_SIZE   = 4

# Application parameters
input_w          = 32
input_h          = 32
input_c          = 3
n_dense_neuron   = 10
shift            = 4

# Compute number of convolutional layers
n_conv_layers = len(filter_channel)

# Get application dataset
x_train,y_train,x_test,y_test,featureShape = tensorflow.get_cifar10_dataset(input_h, input_w, input_c)

# Build CNN application
model = tensorflow.build_neural_network(featureShape, filter_channel, filter_dimension, stride_h, stride_w, input_h, input_w, input_c, n_conv_layers, n_dense_neuron)
tensorflow.training_neural_network(model, x_train, y_train, n_epochs)

# Compute input size
input_size = lib.get_input_size(input_h, input_w, input_c)

# Compute output layer dimensions
layer_dimension = lib.get_output_layer_dimension(input_h, n_conv_layers, filter_dimension, stride_h)

# Compute input channels
input_channel = lib.get_input_channel(input_c, n_conv_layers, filter_channel)

# Generate dictionary
modelDict = lib.create_dictionary(model)

# Adjust shift
shift = 2**shift

# Generate ORCA header
lib.generate_orca_header(modelDict,shift,input_size,filter_dimension,filter_channel,layer_dimension,input_channel,x_test,y_test,100)

# Generate VHDL package
lib.generate_vhdl_package(modelDict,shift,input_size,filter_dimension[0],filter_channel[0],stride_h[0],stride_w[0],layer_dimension[0],1,3,x_test)

# Compute HW parameters
X_SIZE       = input_w
FILTER_WIDTH = filter_dimension[0]
CONVS_PER_LINE = layer_dimension[0]

# Generate generic file for rtl simulation
lib.generate_generic_file(X_SIZE, FILTER_WIDTH, CONVS_PER_LINE, MEM_SIZE, INPUT_SIZE, CARRY_SIZE)

# Generate TCL file with generics for logic synthesis
lib.generate_tcl_generic(X_SIZE, FILTER_WIDTH, CONVS_PER_LINE, MEM_SIZE, INPUT_SIZE, CARRY_SIZE)

# Gererate gold output to validate ORCA simulation
lib.generate_orca_gold(modelDict,shift,input_size,filter_dimension,filter_channel,layer_dimension,input_channel,x_test,y_test,stride_h,stride_w,1)
