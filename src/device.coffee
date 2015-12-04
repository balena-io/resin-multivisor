_ = require 'lodash'
Promise = require 'bluebird'
knex = require './db'
utils = require './utils'
{ resinApi } = require './request'
device = exports
config = require './config'
request = Promise.promisifyAll(require('request'))
execAsync = Promise.promisify(require('child_process').exec)
fs = Promise.promisifyAll(require('fs'))

exports.getUUID = getUUID = (appId) ->
	knex('app').select('uuid').where({ appId })
	.then ([ app ]) ->
		return app.uuid

exports.getID = do ->
	deviceIdPromises = {}
	return (appId) ->
		# We initialise the rejected promise just before we catch in order to avoid a useless first unhandled error warning.
		deviceIdPromises[appId] ?= Promise.rejected()
		# Only fetch the device id once (when successful, otherwise retry for each request)
		deviceIdPromises[appId] = deviceIdPromises[appId].catch ->
			Promise.all([
				knex('config').select('value').where(key: 'apiKey')
				getUUID(appId)
			])
			.spread ([{value: apiKey}], uuid) ->
				resinApi.get(
					resource: 'device'
					options:
						select: 'id'
						filter:
							uuid: uuid
					customOptions:
						apikey: apiKey
				)
			.then (devices) ->
				if devices.length is 0
					throw new Error('Could not find this device?!')
				return devices[0].id

exports.getDeviceType = ->
	return config.multivisor.deviceType

exports.currentState = {}
_.map config.multivisor.apps, (app) ->
	exports.currentState[app.appId] = {}

# Calling this function updates the local device state, which is then used to synchronise
# the remote device state, repeating any failed updates until successfully synchronised.
# This function will also optimise updates by merging multiple updates and only sending the latest state.
exports.updateState = do ->
	applyPromise = {}
	targetState = {}
	actualState = {}
	_.map config.multivisor.apps, (app) ->
		applyPromise[app.appId] = Promise.resolve()
		targetState[app.appId] = {}
		actualState[app.appId] = {}

	getStateDiff = (appId) ->
		_.omit targetState[appId], (value, key) ->
			actualState[appId][key] is value

	applyState = (appId) ->
		stateDiff = getStateDiff(appId)
		if _.size(stateDiff) is 0
			return
		applyPromise[appId] = Promise.join(
			knex('config').select('value').where(key: 'apiKey')
			device.getID(appId)
			([{value: apiKey}], deviceID) ->
				stateDiff = getStateDiff(appId)
				if _.size(stateDiff) is 0 || !apiKey?
					return
				resinApi.patch
					resource: 'device'
					id: deviceID
					body: stateDiff
					customOptions:
						apikey: apiKey
				.then ->
					# Update the actual state.
					_.merge(actualState[appId], stateDiff)
		)
		.catch (error) ->
			utils.mixpanelTrack('Device info update failure', {error, stateDiff})
			# Delay 5s before retrying a failed update
			Promise.delay(5000)
		.finally ->
			# Check if any more state diffs have appeared whilst we've been processing this update.
			applyState(appId)

	return (appId, updatedState = {}, retry = false) ->
		# Remove any updates that match the last we successfully sent.
		_.merge(targetState[appId], updatedState)
		_.merge(exports.currentState[appId], updatedState)

		# Only trigger applying state if an apply isn't already in progress.
		if !applyPromise[appId].isPending()
			applyState(appId)
		return
