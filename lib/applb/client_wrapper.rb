require 'forwardable'
require 'aws-sdk'

module Applb
  class ClientWrapper
    extend Forwardable
    def_delegators :@client, *%i/
      describe_load_balancer_attributes describe_tags set_subnets set_security_groups
      set_ip_address_type modify_load_balancer_attributes create_target_group
      modify_target_group delete_target_group create_listener modify_listener
      delete_listener describe_rules delete_rule create_load_balancer
      create_rule modify_rule set_rule_priorities describe_target_groups/

    def initialize(options)
      @includes = options[:includes] || []
      @excludes = options[:excludes] || []
      @client = Aws::ElasticLoadBalancingV2::Client.new
    end

    def load_balancers
      results = []
      next_marker = nil
      begin
        resp = @client.describe_load_balancers(marker: next_marker)
        resp.load_balancers.each do |lb|
          results << lb if target?(lb)
        end
        next_marker = resp.next_marker
      end while next_marker
      results
    end

    def delete_load_balancer(arn)
      @client.delete_load_balancer(load_balancer_arn: arn)
    end

    def target_groups(*argv)
      results = []
      next_marker = nil
      begin
        resp = @client.describe_target_groups(*argv)
        results.push(*resp.target_groups)
      end while next_marker
      results
    end

    def listeners(*argv)
      results = []
      next_marker = nil
      begin
        resp = @client.describe_listeners(*argv)
        results.push(*resp.listeners)
      end while next_marker
      results
    end

    def rules(*argv)
      results = []
      next_marker = nil
      begin
        resp = @client.describe_rules(*argv)
        results.push(*resp.rules)
      end while next_marker
      results
    end

    def load_balancer_attributes(*argv)
      resp = @client.describe_load_balancer_attributes(*argv)
      resp.attributes
    end
    
    private

    def target?(lb)
      name = lb.load_balancer_name
      unless @includes.empty?
        return @includes.include?(name)
      end
      unless @excludes.empty?
        return !@excludes.any? { |regex| name =~ regex }
      end
      true
    end
  end
end
