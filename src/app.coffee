process.on 'uncaughtException', (e) ->
	console.error('Got unhandled exception', e, e?.stack)

Promise = require 'bluebird'
knex = require './db'
utils = require './utils'
bootstrap = require './bootstrap'
config = require './config'
request = require 'request'
_ = require 'lodash'

knex.init.then ->
	utils.mixpanelProperties.uuid = process.env.RESIN_DEVICE_UUID
	utils.mixpanelTrack('Multivisor start')

	#console.log('Starting connectivity check..')
	#utils.connectivityCheck()

	logsChannels = Promise.map(config.multivisor.apps, (app) ->
		return { appId: app.appId, logsChannel: utils.getOrGenerateSecret("logsChannel#{app.appId}") }
	).then (logsChannels) ->
		channelsByAppId = _.indexBy(logsChannels, 'appId')
		return _.mapValues channelsByAppId, (logsChannelObject) -> logsChannelObject.logsChannel

	bootstrap.startBootstrapping().then ->
		Promise.join utils.getOrGenerateSecret('api'), logsChannels, (secret, logsChannels) ->
			# Persist the uuid in subsequent metrics

			api = require './api'
			application = require('./application')(logsChannels)
			device = require './device'

			bootstrap.done
			.then ->
				console.log('Starting API server..')
				api(application).listen(config.listenPort)
				# Let API know what version we are, and our api connection info.
				console.log('Updating supervisor version and api info')
				_.map config.multivisor.apps, (app) ->
					device.updateState app.appId, {
						api_port: config.listenPort
						api_secret: secret
						supervisor_version: utils.supervisorVersion
						provisioning_progress: null
						provisioning_state: ''
						download_progress: null
						logs_channel: logsChannels[app.appId]
					}

			console.log('Starting Apps..')
			application.initialize()

			#updateIpAddr = ->
			#	callback = (error, response, body ) ->
			#		if !error && response.statusCode == 200 && body.Data.IPAddresses?
			#			device.updateState(
			#				ip_address: body.Data.IPAddresses.join(' ')
			#			)
			#	request.get({ url: "#{config.gosuperAddress}/v1/ipaddr", json: true }, callback )

			#console.log('Starting periodic check for IP addresses..')
			#setInterval(updateIpAddr, 30 * 1000) # Every 30s
			#updateIpAddr()
