
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'mauve/version'

Gem::Specification.new do |spec|
  spec.name          = 'mauvesend'
  spec.version       = Mauve::VERSION
  spec.authors       = ['Patrick Cherry', 'Telyn Roat']
  spec.email         = ['telyn@bytemark.co.uk']

  spec.summary       = 'an alert system for system and network administrators to help you sleep better, and be attentive to your computers.'
  spec.homepage      = 'https://github.com/BytemarkHosting/mauvealert'

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = 'http://src.bytemark.co.uk'
  else
    raise 'RubyGems 2.0 or newer is required to protect against ' \
      'public gem pushes.'
  end

  spec.files = %w[
    lib/mauve/sender.rb
    lib/mauve/mauve_resolv.rb
    lib/mauve/mauve_time.rb
    lib/mauve/version.rb
    lib/mauve/proto.rb
    mauve.proto
  ]

  spec.bindir        = 'bin'
  spec.executables   = 'mauvesend'
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.16'
  spec.add_development_dependency 'rake', '~> 10.0'

  spec.add_runtime_dependency 'ruby_protobuf', '~> 0.4.11'

  #
  # The versions here are to match Jessie
end
