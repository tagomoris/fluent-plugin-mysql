class Fluent::MysqlOutput < Fluent::BufferedOutput
  Fluent::Plugin.register_output('mysql', self)

  include Fluent::SetTimeKeyMixin
  include Fluent::SetTagKeyMixin
  
  config_param :host, :string
  config_param :port, :integer, :default => nil
  config_param :database, :string
  config_param :username, :string
  config_param :password, :string, :default => ''

  config_param :key_names, :string, :default => nil # nil allowed for json format
  config_param :sql, :string, :default => nil
  config_param :table, :string, :default => nil
  config_param :columns, :string, :default => nil

  config_param :format, :string, :default => "raw" # or json

  attr_accessor :handler

  def initialize
    super
    require 'mysql2-cs-bind'
  end

  def configure(conf)
    super

    # TODO tag_mapped

    if @format == 'json'
      @format_proc = Proc.new{|tag, time, record| record.to_json}
    else
      @key_names = @key_names.split(',')
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
      @columns = @columns.split(',')
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
        :database => @database
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
