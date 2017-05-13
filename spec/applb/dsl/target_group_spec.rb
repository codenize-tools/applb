require 'spec_helper'
require 'aws-sdk'
require 'applb/dsl'

RSpec.describe Applb::DSL::EC2::LoadBalancer::TargetGroups::TargetGroup do
  let(:context) { Hashie::Mash.new(options: { color: true}) }
  let(:lb) { nil }
  let(:tg_name) { 'target_group' }
  let(:client) { Aws::ElasticLoadBalancingV2::Client.new }

  describe '#initialize' do
    context 'no values set' do
      subject(:tg) do
        Applb::DSL::EC2::LoadBalancer::TargetGroups::TargetGroup.new(context, tg_name, lb) do
          protocol "HTTP"
          port 80
          vpc_id 'vpc-00000000'
        end.result
      end

      it 'should return default value' do
        expect(tg.name).to eq(tg_name)
        expect(tg.protocol).to eq('HTTP')
        expect(tg.port).to eq(80)
        expect(tg.vpc_id).to eq('vpc-00000000')
        expect(tg.health_check_protocol).to be_nil
        expect(tg.health_check_port).to be_nil
        expect(tg.health_check_path).to be_nil
        expect(tg.health_check_interval_seconds).to be_nil
        expect(tg.health_check_timeout_seconds).to be_nil
        expect(tg.healthy_threshold_count).to be_nil
        expect(tg.unhealthy_threshold_count).to be_nil
        expect(tg.matcher).to be_nil
        expect(tg.instances).to be_empty
      end
    end

    context 'with all values set' do
      subject(:tg) do
        Applb::DSL::EC2::LoadBalancer::TargetGroups::TargetGroup.new(context, tg_name, lb) do
          protocol "HTTP"
          port 80
          vpc_id 'vpc-00000000'
          health_check_protocol "HTTP"
          health_check_port "traffic-port"
          health_check_path "/hello/revision"
          health_check_interval_seconds 30
          health_check_timeout_seconds 5
          healthy_threshold_count 2
          unhealthy_threshold_count 2
          matcher http_code: "200"
          instances 'i-00000000000000000'
        end.result
      end

      it 'should return DSL value' do
        expect(tg.name).to eq(tg_name)
        expect(tg.protocol).to eq('HTTP')
        expect(tg.port).to eq(80)
        expect(tg.vpc_id).to eq('vpc-00000000')
        expect(tg.health_check_protocol).to eq('HTTP')
        expect(tg.health_check_port).to eq('traffic-port')
        expect(tg.health_check_path).to eq('/hello/revision')
        expect(tg.health_check_interval_seconds).to eq(30)
        expect(tg.health_check_timeout_seconds).to eq(5)
        expect(tg.healthy_threshold_count).to eq(2)
        expect(tg.unhealthy_threshold_count).to eq(2)
        expect(tg.matcher).to eq({ http_code: '200' })
        expect(tg.instances).to eq(['i-00000000000000000'])
      end
    end
  end

  describe '#create' do
    after do
      client.describe_target_groups(
        names: ['applb-test-target-group-001']
      ).target_groups.each do |tg|
        client.delete_target_group(target_group_arn: tg.target_group_arn)
      end
    end

    subject(:tg) do
      Applb::DSL::EC2::LoadBalancer::TargetGroups::TargetGroup.new(context, tg_name, lb) do
        protocol "HTTP"
        port 80
        vpc_id AWS_CONFIG[:vpc_id]
        health_check_protocol "HTTP"
        health_check_port "traffic-port"
        health_check_path "/hello/revision"
        health_check_interval_seconds 30
        health_check_timeout_seconds 5
        healthy_threshold_count 2
        unhealthy_threshold_count 2
        matcher http_code: "200"
        instances *AWS_CONFIG[:instances].map(&:name)
      end.result
    end

    let(:tg_name) { 'applb-test-target-group-001' }

    it 'should create target group' do
      result = tg.create
      expect(result.protocol).to eq('HTTP')
      expect(result.port).to eq(80)
      expect(result.vpc_id).to eq(AWS_CONFIG[:vpc_id])
      expect(result.health_check_protocol).to eq('HTTP')
      expect(result.health_check_port).to eq('traffic-port')
      expect(result.health_check_path).to eq('/hello/revision')
      expect(result.health_check_interval_seconds).to eq(30)
      expect(result.health_check_timeout_seconds).to eq(5)
      expect(result.healthy_threshold_count).to eq(2)
      expect(result.unhealthy_threshold_count).to eq(2)
      expect(result.matcher.http_code).to eq('200')

      instance_ids = client.describe_target_health(target_group_arn: result.target_group_arn).
        target_health_descriptions.map(&:target).map(&:id)
      expect(instance_ids).to match_array(AWS_CONFIG[:instances].map(&:id))
    end
  end

  describe '#modify' do
    before do
      @tg = client.create_target_group(
        name: 'applb-test-target-group-001',
        protocol: 'HTTP',
        port: 80,
        vpc_id: AWS_CONFIG[:vpc_id],
        health_check_protocol: 'HTTP',
        health_check_port: '80',
        health_check_path: '/',
        health_check_interval_seconds: '60',
        health_check_timeout_seconds: '10',
        healthy_threshold_count: '3',
        unhealthy_threshold_count: '5',
        matcher: { http_code: '200' },
      ).target_groups.first
      client.register_targets(
        target_group_arn: @tg.target_group_arn,
        targets: AWS_CONFIG[:instances].map { |instance| {id: instance.id} }
      )
    end

    after do
      if @tg
        client.delete_target_group(target_group_arn: @tg.target_group_arn)
      end
    end

    subject(:tg) do
      Applb::DSL::EC2::LoadBalancer::TargetGroups::TargetGroup.new(context, tg_name, lb) do
        protocol "HTTP"
        port 80
        vpc_id AWS_CONFIG[:vpc_id]
        health_check_protocol "HTTP"
        health_check_port "traffic-port"
        health_check_path "/hello/revision"
        health_check_interval_seconds 30
        health_check_timeout_seconds 5
        healthy_threshold_count 2
        unhealthy_threshold_count 2
        matcher http_code: "200,301"
        instances *AWS_CONFIG[:another_instances].map(&:name)
      end.result
    end

    let(:tg_name) { 'applb-test-target-group-001' }

    it 'should modify target group' do
      result = tg.aws(@tg).modify
      expect(result.protocol).to eq('HTTP')
      expect(result.port).to eq(80)
      expect(result.vpc_id).to eq(AWS_CONFIG[:vpc_id])
      expect(result.health_check_protocol).to eq('HTTP')
      expect(result.health_check_port).to eq('traffic-port')
      # modify_target_group does not return health_check_path...
      # expect(result.health_check_path).to eq('/hello/revision')
      expect(result.health_check_interval_seconds).to eq(30)
      expect(result.health_check_timeout_seconds).to eq(5)
      expect(result.healthy_threshold_count).to eq(2)
      expect(result.unhealthy_threshold_count).to eq(2)
      expect(result.matcher.http_code).to eq('200,301')

      instance_ids = client.describe_target_health(target_group_arn: result.target_group_arn).
        target_health_descriptions.map(&:target).map(&:id)
      expect(instance_ids).to match_array(AWS_CONFIG[:another_instances].map(&:id))
    end
  end
end
