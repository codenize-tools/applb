require 'spec_helper'
require 'aws-sdk-elasticloadbalancingv2'
require 'applb/dsl'

RSpec.describe Applb::DSL::EC2::LoadBalancer::Listeners::Listener::Rules::Rule do
  let(:context) { Hashie::Mash.new(options: { color: true}) }
  let(:listener) { 'listener' }

  describe '#initialize' do
    context 'no values set' do
      subject(:rule) do
        Applb::DSL::EC2::LoadBalancer::Listeners::Listener::Rules::Rule.new(context, listener) do
        end.result
      end

      it 'should return default value' do
        expect { rule }.to raise_error(Applb::DSL::Checker::ValidationError)
      end
    end

    context 'with all values set' do
      subject(:rule) do
        Applb::DSL::EC2::LoadBalancer::Listeners::Listener::Rules::Rule.new(context, listener) do
          priority "1"

	  actions(
            target_group_name: "applb-test-target-001",
	    type: "forward",
	  )

	  conditions(
	    field: "path-pattern",
	    values: ["/admin/*"],
	  )
        end.result
      end

      it 'should return default value' do
        expect(rule.priority).to eq('1')
        expect(rule.actions).to eq([{ target_group_arn: nil, target_group_name: 'applb-test-target-001', type: 'forward' }])
        expect(rule.conditions).to eq([{field: 'path-pattern', values: ['/admin/*']}])
        expect(rule.listener_arn).to be_nil
        expect(rule.rule_arn).to be_nil
      end
    end
  end

  describe '#create' do
    before(:all) do
      @client = Aws::ElasticLoadBalancingV2::Client.new
      @lb = @client.create_load_balancer(
        name: 'applb-test-alb-001',
        subnets: AWS_CONFIG[:subnets],
      ).load_balancers.first

      @tg = @client.create_target_group(
        name: 'applb-test-target-001',
        port: 80,
        protocol: 'HTTP',
        vpc_id: AWS_CONFIG[:vpc_id],
      ).target_groups.first

      @listener = @client.create_listener(
        default_actions: [{ target_group_arn: @tg.target_group_arn, type: 'forward' }],
        load_balancer_arn: @lb.load_balancer_arn,
        port: 80,
        protocol: 'HTTP',
      ).listeners.first
    end

    after(:all) do
      if @listener
        @client.delete_listener(listener_arn: @listener.listener_arn)
      end

      if @tg
        @client.delete_target_group(target_group_arn: @tg.target_group_arn)
      end

      if @lb
        @client.delete_load_balancer(load_balancer_arn: @lb.load_balancer_arn)
      end
    end

    let(:rule) do
      Applb::DSL::EC2::LoadBalancer::Listeners::Listener::Rules::Rule.new(context, listener) do
        priority "1"

	actions(
          target_group_name: "applb-test-target-001",
	  type: "forward",
	)

	conditions(
	  field: "path-pattern",
	  values: ["/admin/*"],
	)
      end.result
    end

    it 'should create rule' do
      rule.listener_arn = @listener.listener_arn
      rule.actions.first[:target_group_arn] = @tg.target_group_arn
      result = rule.create
      expect(result.priority).to eq('1')

      condition = result.conditions.first
      expect(condition.field).to eq('path-pattern')
      expect(condition.values).to eq(['/admin/*'])

      action = result.actions.first
      expect(action.target_group_arn).to eq(@tg.target_group_arn)
      expect(action.type).to eq('forward')

      expect(result.is_default).to eq(false)
    end
  end

  describe '#modify' do
    before(:all) do
      @client = Aws::ElasticLoadBalancingV2::Client.new
      @lb = @client.create_load_balancer(
        name: 'applb-test-alb-001',
        subnets: AWS_CONFIG[:subnets],
      ).load_balancers.first

      @tg = @client.create_target_group(
        name: 'applb-test-target-001',
        port: 80,
        protocol: 'HTTP',
        vpc_id: AWS_CONFIG[:vpc_id],
      ).target_groups.first

      @listener = @client.create_listener(
        default_actions: [{ target_group_arn: @tg.target_group_arn, type: 'forward' }],
        load_balancer_arn: @lb.load_balancer_arn,
        port: 80,
        protocol: 'HTTP',
      ).listeners.first

      @rule = @client.create_rule(
        actions: [{ target_group_arn: @tg.target_group_arn, type: 'forward' }],
        conditions: [{ field: 'path-pattern', values: ['/user/*'] }],
        listener_arn: @listener.listener_arn,
        priority: 10,
      ).rules.first
    end

    after(:all) do
      if @listener
        @client.delete_listener(listener_arn: @listener.listener_arn)
      end

      if @tg
        @client.delete_target_group(target_group_arn: @tg.target_group_arn)
      end

      if @lb
        @client.delete_load_balancer(load_balancer_arn: @lb.load_balancer_arn)
      end
    end

    let(:rule) do
      Applb::DSL::EC2::LoadBalancer::Listeners::Listener::Rules::Rule.new(context, listener) do
        priority "1"

	actions(
          target_group_name: "applb-test-target-001",
	  type: "forward",
	)

	conditions(
	  field: "path-pattern",
	  values: ["/admin/*"],
	)
      end.result
    end

    it 'should create rule' do
      rule.aws(@rule)
      rule.listener_arn = @listener.listener_arn
      rule.actions.first[:target_group_arn] = @tg.target_group_arn
      result = rule.modify
      expect(result.priority).to eq('1')

      condition = result.conditions.first
      expect(condition.field).to eq('path-pattern')
      expect(condition.values).to eq(['/admin/*'])

      action = result.actions.first
      expect(action.target_group_arn).to eq(@tg.target_group_arn)
      expect(action.type).to eq('forward')

      expect(result.is_default).to eq(false)
    end
  end
end
