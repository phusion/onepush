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

      def success_greeting
        ["High five", "Awesome", "Hurray", "Congratulations", "Wow"].sample
      end

      def prepare_announcement
        @announcement_thread = Thread.new do
          http = Net::HTTP.new("phusion.github.io", 80)
          begin
            response = http.request(Net::HTTP::Get.new("/pomodori/announcements.json"))
          rescue Timeout::Error, Errno::EINVAL, Errno::ECONNRESET, EOFError,
            Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError => e
            # Ignore error
            return
          end

          if response.code.to_i / 100 == 2
            Thread.current[:result] = response.body
          end
        end
      end

      def print_announcement
        @announcement_thread.join
        if result = @announcement_thread[:result]
          begin
            result = JSON.parse(result)
          rescue JSON::ParserError
            # Ignore error
          else
            puts
            puts Paint[result.first[:message], :bold]
          end
        end
      end
    end
  end
end
