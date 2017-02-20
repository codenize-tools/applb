require 'spec_helper'
require 'applb/dsl'

RSpec.describe Applb::DSL::EC2::LoadBalancer::Attributes do
  let(:context) { {} }
  let(:lb_name) { 'alb' }
  let(:access_logs_args) do
    {
      s3_enabled: true,
      s3_bucket: 'bucket',
      s3_prefix: 'prefix'
    }
  end

  let(:idle_timeout_args) { { timeout_seconds: 10 } }
  let(:deletion_protection_args) { { enabled: true } }

  describe '#initialize' do
    context 'no values set' do
      subject(:attrs) do
        Applb::DSL::EC2::LoadBalancer::Attributes.new(context, lb_name) do
        end.result
      end

      it 'should return default value' do
        s3_enabled = attrs.find { |attr| attr[:key] == 'access_logs.s3.enabled' }[:value]
        s3_bucket = attrs.find { |attr| attr[:key] == 'access_logs.s3.bucket' }[:value]
        s3_prefix = attrs.find { |attr| attr[:key] == 'access_logs.s3.prefix' }[:value]
        expect(s3_enabled).to eq(false)
        expect(s3_bucket).to eq('')
        expect(s3_prefix).to eq('')

        idle_timeout = attrs.find { |attr| attr[:key] == 'idle_timeout.timeout_seconds' }[:value]
        expect(idle_timeout).to eq(60)

        deletion_protection_enabled = attrs.find { |attr| attr[:key] == 'deletion_protection.enabled' }[:value]
        expect(deletion_protection_enabled).to eq(false)
      end
    end

    context 'with all values set' do
      subject(:attrs) do
        Applb::DSL::EC2::LoadBalancer::Attributes.new(context, lb_name) do
          access_logs(
            s3_enabled: true,
            s3_bucket: 'bucket',
            s3_prefix: 'prefix'
          )
          idle_timeout(timeout_seconds: 10)
          deletion_protection(enabled: true)
        end.result
      end

      it 'should return dsl value' do
        s3_enabled = attrs.find { |attr| attr[:key] == 'access_logs.s3.enabled' }[:value]
        s3_bucket = attrs.find { |attr| attr[:key] == 'access_logs.s3.bucket' }[:value]
        s3_prefix = attrs.find { |attr| attr[:key] == 'access_logs.s3.prefix' }[:value]
        expect(s3_enabled).to eq(true)
        expect(s3_bucket).to eq('bucket')
        expect(s3_prefix).to eq('prefix')

        idle_timeout = attrs.find { |attr| attr[:key] == 'idle_timeout.timeout_seconds' }[:value]
        expect(idle_timeout).to eq(10)

        deletion_protection_enabled = attrs.find { |attr| attr[:key] == 'deletion_protection.enabled' }[:value]
        expect(deletion_protection_enabled).to eq(true)
      end
    end
  end
end
