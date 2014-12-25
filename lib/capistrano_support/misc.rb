module Pomodori
  module CapistranoSupport
    module Misc
      def create_user(host, name)
        case host.properties.fetch(:os_class)
        when :redhat
          sudo(host, "adduser #{name} && usermod -L #{name}")
        when :debian
          sudo(host, "adduser --disabled-password --gecos #{name} #{name}")
        else
          raise "Bug"
        end
      end
    end
  end
end
