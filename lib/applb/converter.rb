require 'erb'

module Applb
  class Converter
    def initialize(lbs_by_vpc_id, tags_by_arn)
      @lbs_by_vpc_id = lbs_by_vpc_id
      @tags_by_arn = tags_by_arn
    end

    def convert
      @lbs_by_vpc_id.each do |vpc_id, lbs_by_name|
        yield vpc_id, output_alb(vpc_id, @tags_by_arn, lbs_by_name)
      end
    end

    private

    def output_alb(vpc_id, tags_by_arn, lbs_by_name)
      path = Pathname.new(File.expand_path('../', __FILE__)).join('output_alb.erb')
      ERB.new(path.read, nil, '-').result(binding)
    end
  end
end
