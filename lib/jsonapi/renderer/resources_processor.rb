require 'set'

class Cache
  def initialize
    @cache = {}
  end

  def fetch_multi(keys, &block)
    keys.each_with_object({}) do |k, h|
      @cache[k] = block.call(k) unless @cache.key?(k)
      h[k] = @cache[k]
    end
  end
end

module JSONAPI
  module Renderer
    class ResourcesProcessor
      def initialize(resources, include, fields)
        @resources = resources
        @include   = include
        @fields    = fields


        @cache = Cache.new
      end

      def process
        traverse_resources
        [@primary, @included].map { |res| process_resources(res) }
      end

      private

      def traverse_resources
        @traversed    = Set.new # [type, id, prefix]
        @include_rels = {} # [type, id => Set]
        @queue        = []
        @primary      = []
        @included     = []

        initialize_queue
        traverse_queue
      end

      def initialize_queue
        @resources.each do |res|
          @traversed.add([res.jsonapi_type, res.jsonapi_id, ''])
          traverse_resource(res, @include.keys, true)
          enqueue_related_resources(res, '', @include)
        end
      end

      def traverse_queue
        until @queue.empty?
          res, prefix, include_dir = @queue.pop
          traverse_resource(res, include_dir.keys, false)
          enqueue_related_resources(res, prefix, include_dir)
        end
      end

      def traverse_resource(res, include_keys, primary)
        ri = [res.jsonapi_type, res.jsonapi_id]
        if @include_rels.include?(ri)
          @include_rels[ri].merge!(include_keys)
        else
          @include_rels[ri] = Set.new(include_keys)
          (primary ? @primary : @included) << res
        end
      end

      def enqueue_related_resources(res, prefix, include_dir)
        res.jsonapi_related(include_dir.keys).each do |key, data|
          data.each do |child_res|
            next if child_res.nil?
            child_prefix = "#{prefix}.#{key}"
            enqueue_resource(child_res, child_prefix, include_dir[key])
          end
        end
      end

      def enqueue_resource(res, prefix, include_dir)
        return unless @traversed.add?([res.jsonapi_type,
                                       res.jsonapi_id,
                                       prefix])
        @queue << [res, prefix, include_dir]
      end

      def process_resources(resources)
        return process_resources_with_cache(resources) if @cache

        resources.map do |res|
          ri = [res.jsonapi_type, res.jsonapi_id]
          include_dir = @include_rels[ri]
          fields = @fields[ri.first.to_sym]
          res.as_jsonapi(include: include_dir, fields: fields).to_json
        end
      end

      def process_resources_with_cache(resources)
        hash = cache_key_map(resources)
        cached = @cache.fetch_multi(hash.keys) do |key|
          res, include, fields = hash[key]
          res.as_jsonapi(include: include, fields: fields).to_json
        end

        cached.values
      end

      def cache_key_map(resources)
        resources.each_with_object({}) do |res, h|
          ri = [res.jsonapi_type, res.jsonapi_id]
          include_dir = @include_rels[ri]
          fields = @fields[ri.first.to_sym]
          h[res.jsonapi_cache_key(include: include_dir, fields: fields)] =
            [res, include_dir, fields]
        end
      end
    end
  end
end
