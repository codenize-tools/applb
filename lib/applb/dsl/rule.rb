module Applb
  class DSL
    class EC2
      class LoadBalancer
        class Listeners
          class Listener
            class Rules
              class Rule
                include Applb::DSL::Checker

                class Result
                  ATTRIBUTES = %i/priority actions conditions listener_arn rule_arn/
                  attr_accessor *ATTRIBUTES

                  def initialize(context, listener)
                    @context = context
                    @options = context.options
                    @listener = listener
                  end

                  def aws(aws_rule)
                    @aws_rule = aws_rule
                    self
                  end

                  def to_h
                    Hash[ATTRIBUTES.sort.map { |name| [name, public_send(name)] }]
                  end

                  def create
                    Applb.logger.info("Create rule #{conditions.first[:values].first}")
                    return if @options[:dry_run]

                    Applb.logger.debug("create rule with option blow.")
                    Applb.logger.debug(create_option.pretty_inspect)
                    rule = client.create_rule(create_option).rules.first
                    rule_arn = rule.rule_arn
                    rule
                  end

                  def modify
                    dsl_hash = to_diff_h
                    aws_hash = to_diff_h_aws
                    result = nil

                    # modify rule
                    if dsl_hash != aws_hash
                      Applb.logger.info("Modify rule #{@aws_rule.rule_arn}")
                      Applb.logger.info("<diff>\n#{Applb::Utils.diff(aws_hash, dsl_hash, color: @options[:color])}")

                      unless @options[:dry_run]
                        result = client.modify_rule(modify_option).rules.first
                      end
                    end

                    # modify rule priority
                    if priority.to_s != @aws_rule.priority
                      Applb.logger.info("Modify priority #{@aws_rule.priority} to #{priority}")
                      Applb.logger.info("<diff>\n#{Applb::Utils.diff(@aws_rule.priority, priority, color: @options[:color])}")

                      unless @options[:dry_run]
                        rule_priority_option = {
                          rule_priorities: [{ rule_arn: @aws_rule.rule_arn, priority: priority}]
                        }
                        result = client.set_rule_priorities(rule_priority_option).rules.first
                      end
                    end
                    result
                  end

                  private

                  def create_option
                    options = to_h.reject { |k, v| k == :rule_arn }
                    options[:actions].first.delete(:target_group_name)
                    options
                  end

                  def modify_option
                    options = to_h.reject { |k, v| k == :priority }
                    options[:rule_arn] = @aws_rule.rule_arn
                    options[:actions].first.delete(:target_group_name)
                    options.delete(:listener_arn)
                    options
                  end

                  def to_diff_h
                    Applb::Utils.normalize_hash(to_h).reject do |k, v|
                      %i/:priority listener_arn rule_arn priority/.include?(k)
                    end.tap { |h| h[:actions].first.delete(:target_group_name) }
                  end

                  def to_diff_h_aws
                    Applb::Utils.normalize_hash(@aws_rule.to_h).reject do |k, v|
                      %i/priority is_default rule_arn/.include?(k)
                    end
                  end

                  def needs_modify?
                    to_diff_h != to_diff_h_aws
                  end

                  def client
                    @client ||= Applb::ClientWrapper.new(@options)
                  end
                end

                def initialize(context, listener, &block)
                  @context = context.dup
                  @listener = listener

                  @result = Result.new(context, listener)
                  @result.actions = []
                  @result.conditions =  []

                  instance_eval(&block)
                end

                def result
                  required(:conditions, @result.conditions)
                  required(:priority, @result.priority)
                  required(:actions, @result.actions)
                  @result
                end
                
                private

                def rule_arn(rule_arn)
                  @result.rule_arn = rule_arn
                end

                def priority(priority)
                  @result.priority = priority
                end

                def actions(target_group_name: nil, target_group_arn: nil, type:)
                  @result.actions << {
                    target_group_arn: target_group_arn,
                    target_group_name: target_group_name,
                    type: type,
                  }
                end

                def conditions(field: , values:)
                  @result.conditions << {
                    field: field,
                    values: values,
                  }
                end
              end
            end
          end
        end
      end
    end
  end
end
