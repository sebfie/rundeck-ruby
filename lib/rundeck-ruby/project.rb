module Rundeck
  class Project
    def self.all(session)
      @all ||= begin
                 result = session.get('api/3/projects', 'result', 'projects', 'project') || []
                 result.map{|hash| Project.new(session, hash)}
               end
    end

    def self.find(session, name)
      all(session).first{|p| p.name == name}
    end

    def initialize(session, hash)
      @session = session
      @name = hash['name']
    end
    attr_reader :session, :name

    def jobs(force_reload = false)
      return @jobs unless @jobs.nil? || force_reload
      result = session.get("api/2/jobs?project=#{name}", 'result', 'jobs', 'job') || []
      @jobs = result.map{|hash| Job.from_hash(session, hash)}
    end

    def job(id)
      jobs.find{|j| j.id == id}
    end

    def resources
      qb = ResourceQueryBuilder.new

      yield qb if block_given?

      endpoint = "api/3/resources?project=#{name}&#{qb.query}"
      pp endpoint

      session.get(endpoint, 'project', 'node')
    end

    def resource(resource_name)
      session.get("api/1/resource/#{resource_name}?project=#{name}", 'project', 'node')
    end

    class ResourceQueryBuilder
      def self.fields
        [:name, :hostname, :tags, :os_arch, :os_family, :os_name, :os_version]
      end

      def self.exclude_name(f)
        "exclude_#{f}".to_sym
      end

      attr_accessor :precedence

      fields.each do |f|
        attr_accessor f, exclude_name(f)
      end

      def clause(field)
        val = send(field)
        return nil unless val
        name = field.to_s.gsub('_', '-')
        "#{name}=#{val}"
      end

      def query
        clauses = self.class.fields.map do |f|
          [
            clause(f),
            clause(self.class.exclude_name(f))
          ]
        end

        clauses << "exclude-precedence=#{precedence==:exclude ? true : false}" if precedence
        clauses.flatten.compact.join('&')
      end
    end
  end
end
