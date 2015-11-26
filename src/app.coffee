process.on 'uncaughtException', (e) ->
	console.error('Got unhandled exception', e, e?.stack)

Promise = require 'bluebird'
knex = require './db'
utils = require './utils'
bootstrap = require './bootstrap'
config = require './config'
request = require 'request'
_ = require 'lodash'
vpn = require './vpn/vpn-connect'

knex.init.then ->
	utils.mixpanelProperties.uuid = process.env.RESIN_DEVICE_UUID
	utils.mixpanelTrack('Multivisor start')

	logsChannels = Promise.map(config.multivisor.apps, (app) ->
		utils.getOrGenerateSecret("logsChannel#{app.appId}")
		.then (channel) ->
			return { appId: app.appId, logsChannel: channel }
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
				console.log('Updating supervisor version and api info, and connecting to VPN')
				_.map config.multivisor.apps, (app) ->

					device.getUUID(app.appId)
					.then (uuid) ->
						vpn.startConnection(uuid)

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
