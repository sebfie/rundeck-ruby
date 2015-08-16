module Rundeck
  class ExecutionTimeout < StandardError
    def initialize(execution)
      super("Timed out while waiting for execution #{execution.url} to complete")
    end
  end

  class ExecutionFailure < StandardError
    def initialize(execution)
      super("Execution #{execution.url} failed")
    end
  end

  class APIFailure < StandardError
    def initialize(call, status)
      super("The call to #{call} failed with result #{result}")
    end
  end

  class Execution
    def self.from_hash(session, hash)
      job = Job.from_hash(session, hash['job'])
      new(session, hash, job)
    end

    def initialize(session, hash, job)
      @id = hash['id']
      @url=hash['href']
      @url = URI.join(session.server, URI.split(@url)[5]).to_s if @url # They always return a url of "localhost" for their executions. Replace it with the real URL
      @status=hash['status'].to_sym
      @date_started = hash['date_started']
      @date_ended = hash['date_ended']
      @user = hash['user']
      @args = (hash['argstring'] || "").split
                                      .each_slice(2)
                                      .reduce({}){|acc,cur| acc[cur[0]] = cur[1]; acc}
      @job = job
      @session = session
    end
    attr_reader :id, :url, :status, :date_started, :date_ended, :user, :args, :job, :session

    def self.find(session, id)
      result = session.get("api/1/execution/#{id}", *%w(result executions execution))
      return nil unless result
      job = Job.find(session, result['job']['id'])
      return nil unless job
      Execution.new(session, result, job)
    end

    def self.where(project)
      qb = SearchQueryBuilder.new
      yield qb if block_given?

      endpoint = "api/5/executions?project=#{project.name}#{qb.query}"
      pp endpoint
      results = project.session.get(endpoint, 'result', 'executions', 'execution') || []
      results = [results] if results.is_a?(Hash) #Work around an inconsistency in the API
      results.map {|hash| from_hash(project.session, hash)}
    end

    def output
      path = "api/9/execution/#{id}/output"
      ret = session.get(path)
      result = ret['result']
      raise APIFailure.new(path, result) unless result && result['success']=='true'

      #sort the output by node
      ret = result['output'].slice(*%w(id completed hasFailedNodes))
      ret['log'] = result['output']['entries']['entry'].group_by{|e| e['node']}
      ret
    end

    def wait_for_complete(poll_interval, timeout)
      Timeout.timeout(timeout) do
        while (cur = self.class.find(session, id)).status != :succeeded
          raise ExecutionFailure.new(self) if cur.status == :failed
          sleep(poll_interval)
        end
      end
    rescue Timeout::Error
      raise ExecutionTimeout.new(self)
    end

    class SearchQueryBuilder
      attr_accessor :status, :max, :offset

      class ValidationError < StandardError
        def initialize(field, value, message=nil)
          msg = "Invalid #{field}: #{value}"
          msg += message unless message==nil
          super(msg)
        end
      end

      def self.valid_statuses
        %w(succeeded failed aborted running) << nil
      end

      def validate
        raise ValidationError.new("requested status", status) unless status.nil? || self.class.valid_statuses.include?(status.to_s)
        raise ValidationError.new("offset", offset) unless offset.nil? || offset.to_i >= 0
        raise ValidationError.new("max", max) unless max.nil? || max.to_i >= 0
      end

      def query
        validate

        [
          "",
          status && "statusFilter=#{status}",
          max && "max=#{max.to_i}",
          offset && "offset=#{offset.to_i}",
        ].compact
          .join("&")
          .chomp("&")
      end
    end

  end
end

