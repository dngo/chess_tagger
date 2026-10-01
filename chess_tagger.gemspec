# frozen_string_literal: true

require_relative "lib/chess_tagger/version"

Gem::Specification.new do |spec|
  spec.name = "chess_tagger"
  spec.version = ChessTagger::VERSION
  spec.authors = ["David Ngo"]
  spec.email = ["davngo@gmail.com"]
  spec.summary = "Tag a chess position in FEN with the tactical motifs it matches"
  spec.description = "A Ruby gem that reads a FEN and returns tactical tags such as fork, pin, skewer, discovered attack, and mate in 1, 2, or 3."
  spec.homepage = "https://github.com/dngo/chesshub"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"
  spec.files = Dir["lib/**/*.rb", "bin/*", "README.md", "LICENSE"]
  spec.bindir = "bin"
  spec.executables = ["chess-tagger"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
