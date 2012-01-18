require 'set'


module CodeBuilder


# class Entity
#   def entities()
#   def priority()
#   def source_size()
#   def attach(source)
#   def write_intf(stream)
#   def write_defs(stream)
#   def write_decls(stream)
# end


# TODO min/max Fixnums
module Priority
  DEFAULT = 0
  MIN = -1000
  MAX = +1000
end


class Module

  attr_reader :header, :smallest_source, :main_source

  def initialize
    @entities = Set.new
    @source_size_threshold = 0
  end

  def <<(obj)
    unless @entities.include?(obj)
      @entities << obj
      obj.entities.each {|e| self << e}
    end
  end

  # def new_header()

  # def new_source(index)

  def generate
    @header = new_header
    @sources = []
    (1..source_count).each {|i| @sources << new_source(i)}
    @main_source = @sources.first
    @entities.each do |e|
      @header << e
      @smallest_source = @sources.sort_by {|s| s.size}.first
      @sources.each {|s| e.attach(s)}
    end
    @header.generate
    @sources.each {|s| s.generate}
  end

  private

  def source_count
    total = 0
    @entities.each {|e| total += e.source_size}
    count = @source_size_threshold > 0 ? (total/@source_size_threshold + 1) : 1
    count > 0 ? count : 1
  end

end # Module


def self.priority_sort(entities)
  # TODO in-place operation???
  entities.to_a.sort_by!{|e| e.priority}.reverse!
end # priority_sort


class Code

  attr_reader :entities

  # def new_stream()

  # def write(stream)

  def initialize(m)
    @entities = Set.new
    @module = m
  end

  def generate
    stream = new_stream
    begin
      write(stream)
    ensure
      stream.close
    end
  end

  def <<(e)
    @entities << e
  end

end # Code


class Header < Code
  def write(stream)
    CodeBuilder.priority_sort(entities).each {|e| e.write_intf(stream)}
  end
end # Header


class Source < Code

  attr_reader :index

  def initialize(m, i)
    super(m)
    @index = i
  end

  def write(stream)
    sorted = CodeBuilder.priority_sort(entities)
    sorted.each {|e| e.write_decls(stream)}
    sorted.each {|e| e.write_defs(stream)}
  end

  def main?
    equal?(@module.main_source)
  end

  def smallest?
    equal?(@module.smallest_source)
  end

  def size
    size = 0
    @entities.each {|e| size += e.source_size}
    size
  end

end # Source


end # SourceCode