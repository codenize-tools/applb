require 'applb/error'

module Applb
  class DSL
    module Checker
      private

      class ValidationError < Error
      end

      def required(name, value)
        if value
          case value
          when String
            invalid = value.strip.empty?
          when Array, Hash
            invalid = value.empty?
          end
        else
          invalid = true
        end

        raise ValidationError.new("`#{name}' is required") if invalid
      end
    end
  end
end
