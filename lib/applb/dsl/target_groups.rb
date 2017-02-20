require 'applb/dsl/target_group'

module Applb
  class DSL
    class EC2
      class LoadBalancer
        class TargetGroups
          include Applb::TemplateHelper

          attr_reader :result

          def initialize(context, lb, &block)
            @context = context.dup
            @lb = lb
            @result = []
            instance_eval(&block)
          end

          private

          def target_group(name, &block)
            @result << TargetGroup.new(@context, name, @lb, &block).result
          end
        end
      end
    end
  end
end
