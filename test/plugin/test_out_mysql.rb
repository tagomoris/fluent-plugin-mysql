require 'helper'
require 'mysql2-cs-bind'

class MysqlOutputTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
  end

  CONFIG = %[
host db.local
database testing
username testuser
sql INSERT INTO tbl SET jsondata=?
format json
  ]

  def create_driver(conf = CONFIG, tag='test')
    d = Fluent::Test::BufferedOutputTestDriver.new(Fluent::MysqlOutput, tag).configure(conf)
    d.instance.instance_eval {
      def client
        obj = Object.new
        obj.instance_eval {
          def xquery(*args); [1]; end
          def close; true; end
        }
        obj
      end
    }
    d
  end

  def test_configure
    d = create_driver %[
host database.local
database foo
username bar
sql INSERT INTO baz SET jsondata=?
format json
    ]
    d = create_driver %[
host database.local
database foo
username bar
table baz
columns jsondata
format json
    ]
    d = create_driver %[
host database.local
database foo
username bar
password mogera
key_names field1,field2,field3
table baz
columns col1, col2 ,col3
    ]
    assert_equal ['field1', 'field2', 'field3'], d.instance.key_names
    assert_equal 'INSERT INTO baz (col1,col2,col3) VALUES (?,?,?)', d.instance.sql
    d = create_driver %[
host database.local
database foo
username bar
password mogera
key_names field1 ,field2, field3
table baz
columns col1, col2 ,col3
    ]
    assert_equal ['field1', 'field2', 'field3'], d.instance.key_names
    assert_equal 'INSERT INTO baz (col1,col2,col3) VALUES (?,?,?)', d.instance.sql

    assert_raise(Fluent::ConfigError) {
      d = create_driver %[
host database.local
database foo
username bar
password mogera
key_names field1,field2,field3
sql INSERT INTO baz (col1,col2,col3,col4) VALUES (?,?,?,?)
      ]
    }


  end

  def test_format
    d = create_driver

    time = Time.parse("2011-01-02 13:14:15 UTC").to_i
    d.emit({"a"=>1}, time)
    d.emit({"a"=>2}, time)

    #d.expect_format %[2011-01-02T13:14:15Z\ttest\t{"a":1}\n]
    #d.expect_format %[2011-01-02T13:14:15Z\ttest\t{"a":2}\n]
    d.expect_format ['test', time, {"a" => 1}.to_json].to_msgpack
    d.expect_format ['test', time, {"a" => 2}.to_json].to_msgpack

    d.run
  end

  def test_time_and_tag_key
    d = create_driver %[
host database.local
database foo
username bar
password mogera
include_time_key yes
utc
include_tag_key yes
table baz
key_names time,tag,field1,field2,field3,field4
sql INSERT INTO baz (coltime,coltag,col1,col2,col3,col4) VALUES (?,?,?,?,?,?)
    ]
    assert_equal 'INSERT INTO baz (coltime,coltag,col1,col2,col3,col4) VALUES (?,?,?,?,?,?)', d.instance.sql

    time = Time.parse('2012-12-17 01:23:45 UTC').to_i
    record = {'field1'=>'value1','field2'=>'value2','field3'=>'value3','field4'=>'value4'}
    d.emit(record, time)
    d.expect_format ['test', time, ['2012-12-17T01:23:45Z','test','value1','value2','value3','value4']].to_msgpack
    d.run
  end

  def test_time_and_tag_key_complex
    d = create_driver %[
host database.local
database foo
username bar
password mogera
include_time_key yes
utc
time_format %Y%m%d-%H%M%S
time_key timekey
include_tag_key yes
tag_key tagkey
table baz
key_names timekey,tagkey,field1,field2,field3,field4
sql INSERT INTO baz (coltime,coltag,col1,col2,col3,col4) VALUES (?,?,?,?,?,?)
    ]
    assert_equal 'INSERT INTO baz (coltime,coltag,col1,col2,col3,col4) VALUES (?,?,?,?,?,?)', d.instance.sql

    time = Time.parse('2012-12-17 09:23:45 JST').to_i # JST(+0900)
    record = {'field1'=>'value1','field2'=>'value2','field3'=>'value3','field4'=>'value4'}
    d.emit(record, time)
    d.expect_format ['test', time, ['20121217-002345','test','value1','value2','value3','value4']].to_msgpack
    d.run
  end

  def test_time_and_tag_key_json
    d = create_driver %[
host database.local
database foo
username bar
password mogera
include_time_key yes
utc
time_format %Y%m%d-%H%M%S
time_key timekey
include_tag_key yes
tag_key tagkey
table accesslog
columns jsondata
format json
    ]
    assert_equal 'INSERT INTO accesslog (jsondata) VALUES (?)', d.instance.sql

    time = Time.parse('2012-12-17 09:23:45 JST').to_i # JST(+0900)
    record = {'field1'=>'value1'}
    d.emit(record, time)
    # Ruby 1.9.3 Hash saves its key order, so this code is OK.
    d.expect_format ['test', time, record.merge({'timekey'=>'20121217-002345','tagkey'=>'test'}).to_json].to_msgpack
    d.run
  end

  def test_jsonpath_format
    d = create_driver %[
      host database.local
      database foo
      username bar
      password mogera
      include_time_key yes
      utc
      include_tag_key yes
      table baz
      format jsonpath
      key_names time, tag, id, data.name, tags[0]
      sql INSERT INTO baz (coltime,coltag,id,name,tag1) VALUES (?,?,?,?,?)
    ]
    assert_equal 'INSERT INTO baz (coltime,coltag,id,name,tag1) VALUES (?,?,?,?,?)', d.instance.sql

    time = Time.parse('2012-12-17 01:23:45 UTC').to_i
    record = { 'id' => 15, 'data'=> {'name' => 'jsonpath' }, 'tags' => ['unit', 'simple'] }
    d.emit(record, time)
    d.expect_format ['test', time, ['2012-12-17T01:23:45Z','test',15,'jsonpath','unit']].to_msgpack
    d.run
  end

  def test_write
    # hmm....
  end
end
