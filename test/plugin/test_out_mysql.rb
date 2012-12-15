require 'helper'

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
    obj = Object.new
    obj.instance_eval {
      def escape(v)
        v
      end
      def query(*args); [1]; end
      def close; true; end
    }
    d.instance.handler = obj
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
columns col1,col2,col3
    ]
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

  def test_configure_with_tag
    d = create_driver %[
host database.local
database foo
username bar
table baz
columns jsondata
tag_column tag
format json
    ]
    assert_equal 'INSERT INTO baz (jsondata,tag) VALUES (?,?)', d.instance.sql

    d = create_driver %[
host database.local
database foo
username bar
password mogera
key_names field1,field2,field3
table baz
columns col1,col2,col3
tag_column tag
    ]
    assert_equal 'INSERT INTO baz (col1,col2,col3,tag) VALUES (?,?,?,?)', d.instance.sql
  end

  def test_configure_with_time
    d = create_driver %[
host database.local
database foo
username bar
table baz
columns jsondata
time_column time
format json
    ]
    assert_equal 'INSERT INTO baz (jsondata,time) VALUES (?,?)', d.instance.sql

    d = create_driver %[
host database.local
database foo
username bar
password mogera
key_names field1,field2,field3
table baz
columns col1,col2,col3
time_column time
    ]
    assert_equal 'INSERT INTO baz (col1,col2,col3,time) VALUES (?,?,?,?)', d.instance.sql
  end

  def test_configure_with_tag_and_time
    d = create_driver %[
host database.local
database foo
username bar
table baz
columns jsondata
tag_column tag
time_column time
format json
    ]
    assert_equal 'INSERT INTO baz (jsondata,tag,time) VALUES (?,?,?)', d.instance.sql

    d = create_driver %[
host database.local
database foo
username bar
password mogera
key_names field1,field2,field3
table baz
columns col1,col2,col3
tag_column tag
time_column time
    ]
    assert_equal 'INSERT INTO baz (col1,col2,col3,tag,time) VALUES (?,?,?,?,?)', d.instance.sql
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

  def test_write
    # d = create_driver

    # time = Time.parse("2011-01-02 13:14:15 UTC").to_i
    # d.emit({"a"=>1}, time)
    # d.emit({"a"=>2}, time)

    # ### FileOutput#write returns path
    # path = d.run
    # expect_path = "#{TMP_DIR}/out_file_test._0.log.gz"
    # assert_equal expect_path, path
  end
end
