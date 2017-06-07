# coding: utf-8
require 'helper'
require 'mysql2-cs-bind'
require 'fluent/test/driver/output'
require 'fluent/plugin/buffer'
require 'fluent/config'
require 'time'
require 'timecop'

class MysqlBulkOutputTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
  end

  def config_element(name = 'test', argument = '', params = {}, elements = [])
    Fluent::Config::Element.new(name, argument, params, elements)
  end

  CONFIG = %[
    database test_app_development
    username root
    password hogehoge
    column_names id,user_name,created_at
    key_names id,users,created_at
    table users
  ]

  def create_driver(conf = CONFIG)
    d = Fluent::Test::Driver::Output.new(Fluent::Plugin::MysqlBulkOutput).configure(conf)
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

  def create_metadata(timekey: nil, tag: nil, variables: nil)
    Fluent::Plugin::Buffer::Metadata.new(timekey, tag, variables)
  end

  class TestExpandPlaceholders < self
    data("table" => {"database" => "test_app_development",
                     "table" => "users_${tag}",
                     "extracted_database" => "test_app_development",
                     "extracted_table" => "users_input_mysql"
                    },
         "database" => {"database" => "test_app_development_${tag}",
                        "table" => "users",
                        "extracted_database" => "test_app_development_input_mysql",
                        "extracted_table" => "users"
                       },
        )
    def test_expand_tag_placeholder(data)
      config = config_element('ROOT', '', {
                                "@type" => "mysql_bulk",
                                "host" => "localhost",
                                "database" => data["database"],
                                "username" => "root",
                                "password" => "hogehoge",
                                "column_names" => "id,user_name,created_at",
                                "table" => data["table"],
                              }, [config_element('buffer', 'tag', {
                                                   "@type" => "memory",
                                                   "flush_interval" => "60s",
                                                 }, [])])
      d = create_driver(config)
      time = Time.now
      metadata = create_metadata(timekey: time.to_i, tag: 'input.mysql')
      database, table = d.instance.expand_placeholders(metadata)
      assert_equal(data["extracted_database"], database)
      assert_equal(data["extracted_table"], table)
    end

    def setup
      Timecop.freeze(Time.parse("2016-09-26"))
    end

    data("table" => {"database" => "test_app_development",
                     "table" => "users_%Y%m%d",
                     "extracted_database" => "test_app_development",
                     "extracted_table" => "users_20160926"
                    },
         "database" => {"database" => "test_app_development_%Y%m%d",
                        "table" => "users",
                        "extracted_database" => "test_app_development_20160926",
                        "extracted_table" => "users"
                       },
        )
    def test_expand_time_placeholder(data)
      config = config_element('ROOT', '', {
                                "@type" => "mysql_bulk",
                                "host" => "localhost",
                                "database" => data["database"],
                                "username" => "root",
                                "password" => "hogehoge",
                                "column_names" => "id,user_name,created_at",
                                "table" => data["table"],
                              }, [config_element('buffer', 'time', {
                                                   "@type" => "memory",
                                                   "timekey" => "60s",
                                                   "timekey_wait" => "60s"
                                                 }, [])])
      d = create_driver(config)
      time = Time.now
      metadata = create_metadata(timekey: time.to_i, tag: 'input.mysql')
      database, table = d.instance.expand_placeholders(metadata)
      assert_equal(data["extracted_database"], database)
      assert_equal(data["extracted_table"], table)
    end

    def teardown
      Timecop.return
    end
  end

  def test_configure_error
    assert_raise(Fluent::ConfigError) do
      create_driver %[
        host localhost
        database test_app_development
        username root
        password hogehoge
        table users
        on_duplicate_key_update true
        on_duplicate_update_keys user_name,updated_at
        flush_interval 10s
      ]
    end

    assert_raise(Fluent::ConfigError) do
      create_driver %[
        host localhost
        database test_app_development
        username root
        password hogehoge
        column_names id,user_name,created_at,updated_at
        table users
        on_duplicate_key_update true
        flush_interval 10s
      ]
    end

    assert_raise(Fluent::ConfigError) do
      create_driver %[
        host localhost
        username root
        password hogehoge
        column_names id,user_name,created_at,updated_at
        table users
        on_duplicate_key_update true
        on_duplicate_update_keys user_name,updated_at
        flush_interval 10s
      ]
    end

    assert_raise(Fluent::ConfigError) do
      create_driver %[
        host localhost
        username root
        password hogehoge
        column_names id,user_name,login_count,created_at,updated_at
        table users
        on_duplicate_key_update true
        on_duplicate_update_keys login_count,updated_at
        on_duplicate_update_custom_values login_count
        flush_interval 10s
      ]
    end
  end

  def test_configure
    # not define format(default csv)
    assert_nothing_raised(Fluent::ConfigError) do
      create_driver %[
        host localhost
        database test_app_development
        username root
        password hogehoge
        column_names id,user_name,created_at,updated_at
        table users
        on_duplicate_key_update true
        on_duplicate_update_keys user_name,updated_at
        flush_interval 10s
      ]
    end

    assert_nothing_raised(Fluent::ConfigError) do
      create_driver %[
        database test_app_development
        username root
        password hogehoge
        column_names id,user_name,created_at,updated_at
        table users
      ]
    end

    assert_nothing_raised(Fluent::ConfigError) do
      create_driver %[
        database test_app_development
        username root
        password hogehoge
        column_names id,user_name,created_at,updated_at
        table users
        on_duplicate_key_update true
        on_duplicate_update_keys user_name,updated_at
      ]
    end

    assert_nothing_raised(Fluent::ConfigError) do
      create_driver %[
        database test_app_development
        username root
        password hogehoge
        column_names id,user_name,created_at,updated_at
        key_names id,user,created_date,updated_date
        table users
        on_duplicate_key_update true
        on_duplicate_update_keys user_name,updated_at
      ]
    end

    assert_nothing_raised(Fluent::ConfigError) do
      create_driver %[
        database test_app_development
        username root
        password hogehoge
        key_names id,url,request_headers,params,created_at,updated_at
        column_names id,url,request_headers_json,params_json,created_date,updated_date
        json_key_names request_headers,params
        table access
      ]
    end

    assert_nothing_raised(Fluent::ConfigError) do
      create_driver %[
        database test_app_development
        username root
        password hogehoge
        column_names id,user_name,login_count,created_at,updated_at
        key_names id,user_name,login_count,created_date,updated_date
        table users
        on_duplicate_key_update true
        on_duplicate_update_keys login_count,updated_at
        on_duplicate_update_custom_values ${`login_count` + 1},updated_at
      ]
    end
  end

  def test_variables
    d = create_driver %[
      database test_app_development
      username root
      password hogehoge
      column_names id,user_name,created_at,updated_at
      table users
      on_duplicate_key_update true
      on_duplicate_update_keys user_name,updated_at
    ]

    assert_equal ['id','user_name','created_at','updated_at'], d.instance.key_names
    assert_equal ['id','user_name','created_at','updated_at'], d.instance.column_names
    assert_equal nil, d.instance.json_key_names
    assert_equal nil, d.instance.unixtimestamp_key_names
    assert_equal " ON DUPLICATE KEY UPDATE user_name = VALUES(user_name),updated_at = VALUES(updated_at)", d.instance.instance_variable_get(:@on_duplicate_key_update_sql)

    d = create_driver %[
      database test_app_development
      username root
      password hogehoge
      column_names id,user_name,created_at,updated_at
      table users
    ]

    assert_equal ['id','user_name','created_at','updated_at'], d.instance.key_names
    assert_equal ['id','user_name','created_at','updated_at'], d.instance.column_names
    assert_equal nil, d.instance.json_key_names
    assert_equal nil, d.instance.unixtimestamp_key_names
    assert_nil d.instance.instance_variable_get(:@on_duplicate_key_update_sql)

    d = create_driver %[
      database test_app_development
      username root
      password hogehoge
      key_names id,user_name,created_at,updated_at
      column_names id,user,created_date,updated_date
      table users
    ]

    assert_equal ['id','user_name','created_at','updated_at'], d.instance.key_names
    assert_equal ['id','user','created_date','updated_date'], d.instance.column_names
    assert_equal nil, d.instance.json_key_names
    assert_equal nil, d.instance.unixtimestamp_key_names
    assert_nil d.instance.instance_variable_get(:@on_duplicate_key_update_sql)

    d = create_driver %[
      database test_app_development
      username root
      password hogehoge
      key_names id,url,request_headers,params,created_at,updated_at
      column_names id,url,request_headers_json,params_json,created_date,updated_date
      unixtimestamp_key_names created_at,updated_at
      json_key_names request_headers,params
      table access
    ]

    assert_equal ['id','url','request_headers','params','created_at','updated_at'], d.instance.key_names
    assert_equal ['id','url','request_headers_json','params_json','created_date','updated_date'], d.instance.column_names
    assert_equal ['request_headers','params'], d.instance.json_key_names
    assert_equal ['created_at', 'updated_at'], d.instance.unixtimestamp_key_names
    assert_nil d.instance.instance_variable_get(:@on_duplicate_key_update_sql)

    d = create_driver %[
      database test_app_development
      username root
      password hogehoge
      column_names id,user_name,login_count,created_at,updated_at
      table users
      on_duplicate_key_update true
      on_duplicate_update_keys login_count,updated_at
      on_duplicate_update_custom_values ${`login_count` + 1},updated_at
    ]

    assert_equal ['id','user_name','login_count','created_at','updated_at'], d.instance.key_names
    assert_equal ['id','user_name','login_count','created_at','updated_at'], d.instance.column_names
    assert_equal nil, d.instance.json_key_names
    assert_equal nil, d.instance.unixtimestamp_key_names
    assert_equal " ON DUPLICATE KEY UPDATE login_count = `login_count` + 1,updated_at = VALUES(updated_at)", d.instance.instance_variable_get(:@on_duplicate_key_update_sql)
  end

  def test_spaces_in_columns
    d = create_driver %[
      database test_app_development
      username root
      password hogehoge
      column_names id, user_name, created_at, updated_at
      table users
    ]

    assert_equal ['id','user_name','created_at','updated_at'], d.instance.key_names
    assert_equal ['id','user_name','created_at','updated_at'], d.instance.column_names

    d = create_driver %[
      database test_app_development
      username root
      password hogehoge
      key_names id, user_name, created_at, updated_at
      column_names id, user_name, created_at, updated_at
      table users
    ]

    assert_equal ['id','user_name','created_at','updated_at'], d.instance.key_names
    assert_equal ['id','user_name','created_at','updated_at'], d.instance.column_names
  end
end
