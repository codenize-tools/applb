require 'applb/dsl/listener'

module Applb
  class DSL
    class EC2
      class LoadBalancer
        class Listeners
          include Applb::TemplateHelper

          attr_reader :result

          def initialize(context, lb_name, &block)
            @context = context.dup
            @lb_name = lb_name
            @result = []

            instance_eval(&block)
          end

          private

          def listener(&block)
            @result << Listener.new(@context, @lb_name, &block).result
          end
        end
      end
    end
  end
end
