require 'json'
require 'resolv'
require 'ipaddr'
require 'uri'

module Pomodori
  module Commands
    class OpenUtils
      def initialize(params)
        @params = params
        @app_config = params.app_config
      end

      def check_hosts_file_garbage!
        internal_app_ips = resolve_hostname(internal_app_hostname)
        if internal_app_ips.size > 1 || !app_server_ips.include?(internal_app_ips[0])
          abort " *** ERROR: It looks like you have old entries in /etc/hosts which are interfering. " +
              "Please edit /etc/hosts, remove all entries that contain '#{internal_app_hostname}', " +
              "then re-run 'pomodori open'."
        end
      end

      def hosts_file_up_to_date?
        internal_app_ips = resolve_hostname(internal_app_hostname)
        if internal_app_ips.any?
          internal_app_ips.all? do |internal_app_ip|
            app_server_ips.include?(internal_app_ip)
          end
        else
          false
        end
      end

      def app_dns_resolves_to_one_of_app_servers?
        public_ips = resolve_hostname(public_domain_name)
        if public_ips.any?
          public_ips.all? do |public_ip|
            app_server_ips.include?(public_ip)
          end
        else
          false
        end
      end

      def resolve_hostname(hostname)
        Resolv.getaddresses(hostname).uniq
      rescue Resolv::ResolvError
        []
      end

      def internal_app_hostname
        "pomodori-#{@params.app_id}"
      end

      def app_server_ips
        @app_server_ips ||= begin
          hostnames = @params.app_server_addresses.map do |addr|
            URI.parse("scheme://#{addr}").hostname
          end
          ips = hostnames.map do |hostname|
            resolve_hostname(hostname)
          end
          ips.flatten.uniq
        end
      end

      def install_hosts_file_entry
        entry = "#{app_server_ips.first} #{internal_app_hostname}"
        puts " => Installing /etc/hosts entry: #{entry}"
        puts "    Sudo password may be required."
        if !system(%Q{sudo sh -c 'echo >> /etc/hosts && echo "#{entry}" >> /etc/hosts'})
          abort "Unable to install /etc/hosts entry."
        end
        puts " => /etc/hosts successfully modified."
        puts
      end

      def public_domain_name
        @public_domain_name ||= begin
          name = @app_config.domain_names.split(/ +/).first
          name.sub!(/^\*?\.?/, '')
          name
        end
      end

      def public_url
        "http://#{public_domain_name}/"
      end

      def open_address(url)
        if RUBY_PLATFORM =~ /darwin/
          puts "Opening #{url}"
          system("open #{url}")
        else
          puts "Please open this URL: #{url}"
        end
      end

      def using_amazon_ec2?
        service   = "service".freeze
        ec2       = "EC2".freeze
        ip_prefix = "ip_prefix".freeze
        blocks    = load_amazon_ip_ranges

        blocks["prefixes"].any? do |block|
          if block[service] == ec2
            begin
              ip = IPAddr.new(block[ip_prefix])
              app_server_ips.any? do |app_server_ip|
                ip.include?(app_server_ip)
              end
            rescue IPAddr::InvalidAddressError
              false
            end
          else
            false
          end
        end
      end

      def load_amazon_ip_ranges
        JSON.parse(File.read(File.join(ROOT, "lib", "amazon-ip-ranges.json")))
      end
    end
  end
end
