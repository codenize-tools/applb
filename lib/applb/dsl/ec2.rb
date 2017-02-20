require 'ostruct'
require 'applb/dsl/load_balancer'

module Applb
  class DSL
    class EC2
      include Applb::TemplateHelper

      attr_reader :result

      def initialize(context, vpc_id, lbs, &block)
        @context = context.merge(vpc_id: vpc_id)

        @result = OpenStruct.new({
          vpc_id: vpc_id,
          load_balancers: lbs,
        })

        @names = lbs.map(&:name)
        instance_eval(&block)
      end

      private

      def elb_v2(name, &block)
        if @names.include?(name)
          raise "#{@result.vpc_id}: #{name} is already defined"
        end

        @result.load_balancers << LoadBalancer.new(@context, name, @result.vpc_id, &block).result
        @names << name
      end
    end
  end
end
