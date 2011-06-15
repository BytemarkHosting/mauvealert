# 
# stolen from http://github.com/cschneid/irclogger/blob/master/lib/partials.rb
# and made a lot more robust by me
#

module Sinatra::Partials
  def do_render(template, options={})
    haml(template, options)
  end

  def partial(template, *args)
    template_array = template.to_s.split('/')
    template = template_array[0..-2].join('/') + "/_#{template_array[-1]}"
    options = args.last.is_a?(Hash) ? args.pop : {}
    options.merge!(:layout => false)
    if collection = options.delete(:collection) then
      # take a copy of the locals hash, so we don't overwrite it.
      locals = (options.delete(:locals) || {})
      collection.inject([]) do |buffer, member|
        buffer << do_render(:"#{template}", options.merge(:layout =>
        false, :locals => {template_array[-1].to_sym => member}.merge(locals)))
      end.join("\n")
    else
      do_render(:"#{template}", options)
    end
  end
end

