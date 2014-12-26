require 'hashie/extensions/indifferent_access'
require 'hashie/extensions/merge_initializer'

module Pomodori
  class HashWithIndifferentAccess < Hash
    include Hashie::Extensions::IndifferentAccess
    include Hashie::Extensions::MergeInitializer
  end
end
