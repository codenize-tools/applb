# Applb

[![Build Status](https://travis-ci.org/wata-gh/applb.svg)](https://travis-ci.org/wata-gh/applb)

Applb is a tool to manage ELB v2(ALB).
It defines the state of ELB v2(ALB) using DSL, and updates ELB v2(ALB) according to DSL.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'applb'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install applb

## Usage

```
export AWS_ACCESS_KEY_ID='...'
export AWS_SECRET_ACCESS_KEY='...'
export AWS_REGION='ap-northeast-1'
applb -e -o ALBfile  # export ELB v2(ALB)
vi ALBFile
applb -a --dry-run
applb -a             # apply `ALBfile` to ELB
```

## Help

```
Usage: applb [options]
    -h, --help                       Show help
    -v, --debug                      Show debug log
    -a, --apply                      apply DSL
    -e, --export                     export to DSL
    -n, --dry-run                    dry run
    -f, --file FILE                  use selected DSL file
    -s, --split                      split export DSL file to 1 per VPC
        --split-more
                                     split export DSL file to 1 per load balancer
        --no-color
                                     no color
    -i, --include_names NAMES        include ELB v2(ALB) names
    -x, --exclude_names NAMES        exclude ELB v2(ALB) names by regex
```

## ALBfile

```ruby
require 'other/albfile'

ec2 "vpc-XXXXXXXX" do
  elb_v2 "my-app-load-balancer" do
    subnets(
      "subnet-XXXXXXXX",
      "subnet-YYYYYYYY",
    )

    security_groups(
      "sg-XXXXXXXX",
      "sg-YYYYYYYY",
    )

    scheme("internet-facing") # internal or internet-facing

    ip_address_type("ipv4") # ipv4 or dualstack

    attributes do
      # currently applb does not create bucket and set bucket policy.
      # you must create and set bucket policy by yourself.
      access_logs({
        s3_enabled: false,
        s3_bucket: nil,
        s3_prefix: nil,
      })
      idle_timeout timeout_seconds: 60
      deletion_protection enabled: false
    end

    target_groups do
      target_group "my-target-group" do
        protocol "HTTP" # HTTP or HTTPS
        port 80
        vpc_id "vpc-XXXXXXXX"
        health_check_interval_seconds 30
        health_check_path "/healthcheck"
        health_check_port "traffic-port" # specify port number or use traffic-port which indicates the port on which each target receives traffic from the load balancer.
        health_check_protocol "HTTP" # HTTP or HTTPS
        health_check_timeout_seconds 5
        healthy_threshold_count 5
        unhealthy_threshold_count 2
        matcher http_code: "200"
      end

      target_group "my-target-group2" do
        protocol "HTTP"
        port 80
        vpc_id "vpc-XXXXXXXX"
        health_check_interval_seconds 30
        health_check_path "/healthcheck"
        health_check_port "traffic-port"
        health_check_protocol "HTTP"
        health_check_timeout_seconds 5
        healthy_threshold_count 5
        unhealthy_threshold_count 2
        matcher http_code: "200" # if needs multiple values set like 200,302 or 200-299
      end
    end

    listeners do
      # https sample
      listener do
        # if multiple certificates is needed, call certificates method multiple times.
        # eg.
        # certificates certificate_arn: "[certificate arn1]"
        # certificates certificate_arn: "[certificate arn2]"
        certificates certificate_arn: "arn:aws:acm:ap-northeast-1:XXXXXXXXXXXX:certificate/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
        ssl_policy "ELBSecurityPolicy-2015-05"
        port 443
        protocol "HTTPS" # HTTP or HTTPS

        default_actions(
          target_group_name: "my-target-group", # set target_group_name defined above
          # [optional]
          # needs this to avoid unnecessary call of create_target_group.
          target_group_arn: "arn:aws:elasticloadbalancing:ap-northeast-1:XXXXXXXXXXXX:targetgroup/my-target-group/XXXXXXXXXXXXXXXX",
          type: "forward",
        )

        rules do
          # no rules
        end
      end

      # http sample
      listener do
        port 80
        protocol "HTTP"

        default_actions(
          target_group_name: "my-target-group",
          # [optional]
          # needs this to avoid unnecessary call of create_target_group.
          target_group_arn: "arn:aws:elasticloadbalancing:ap-northeast-1:XXXXXXXXXXXX:targetgroup/my-target-group/XXXXXXXXXXXXXXXX",
          type: "forward",
        )

        rules do
          rule do
            # caution!
            # rule_arn is needed to update rule_arn.
            # after created rule_arn you are strongly recommended to write rule_arn.
            rule_arn "arn:aws:elasticloadbalancing:ap-northeast-1:XXXXXXXXXXXX:listener-rule/app/my-app-load-balancer/XXXXXXXXXXXXXXXX/XXXXXXXXXXXXXXXX/XXXXXXXXXXXXXXXX"
            # caution!
            # currently priority is used by set_rule_priorities one by one.
            # this means if priority is conflicted each other, applb fails to modify rule.
            # so it is recommended to modify priority number that is not used yet.
            priority "3"

            actions(
              target_group_name: "my-target-group2",
              # [optional]
              # needs this to avoid unnecessary call of create_target_group.
              target_group_arn: "arn:aws:elasticloadbalancing:ap-northeast-1:XXXXXXXXXXXX:targetgroup/my-target-group2/XXXXXXXXXXXXXXXX",
              type: "forward",
            )

            conditions(
              field: "path-pattern",
              values: ["/admin/*"], # * for 0 or more characters and ? for exactly 1 character
            )
          end

          rule do
            rule_arn "arn:aws:elasticloadbalancing:ap-northeast-1:XXXXXXXXXXXX:listener-rule/app/my-app-load-balancer/XXXXXXXXXXXXXXXX/XXXXXXXXXXXXXXXX/XXXXXXXXXXXXXXXX""
            priority "4"

            actions(
              target_group_name: "my-target-group2",
              # [optional]
              # needs this to avoid unnecessary call of create_target_group.
              target_group_arn: "arn:aws:elasticloadbalancing:ap-northeast-1:XXXXXXXXXXXX:targetgroup/my-target-group2/XXXXXXXXXXXXXXXX",
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
  end
end
```

## Use template

```
template "target_groups" do
  target_groups do
    target_group "my-target-group" do
      protocol "HTTP"
      port context.port || 80 # use default 80 or override context value
      vpc_id "vpc-XXXXXXXX"
      health_check_interval_seconds 30
      health_check_path "/healthcheck"
      health_check_port "traffic-port"
      health_check_protocol "HTTP"
      health_check_timeout_seconds 5
      healthy_threshold_count 5
      unhealthy_threshold_count 2
      matcher http_code: "200"
    end
end

ec2 "vpc-XXXXXXXXX" do
  elb_v2 "my-app-load-balancer" do
    subnets(
      "subnet-XXXXXXXX",
      "subnet-YYYYYYYY",
      )
    end

    include_template "target_groups", port: 80
  end
end
```

## Test

set your AWS arn for [spec/aws_config.yml.sample](https://github.com/wata-gh/applb/blob/master/spec/aws_config.yml.sample) and rename to spec/aws_config.yml.

## Similar tools

* [Codenize.tools](http://codenize.tools/)

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/wata-gh/applb.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

