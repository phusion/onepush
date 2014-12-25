module Pomodori
  module Utils
    BooleanValue = lambda do |value|
      ["true", "t", "yes", "y", "1"].include?(value.to_s.downcase)
    end

    def self.EnumValue(property_name, *allowed_values)
      lambda do |value|
        if allowed_values.include?(value)
          value
        else
          raise Hashie::CoercionError, "Value #{value.inspect} is not allowed for the #{property_name} property"
        end
      end
    end
  end
end
