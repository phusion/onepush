module Pomodori
  module Commands
    class Base
      def initialize(argv)
        @argv = argv.dup
        @options = self.class.create_default_options
      end

      def run
        parse_options
        validate_options
      end

    private
      def self.create_default_options
        return {}
      end

      def parse_options
        @parser = self.class.create_option_parser(@options)
        begin
          @parser.parse!(@argv)
        rescue OptionParser::ParseError => e
          STDERR.puts "*** ERROR: #{e}"
          abort @parser.to_s
        end
        if @options[:help]
          puts @parser
          exit
        end
      end

      def setup_paint_mode
        if !STDOUT.tty?
          Paint.mode = 0
        end
      end
    end
  end
end
