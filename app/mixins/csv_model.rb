# encoding: utf-8
require "csv"

module CSVModel

  def self.included base
    base.extend ClassMethods
  end

  def merge! model
    fill!(model.to_s.split("@"))
  end

  def fill! row
    self.class.column_names.each_with_index do |name, index|
      public_send "#{name}=", row[index]
    end
  end

  def to_s
    self.class.column_names.collect {|name| public_send name }.join "@"
  end


  module ClassMethods
    def csv_model options={}
      column_names = options.fetch(:column_names)

      define_singleton_method :column_names do
        column_names
      end

      define_singleton_method :delta_file_name do
        options.fetch(:delta_file_name)
      end

      define_singleton_method :log_file_name do
        options.fetch(:log_file_name)
      end

      define_method :operation do
        public_send options.fetch(:operation_attribute)
      end
    end

    def parse file_name
      models = []
      begin
        open(file_name, "r:ISO-8859-1").readlines.each do |line|
          line.encode! "UTF-8"
          line.gsub! "\n", ""
          line.gsub! "\r", ""

          model = new
          model.fill! line.split("@")
          models.push model
        end
      rescue => e 
        puts e.message
      end
      models
    end

    def import_from_log(file_name=nil)
      progress = ProgressLogger.new 1
      parses = nil

      file_name ||= log_file_name
      log_time("#{self} parse(#{file_name})") do
        parses = parse(file_name)
      end

      bulk_insert = "INSERT INTO #{self.storage_name} (#{self.column_names.join(',')}) VALUES "
      models = parses.shift(500)
      while !models.empty? do
        values = models.map{ |m| "(#{ m.class.column_names.map{ |c| "'#{ m.send(c).to_s.gsub(/\\/, '\&\&').gsub(/'/, "''") }'" }.join(',') })" }
        next if values.empty?
        log_time("#{self} insert(#{ values.size })") do
          q = bulk_insert + values.join(',') + ';'
          DataMapper.repository.adapter.execute(q.force_encoding('ASCII-8BIT'))
          progress.log if !ENV['VERBOSE']
        end
        models = parses.shift(500)
      end
    end

    def log_time(label)
      st = Time.now.to_f
      yield
      puts "#{label} #{'%0.2fms' % ( ( Time.now.to_f - st ) * 1000 )}" if ENV['VERBOSE']
    end
  end
end

