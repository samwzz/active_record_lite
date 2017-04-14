require_relative 'db_connection'
require 'active_support/inflector'
require 'byebug'
# NB: the attr_accessor we wrote in phase 0 is NOT used in the rest
# of this project. It was only a warm up.

class SQLObject
  def self.columns
    return @columns if @columns
    result = DBConnection.execute2(<<-SQL).first
      SELECT
        *
      FROM
        "#{table_name}"
    SQL

    @columns = result.map(&:to_sym)
  end

  def self.finalize!
    self.columns.each do |name|
      define_method(name) do
        self.attributes[name]
      end

      define_method("#{name}=") do |value|
        self.attributes[name] = value
      end
    end
  end

  def self.table_name=(table_name)
    @table_name = table_name
  end

  def self.table_name
    @table_name ||= self.to_s.tableize
  end

  def self.all
    rows = DBConnection.execute(<<-SQL)
      SELECT
        *
      FROM
        "#{self.table_name}"
    SQL
    self.parse_all(rows)
  end

  # converts hash to Model object
  def self.parse_all(results)
    results.map do |hash|
      self.new(hash)
    end
  end

  def self.find(id)
    results = DBConnection.execute(<<-SQL, id)
      SELECT
        *
      FROM
        "#{table_name}"
      WHERE
        id = ?
    SQL
    self.parse_all(results).first
  end

  def initialize(params = {})
    params.each do |attr_name, value|
      attr_name = attr_name.to_sym
      # byebug
      unless self.class.send(:columns).include?(attr_name)
        raise "unknown attribute '#{attr_name}'"
      end
      # calls attr_accessor methods defined by finalize!
      self.send("#{attr_name}=", value)
    end

  end

  def attributes
    @attributes ||= {}
    @attributes
  end

  def attribute_values
    self.class.columns.map do |attr_name|
      self.send(attr_name)
    end
  end

  def insert
    columns = self.class.columns.drop(1)
    col_names = columns.join(", ")
    question_marks = (["?"] * columns.length).join(", ")

    DBConnection.execute(<<-SQL, *attribute_values.drop(1))
      INSERT INTO
        #{self.class.table_name} (#{col_names})
      VALUES
        (#{question_marks})
    SQL
    self.id = DBConnection.last_insert_row_id
  end

  def update
    columns = self.class.columns.drop(1)
    set_line = columns.map { |attr_name| "#{attr_name} = ?" }.join(", ")

    DBConnection.execute(<<-SQL, *attribute_values.drop(1), id: self.id)
      UPDATE
        #{self.class.table_name}
      SET
        #{set_line}
      WHERE
        :id
    SQL
  end

  def save
    self.id.nil? ? insert : update
  end
end
