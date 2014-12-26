require 'stringio'

module Pomodori
  module CapistranoSupport
    module FileManipulation
      def sudo_download(host, path, io)
        mktempdir(host) do |tmpdir|
          e_tmpdir = Shellwords.escape(tmpdir)
          e_path = Shellwords.escape(path)
          username = host.user || "root"
          sudo(host, "cp #{e_path} #{e_tmpdir}/file && chown #{username}: #{e_tmpdir} #{e_tmpdir}/file")
          download!("#{tmpdir}/file", io)
        end
      end

      def sudo_download_to_string(host, path)
        io = StringIO.new
        io.binmode
        sudo_download(host, path, io)
        io.string
      end

      def sudo_upload(host, io, path, options = {})
        mktempdir(host) do |tmpdir|
          chown = options[:chown] || "root:"
          chmod = options[:chmod] || "600"
          if io.is_a?(String)
            str = io
            io = StringIO.new
            io.binmode
            io.write(str)
            io.rewind
          end
          upload!(io, "#{tmpdir}/file")
          sudo(host, "chown #{chown} #{tmpdir}/file && chmod #{chmod} #{tmpdir}/file && mv #{tmpdir}/file #{path}")
        end
      end

      def download_to_string(path, options = {})
        io = StringIO.new
        io.binmode
        download!(path, io, options)
        io.string
      end

      def try_download_to_string(path)
        if test_cond("-e #{path}")
          download_to_string(path)
        else
          nil
        end
      end

      def mktempdir(host, options = {})
        tmpdir = capture("mktemp -d /tmp/pomodori.XXXXXXXX").strip
        begin
          yield tmpdir
        ensure
          if options.fetch(:sudo, true)
            sudo(host, "rm -rf #{tmpdir}")
          else
            execute "rm -rf #{tmpdir}"
          end
        end
      end


      def edit_section_in_string(str, section_name, content)
        section_begin_str = "###### BEGIN #{section_name} ######"
        section_end_str   = "###### END #{section_name} ######"

        lines = str.split("\n", -1)
        content.chomp!

        start_index = lines.find_index(section_begin_str)
        if !start_index
          # Section is not in file.
          return if content.empty?
          lines << section_begin_str
          lines << content
          lines << section_end_str
        else
          end_index = start_index + 1
          while end_index < lines.size && lines[end_index] != section_end_str
            end_index += 1
          end
          if end_index == lines.size
            # End not found. Pretend like the section is empty.
            end_index = start_index
          end
          lines.slice!(start_index, end_index - start_index + 1)
          if !content.empty?
            lines.insert(start_index, section_begin_str, content, section_end_str)
          end
        end

        if lines.last && lines.last.empty?
          lines.pop
        end
        lines.join("\n") << "\n"
      end

      def sudo_edit_file_section(host, path, section_name, content, options)
        if sudo_test(host, "[[ -e #{path} ]]")
          str = sudo_download_to_string(host, path)
        else
          str = ""
        end
        io = StringIO.new
        io.binmode
        io.write(edit_section_in_string(str, section_name, content))
        io.rewind
        sudo_upload(host, io, path, options)
      end

      def check_file_change(host, path)
        md5_old = sudo_capture(host, "md5sum #{path} 2>/dev/null; true").strip
        yield
        md5_new = sudo_capture(host, "md5sum #{path}").strip
        md5_old != md5_new
      end
    end
  end
end
