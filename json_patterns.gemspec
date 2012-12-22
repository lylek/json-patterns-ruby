Gem::Specification.new do |s|
  s.name        = 'json_patterns'
  s.version     = '0.1.2'
  s.date        = '2012-10-11'
  s.summary     = "A DSL of patterns to validate JSON structure"
  s.description = "Validate patterns in JSON using a domain-specific language" +
    " that looks as much as possible like the JSON you are trying to validate."
  s.authors     = ["Lyle Kopnicky"]
  s.email       = 'lyle@kopnicky.com'
  s.files       = Dir["README.md"] + Dir["lib/*.rb"] + Dir["test/*.rb"]
  s.test_files  = Dir["test/*.rb"]
  s.homepage    =
    'http://github.com/lylek/json-patterns-ruby'
  s.required_ruby_version = '>= 1.9.0'
end
