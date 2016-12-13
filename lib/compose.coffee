_         = require 'lodash'
path      = require 'path'
resolvep  = require 'resolve-path'

module.exports = (config) ->
  networkValue = "#{config.host_if} -i eth0 @CONTAINER_NAME@ dhclient @#{config.vlan}"
  networkEnv = 'eth0_pipework_cmd'

  augmentCompose: (instance, options, doc) ->
    addNetworkContainer = (serviceName, service) ->
      if service.labels['bigboat.service.type'] is 'service'
        labels = _.extend {}, service.labels
        labels['bigboat.service.type'] = 'net'
        subDomain = "#{instance}.#{config.domain}.#{config.tld}"
        netcontainer =
          image: 'ictu/pipes'
          environment: eth0_pipework_cmd: networkValue
          hostname: "#{serviceName}.#{subDomain}"
          dns_search: subDomain
          network_mode: 'none'
          labels: labels
          stop_signal: 'SIGKILL'
        if service.container_name
          netcontainer['container_name'] = "#{service.container_name}-net"

        doc["bb-net-#{serviceName}"] = netcontainer
        # remove the hostname if set in the service, the hostname is set from
        # the network container
        delete service.hostname
        delete service.net
        service.network_mode = "service:bb-net-#{serviceName}"
      else service.network_mode = "service:bb-net-#{service.labels['bigboat.service.name']}"

    resolvePath = (root, path) ->
      path = path[1...] if path[0] is '/'
      resolvep root, path

    addVolumeMapping = (serviceName, service) ->
      bucketPath = path.join config.dataDir, config.domain, options.storageBucket if options.storageBucket
      service.volumes = service.volumes?.map (v) ->
        vsplit = v.split ':'
        try
          if vsplit.length is 2
            if vsplit[1] in ['rw', 'ro']
              v
            else if bucketPath
              "#{resolvePath bucketPath, vsplit[0]}:#{vsplit[1]}"
            else vsplit[1]
          else if vsplit.length is 3
            if bucketPath
              "#{resolvePath bucketPath, vsplit[0]}:#{vsplit[1]}:#{vsplit[2]}"
            else "#{vsplit[1]}"
          else v
        catch e
          console.error "Error while mapping volumes. Root: #{bucketPath}, path: #{v}", e
          null
      delete service.volumes unless service.volumes
      service.volumes = service.volumes.filter((s) -> s) if service.volumes

    restrictCompose = (serviceName, service) ->
      delete service.cap_add
      delete service.cap_drop
      delete service.cgroup_parent
      delete service.devices
      delete service.dns
      delete service.dns_search
      delete service.tmpfs
      delete service.networks
      delete service.privileged



    migrateLinksToDependsOn = (serviceName, service) ->
      if service.links
        service.depends_on = _.union (service.depends_on or []), service.links
        delete service.links

    addDockerMapping = (serviceName, service) ->
      if service.labels['bigboat.container.map_docker'] is 'true'
        service.volumes = [] unless service.volumes
        service.volumes.push '/var/run/docker.sock:/var/run/docker.sock'

    for serviceName, service of doc
      addNetworkContainer serviceName, service
      addVolumeMapping serviceName, service
      addDockerMapping serviceName, service
      migrateLinksToDependsOn serviceName, service
      restrictCompose serviceName, service

    version: '2'
    services: doc
