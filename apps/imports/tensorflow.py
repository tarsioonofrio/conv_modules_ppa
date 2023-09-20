from tensorflow import keras
import numpy as np
import pathlib
import re

def get_mnist_dataset(input_h,input_w,input_c):
   # Get MNIST dataset
   mnist = keras.datasets.mnist
   
   # Load its data into training and test vectors
   (x_train, y_train),(x_test, y_test) = mnist.load_data()
   
   # Reshape
   numTrainImages=len(x_train)
   x_train=x_train.reshape(numTrainImages, input_h, input_w, input_c)
   numTestImages=len(x_test)
   x_test=x_test.reshape(numTestImages, input_h, input_w, input_c)
   
   # Normalize the data
   x_train, x_test = x_train / 255.0, x_test / 255.0
   
   # Collect feature size info
   imgSize0=len(x_train[0])
   imgSize1=len(x_train[0][0])
   numPixels=imgSize0*imgSize1
   featureShape=(1,imgSize0,imgSize1)
   
   return x_train, y_train, x_test, y_test, featureShape

def get_cifar10_dataset(input_h,input_w,input_c):
   # Get CIFAR10 dataset
   cifar10 = keras.datasets.cifar10
   
   # Load its data into training and test vectors
   (x_train, y_train),(x_test, y_test) = cifar10.load_data()
   
   # Reshape
   numTrainImages=len(x_train)
   x_train=x_train.reshape(numTrainImages, input_h, input_w, input_c)
   numTestImages=len(x_test)
   x_test=x_test.reshape(numTestImages, input_h, input_w, input_c)
   
   # Normalize the data
   x_train, x_test = x_train / 255.0, x_test / 255.0
   
   # Collect feature size info
   imgSize0=len(x_train[0])
   imgSize1=len(x_train[0][0])
   numPixels=imgSize0*imgSize1
   featureShape=(1,imgSize0,imgSize1)
   
   return x_train, y_train, x_test, y_test, featureShape
   
def build_neural_network(featureShape, filter_channel, filter_dimension, stride_h, stride_w, input_h, input_w, input_c, n_conv_layers, n_dense_neuron):
   # Clearup everything before running
   keras.backend.clear_session()

   # Create model
   model = keras.models.Sequential()

   # Add layers
   model.add(keras.layers.Conv2D(filter_channel[0], (filter_dimension[0],filter_dimension[0]), strides=(stride_h[0], stride_w[0]), activation='relu', input_shape=(input_h, input_w, input_c)))
   
   for i in range(1,n_conv_layers):
      model.add(keras.layers.Conv2D(filter_channel[i], (filter_dimension[i],filter_dimension[i]), strides=(stride_h[i], stride_w[i]), activation='relu'))
      
   model.add(keras.layers.Flatten())
   model.add(keras.layers.Dense(n_dense_neuron, activation='softmax'))

   # Build model and #print summary
   model.build(input_shape=featureShape)

   # Compile model
   model.compile(optimizer='adam', loss='sparse_categorical_crossentropy', metrics=['accuracy'])
   
   return model


def training_neural_network(model, x_train, y_train, validation_data, n_epochs):
   # Training
   history = model.fit(x_train, y_train, validation_data=validation_data, epochs=n_epochs)

