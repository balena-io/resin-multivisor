_ = require 'lodash'
Docker = require 'dockerode'
PUBNUB = require 'pubnub'
Promise = require 'bluebird'
es = require 'event-stream'

initialised = new Promise (resolve) ->
	exports.init = (config) ->
		exports.pubnub = PUBNUB.init(config.pubnub)
		resolve(config)

dockerPromise = initialised.then (config) ->
	docker = Promise.promisifyAll(new Docker(socketPath: config.dockerSocket))
	# Hack dockerode to promisify internal classes' prototypes
	Promise.promisifyAll(docker.getImage().constructor.prototype)
	Promise.promisifyAll(docker.getContainer().constructor.prototype)
	return docker

disableLogs = false
exports.disableLogPublishing = (disable) ->
				disableLogs = disable

exports.new = do ->
	publishQueues = {}
	loggers = {}
	return (channel) ->
		disableLogs[channel] = false

		loggers[channel] = {
			log: ->
				loggers[channel].publish(arguments...)

			publish: do ->
				publishQueues[channel] = []

				initialised.then (config) ->
					# Redefine original function
					loggers[channel].publish = (message) ->
						# Disable sending logs for bandwidth control
						return if disableLogs
						if _.isString(message)
							message = { message }

						_.defaults message,
							timestamp: Date.now()
							# Stop pubnub logging loads of "Missing Message" errors, as they are quite distracting
							message: ' '

						exports.pubnub.publish({ channel, message })

					# Replay queue now that we have initialised the publish function
					publish(args...) for args in publishQueues[channel]

				return -> publishQueue.push(arguments)

			attach: (app) ->
				dockerPromise.then (docker) ->
					docker.getContainer(app.containerId)
					.attachAsync({ stream: true, stdout: true, stderr: true, tty: true })
					.then (stream) ->
						stream.pipe(es.split()).on('data', loggers[channel].publish)
		}

		return loggers[channel]
