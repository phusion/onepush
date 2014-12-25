module Pomodori
  module Utils
    # Extends Hashie::Dash's `property` method so that you
    # can define type coercion rules using the `property` method.
    # If you pass a type coercion rule (as `coerce_key` expects it)
    # as the second parameter, then `coerce_key` will be called
    # automatically for you.
    #
    # You can write this:
    #
    #     property :foo, String, :required => true
    #
    # Which this module translates to:
    #
    #     property :foo, :required => true
    #     coerce_key :foo, String
    module HashieCoerceableProperty
      def property(*args)
        if args[1].is_a?(Class) || args[1].is_a?(Proc) || args[1].is_a?(Array)
          coercion_rule = args.delete_at(1)
          super(*args)
          coerce_key(args[0], coercion_rule)
        else
          super
        end
      end
    end
  end
end
