class Fluent::MysqlOutput < Fluent::BufferedOutput
  Fluent::Plugin.register_output('mysql', self)

  include Fluent::SetTimeKeyMixin
  include Fluent::SetTagKeyMixin

  config_param :host, :string
  config_param :port, :integer, :default => nil
  config_param :database, :string
  config_param :username, :string
  config_param :password, :string, :default => '', :secret => true
  config_param :sslkey, :string, :default => nil
  config_param :sslcert, :string, :default => nil
  config_param :sslca, :string, :default => nil
  config_param :sslcapath, :string, :default => nil
  config_param :sslcipher, :string, :default => nil
  config_param :sslverify, :bool, :default => nil
  config_param :encoding, :string, :default => nil
  config_param :collation, :string, :default => nil

  config_param :key_names, :string, :default => nil # nil allowed for json format
  config_param :sql, :string, :default => nil
  config_param :table, :string, :default => nil
  config_param :columns, :string, :default => nil

  config_param :format, :string, :default => "raw" # or json

  attr_accessor :handler

  def initialize
    super
    require 'mysql2-cs-bind'
    require 'jsonpath'
  end

  # Define `log` method for v0.10.42 or earlier
  unless method_defined?(:log)
    define_method("log") { $log }
  end

  def configure(conf)
    super

    log.warn "[mysql] This plugin deprecated. You should use mysql_bulk."

    # TODO tag_mapped

    case @format
    when 'json'
      @format_proc = Proc.new{|tag, time, record| record.to_json}
    when 'jsonpath'
      @key_names = @key_names.split(/\s*,\s*/)
      @format_proc = Proc.new do |tag, time, record|
        json = record.to_json
        @key_names.map do |k|
          JsonPath.new(k.strip).on(json).first
        end
      end
    else
      @key_names = @key_names.split(/\s*,\s*/)
      @format_proc = Proc.new{|tag, time, record| @key_names.map{|k| record[k]}}
    end

    if @columns.nil? and @sql.nil?
      raise Fluent::ConfigError, "columns or sql MUST be specified, but missing"
    end
    if @columns and @sql
      raise Fluent::ConfigError, "both of columns and sql are specified, but specify one of them"
    end

    if @sql
      begin
        if @format == 'json'
          Mysql2::Client.pseudo_bind(@sql, [nil])
        else
          Mysql2::Client.pseudo_bind(@sql, @key_names.map{|n| nil})
        end
      rescue ArgumentError => e
        raise Fluent::ConfigError, "mismatch between sql placeholders and key_names"
      end
    else # columns
      raise Fluent::ConfigError, "table missing" unless @table
      @columns = @columns.split(/\s*,\s*/)
      cols = @columns.join(',')
      placeholders = if @format == 'json'
                       '?'
                     else
                       @key_names.map{|k| '?'}.join(',')
                     end
      @sql = "INSERT INTO #{@table} (#{cols}) VALUES (#{placeholders})"
    end
  end

  def start
    super
  end

  def shutdown
    super
  end

  def format(tag, time, record)
    [tag, time, @format_proc.call(tag, time, record)].to_msgpack
  end

  def client
    Mysql2::Client.new({
        :host => @host, :port => @port,
        :username => @username, :password => @password,
        :database => @database,
        :sslkey => @sslkey,
        :sslcert => @sslcert,
        :sslca => @sslca,
        :sslcapath => @sslcapath,
        :sslcipher => @sslcipher,
        :sslverify => @sslverify,
        :encoding => @encoding,
        :collation => @collation,
        :flags => Mysql2::Client::MULTI_STATEMENTS,
      })
  end

  def write(chunk)
    handler = self.client
    chunk.msgpack_each { |tag, time, data|
      handler.xquery(@sql, data)
    }
    handler.close
  end
end
