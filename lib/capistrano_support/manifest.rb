module Pomodori
  module CapistranoSupport
    module Manifest
      def check_manifest_requirements(manifest)
        ['id', 'type', 'domain_names'].each do |key|
          if !manifest[key]
            fatal_and_abort("The '#{key}' option must be set")
          end
        end
        if manifest['passenger_enterprise'] && !manifest['passenger_enterprise_download_token']
          fatal_and_abort("If you set passenger_enterprise to true, then you must also " +
            "set passenger_enterprise_download_token")
        end
      end
    end
  end
end
