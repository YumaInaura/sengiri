module Sengiri
  class BroadcastProxy
    include Enumerable

    def self.thread_pool
      @pool ||= Concurrent::ThreadPoolExecutor.new(
        min_threads: [4, Concurrent.processor_count].max,
        max_threads: [4, Concurrent.processor_count].max)
    end

    def initialize(shard_classes, scope: nil)
      @shard_classes = shard_classes
      @scope = scope
    end

    def each(&block)
      if block_given?
        to_a.each(&block)
      else
        to_a.each
      end
    end

    def to_a
      execute(&:to_a).flatten
    end

    def size
      to_a.size
    end

    def find_by(query)
      records = execute { |relation|
        relation.find_by(query)
      }
      records.detect { |record| record }
    end

    def find_by!(query)
      result = find_by(query)
      if result.nil?
        raise ActiveRecord::RecordNotFound.new("Couldn't find #{query} with an out of range value")
      end
      result
    end

    def exists?
      execute(&:exists?).any? { |exists| exists }
    end

    private

    def execute
      @shard_classes.map { |shard_class|
        Concurrent::Future.execute do
          shard_class.connection_pool.with_connection do
            yield(scoped(shard_class))
          end
        end
      }.each_with_object([]) { |future, values|
        values << future.value
        raise future.reason if future.rejected?
      }
    end

    def scoped(shard_class)
      if @scope
        shard_class.merge(@scope)
      else
        shard_class.all
      end
    end
  end
end