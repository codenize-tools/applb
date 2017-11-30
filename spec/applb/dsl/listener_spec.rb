require 'spec_helper'
require 'applb/dsl'
require 'aws-sdk-elasticloadbalancingv2'
require 'pry'

RSpec.describe Applb::DSL::EC2::LoadBalancer::Listeners::Listener do
  let(:context) { Hashie::Mash.new(options: { color: true}) }
  let(:lb_name) { 'alb' }

  describe '#initialize' do
    context 'no values set' do
      subject(:listener) do
        Applb::DSL::EC2::LoadBalancer::Listeners::Listener.new(context, lb_name) do
        end.result
      end

      it 'should return default value' do
        expect(listener.certificates).to be_nil
        expect(listener.ssl_policy).to be_nil
        expect(listener.port).to be_nil
        expect(listener.protocol).to be_nil
        expect(listener.default_actions).to be_nil
        expect(listener.rules).to be_nil
      end
    end

    context 'with http values set' do
      subject(:listener) do
        Applb::DSL::EC2::LoadBalancer::Listeners::Listener.new(context, lb_name) do
          port 80
          protocol "HTTP"
          default_actions(
            target_group_name: "target",
	    type: "forward",
          )

          rules do
          end
        end.result
      end

      it 'should return DSL value' do
        expect(listener.certificates).to be_nil
        expect(listener.ssl_policy).to be_nil
        expect(listener.port).to eq(80)
        expect(listener.protocol).to eq('HTTP')
        action = listener.default_actions.first
        expect(action[:target_group_name]).to eq('target')
        expect(action[:target_group_arn]).to be_nil
        expect(action[:type]).to eq('forward')
        expect(listener.rules).to be_nil
      end
    end

    context 'with https values set' do
      subject(:listener) do
        Applb::DSL::EC2::LoadBalancer::Listeners::Listener.new(context, lb_name) do
          certificates certificate_arn: "arn:aws:acm:ap-northeast-1:000000000000:certificate/00000000-0000-0000-0000-000000000000"
          certificates certificate_arn: "arn:aws:acm:ap-northeast-1:000000000000:certificate/00000000-0000-0000-0000-000000000001"
	  ssl_policy "ELBSecurityPolicy-2016-08"
	  port 443
	  protocol "HTTPS"

          default_actions(
            target_group_name: "target",
            target_group_arn: "arn:aws:elasticloadbalancing:ap-northeast-1:000000000000:targetgroup/target/0000000000000000",
	    type: "forward",
          )

          rules do
          end
        end.result
      end

      let(:certificate_arn) { 'arn:aws:acm:ap-northeast-1:000000000000:certificate/00000000-0000-0000-0000-000000000000' }
      let(:certificate_arn1) { 'arn:aws:acm:ap-northeast-1:000000000000:certificate/00000000-0000-0000-0000-000000000001' }
      let(:target_group_arn) { 'arn:aws:elasticloadbalancing:ap-northeast-1:000000000000:targetgroup/target/0000000000000000' }
      let(:ssl_policy) { 'ELBSecurityPolicy-2016-08' }
      it 'should return DSL value' do
        certificate = listener.certificates.first
        expect(certificate[:certificate_arn]).to eq(certificate_arn)
        certificate = listener.certificates[1]
        expect(certificate[:certificate_arn]).to eq(certificate_arn1)

        expect(listener.ssl_policy).to eq(ssl_policy)
        expect(listener.port).to eq(443)
        expect(listener.protocol).to eq('HTTPS')
        action = listener.default_actions.first
        expect(action[:target_group_name]).to eq('target')
        expect(action[:target_group_arn]).to eq(target_group_arn)
        expect(action[:type]).to eq('forward')
        expect(listener.rules).to be_nil
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
    end

    after(:all) do
      @client.describe_listeners(
        load_balancer_arn: @lb.load_balancer_arn
      ).listeners.each do |listener|
        @client.delete_listener(listener_arn: listener.listener_arn)
      end

      if @tg
        @client.delete_target_group(target_group_arn: @tg.target_group_arn)
      end

      if @lb
        @client.delete_load_balancer(load_balancer_arn: @lb.load_balancer_arn)
      end
    end

    let(:listener) do
      Applb::DSL::EC2::LoadBalancer::Listeners::Listener.new(context, lb_name) do
	port 80
	protocol "HTTP"

        default_actions(
          target_group_name: 'applb-test-target-001',
	  type: "forward",
        )

        rules do
        end
      end.result
    end

    it 'should create listener' do
      listener.load_balancer_arn = @lb.load_balancer_arn
      listener.default_actions.first[:target_group_arn] = @tg.target_group_arn
      @result = listener.create
      expect(@result.port).to eq(80)
      expect(@result.protocol).to eq('HTTP')
      action = @result.default_actions.first
      expect(action.target_group_arn).to eq(@tg.target_group_arn)
      expect(action.type).to eq('forward')
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
        default_actions: [{target_group_arn: @tg.target_group_arn, type: 'forward'}],
        load_balancer_arn: @lb.load_balancer_arn,
        port: 80,
        protocol: 'HTTP',
      ).listeners.first
    end

    after(:all) do
      @client.describe_listeners(
        load_balancer_arn: @lb.load_balancer_arn
      ).listeners.each do |listener|
        @client.delete_listener(
          listener_arn: listener.listener_arn
        )
      end

      if @tg
        @client.delete_target_group(
          target_group_arn: @tg.target_group_arn
        )
      end

      if @lb
        @client.delete_load_balancer(
          load_balancer_arn: @lb.load_balancer_arn
        )
      end
    end

    let(:listener) do
      Applb::DSL::EC2::LoadBalancer::Listeners::Listener.new(context, lb_name) do
        certificates certificate_arn: AWS_CONFIG[:certificate_arn]
	ssl_policy "ELBSecurityPolicy-2016-08"
	port 443
	protocol "HTTPS"

        default_actions(
          target_group_name: "applb-test-target-001",
	  type: "forward",
        )

        rules do
        end
      end.result
    end

    it 'should modify listener' do
      listener.load_balancer_arn = @lb.load_balancer_arn
      listener.default_actions.first[:target_group_arn] = @tg.target_group_arn
      @result = listener.aws(@listener).modify
      expect(@result.certificates.first[:certificate_arn]).to eq(AWS_CONFIG[:certificate_arn])
      expect(@result.port).to eq(443)
      expect(@result.protocol).to eq('HTTPS')
      action = @result.default_actions.first
      expect(action.target_group_arn).to eq(@tg.target_group_arn)
      expect(action.type).to eq('forward')
    end
  end
end
