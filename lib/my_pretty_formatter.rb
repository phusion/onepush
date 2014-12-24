require 'sshkit/formatters/pretty'
require 'colorize'

module Pomodori
  # Fixes SSHKit's Pretty formatter so that it doesn't colorize
  # output when outputting to a non-TTY.
  class MyPrettyFormatter < SSHKit::Formatter::Pretty
    class MaybeColor
      def initialize(io)
        @io = io
      end

      STYLES = [String::COLORS, String::MODES].flat_map(&:keys)

      STYLES.each do |style|
        eval %{
        def #{style}(string='')
          string = yield if block_given?
          @io.tty? ? string.colorize(:#{style}) : string
        end
        }
      end
    end

  private
    def c
      @c ||= MaybeColor.new(@original_output)
    end
  end
end