module Applb
  class DSL
    class EC2
      class LoadBalancer
        class TargetGroups
          class TargetGroup
            include Checker
            include Applb::TemplateHelper

            class Result
              ATTRIBUTES = %i/
                name protocol port vpc_id health_check_protocol health_check_port health_check_path
                health_check_interval_seconds health_check_timeout_seconds healthy_threshold_count
                unhealthy_threshold_count matcher instances
              /

              attr_accessor *ATTRIBUTES

              def initialize(context)
                @context = context
                @options = context.options
              end

              def to_h
                Hash[ATTRIBUTES.sort.map { |name| [name, public_send(name)] }]
              end

              def aws(aws_tg)
                @aws_tg = aws_tg
                @aws_instances = client.target_group_instances(@aws_tg.target_group_arn)
                self
              end

              def create
                Applb.logger.info("Create target group #{name}")
                return if @options[:dry_run]
                client.create_target_group(create_option).target_groups.first
              end

              def modify
                dsl_hash = to_diff_h
                aws_hash = to_diff_h_aws
                return if dsl_hash == aws_hash

                Applb.logger.info("Modify target group #{name}")
                Applb.logger.info("<diff>\n#{Applb::Utils.diff(aws_hash, dsl_hash, color: @options[:color])}")
                return if @options[:dry_run]

                modify_instances
                client.modify_target_group(modify_option).target_groups.first
              end

              private

              def create_option
                hash = to_h
                hash.delete(:instances)
                hash
              end

              UNMODIFIABLE_ATTRIBUTES = %i/name port protocol vpc_id/
              def modify_option
                hash = to_h
                hash.delete(:instances)
                hash.merge(target_group_arn: @aws_tg.target_group_arn).
                  reject! { |k, v| UNMODIFIABLE_ATTRIBUTES.include?(k) }
              end

              def to_diff_h
                hash = to_h
                hash.delete(:target_group_arn)
                Hash[hash.sort]
              end

              def to_diff_h_aws
                hash = @aws_tg.to_h
                hash[:name] = hash.delete(:target_group_name)
                hash[:instances] = @aws_instances
                hash.delete(:target_group_arn)
                hash.delete(:load_balancer_arns)
                Hash[hash.sort]
              end

              def modify_instances
                return if instances == @aws_instances

                register_targets = (instances - @aws_instances).map do |instance|
                  instance_id = client.instance_names.key(instance) || instance
                  {id: instance_id}
                end
                if !register_targets.empty?
                  client.register_targets(target_group_arn: @aws_tg.target_group_arn, targets: register_targets)
                end

                deregister_targets = (@aws_instances - instances).map do |instance|
                  instance_id = client.instance_names.key(instance) || instance
                  {id: instance_id}
                end
                if !deregister_targets.empty?
                  client.deregister_targets(target_group_arn: @aws_tg.target_group_arn, targets: deregister_targets)
                end
              end

              def client
                @client ||= Applb::ClientWrapper.new(@options)
              end
            end

            def initialize(context, name, lb_name, &block)
              @context = context.dup
              @lb_name = lb_name
              @result = Result.new(@context)
              @result.name = name
              @result.instances = []

              instance_eval(&block)
            end

            def result
              required(:name, @result.name)
              required(:protocol, @result.protocol)
              required(:port, @result.port)
              required(:vpc_id, @result.vpc_id)

              @result
            end

            private

            def name(name)
              @result.name = name
            end

            def protocol(protocol)
              @result.protocol = protocol
            end

            def port(port)
              @result.port = port
            end

            def vpc_id(vpc_id)
              @result.vpc_id = vpc_id
            end

            def health_check_protocol(health_check_protocol)
              @result.health_check_protocol = health_check_protocol
            end

            def health_check_port(health_check_port)
              @result.health_check_port = health_check_port
            end

            def health_check_path(health_check_path)
              @result.health_check_path = health_check_path
            end

            def health_check_interval_seconds(health_check_interval_seconds)
              @result.health_check_interval_seconds = health_check_interval_seconds
            end

            def health_check_timeout_seconds(health_check_timeout_seconds)
              @result.health_check_timeout_seconds = health_check_timeout_seconds
            end

            def healthy_threshold_count(healthy_threshold_count)
              @result.healthy_threshold_count = healthy_threshold_count
            end

            def unhealthy_threshold_count(unhealthy_threshold_count)
              @result.unhealthy_threshold_count = unhealthy_threshold_count
            end

            def matcher(http_code:)
              @result.matcher = { http_code: http_code }
            end

            def instances(*instances)
              @result.instances = instances.sort
            end
          end
        end
      end
    end
  end
end
