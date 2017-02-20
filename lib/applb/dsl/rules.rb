require 'applb/dsl/rule'

module Applb
  class DSL
    class EC2
      class LoadBalancer
        class Listeners
          class Listener
            class Rules
              def initialize(context, listener, &block)
                @context = context.dup
                @listener = listener

                @result = []

                instance_eval(&block)
              end

              attr_reader :result
              
              private

              def rule(&block)
                @result << Rule.new(@context, @listener, &block).result
              end
            end
          end
        end
      end
    end
  end
end
