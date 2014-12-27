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

      def maybe_load_default_config_files(dir = Dir.pwd)
        if !@options[:loaded]
          if File.exist?(File.join(dir, "pomodori.json"))
            @options.merge!(JSON.parse(File.read(File.join(dir, "pomodori.json"))))
            @options[:loaded] = true
          elsif File.exist?(File.join(dir, "onepush.json"))
            @options.merge!(JSON.parse(File.read(File.join(dir, "onepush.json"))))
            @options[:loaded] = true
          else
            abort " *** ERROR: No configuration file found. Please run " +
              "`pomodori init` first, or specify a configuration file " +
              "with --config."
          end
        end
      end

      def setup_paint_mode
        if !STDOUT.tty?
          Paint.mode = 0
        end
      end

      def success_greeting
        ["High five", "Awesome", "Hurray", "Congratulations", "Wow", "Splendid"].sample
      end

      def notice(message)
        puts "NOTICE -- #{message}"
      end

      def report_progress(value)
        puts "PROGRS -- #{value}"
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
        return if !@announcement_thread
        @announcement_thread.join
        if result = @announcement_thread[:result]
          begin
            announcements = JSON.parse(result)
          rescue JSON::ParserError
            # Ignore error
          else
            puts
            if message = find_most_recent_announcement(announcements)
              puts Paint[message, :bold]
              update_last_announcement_read_time
            end
          end
        end
      end

      def find_most_recent_announcement(announcements)
        announcements = announcements.find_all do |ann|
          Time.parse(ann["date"]) > last_read_announcement_date
        end
        announcements.sort! do |a, b|
          Time.parse(a["date"]) <=> Time.parse(b["date"])
        end
        if announcements.any?
          announcements.last["message"]
        else
          nil
        end
      end

      def last_announcement_read_time_file
        @last_announcement_read_time_file ||= begin
          home = Etc.getpwuid.dir
          File.join(home, ".pomodori", "last_announcement_read_time")
        end
      end

      def last_read_announcement_date
        if File.exist?(last_announcement_read_time_file)
          Time.parse(File.read(last_announcement_read_time_file))
        else
          Time.now - (60 * 60 * 24 * 7)
        end
      end

      def update_last_announcement_read_time
        FileUtils.mkdir_p(File.dirname(last_announcement_read_time_file))
        File.open(last_announcement_read_time_file, "w") do |f|
          f.write(Time.now.to_s)
        end
      end
    end
  end
end
