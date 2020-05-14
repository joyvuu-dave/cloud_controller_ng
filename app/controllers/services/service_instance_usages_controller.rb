module VCAP::CloudController
  class ServiceInstanceUsagesController < RestController::ModelController
    get '/v2/service_instance_usages', :enumerate
  end
end
