module Applb
  module TemplateHelper
    def include_template(template_name, context = {})
      template = @context.templates[template_name.to_s]

      unless template
        raise "Template `#{template_name}' is not defined"
      end

      context_org = @context
      @context = @context.merge(context)
      instance_eval(&template)
      @context = context_org
    end

    def context
      @context
    end
  end
end
