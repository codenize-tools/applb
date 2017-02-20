require 'hashie'
require 'applb/template_helper'
require 'applb/dsl/ec2'

module Applb
  class DSL
    include Applb::TemplateHelper

    class << self
      def define(source, filepath, options)
        self.new(filepath, options) do
          eval(source, binding, filepath)
        end
      end
    end

    attr_reader :result
    
    def initialize(filepath, options,&block)
      @filepath = filepath
      @result = OpenStruct.new(ec2s: {})

      @context = Hashie::Mash.new(
        filepath: filepath,
        templates: {},
        options: options,
      )

      instance_eval(&block)
    end

    def require(file)
      albfile = (file =~ %r|\A/|) ? file : File.expand_path(File.join(File.dirname(@path), file))

      if File.exist?(albfile)
        instance_eval(File.read(albfile), albfile)
      elsif File.exist?("#{albfile}.rb")
        instance_eval(File.read("#{albfile}.rb"), "#{albfile}.rb")
      else
        Kernel.require(file)
      end
    end

    def template(name, &block)
      @context.templates[name.to_s] = block
    end

    def ec2(vpc_id, &block)
      if ec2_result = @result.ec2s[vpc_id]
        @result.ec2s[vpc_id] = EC2.new(@context, vpc_id, ec2_result.load_balancers, &block).result
      else
        @result.ec2s[vpc_id] = EC2.new(@context, vpc_id, [], &block).result
      end
    end
  end
end
