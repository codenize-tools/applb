require 'applb/dsl/rules'
require 'applb/utils'
require 'applb/client_wrapper'

module Applb
  class DSL
    class EC2
      class LoadBalancer
        class Listeners
          class Listener
            include Checker
            include Applb::TemplateHelper

            class Result
              ATTRIBUTES = %i/certificates ssl_policy port protocol default_actions rules load_balancer_arn/
              attr_accessor *ATTRIBUTES

              def initialize(context, lb_name)
                @context = context
                @options = context.options
                @lb_name = lb_name
              end

              def to_h
                Hash[ATTRIBUTES.sort.map { |name| [name, public_send(name)] }]
              end

              def aws(aws_listener)
                @aws_listener = aws_listener
                self
              end

              def create
                Applb.logger.info("#{@lb_name} Create listener for port #{port}")
                return if @options[:dry_run]
                client.create_listener(create_option).listeners.first
              end

              def modify
                dsl_hash = to_diff_h
                aws_hash = to_diff_h_aws
                return if dsl_hash == aws_hash

                Applb.logger.info("#{@lb_name} Modify listener for port #{port}")
                Applb.logger.info("<diff>\n#{Applb::Utils.diff(aws_hash, dsl_hash, color: @options[:color])}")
                return if @options[:dry_run]

                client.modify_listener(modify_option).listeners.first
              end

              private

              def to_diff_h
                options = Applb::Utils.normalize_hash(to_h)
                target_group_name = options[:default_actions].first.delete(:target_group_name)
                if options[:ssl_policy] && options[:ssl_policy].empty?
                  options.delete(:certificates)
                  options.delete(:ssl_policy)
                end
                options.reject! { |k, v| %i/listener_arn load_balancer_arn rules/.include?(k) }
              end

              def to_diff_h_aws
                options = Applb::Utils.normalize_hash(@aws_listener.to_h)
                if options[:ssl_policy] && options[:ssl_policy].empty?
                  options.delete(:certificates)
                  options.delete(:ssl_policy)
                end
                options.reject! { |k, v| %i/listener_arn load_balancer_arn rules/.include?(k) }
              end

              def create_option
                options = to_h.reject { |k, _| %i/policy_name rules/.include?(k) }
                options[:default_actions].first.delete(:target_group_name)
                options
              end

              def modify_option
                to_diff_h.merge(listener_arn: @aws_listener.listener_arn)
              end

              def client
                @client ||= Applb::ClientWrapper.new(@options)
              end
            end

            attr_reader :result
            
            def initialize(context, lb_name, &block)
              @context = context.dup
              @lb_name = lb_name

              @result = Result.new(@context, @lb_name)

              instance_eval(&block)
            end

            private

            def certificates(certificate_arn:)
              @result.certificates ||= []
              @result.certificates << {certificate_arn: certificate_arn}
            end

            def ssl_policy(ssl_policy)
              @result.ssl_policy = ssl_policy if ssl_policy
            end

            def port(port)
              @result.port = port
            end

            def protocol(protocol)
              @result.protocol = protocol
            end

            def default_actions(target_group_name: nil, target_group_arn: nil, type:)
              unless target_group_name || target_group_arn
                raise "target_group_name or target_group_arn is required"
              end
              @result.default_actions ||= []
              @result.default_actions << {
                target_group_arn: target_group_arn,
                target_group_name: target_group_name,
                type: type,
              }
            end

            def rules(&block)
              rules = Rules.new(@context, self, &block).result
              unless rules.empty?
                @result.rules = rules
              end
            end
          end
        end
      end
    end
  end
end
