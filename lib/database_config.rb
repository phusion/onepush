require 'hashie/mash'
require 'hashie/extensions/coercion'

module Pomodori
  class DatabaseConfig < Hashie::Mash
    include Hashie::Extensions::Coercion

    coerce_key :host, String
    coerce_key :port, Integer
    coerce_key :database, String
    coerce_key :username, String
    coerce_key :password, String

    def validate_and_finalize!(app_config)
    end
  end
end
