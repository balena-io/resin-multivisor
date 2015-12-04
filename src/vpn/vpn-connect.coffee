Promise = require 'bluebird'
fs = Promise.promisifyAll(require('fs'))
spawn = require('child_process').spawn
_ = require 'lodash'

exports.createConnection = (uuid, apiKey, endpoint) ->
	authfile = "/data/vpn/auth-#{uuid}.conf"
	fs.readFileAsync('/usr/src/multivisor/src/vpn/client.conf.tmpl')
	.then (templateText) ->
		template = _.template(templateText)
		fs.writeFileAsync("/data/vpn/#{uuid}.conf", template({ endpoint, authfile }))
	.then ->
		fs.writeFileAsync(authfile, "#{uuid}\n#{apiKey}\n")

exports.startConnection = (uuid) ->
	spawn('/usr/sbin/openvpn', ['--daemon', '--writepid', '/var/run/openvpn/resin.pid', '--cd', '/data/vpn/', '--config', "#{uuid}.conf"])



