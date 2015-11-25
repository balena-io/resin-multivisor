Promise = require 'bluebird'
_ = require 'lodash'
fs = Promise.promisifyAll require 'fs'
config = require './config'
knex = require './db'
mixpanel = require 'mixpanel'
url = require 'url'
randomHexString = require './lib/random-hex-string'
request = Promise.promisifyAll require 'request'
logger = require './lib/logger'

utils = exports

# Parses package.json and returns resin-supervisor's version
exports.supervisorVersion = require('../package.json').version

mixpanelClient = mixpanel.init(config.mixpanelToken)

exports.mixpanelProperties = mixpanelProperties =
	username: config.multivisor.username

exports.mixpanelTrack = (event, properties = {}) ->
	# Allow passing in an error directly and having it assigned to the error property.
	if properties instanceof Error
		properties = error: properties

	# If the properties has an error argument that is an Error object then it treats it nicely,
	# rather than letting it become `{}`
	if properties.error instanceof Error
		properties.error =
			message: properties.error.message
			stack: properties.error.stack

	console.log('Event:', event, JSON.stringify(properties))
	# Mutation is bad, and it should feel bad
	properties = _.assign(_.cloneDeep(properties), mixpanelProperties)

	mixpanelClient.track(event, properties)

secretPromises = {}
generateSecret = (name) ->
	Promise.try ->
		return config.forceSecret[name] if config.forceSecret[name]?
		return randomHexString.generate()
	.then (newSecret) ->
		secretInDB = { key: "#{name}Secret", value: newSecret }
		knex('config').update(secretInDB).where(key: "#{name}Secret")
		.then (affectedRows) ->
			knex('config').insert(secretInDB) if affectedRows == 0
		.return(newSecret)

exports.newSecret = (name) ->
	secretPromises[name] ?= Promise.resolve()
	secretPromises[name] = secretPromises[name].then ->
		generateSecret(name)

exports.getOrGenerateSecret = (name) ->
	secretPromises[name] ?= knex('config').select('value').where(key: "#{name}Secret").then ([ secret ]) ->
		return secret.value if secret?
		generateSecret(name)
	return secretPromises[name]

exports.extendEnvVars = (env, uuid) ->
	host = '127.0.0.1'
	newEnv =
		RESIN_DEVICE_UUID: uuid
		RESIN_SUPERVISOR_ADDRESS: "http://#{host}:#{config.listenPort}"
		RESIN_SUPERVISOR_HOST: host
		RESIN_SUPERVISOR_PORT: config.listenPort
		RESIN_SUPERVISOR_API_KEY: exports.getOrGenerateSecret('api')
		RESIN_SUPERVISOR_VERSION: exports.supervisorVersion
		RESIN: '1'
		USER: 'root'
	if env?
		_.extend(newEnv, env)
	return Promise.props(newEnv)

# Callback function to enable/disable logs
exports.resinLogControl = (val) ->
	logger.disableLogPublishing(val == 'false')
	console.log('Logs enabled: ' + val)
