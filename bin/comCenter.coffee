# Requires
coffee = require 'coffee-script'
nowjs = require 'now'
tasks = require './tasks'
redis = require 'redis'
redis_client = redis.createClient()

# ComCenter
class ComCenter

    # Server
    server: null
    everyone: null
    port: null
    connectedClients: {}
    groupData: {}


    # Initialise
    constructor: (server,ioserver) ->
        # Prepare
        @server = server


        #Create the everyone object for nowjs.  clientWrite determines whether client can change server scope variables
        @everyone = nowjs.initialize(@server, {clientWrite:true}, ioserver)


        #Setup up routes for access to the comCenter
        @server.use tasks(@)

        @setupComCenter()


    setupComCenter: ->
        comCenter = @
        connectedClients = @connectedClients
        groupData = @groupData

        #Trigger when each client connects
        @everyone.on 'connect', ->
            console.log("Connected: " + @user.clientId)

        @everyone.on 'disconnect', ->
            #Remove client from the connectedClients object
            delete connectedClients[@now.name]


            console.log("Left: " + @now.name)



        @everyone.now.handshake = ->
            #Add client to the connectedClients object
            connectedClients[@now.name] = @user.clientId
            console.log 'showing connected clients after handshake'
            console.log '=========================================='
            console.log JSON.stringify(connectedClients)

            console.log("Joined: " + @now.name)

        nowjs.on('disconnect', ->
            if @now.group?
                nowjs.getGroup(@now.group).now.receiveMessage({fromUser:"server", message:"#{@now.name} has left the session.", messageType:'serverMessage'})


            #remove the client from any rooms he's currently in
            nowjs.getGroup(@now.group).removeUser(@user.clientId)

        )

        @everyone.now.joinGroup = (groupName) ->
            console.log('groupname: '+groupName)
            #remove the client from any rooms he's currently in
            nowjs.getGroup(@now.group).removeUser(@user.clientId)

            #add the client to the new group
            nowjs.getGroup(groupName).addUser(@user.clientId)
            @now.group = groupName

            console.log 'joining group...'
            console.log '==========================='
            console.log JSON.stringify(@now.group)

            #Create the groupData storage object if it doesn't already exist
            if not groupData[@now.group]?
                groupData[@now.group] = {}


            if @now.group?
                nowjs.getGroup(@now.group).now.receiveMessage({fromUser:"server", message:"#{@now.name} has joined the session.", messageType:'serverMessage'})


            #Tell the new connecting user if the host is connected and run the corresponding function if so
            if groupData[@now.group].hostConnected == true

                #clientId of the requesting client
                clientId = @user.clientId

                functionInfo = {functionName:'hostIsConnected',args:groupData[@now.group]}


                #Send message to the requesting user
                nowjs.getClient clientId, ->
                    @now.receiveMessage({message:functionInfo, fromUser:"server", messageType:'groupFunction'})




        @everyone.now.callGroupFunction = (functionInfo) ->
            #Call a specific function for everyone in a group
            if @now.group?
                nowjs.getGroup(@now.group).now.receiveMessage({message:functionInfo, fromUser:@now.name, messageType:'groupFunction'})



        @everyone.now.sendGroupMessage = (message) ->
            #Send a message to everyone in a group
            if @now.group?
                nowjs.getGroup(@now.group).now.receiveMessage({message:message, fromUser:@now.name, messageType:'groupMessage'})


        @everyone.now.sendPrivateMessage = (message,toUser) ->
            #get the clientId from connected users

            clientId = connectedClients[toUser]

            fromUser = @now.name

            #Send message to the recipient user
            nowjs.getClient clientId, ->
                @now.receiveMessage({message:message,fromUser:fromUser,messageType:'privateMessage'})




        @everyone.now.updateGroupData = (data) ->
            #data should be an object.  Update groupData with the data object

            for key,val of data
                groupData[@now.group][key] = val

        @everyone.now.connectHost = ->
            groupData[@now.group].hostConnected = true

            functionInfo = {functionName:'hostIsConnected',args:groupData[@now.group]}

            #Tell all members that the host is connected
            if @now.group?
                console.log 'tocall hostIsConnected'
                nowjs.getGroup(@now.group).now.receiveMessage({message:functionInfo, fromUser:@now.name, messageType:'groupFunction'})


        @everyone.now.addActiveDoc = (docInfo) ->
            #add the specified document to global list of docs that have been updated and not saved to disk
            for file_slug,value of docInfo
                project_id = value.project_id
                file_rel_path = value.file_rel_path
                redis_client.hmset("project:#{project_id}:to_sync",file_slug,file_rel_path)
                redis_client.hmset("project:#{project_id}:to_push",file_slug,file_rel_path)



    # This function will be exposed over HTTP to update a user when tasks are complete
    handleTask: (message,toUser) ->
        comCenter = @
        console.log 'receiving handleTask'

        #get the clientId from connected users
        clientId = comCenter.connectedClients[toUser]
        fromUser = 'SERVER'


        #Send message to the recipient user
        nowjs.getClient clientId, ->
            @now.receiveMessage({message:message,fromUser:fromUser,messageType:'taskMessage'})




# API
comcenter =
    createInstance: (server,options) ->
        return new ComCenter(server,options)

# Export
module.exports = comcenter

