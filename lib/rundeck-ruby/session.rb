require 'json'
require 'active_support/all'
require 'rest_client'


module Rundeck
  class Session
    def initialize(server, token, options={})
      @server = server
      @token = token
      @options = options
      @resource = RestClient::Resource.new(server, options)
    end

    attr_reader :server, :token

    def get(url, *keys)
      xml = @resource[url].get('X-Rundeck-Auth-Token'=> token)
      hash = Maybe(Hash.from_xml(xml))
      keys.reduce(hash){|acc, cur| acc && acc[cur]}
    end

    def system_info
      get('api/1/system/info', 'result', 'system')
    end

    def projects
      Project.all(self)
    end

    def project(name)
      Project.find(self, name)
    end
  end
end
