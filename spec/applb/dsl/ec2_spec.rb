require 'spec_helper'
require 'applb/dsl'

RSpec.describe Applb::DSL::EC2 do
  let(:context) { Hashie::Mash.new(options: {}) }
  let(:vpc_id) { 'vpc-00000000' }
  let(:lbs) { [] }

  describe('#initialize') do
    context 'no values set' do
      subject(:ec2) do
        Applb::DSL::EC2.new(context, vpc_id, lbs) do
        end.result
      end

      it 'should return default value' do
        expect(ec2.vpc_id).to eq(vpc_id)
      end
    end

    context 'with all values set' do
      subject(:ec2) do
        Applb::DSL::EC2.new(context, vpc_id, lbs) do
          elb_v2 "alb" do
            subnets('subnet-00000000')
            security_groups('sg-00000000')
          end
        end.result
      end

      it 'should return default value' do
        expect(ec2.vpc_id).to eq(vpc_id)
        expect(ec2.load_balancers.length).to eq(1)
        lb = ec2.load_balancers.first
        expect(lb.name).to eq('alb')
        expect(lb.subnets).to eq(['subnet-00000000'])
        expect(lb.security_groups).to eq(['sg-00000000'])
      end
    end
  end
end
