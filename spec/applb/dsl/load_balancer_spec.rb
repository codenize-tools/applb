require 'spec_helper'
require 'aws-sdk-elasticloadbalancingv2'
require 'applb/dsl'

RSpec.describe Applb::DSL::EC2::LoadBalancer do
  let(:context) { Hashie::Mash.new(options: { color: true}) }
  let(:lb_name) { 'alb' }
  let(:vpc_id) { 'vpc-00000000' }

  describe '#initialize' do
    context 'no values set' do
      subject(:lb) do
        Applb::DSL::EC2::LoadBalancer.new(context, lb_name, vpc_id) do
          subnets('subnet-0000000', 'subnet-0000001')
          security_groups('sg-00000000')
        end.result
      end

      it 'should return default value' do
        expect(lb.name).to eq(lb_name)
        expect(lb.subnets).to eq(['subnet-0000000', 'subnet-0000001'])
        expect(lb.security_groups).to eq(['sg-00000000'])
        expect(lb.scheme).to be_nil
        expect(lb.tags).to be_nil
        expect(lb.ip_address_type).to be_nil
        expect(lb.attributes.length).to eq(5)
        expect(lb.target_groups).to be_empty
        expect(lb.listeners).to be_empty
        expect(lb.load_balancer_arn).to be_nil
      end
    end

    context 'with all values set' do
      subject(:lb) do
        Applb::DSL::EC2::LoadBalancer.new(context, lb_name, vpc_id) do
          subnets("subnet-00000000", "subnet-00000001")
          security_groups("sg-00000000")
          scheme("internal")
          ip_address_type("ipv4")
          tags("Project" => "Applb")

          attributes do
            access_logs(
              s3_enabled: false,
	      s3_bucket: nil,
	      s3_prefix: nil,
            )
            idle_timeout timeout_seconds: 60
            deletion_protection enabled: false
          end

          target_groups do
            target_group "applb-test-target-001" do
              protocol "HTTP"
              port 80
              vpc_id "vpc-00000000"
              health_check_interval_seconds 30
              health_check_path "/hello/revision"
              health_check_port "traffic-port"
              health_check_protocol "HTTP"
              health_check_timeout_seconds 5
              healthy_threshold_count 2
              unhealthy_threshold_count 2
              matcher http_code: "200"
            end
          end

          listeners do
            listener do
	      port 80
	      protocol "HTTP"

              default_actions(
                target_group_name: "applb-test-target-001",
	        type: "forward",
              )

              rules do
	        rule do
                  priority "1"
                  
	          actions(
                    target_group_name: "applb-test-target-001",
	            type: "forward",
	          )

	          conditions(
	            field: "path-pattern",
	            values: ["/admin/*"],
	          )
	        end

	        rule do
                  priority "1"
                  
	          actions(
                    target_group_name: "applb-test-target-001",
	            type: "forward",
	          )
                  
	          conditions(
	            field: "path-pattern",
	            values: ["/user/*"],
	          )
	        end
              end
            end
          end
        end.result
      end

      it 'should return DSL value' do
        expect(lb.name).to eq(lb_name)
        expect(lb.subnets).to eq(['subnet-00000000', 'subnet-00000001'])
        expect(lb.security_groups).to eq(['sg-00000000'])
        expect(lb.scheme).to eq('internal')
        expect(lb.ip_address_type).to eq('ipv4')
        expect(lb.tags).to eq([{key: 'Project', value: 'Applb'}])
        expect(lb.attributes.length).to eq(5)
        expect(lb.target_groups.length).to eq(1)
        expect(lb.target_groups.first.name).to eq('applb-test-target-001')
        expect(lb.listeners.length).to eq(1)
      end
    end
  end

  describe '#create' do
    after(:all) do
      client = Aws::ElasticLoadBalancingV2::Client.new
      client.describe_load_balancers(
        names: ['applb-test-001']
      ).load_balancers.each do |lb|
        client.delete_load_balancer(load_balancer_arn: lb.load_balancer_arn)
      end
    end

    subject(:lb) do
      Applb::DSL::EC2::LoadBalancer.new(context, lb_name, vpc_id) do
        subnets(*AWS_CONFIG[:subnets])
        security_groups(*AWS_CONFIG[:security_groups])
        scheme("internal")
        ip_address_type("ipv4")
        tags("Project" => "Applb")
      end.result.create
    end

    let(:lb_name) { 'applb-test-001' }

    it 'should create load balancer' do
      expect(lb.availability_zones.map { |h| h[:subnet_id] }.sort).to eq(AWS_CONFIG[:subnets].sort)
      expect(lb.security_groups.sort).to eq(AWS_CONFIG[:security_groups].sort)
      expect(lb.scheme).to eq('internal')
      expect(lb.ip_address_type).to eq('ipv4')
      expect(lb.load_balancer_name).to eq(lb_name)
      expect(lb.type).to eq('application')
      expect(lb.vpc_id).to eq(AWS_CONFIG[:vpc_id])
    end
  end

  describe '#modify' do
    before(:all) do
      @client = Aws::ElasticLoadBalancingV2::Client.new
      @aws_lb = @client.create_load_balancer(
        name: 'applb-test-001',
        subnets: AWS_CONFIG[:subnets],
        security_groups: [AWS_CONFIG[:default_security_group]],
      ).load_balancers.first
    end

    after(:all) do
      @client.describe_load_balancers(
        names: ['applb-test-001']
      ).load_balancers.each do |lb|
        @client.modify_load_balancer_attributes(
          load_balancer_arn: lb.load_balancer_arn,
          attributes: [{key: 'deletion_protection.enabled', value: 'false'}],
        )
        @client.delete_load_balancer(load_balancer_arn: lb.load_balancer_arn)
      end
    end

    subject(:lb) do
      Applb::DSL::EC2::LoadBalancer.new(context, lb_name, vpc_id) do
        subnets(*AWS_CONFIG[:another_subnets])
        security_groups(*AWS_CONFIG[:security_groups])
        scheme("internet-facing")
        ip_address_type("dualstack")
        tags("Project" => "Applb")
        attributes do
          access_logs({
            s3_enabled: false,
	    s3_bucket: nil,
	    s3_prefix: nil,
          })
          idle_timeout timeout_seconds: 30
          deletion_protection enabled: true
        end
      end.result
    end

    let(:lb_name) { 'applb-test-001' }

    it 'should modify load balancer' do
      lb.aws(@aws_lb)

      azs = lb.modify_subnets.sort_by { |az| az.subnet_id }
      expect(azs[0].subnet_id).to eq(AWS_CONFIG[:another_subnets].sort[0])
      expect(azs[1].subnet_id).to eq(AWS_CONFIG[:another_subnets].sort[1])

      sg_ids = lb.modify_security_groups.sort
      expect(sg_ids[0]).to eq(AWS_CONFIG[:security_groups].sort[0])
      expect(sg_ids[1]).to eq(AWS_CONFIG[:security_groups].sort[1])
      expect(lb.modify_ip_address_type).to eq('dualstack')

      attrs = lb.modify_load_balancer_attributes
      # access_logs is not modified due to difficulty to prepare s3 bucket
      s3_enabled = attrs.find { |attr| attr[:key] == 'access_logs.s3.enabled' }[:value]
      s3_bucket = attrs.find { |attr| attr[:key] == 'access_logs.s3.bucket' }[:value]
      s3_prefix = attrs.find { |attr| attr[:key] == 'access_logs.s3.prefix' }[:value]
      expect(s3_enabled).to eq('false')
      expect(s3_bucket).to eq('')
      expect(s3_prefix).to eq('')

      idle_timeout = attrs.find { |attr| attr[:key] == 'idle_timeout.timeout_seconds' }[:value]
      expect(idle_timeout).to eq('30')

      deletion_protection_enabled = attrs.find { |attr| attr[:key] == 'deletion_protection.enabled' }[:value]
      expect(deletion_protection_enabled).to eq('true')
    end
  end
end
