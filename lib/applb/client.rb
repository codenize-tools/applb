require 'pp'
require 'applb/client_wrapper'
require 'applb/converter'
require 'applb/dsl'
require 'applb/dsl/load_balancer'
require 'applb/error'
require 'applb/filterable'
require 'applb/utils'

module Applb
  class Client
    include Filterable

    MAGIC_COMMENT = <<-EOS
# -*- mode: ruby -*-
# vi: set ft=ruby :
    EOS

    def initialize(filepath, options = {})
      @filepath = filepath
      @options = options
    end

    def apply
      dsl = load_file(@filepath)

      dsl_ec2s = dsl.ec2s
      aws_ec2s = client.load_balancers.group_by(&:vpc_id)

      dsl.ec2s.each do |vpc_id, dsl_ec2|
        aws_ec2 = aws_ec2s[vpc_id] || []

        traverse_ec2(vpc_id, dsl_ec2, aws_ec2)
      end
    end

    def export
      result = {}

      lbs = client.load_balancers
      tags_by_arn = describe_tags(lbs)
      
      lbs.each do |lb|
        attributes = client.load_balancer_attributes(load_balancer_arn: lb.load_balancer_arn)
        target_groups = describe_target_groups(lb)
        listeners = describe_listeners(lb)
        rules_by_listener_arn = listeners.each_with_object({}) do |listener, rules_by_listener_arn|
          rules_by_listener_arn[listener.listener_arn] = describe_rules(listener)
        end
        (result[lb.vpc_id] ||= {})[lb.load_balancer_name] = export_lb(
          lb,
          attributes,
          target_groups,
          listeners,
          rules_by_listener_arn,
        )
      end

      path = Pathname.new(@filepath)
      base_dir = path.parent
      if @options[:split_more]
        result.each do |vpc_id, lbs_by_name|
          lbs_by_name.each do |name, lbs|
            Converter.new({vpc_id => {name => lbs}}, tags_by_arn).convert do |vpc_id, dsl|
              alb_base_dir = base_dir.join("#{vpc_id}")
              FileUtils.mkdir_p(alb_base_dir)
              alb_file = alb_base_dir.join("#{name}.alb")
              Applb.logger.info("export #{alb_file}")
              open(alb_file, 'wb') do |f|
                f.puts MAGIC_COMMENT
                f.puts dsl
              end
            end
          end
        end
      elsif @options[:split]
        Converter.new(result, tags_by_arn).convert do |vpc_id, dsl|
          FileUtils.mkdir_p(base_dir)
          alb_file = base_dir.join("#{vpc_id}.alb")
          Applb.logger.info("export #{alb_file}")
          open(alb_file, 'wb') do |f|
            f.puts MAGIC_COMMENT
            f.puts dsl
          end
        end
      else
        dsls = []
        Converter.new(result, tags_by_arn).convert do |vpc_id, dsl|
          dsls << dsl
        end

        FileUtils.mkdir_p(base_dir)
        Applb.logger.info("export #{path}")
        open(path, 'wb') do |f|
          f.puts MAGIC_COMMENT
          f.puts dsls.join("\n")
        end
      end
    end

    private

    def load_file(file)
      open(file) do |f|
        DSL.define(f.read, file, @options).result
      end
    end

    def traverse_ec2(vpc_id, dsl_ec2, aws_ec2)
      dsl_lb_by_name = dsl_ec2.load_balancers.group_by(&:name).each_with_object({}) do |(k, v), h|
        h[k] = v.first if target?(k)
      end
      aws_lb_by_name = aws_ec2.group_by(&:load_balancer_name).each_with_object({}) do |(k, v), h|
        h[k] = v.first if target?(k)
      end

      # create
      dsl_lb_by_name.reject { |n| aws_lb_by_name[n] }.each do |name, dsl_lb|
        aws_lb_by_name[name] = dsl_lb.create
      end

      # modify
      dsl_lb_by_name.each do |name, dsl_lb|
        next unless aws_lb = aws_lb_by_name.delete(name)

        dsl_lb.aws(aws_lb)
        traverse_lb(dsl_lb, aws_lb)
      end

      # delete
      aws_lb_by_name.each do |name, aws_lb|
        Applb.logger.info "Delete ELB v2 #{name}"
        aws_tgs = client.describe_target_groups(
          load_balancer_arn: aws_lb.load_balancer_arn,
        ).target_groups
        unless @options[:dry_run]
          client.delete_load_balancer(aws_lb.load_balancer_arn)
          # wait until load_balancer is deleted
          sleep 3
        end
        aws_tgs.each do |tg|
          Applb.logger.info "Delete target_group associated #{tg.target_group_name}"
          next if @options[:dry_run]
          client.delete_target_group(
            target_group_arn: tg.target_group_arn,
          )
        end
      end
    end

    def traverse_lb(dsl_lb, aws_lb)
      dsl_lb.modify_subnets
      dsl_lb.modify_security_groups
      dsl_lb.modify_ip_address_type
      dsl_lb.modify_load_balancer_attributes

      traverse_target_groups(dsl_lb, aws_lb)
      traverse_listeners(dsl_lb, aws_lb)
    end

    def traverse_target_groups(dsl_lb, aws_lb)
      aws_tg_by_name = @client.target_groups(load_balancer_arn: aws_lb.load_balancer_arn).group_by(&:target_group_name).each_with_object({}) do |(k, v), h|
        h[k] = v.first
      end
      dsl_tg_by_name = dsl_lb.target_groups.group_by(&:name).each_with_object({}) do |(k, v), h|
        h[k] = v.first
      end

      # create
      dsl_tg_by_name.reject { |n, _| aws_tg_by_name[n] }.each do |name, dsl_tg|
        aws_tg_by_name[name] = dsl_tg.create
      end

      # modify
      dsl_tg_by_name.each do |name, dsl_tg|
        aws_tg = aws_tg_by_name.delete(name)
        next unless aws_tg

        dsl_tg.aws(aws_tg).modify
      end

      aws_tg_by_name.each do |name, aws_tg|
        Applb.logger.info("Delete target group #{name}")
        next if @options[:dry_run]
        # client.modify_listener({}) TODO remove from listener first
        client.delete_target_group(target_group_arn: aws_tg.target_group_arn)
      end
    end

    def traverse_listeners(dsl_lb, aws_lb)
      aws_listener_by_port = @client.listeners(load_balancer_arn: aws_lb.load_balancer_arn).group_by(&:port).each_with_object({}) do |(k, v), h|
        h[k] = v.first
      end

      aws_target_group_by_name = @client.target_groups.group_by(&:target_group_name).each_with_object({}) do |(k, v), h|
        h[k] = v.first
      end
      aws_target_group_by_arn = aws_target_group_by_name.each_with_object({}) do |(k, v), h|
        h[v.target_group_arn] = v
      end

      dsl_listener_by_port = dsl_lb.listeners.group_by(&:port).each_with_object({}) do |(k, v), h|
        dsl_listener = v.first
        dsl_listener.load_balancer_arn = aws_lb.load_balancer_arn
        h[k] = dsl_listener
      end

      # create
      dsl_listener_by_port.reject { |port, _| aws_listener_by_port[port] }.each do |port, dsl_listener|
        # resolve target_group_arn by target_group_name
        target_group_name = dsl_listener.default_actions.first[:target_group_name]
        if target_group_name
          dsl_listener.default_actions.first[:target_group_arn] = aws_target_group_by_name[target_group_name].target_group_arn
        end
        aws_listener_by_port[port] = dsl_listener.create
      end

      # modify
      dsl_listener_by_port.each do |port, dsl_listener|
        aws_listener = aws_listener_by_port.delete(port)
        next unless aws_listener

        target_group_name = dsl_listener.default_actions.first[:target_group_name]
        if target_group_name
          dsl_listener.default_actions.first[:target_group_arn] = aws_target_group_by_name[target_group_name].target_group_arn
        end
        dsl_listener.aws(aws_listener).modify
        traverse_rule(dsl_listener, aws_listener, aws_target_group_by_name)
      end

      # delete
      aws_listener_by_port.each do |port, aws_listener|
        aws_actions = client.describe_rules(listener_arn: aws_listener.listener_arn).rules.map(&:actions).flatten
        Applb.logger.info("#{aws_lb.load_balancer_name} Delete listener for port #{port}")
        unless @options[:dry_run]
          client.delete_listener(listener_arn: aws_listener.listener_arn)
        end
        (aws_actions + aws_listener.default_actions).each do |action|
          aws_tg = aws_target_group_by_arn.delete(action.target_group_arn)
          next unless aws_tg
          Applb.logger.info("#{aws_lb.load_balancer_name} Delete target_group associated #{aws_tg.target_group_name}")
          next if @options[:dry_run]
          client.delete_target_group(target_group_arn: action.target_group_arn)
        end
      end
    end

    class TargetGroupResolveError < Error
    end

    def traverse_rule(dsl_listener, aws_listener, aws_target_group_by_name)
      dummy_idx = 0
      dsl_rule_by_arn = (dsl_listener.rules || []).each_with_object({}) do |dsl_rule, h|
        # give dummy arn for grouping
        arn = dsl_rule.rule_arn ? dsl_rule.rule_arn : "dummy-#{(dummy_idx += 1)}"
        # set listener_arn here
        dsl_rule.listener_arn = aws_listener.listener_arn
        h[arn] = dsl_rule
      end
      aws_rules = client.describe_rules(listener_arn: aws_listener.listener_arn).rules
      aws_rule_by_arn = aws_rules.reject(&:is_default).group_by(&:rule_arn).each_with_object({}) do |(k, v), h|
        h[k] = v.first
      end

      # create
      dsl_rule_by_arn.reject { |arn, _| aws_rule_by_arn[arn] }.each do |arn, dsl_rule|
        # resolve target_group_arn by target_group_name
        target_group_name = dsl_rule.actions.first[:target_group_name]
        if target_group_name
          Applb.logger.debug("Resolve target_group_arn by target_group_name. -> #{target_group_name}")
          aws_tg = aws_target_group_by_name[target_group_name]
          unless aws_tg
            Applb.logger.error("AWS target groups by name:\n#{aws_target_group_by_name.pretty_inspect}")
            raise TargetGroupResolveError.new("target_group_name #{target_group_name}")
          end
          dsl_rule.actions.first[:target_group_arn] = aws_tg.target_group_arn
        end

        rule = dsl_rule.create
        next if @options[:dry_run]
        dsl_rule_by_arn[rule.rule_arn] = dsl_rule_by_arn.delete(arn)
      end

      # modify
      dsl_rule_by_arn.each do |arn, dsl_rule|
        aws_rule = aws_rule_by_arn.delete(arn)
        next unless aws_rule

        # resolve target_group_arn by target_group_name
        target_group_name = dsl_rule.actions.first[:target_group_name]
        if target_group_name
          Applb.logger.debug("Resolve target_group_arn by target_group_name. -> #{target_group_name}")
          aws_tg = aws_target_group_by_name[target_group_name]
          unless aws_tg
            Applb.logger.error("AWS target groups by name:\n#{aws_target_group_by_name.pretty_inspect}")
            raise TargetGroupResolveError.new("target_group_name #{target_group_name}")
          end
          dsl_rule.actions.first[:target_group_arn] = aws_tg.target_group_arn
        end

        dsl_rule.aws(aws_rule).modify
      end

      # delete
      aws_rule_by_arn.values.each do |aws_rule|
        Applb.logger.info("Delete rule #{aws_rule.conditions.first[:values].first}")
        next if @options[:dry_run]
        Applb.logger.debug("deleting rule_arn #{aws_rule.rule_arn}")
        client.delete_rule(rule_arn: aws_rule.rule_arn)
      end
    end

    # @param [Aws::ElasticLodaBalancingV2::Types::LoadBalancer] lb
    def describe_tags(lbs)
      result = {}
      arns = lbs.map(&:load_balancer_arn)
      unless arns.empty?
        resp = client.describe_tags(resource_arns: lbs.map(&:load_balancer_arn))
        resp.tag_descriptions.each do |tag_desc|
          result[tag_desc.resource_arn] = Hash[tag_desc.tags.map { |tag| [tag.key, tag.value] }]
        end
      end
      result
    end

    def describe_target_groups(lb)
      client.target_groups(load_balancer_arn: lb.load_balancer_arn)
    end

    def describe_listeners(lb)
      client.listeners(load_balancer_arn: lb.load_balancer_arn)
    end

    def describe_rules(listener)
      client.rules(listener_arn: listener.listener_arn)
    end

    # @param [Aws::ElasticLodaBalancingV2::Types::LoadBalancer] lb
    # @param [Array<Types::LoadBalancerAttribute>] attrs
    # @param [Array<Types::TargetGroup>] target_groups
    # @param [Array<Types::Listener>] listeners
    # @param [Hash] rules_by_listener_arn
    def export_lb(lb, attrs, target_groups, listeners, rules_by_listener_arn)
      {
        availability_zones: lb.availability_zones.map { |az| Hash[az.each_pair.to_a] },
        canonical_hosted_zone_id: lb.canonical_hosted_zone_id,
        created_time: lb.created_time,
        dns_name: lb.dns_name,
        ip_address_type: lb.ip_address_type,
        load_balancer_arn: lb.load_balancer_arn,
        load_balancer_name: lb.load_balancer_name,
        scheme: lb.scheme,
        security_groups: lb.security_groups,
        state: lb.state,
        type: lb.type,
        vpc_id: lb.vpc_id,
        attributes: export_attributes(attrs),
        target_groups: target_groups,
        listeners: listeners,
        rules_by_listener_arn: rules_by_listener_arn,
      }
    end

    # @param [Array<Types::LoadBalancerAttribute>] attrs
    def export_attributes(attrs)
      result = {}
      attrs.each do |attr|
        case attr.key
        when 'access_logs.s3.enabled' then
          (result['access_logs'] ||= {s3: {}})[:s3][:enabled] = attr.value
        when 'access_logs.s3.prefix' then
          result['access_logs'] ||= {s3: {}}[:s3][:prefix] = attr.value
        when 'access_logs.s3.bucket' then
          result['access_logs'] ||= {s3: {}}[:s3][:bucket] = attr.value
        else
          result[attr.key] = attr.value
        end
      end
      result
    end

    def client
      @client ||= ClientWrapper.new(@options)
    end
  end
end
