class Fluent::MysqlOutput < Fluent::BufferedOutput
  Fluent::Plugin.register_output('mysql', self)

  config_param :host, :string
  config_param :port, :integer, :default => nil
  config_param :database, :string
  config_param :username, :string
  config_param :password, :string => nil

  config_param :key_names, :string, :default => nil # nil allowed for json format
  config_param :sql, :string, :default => nil
  config_param :table, :string, :default => nil
  config_param :columns, :string, :default => nil

  config_param :format, :string, :default => "raw" # or json

  def initialize
    super
    require 'mysql2'
  end

  def configure(conf)
    super

    # TODO tag_mapped

    if @format == 'json'
      # TODO time, tag, and json values
      @format_proc = Proc.new{|tag, time, record| record.to_json}
    else
      # TODO time,tag in key_names
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
        # using nil to pass call of @handler.escape (@handler is set in #start)
        if @format == 'json'
          pseudo_bind(@sql, nil)
        else
          pseudo_bind(@sql, @key_names.map{|n| nil})
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
    @handler = Mysql2::Client.new({:host => @host, :port => @port,
                                    :username => @username, :password => @password,
                                    :database => @database})
  end

  def shutdown
    super
    @handler.close
  end

  def pseudo_bind(sql, values)
    sql = sql.dup

    placeholders = []
    search_pos = 0
    while pos = sql.index('?', search_pos)
      placeholders.push(pos)
      search_pos = pos + 1
    end
    raise ArgumentError, "mismatch between placeholders number and values arguments" if placeholders.length != values.length

    while pos = placeholders.pop()
      rawvalue = values.pop()
      if rawvalue.nil?
        sql[pos] = 'NULL'
      elsif rawvalue.is_a?(Time)
        val = rawvalue.strftime('%Y-%m-%d %H:%M:%S')
        sql[pos] = "'" + val + "'"
      else
        val = @handler.escape(rawvalue.to_s)
        sql[pos] = "'" + val + "'"
      end
    end
    sql
  end

  def query(sql, *values)
    values = values.flatten
    # pseudo prepared statements
    return @handler.query(sql) if values.length < 1
    @handler.query(self.pseudo_bind(sql, values))
  end

  def format(tag, time, record)
    [tag, time, @format_proc.call(record)].to_msgpack
  end

  def write(chunk)
    chunk.msgpack_each { |time, data|
      query(@sql, data)
    }
  end
end
