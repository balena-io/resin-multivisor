Promise = require 'bluebird'
fs = Promise.promisifyAll require 'fs'
utils = require './utils'
#tty = require './lib/tty'
knex = require './db'
express = require 'express'
bodyParser = require 'body-parser'
request = require 'request'
config = require './config'
device = require './device'

module.exports = (application) ->
	api = express()
	api.use(bodyParser())
	api.use (req, res, next) ->
		utils.getOrGenerateSecret('api')
		.then (secret) ->
			if req.query.apikey is secret
				next()
			else
				res.sendStatus(401)
		.catch (err) ->
			# This should never happen...
			res.status(503).send('Invalid API key in supervisor')

	api.get '/ping', (req, res) ->
		res.send('OK')

	api.get '/v1/device', (req, res) ->
		appId = req.query.appId
		if device.currentState[appId]?
			res.status(200).send(device.currentState[appId])
		else
			res.status(404).send('App not found')

	api.post '/v1/update', (req, res) ->
		utils.mixpanelTrack('Update notification')
		application.update(req.body.force)
		res.sendStatus(204)

	api.post '/v1/restart', (req, res) ->
		appId = req.body.appId
		force = req.body.force
		utils.mixpanelTrack('Restart container', appId)
		if !appId?
			return res.status(400).send('Missing app id')
		Promise.using application.lockUpdates(appId, force), ->
			knex('app').select().where({ appId })
			.then ([ app ]) ->
				if !app?
					throw new Error('App not found')
				application.kill(app)
				.then ->
					application.start(app)
		.then ->
			res.status(200).send('OK')
		.catch (err) ->
			res.status(503).send(err?.message or err or 'Unknown error')

	return api
