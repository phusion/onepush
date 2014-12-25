module Pomodori
  module CapistranoSupport
    module Caching
      def cache(host, name)
        if result = host.properties.fetch("cache_#{name}")
          result[0]
        else
          result = [yield]
          host.properties.set("cache_#{name}", result)
          result[0]
        end
      end

      def clear_cache(host, name)
        host.properties.set("cache_#{name}", nil)
      end
    end
  end
end
