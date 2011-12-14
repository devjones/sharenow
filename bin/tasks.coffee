# A REST-ful frontend to the OT server.
#
# See the docs for details and examples about how the protocol works.

http = require 'http'
sys = require 'sys'
util = require 'util'
url = require 'url'

connect = require 'connect'

send403 = (res, message = 'Forbidden') ->
	res.writeHead 403, {'Content-Type': 'text/plain'}
	res.end message

send404 = (res, message = '404: Your document could not be found.\n') ->
	res.writeHead 404, {'Content-Type': 'text/plain'}
	res.end message

sendError = (res, message) ->
	if message == 'forbidden'
		send403 res
	else if message == 'Document does not exist'
		send404 res
	else
		console.warn "REST server does not know how to send error: '#{message}'"
		res.writeHead 500, {'Content-Type': 'text/plain'}
		res.end "Error: #{message}"

send400 = (res, message) ->
	res.writeHead 400, {'Content-Type': 'text/plain'}
	res.end message

send200 = (res, message = 'OK') ->
	res.writeHead 200, {'Content-Type': 'text/plain'}
	res.end message

sendJSON = (res, obj) ->
	res.writeHead 200, {'Content-Type': 'application/json'}
	res.end JSON.stringify(obj) + '\n'

# Callback is only called if the object was indeed JSON
expectJSONObject = (req, res, callback) ->
	pump req, (data) ->
		try
			obj = JSON.parse data
		catch error
			send400 res, 'Supplied JSON invalid'
			return

		callback(obj)

pump = (req, callback) ->
	data = ''
	req.on 'data', (chunk) -> data += chunk
	req.on 'end', () -> callback(data)

# connect.router will be removed in connect 2.0 - this code will have to be rewritten or
# more libraries pulled in.
# https://github.com/senchalabs/connect/issues/262
router = (app, comCenter) ->

	# GET returns the document snapshot. The version and type are sent as headers.
	# I'm not sure what to do with document metadata - it is inaccessable for now.
	app.post '/taskupdate/:username/', (req, res) ->
        console.log 'receiving a post request...'

        query = url.parse(req.url, true).query

        task_id = if query?.task_id?
            query?.task_id
        else
            task_id = req.body.task_id

        task_status = if query?.task_status?
            query?.task_status
        else
            task_status = req.body.task_status

        task_message = if query?.task_message?
            query?.task_message
        else
            task_message = req.body.task_message

        task_content = if query?.task_content?
            query?.task_content
        else
            task_content = req.body.task_content || ''

        if task_id and task_status
            message_obj  = {task_id:task_id,task_status:task_status, task_message: task_message, code:'ok', task_content:task_content}
        else
            message_obj = {code:'error'}

        comCenter.handleTask(message_obj,req.params.username)
        return send200(res)

# Attach the frontend to the supplied http.Server.
#
# As of sharejs 0.4.0, options is ignored. To control the deleting of documents, specify an auth() function.
module.exports = (comCenter) ->
	connect.router (app) -> router(app, comCenter)
