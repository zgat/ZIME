#!/usr/bin/env ruby
# SPDX-License-Identifier: GPL-3.0-or-later
require 'json'
require 'zlib'
require 'open3'
require 'tmpdir'
require 'digest'

Dir.chdir(File.expand_path('..', __dir__))
def query(path, sql)
  output, error, status = Open3.capture3('/usr/bin/sqlite3', '-json', path, sql)
  abort error unless status.success?
  JSON.parse(output)
end

Dir.mktmpdir('zime-source-identity-') do |scratch|
  gzip = File.join(scratch, 'fixture.gz')
  source = <<~CEDICT
    你 你 [ni3] /you (informal, as opposed to courteous 您[nin2])/
    妳 你 [ni3] /you (Note: In Taiwan, 妳 is used to address females, but in mainland China, it is not commonly used. Instead, 你 is used to address both males and females.)/
    發 发 [fa1] /to send out/to issue/
    髮 发 [fa4] /hair/Taiwan pr. [fa3]/
    例 例 [li4] /example (with "quotes")/CL:個|个[ge4]/
    明天見 明天见 [ming2 tian1 jian4] /see you tomorrow/
    看穿 看穿 [kan4 chuan1] /see through (a person, scheme, trick etc)/
    亦作 亦作 [yi4 zuo4] /also written as/
    亦稱 亦称 [yi4 cheng1] /also known as/
    費城 费城 [Fei4 cheng2] /Philadelphia, Pennsylvania/abbr. for 費拉德爾菲亞|费拉德尔菲亚[Fei4 la1 de2 er3 fei1 ya4]/
    費拉德爾菲亞 费拉德尔菲亚 [Fei4 la1 de2 er3 fei1 ya4] /Philadelphia, Pennsylvania/abbr. to 費城|费城[Fei4 cheng2]/
    世博 世博 [Shi4 bo2] /abbr. for 世界博覽會|世界博览会[Shi4 jie4 Bo2 lan3 hui4], World Expo/
    瞭解 瞭解 [liao3 jie3] /variant of 了解[liao3 jie3]/
    了解 了解 [liao3 jie3] /to understand/
    了解 了解 [Liao3 jie3] /a proper name that must not leak into a reading-qualified reference/
    甲 甲 [jia3] /see 乙[yi3]/
    乙 乙 [yi3] /see 甲[jia3]/
    丙 丙 [bing3] /see 不存在[bu4 cun2 zai4]/
    丁 丁 [ding1] /used in 了解[liao3 jie3]/
    戊 戊 [wu4] /see also 了解[liao3 jie3]/
    己 己 [ji3] /(a grammatical definition)/
    妳 奶 [nai3] /variant of 奶[nai3]/
    奶 奶 [nai3] /milk/
  CEDICT
  Zlib::GzipWriter.open(gzip) { |writer| writer.write(source) }
  databases = %w[first second].map do |name|
    path = File.join(scratch, "#{name}.sqlite3")
    output, error, status = Open3.capture3('scripts/build-zime-lexicon', gzip, path)
    abort "#{output}\n#{error}" unless status.success?
    path
  end
  abort 'fixture rebuild was not deterministic' unless databases.map { |path| Digest::SHA256.file(path).hexdigest }.uniq.length == 1
  rows = query(databases.first, 'SELECT traditional,simplified,pinyin,senses FROM source_entries ORDER BY id')
  abort 'source identities were merged' unless rows.first(5).map { |row| row['traditional'] } == %w[你 妳 發 髮 例]
  abort 'distinct readings lost' unless rows[2..3].map { |row| row['pinyin'] } == %w[fa1 fa4]
  abort 'JSON / quotation / classifier roundtrip failed' unless JSON.parse(rows[4]['senses']) == ['example (with "quotes")', 'CL:個|个[ge4]']
  annotations = query(databases.first, 'SELECT term,all_senses FROM annotations').to_h { |row| [row['term'], JSON.parse(row['all_senses'])] }
  {'明天见' => ['see you tomorrow'], '看穿' => ['see through (a person, scheme, trick etc)'],
    '亦作' => ['also written as'], '亦称' => ['also known as'], '费城' => ['Philadelphia, Pennsylvania'],
    '世博' => ['World Expo'], '瞭解' => ['to understand'], '妳' => ['you'],
    '甲' => [], '乙' => [], '丙' => [], '丁' => [], '戊' => [], '己' => ['a grammatical definition']}.each do |term, expected|
    abort "projection #{term}: #{annotations[term].inspect} != #{expected.inspect}" unless annotations[term] == expected
  end
  output, error, status = Open3.capture3('scripts/build-zime-lexicon', gzip, databases.first)
  abort "overwrote existing output: #{output} #{error}" if status.success?
end

# Independently compare every shipped source record to the pinned gzip.
path = 'resources/zime-cedict.sqlite3'
rows = query(path, 'SELECT id,traditional,simplified,pinyin,priority,senses FROM source_entries ORDER BY id')
index = 0
Zlib::GzipReader.open('data/zime/cedict.txt.gz') do |gzip|
  gzip.each_line do |line|
    line = line.force_encoding('UTF-8').strip
    next if line.empty? || line.start_with?('#')
    words, definition = line.split(' /', 2)
    traditional, simplified, reading = words.split(' ', 3)
    pinyin = reading.delete_prefix('[').delete_suffix(']')
    senses = definition.delete_suffix('/').split('/', -1)
    expected = {'id' => index + 1, 'traditional' => traditional, 'simplified' => simplified,
      'pinyin' => pinyin, 'priority' => pinyin.match?(/\A[A-Z]/) ? 1 : 0, 'senses' => JSON.generate(senses)}
    abort "shipped source row #{index + 1} differs" unless rows[index] == expected
    index += 1
  end
end
abort 'shipped source row count differs' unless rows.length == index && index == 124_988
abort 'database schema version differs' unless query(path, 'PRAGMA user_version').first['user_version'] == 3
abort 'prepared projection revision differs' unless query(path, "SELECT value FROM metadata WHERE key='projection_revision'").first['value'] == '3'
abort 'raw senses were dropped' unless query(path, 'SELECT SUM(json_array_length(senses)) AS n FROM source_entries').first['n'] == 199_654
abort 'database integrity failed' unless query(path, 'PRAGMA integrity_check').first['integrity_check'] == 'ok'
puts "ZIME source identity: PASS (#{index} complete source rows, script/readings preserved; deterministic fixture; overwrite rejected)"
