
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'mauve/version'

Gem::Specification.new do |spec|
  spec.name          = 'mauve'
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

  spec.files = Dir['**/*']
  spec.bindir        = 'bin'
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.16'
  spec.add_development_dependency 'rake', '~> 10.0'

  spec.add_runtime_dependency 'datamapper'
  spec.add_runtime_dependency 'dm-aggregates'
  spec.add_runtime_dependency 'dm-do-adapter'
  spec.add_runtime_dependency 'dm-migrations'
  spec.add_runtime_dependency 'dm-postgres-adapter'
  spec.add_runtime_dependency 'dm-sqlite-adapter'
  spec.add_runtime_dependency 'dm-transactions'
  spec.add_runtime_dependency 'dm-types'
  spec.add_runtime_dependency 'dm-validations'
  spec.add_runtime_dependency 'ruby_protobuf', '~> 0.4.11'

  #
  # The versions here are to match Jessie
  #
  spec.add_runtime_dependency 'haml', '~> 4.0.5'
  spec.add_runtime_dependency 'haml-contrib', '~> 1.0.0'
  spec.add_runtime_dependency 'ipaddress', '~> 0.8.0'
  spec.add_runtime_dependency 'json', '~> 1.8.1'
  spec.add_runtime_dependency 'locale', '~> 2.1.0'
  spec.add_runtime_dependency 'log4r', '~> 1.1.10'
  spec.add_runtime_dependency 'rack', '~> 1.5.2'
  spec.add_runtime_dependency 'rack-flash3', '~> 1.0.5'
  spec.add_runtime_dependency 'rack-protection', '~> 1.5.2'
  spec.add_runtime_dependency 'RedCloth', '~> 4.2.9'
  spec.add_runtime_dependency 'rmail', '~> 1.1.0'
  spec.add_runtime_dependency 'sanitize', '~> 2.1.0'
  spec.add_runtime_dependency 'sinatra', '~> 1.4.5'
  spec.add_runtime_dependency 'thin', '~> 1.6.3'
  spec.add_runtime_dependency 'tilt', '~> 1.4.1'

  spec.add_development_dependency 'rack-test', '~> 0.6.3'
  spec.add_development_dependency 'simplecov'
  spec.add_development_dependency 'timecop', '~> 0.7.1'
  spec.add_development_dependency 'webmock', '~> 1.19.0'
end
