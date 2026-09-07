# SPDX-License-Identifier: GPL-3.0-or-later
require 'json'
require 'tmpdir'
require 'open3'

Dir.chdir(File.expand_path('..', __dir__))
generator = 'scripts/build-zime-case-aliases.rb'
Dir.mktmpdir('zime-case-aliases-') do |scratch|
  input = File.join(scratch, 'decisions.tsv')
  first = File.join(scratch, 'first.inc')
  second = File.join(scratch, 'second.inc')
  File.write(input, "text\ttranslation\nMiXeDfixture\t测试释义\nOTHERfixture\t另一释义\nordinary\t普通词\nSkipFixture\t-\n")
  [first, second].each do |output|
    stdout, stderr, status = Open3.capture3('/usr/bin/ruby', generator, input, output)
    abort "#{stdout}\n#{stderr}" unless status.success?
  end
  source = File.read(first)
  abort 'case aliases are not deterministic' unless source == File.read(second)
  abort 'arbitrary mixed-case headword was not indexed' unless source.include?('{"mixedfixture", "MiXeDfixture"}')
  abort 'ordinary/omitted definition became a case alias' if source.include?('ordinary') || source.include?('SkipFixture')
  File.open(input, 'a') { |file| file.puts "AnotherNEWword\t新词释义" }
  _, stderr, status = Open3.capture3('/usr/bin/ruby', generator, input, first)
  abort stderr unless status.success?
  abort 'new dictionary entry required a word-specific code change' unless File.read(first).include?('{"anothernewword", "AnotherNEWword"}')
end

source = File.read('build/zime-english-case-aliases.inc')
covered = 0
File.foreach('build/linnet-english-cache/linnet.smart-index.tsv') do |line|
  key = line.split("\t", 2).first
  next unless key.start_with?('m/zh/')
  word = key.delete_prefix('m/zh/')
  folded = word.tr('A-Z', 'a-z')
  next if word == folded
  pair = "{#{JSON.generate(folded)}, #{JSON.generate(word)}}"
  abort "uncovered case-sensitive metadata headword: #{word}" unless source.include?(pair)
  covered += 1
end
abort 'dictionary-wide coverage fixture is missing' unless covered > 500
puts "ZIME case aliases: PASS (#{covered} metadata heads; arbitrary new words; deterministic generation)"
