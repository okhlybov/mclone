$LOAD_PATH << 'lib'

require 'mclone'

Gem::Specification.new do |spec|
  spec.name          = 'mclone'
  spec.version       = Mclone::VERSION
  spec.authors       = ['Oleg A. Khlybov']
  spec.email         = ['fougas@mail.ru']
  spec.summary       = 'Rclone frontend for offline synchronization'
  spec.homepage      = 'https://github.com/okhlybov/mclone'
  spec.license       = 'BSD-3-Clause'
  spec.executables   << 'mclone'
  spec.file          = Dir['lib/**/*.rb'] + Dir['bin/*']
  spec.platform      = Gem::Platform::RUBY
  spec.required_ruby_version = '>= 2.5.0'
  spec.add_runtime_dependency 'clamp', '~> 1.3'
  spec.add_runtime_dependency 'ffi', '~> 1.15'
end