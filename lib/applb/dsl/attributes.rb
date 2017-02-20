module Applb
  class DSL
    class EC2
      class LoadBalancer
        class Attributes
          include Applb::DSL::Checker
          include Applb::TemplateHelper

          attr_reader :result
          
          def initialize(context, lb_name, &block)
            @context = context.dup
            @lb_name = lb_name

            @result = {
              'access_logs.s3.enabled' => false,
              'access_logs.s3.bucket' => '',
              'access_logs.s3.prefix' => '',
              'idle_timeout.timeout_seconds' => 60,
              'deletion_protection.enabled' => false,
            }
            
            instance_eval(&block)
          end

          def result
            @result.map { |k, v| {key: k, value: v} }
          end

          private

          def access_logs(args)
            @result['access_logs.s3.enabled'] = args[:s3_enabled] if args[:s3_enabled]
            @result['access_logs.s3.bucket'] = args[:s3_bucket] if args[:s3_bucket]
            @result['access_logs.s3.prefix'] = args[:s3_prefix] if args[:s3_prefix]
          end

          def idle_timeout(timeout_seconds:)
            @result['idle_timeout.timeout_seconds'] = timeout_seconds if timeout_seconds
          end

          def deletion_protection(enabled:)
            @result['deletion_protection.enabled'] = enabled if enabled
          end
        end
      end
    end
  end
end
