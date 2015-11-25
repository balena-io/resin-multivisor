Promise = require 'bluebird'
_ = require 'lodash'
knex = require './db'
utils = require './utils'
deviceRegister = require 'resin-register-device'
{ resinApi } = require './request'

config = require './config'
device = require './device'

DuplicateUuidError = (err) ->
	return err.message == '"uuid" must be unique.'

bootstrapper = {}

bootstrap = (app) ->
	userConfig = {
		deviceType: config.multivisor.deviceType
		uuid: app.uuid
		applicationId: app.appId
		userId: config.multivisor.userId
		apiKey: config.multivisor.apiKey
	}
	Promise.try ->
		deviceRegister.register(resinApi, userConfig)
		.catch DuplicateUuidError, ->
	.then ->
		bootstrapper.doneBootstrapping[app.appId]()

generateUUIDsAndLoadPreloadedApps = ->
	knex('app').select()
	.then (apps) ->
		Promise.map config.multivisor.apps, (configApp) ->
			savedApp = _.find apps, (a) -> a.appId = configApp.appId
			return savedApp if savedApp?
			deviceRegister.generateUUID()
			.then (uuid) ->
				appToSave = configApp
				Promise.try ->
					return utils.extendEnvVars(appToSave.env, uuid) if config.multivisor.isPreloaded
					return appToSave.env
				.then (extendedEnv) ->
					appToSave.env = extendedEnv
					appToSave.uuid = uuid
					knex('app').insert(appToSave)
					.return(appToSave)
	.catch (err) ->
		console.log('Error generating and saving UUID: ', err)
		Promise.delay(config.bootstrapRetryDelay)
		.then ->
			generateUUIDsAndLoadPreloadedApps()



bootstrapOrRetry = (app) ->
	utils.mixpanelTrack('Device bootstrap', { app })
	bootstrap(app).catch (err) ->
		utils.mixpanelTrack('Device bootstrap failed, retrying', { app, error: err, delay: config.bootstrapRetryDelay })
		setTimeout ->
			bootstrapOrRetry(app)
		, config.bootstrapRetryDelay

bootstrapper.doneBootstrapping = {}
bootstrapper.done = Promise.map(config.multivisor.apps, (app) ->
	new Promise (resolve) ->
		bootstrapper.doneBootstrapping[app.appId] = ->
			resolve()
).then ->
	console.log('Finishing bootstrapping')
	Promise.all([
		knex('config').whereIn('key', ['apiKey', 'username', 'userId', 'version']).delete()
		.then ->
			knex('config').insert([
				{ key: 'apiKey', value: config.multivisor.apiKey }
				{ key: 'username', value: config.multivisor.username }
				{ key: 'userId', value: config.multivisor.userId }
				{ key: 'version', value: utils.supervisorVersion }
				{ key: 'bootstrapped', value: '1' }
			])
	])
.then ->
	bootstrapper.bootstrapped = true

bootstrapper.bootstrapped = false
bootstrapper.startBootstrapping = ->
	knex('config').select('value').where(key: 'bootstrapped')
	.then ([ bootstrapped ]) ->
		if bootstrapped?.value == '1'
			bootstrapper.doneBootstrapping()
			return
		console.log('New device detected. Bootstrapping..')
		generateUUIDsAndLoadPreloadedApps()
		.map(bootstrapOrRetry)

module.exports = bootstrapper
