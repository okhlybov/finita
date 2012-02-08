$LOAD_PATH << 'lib'; require 'finita'
Gem::Specification.new do |spec|
  spec.name = 'finita'
  spec.version = Finita::VERSION
  spec.author = 'Oleg A. Khlybov'
  spec.email = 'fougas@mail.ru'
  spec.homepage = 'http://finita.sourceforge.net/'
  spec.summary = 'Package for solving complex PDE/algebraic systems of equations numerically using grid methods'
  spec.required_ruby_version = Gem::Requirement.new('>= 1.9.1')
  spec.executables = ['finitac']
  spec.files = Dir['bin/finitac'] + Dir['lib/**/*.rb']
end