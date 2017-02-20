require 'applb/dsl/checker'
require 'applb/dsl/attributes'
require 'applb/dsl/listeners'
require 'applb/dsl/target_groups'

module Applb
  class DSL
    class EC2
      class LoadBalancer
        include Applb::DSL::Checker
        include Applb::TemplateHelper

        class Result
          ATTRIBUTES = %i/name instances scheme subnets security_groups tags ip_address_type attributes target_groups listeners load_balancer_arn/
          attr_accessor *ATTRIBUTES

          def initialize(context)
            @context = context
            @options = context.options
          end

          def to_h
            Hash[ATTRIBUTES.sort.map { |name| [name, public_send(name)] }]
          end

          CREATE_KEYS = %i/name subnets security_groups scheme tags ip_address_type/
          def create_option
            to_h.select { |k, _| CREATE_KEYS.include?(k) }
          end

          def create
            Applb.logger.info "Create ELBv2 #{name}"
            return if @options[:dry_run]

            client.create_load_balancer(create_option).load_balancers.first
          end

          def aws(aws_lb)
            @aws_lb = aws_lb
            self
          end

          def subnets_updated?
            subnets.sort != @aws_lb.availability_zones.map(&:subnet_id).sort
          end

          def security_groups_updated?
            security_groups.sort != @aws_lb.security_groups.sort
          end

          def ip_address_type_updated?
            ip_address_type != @aws_lb.ip_address_type
          end

          def modify_subnets
            return unless subnets_updated?

            Applb.logger.info("Modify #{name} subnets")
            diff = Applb::Utils.diff(
              @aws_lb.availability_zones.map(&:subnet_id).sort,
              subnets.sort,
              color: @options[:color],
            )
            Applb.logger.info("<diff>\n#{diff}")
            return if @options[:dry_run]

            client.set_subnets(
              load_balancer_arn: @aws_lb.load_balancer_arn,
              subnets: subnets,
            ).availability_zones
          end

          def modify_security_groups
            return unless security_groups_updated?

            Applb.logger.info "Modify #{name} security_groups"
            diff = Applb::Utils.diff(
              @aws_lb.security_groups.sort,
              security_groups.sort,
              color: @options[:color],
            )
            Applb.logger.info("<diff>\n#{diff}")
            return if @options[:dry_run]

            client.set_security_groups(
              load_balancer_arn: @aws_lb.load_balancer_arn,
              security_groups: security_groups,
            ).security_group_ids
          end

          def modify_ip_address_type
            return unless ip_address_type_updated?

            Applb.logger.info "Modify #{name} ip_address_type"
            diff = Applb::Utils.diff(
              @aws_lb.ip_address_type,
              ip_address_type,
              color: @options[:color],
            )
            Applb.logger.info("<diff>\n#{diff}")

            return if @options[:dry_run]
            client.set_ip_address_type(
              load_balancer_arn: @aws_lb.load_balancer_arn,
              ip_address_type: ip_address_type,
            ).ip_address_type
          end

          def modify_load_balancer_attributes
            attrs = attributes.map do |attr|
              {key: attr[:key], value: attr[:value].to_s}
            end
            log_enabled = attrs.find { |attr| attr[:key] == 'access_logs.s3.enabled' }[:value]
            if log_enabled.to_s == 'false'
              attrs.reject! do |attr|
                %w/access_logs.s3.bucket access_logs.s3.prefix/.include?(attr[:key])
              end
            end
            dsl_hash = attrs.map { |a| a.to_h }.sort { |a, b| a[:key] <=> b[:key] }

            aws_attributes = client.describe_load_balancer_attributes(
              load_balancer_arn: @aws_lb.load_balancer_arn,
            ).attributes
            aws_hash = aws_attributes.map { |a| a.to_h }.sort { |a, b| a[:key] <=> b[:key] }
            aws_log_enabled = aws_attributes.find { |attr| attr[:key] == 'access_logs.s3.enabled' }[:value]
            if aws_log_enabled == 'false'
              aws_hash.reject! do |attr|
                %w/access_logs.s3.bucket access_logs.s3.prefix/.include?(attr[:key])
              end
            end

            return if dsl_hash == aws_hash

            Applb.logger.info "Modify #{name} load_balancer_attributes"
            Applb.logger.info("<diff>\n#{Applb::Utils.diff(aws_hash, dsl_hash, color: @options[:color])}")
            return if @options[:dry_run]

            client.modify_load_balancer_attributes(
              load_balancer_arn: @aws_lb.load_balancer_arn,
              attributes: attrs,
            ).attributes
          end

          private

          def client
            @client ||= Applb::ClientWrapper.new(@options)
          end
        end

        def initialize(context, name, vpc_id, &block)
          @name = name
          @vpc_id = vpc_id
          @context = context.merge(name: name)

          @result = Result.new(@context)
          @result.name = name
          @result.attributes = Attributes.new(@context, @name) {}.result
          @result.instances = []

          instance_eval(&block)
        end

        def result
          required(:subnets, @result.subnets)
          required(:security_groups, @result.security_groups)
          
          @result
        end

        private
        
        def subnets(*subnets)
          @result.subnets = subnets
        end

        def security_groups(*security_groups)
          @result.security_groups = security_groups
        end

        def scheme(scheme)
          @result.scheme = scheme
        end

        def tags(tags)
          @result.tags = tags.map { |k, v| { key: k, value: v } }
        end

        def ip_address_type(ip_address_type)
          @result.ip_address_type = ip_address_type
        end

        def attributes(&block)
          @result.attributes = Attributes.new(@context, @name, &block).result
        end

        def target_groups(&block)
          @result.target_groups = TargetGroups.new(@context, @name, &block).result
        end
      
        def listeners(&block)
          @result.listeners = Listeners.new(@context, @name, &block).result
        end
      end
    end
  end
end
