require 'menoh/version'
require 'menoh/menoh_native'

module Menoh
  class Menoh
    def initialize(file)
      raise "No such file : #{file}" unless File.exist?(file)

      native_init file
      yield self if block_given?
    end

    def make_model(option)
      raise "Required ':backend' : #{option[:backend]}" if option[:backend].nil?
      model = MenohModel.new self, option
      yield model if block_given?
      model
    end
  end

  class MenohModel
    def initialize(menoh, option)
      if option[:input_layers].nil? || option[:input_layers].empty?
        raise "Required ':input_layers'"
      end
      raise "Required ':input_layers'" unless option[:input_layers].instance_of?(Array)
      option[:input_layers].each_with_index do |input_layer, i|
        raise 'Invalid option : input_layers' unless input_layer.instance_of?(Hash)
        raise "Invalid name for input_layer[#{i}]" unless input_layer[:name].instance_of?(String)
        raise "Invalid dims for input_layer[#{i}]" unless input_layer[:dims].instance_of?(Array)
      end
      if option[:output_layers].nil? || option[:output_layers].empty?
        raise "Invalid ':output_layers'"
      end
      native_init menoh, option
      @option = option
      yield self if block_given?
    end

    def run(dataset)
      raise 'Invalid dataset' if !dataset.instance_of?(Array) || dataset.empty?
      if dataset.length != @option[:input_layers].length
        raise "Invalid input num: expected==#{@option[:input_layers].length} actual==#{dataset.length}"
      end
      dataset_for_native = []
      dataset.each do |input|
        if !input[:data].instance_of?(Array) || input[:data].empty?
          raise "Invalid dataset for layer #{input[:name]}"
        end
        target_layer = @option[:input_layers].find { |item| item[:name] == input[:name] }
        expected_data_length = target_layer[:dims].inject(:*)
        if input[:data].length != expected_data_length
          raise "Invalid data length: expected==#{expected_data_length} actual==#{input[:data].length}"
        end
        dataset_for_native << input[:data]
      end

      # run
      results = native_run dataset_for_native

      # reshape result
      results.map do |raw|
        buffer = raw[:data]
        shape = raw[:shape]
        raw[:data] = Util.reshape buffer, shape
      end

      yield results if block_given?
      results
    end
  end

  module Util
    def self.reshape(buffer, shape)
      sliced_buffer = buffer.each_slice(buffer.length / shape[0]).to_a
      if shape.length > 2
        next_shape = shape.slice(1, shape.length)
        sliced_buffer = sliced_buffer.map { |buf| reshape buf, next_shape }
      end
      sliced_buffer
    end
  end
end
