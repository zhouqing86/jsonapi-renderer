require 'jsonapi/include_directive'
require 'jsonapi/renderer/resources_processor'

module JSONAPI
  module Renderer
    class Document
      def initialize(params = {})
        @data    = params.fetch(:data,    :no_data)
        @errors  = params.fetch(:errors,  [])
        @meta    = params.fetch(:meta,    nil)
        @links   = params.fetch(:links,   {})
        @fields  = _symbolize_fields(params.fetch(:fields, {}))
        @jsonapi = params.fetch(:jsonapi, nil)
        @include = JSONAPI::IncludeDirective.new(params.fetch(:include, {}))
      end

      def to_json
        @json ||= document_hash
      end

      private

      def document_hash
        parts = []
        if @data != :no_data
          parts.concat(data_hash)
        elsif @errors.any?
          parts << errors_hash
        end
        parts << "\"links\":#{@links.to_json}"      if @links.any?
        parts << "\"meta\":#{@meta.to_json}"        unless @meta.nil?
        parts << "\"jsonapi\": #{@jsonapi.to_json}" unless @jsonapi.nil?

        parts.any? ? "{#{parts.join(',')}}" : ''
      end

      def data_hash
        primary, included =
          ResourcesProcessor.new(Array(@data), @include, @fields).process
        [].tap do |arr|
          data = if @data.respond_to?(:each)
                   "[#{primary.join(',')}]"
                 elsif @data.nil?
                   'null'
                 else
                   primary.first
                 end
          arr << "\"data\":#{data}"
          arr << "\"included\":[#{included.join(',')}]" if included.any?
        end
      end

      def errors_hash
        "\"errors\":[#{@errors.map(&:as_jsonapi).map(&:to_json).join(',')}]"
      end

      def _symbolize_fields(fields)
        fields.each_with_object({}) do |(k, v), h|
          h[k.to_sym] = v.map(&:to_sym)
        end
      end
    end
  end
end
