require 'menoh/version'
require 'menoh/menoh_native'
require 'json'
require 'numo/narray'

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
    DTYPE_TO_NUMO_NARRAY_CLASS = {
      float: Numo::SFloat,
      float32: Numo::SFloat,
      float64: Numo::DFloat,
      int8: Numo::Int8,
      int16: Numo::Int16,
      int32: Numo::Int32,
      int64: Numo::Int64
    }.freeze

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

      option = option.dup
      if option.key?(:backend_config)
        config = option[:backend_config]
        unless config.nil? || config.is_a?(String)
          option[:backend_config] = JSON.dump(config)
        end
      end

      native_init menoh, option
      @option = option
      yield self if block_given?
    end

    def run(dataset, numo_narray: false)
      raise 'Invalid dataset' if !dataset.instance_of?(Array) || dataset.empty?
      if dataset.length != @option[:input_layers].length
        raise "Invalid input num: expected==#{@option[:input_layers].length} actual==#{dataset.length}"
      end

      dataset.each do |input|
        raise "Empty data for layer #{input[:name]}" if input[:data].empty?

        if input[:data].instance_of?(Array)
          set_data(input[:name], input[:data])
        elsif input[:data].instance_of?(Numo::SFloat)
          if dataset.length != @option[:input_layers].length
            raise "Invalid input num: expected==#{@option[:input_layers].length} actual==#{dataset.length}"
          end
          set_data_str(input[:name], input[:data].to_binary)
        else
          raise "Invalid dataset for layer #{input[:name]}"
        end
      end

      # run
      native_run

      # reshape result
      results = @option[:output_layers].map do |name|
        dtype = get_dtype(name)
        shape = get_shape(name)
        data = nil
        if numo_narray
          c = DTYPE_TO_NUMO_NARRAY_CLASS[dtype]
          raise InvalidDType, "unsupported dtype: #{dtype}" if c.nil?

          data = c.from_binary(get_data_str(name), get_shape(name))
        else
          buffer = get_data(name)
          data = Util.reshape(buffer, shape)
        end
        { name: name, shape: shape, data: data }
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
