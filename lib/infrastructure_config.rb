require 'hashie/trash'
require 'hashie/extensions/ignore_undeclared'
require 'hashie/extensions/coercion'
require 'hashie/extensions/indifferent_access'
require 'hashie/extensions/dash/indifferent_access'
require_relative './utils/hashie_coerceable_property'
require_relative './utils/coercers'

module Pomodori
  class InfrastructureConfig < Hashie::Trash
    include Hashie::Extensions::IgnoreUndeclared
    include Hashie::Extensions::Coercion
    include Hashie::Extensions::Dash::IndifferentAccess
    extend Utils::HashieCoerceableProperty
    BooleanValue = Utils::BooleanValue

    property :app_id, String, required: true
  end
end
