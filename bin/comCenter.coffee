# Requires
coffee = require 'coffee-script'
nowjs = require 'now'
tasks = require './tasks'
redis = require 'redis'
spawn = require('child_process').spawn
redis_client = redis.createClient()

# ComCenter
class ComCenter

    # Server
    server: null
    everyone: null
    port: null
    connectedClients: {}
    groupData: {}
    projects : {}


    # Initialise
    constructor: (server,ioserver,options) ->
        # Prepare
        @server = server
        @options = options


        #Create the everyone object for nowjs.  clientWrite determines whether client can change server scope variables
        @everyone = nowjs.initialize(@server, {clientWrite:true}, ioserver)


        #Setup up routes for access to the comCenter
        @server.use tasks(@)
        @setupComCenter()


    setupComCenter: ->
        comCenter = @
        connectedClients = @connectedClients
        groupData = @groupData
        projects = @projects
        options = @options

        @initializeProjects()

        #Trigger when each client connects
        @everyone.on 'connect', ->
            console.log("Connected: " + @user.clientId)

        @everyone.on 'disconnect', ->
            oldProject = connectedClients[@now.name]?.activeProject

            # Decrement the number of active users in the old project for the client
            if oldProject?
                projects.updateActiveUsers(oldProject,-1)

            #Remove client from the connectedClients object
            delete connectedClients[@now.name]

            console.log("Left: " + @now.name)



        @everyone.now.handshake = ->
            #Add client to the connectedClients object
            connectedClients[@now.name] = {}
            connectedClients[@now.name].clientId = @user.clientId
            connectedClients[@now.name].activeProject = null
            connectedClients[@now.name].subscribedProjects = null


            console.log 'showing connected clients after handshake'
            console.log '=========================================='
            console.log JSON.stringify(connectedClients)

            console.log("Joined: " + @now.name)

        nowjs.on('disconnect', ->
            if @now.group?
                nowjs.getGroup(@now.group).now.receiveMessage({fromUser:"server", message:"#{@now.name} has left the session.", messageType:'serverMessage'})

            if groupData[@now.group].hostClientId == @user.clientId
                groupData[@now.group].hostConnected = false

            #remove the client from any rooms he's currently in
            nowjs.getGroup(@now.group).removeUser(@user.clientId)

        )

        @everyone.now.subscribeToProjects = (projectCollection) ->

            for project in projectCollection
                console.log "now listening for project #{project.id}"
                #add the client to start listening to changes in the projects
                nowjs.getGroup("projectSubscribers_#{project.id}").addUser(@user.clientId)

        @everyone.now.unsubscribeFromProjects = (projectCollection) ->

            for project in projectCollection
                # remove the client from listening to the projects
                nowjs.getGroup("projectSubscribers_#{project.id}").removeUser(@user.clientId)



        @everyone.now.joinGroup = (groupName) ->
            console.log('groupname: ' + groupName)
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

            clientId = connectedClients[toUser].clientId

            fromUser = @now.name

            #Send message to the recipient user
            nowjs.getClient clientId, ->
                @now.receiveMessage({message:message,fromUser:fromUser,messageType:'privateMessage'})


        @everyone.now.updateGroupData = (data) ->
            #data should be an object.  Update groupData with the data object

            for key,val of data
                groupData[@now.group][key] = val

        @everyone.now.connectHost = ->
            #Update info on the host for the session
            groupData[@now.group].hostConnected = true
            groupData[@now.group].hostClientId = @user.clientId


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



        @everyone.now.changeActiveProject = (projectId) ->
            console.log 'changing the active project'
            console.log projectId

            fromUser = @now.name

            console.log 'fromUser---------'
            console.log fromUser
            console.log 'connectedClients---------'
            console.log connectedClients
            console.log 'connectedClients[fromUser]---------'
            console.log connectedClients[fromUser]

            oldProject = connectedClients[fromUser]?.activeProject

            # Decrement the number of active users in the old project for the client
            if oldProject?
                console.log "oldproject is:\n" + JSON.stringify(oldProject)
                projects.updateActiveUsers(oldProject,-1)

            connectedClients[fromUser].activeProject = projectId
            projects.updateActiveUsers(projectId,1)

            console.log 'connectedClients[fromUser]---------'
            console.log connectedClients[fromUser]



        @everyone.now.testFun = (args,callback) ->

            console.log 'the promise on the server'
            console.log(JSON.stringify(callback))
            ###
            setTimeout(
                ->
                    aprom.resolve('done')
                args.length * 1000
            )
            ###

            return callback('woah')





        #Handle file system access
        @everyone.now.runCommand = (params,userData, callback) ->
            console.log(JSON.stringify(params))
            console.log(JSON.stringify(userData))

            if userData.username? and userData.project?.slug?
                projectPath = "#{options.projectRoot}/projects/#{userData.username}/#{userData.project.slug}/"
            else
                return

            console.log('path: ' + projectPath)

            args = params[1..params.length]
            program = params[0]

            commandOptions = {
                cwd: projectPath
            }
            command = spawn(program,args,commandOptions)

            output = ''
            # Handle child process output stream events
            command.stdout.on('data',(data) ->
                console.log 'receive data from process'
                output += data.toString('utf8')

                # Put the exit event as a nested function
                command.on('exit',  (code) ->
                    console.log 'process ending'

                    if code != 0
                        output = 'There was an error'
                    console.log 'code is: ' + code.toString()
                    console.log output
                    callback(output)
                )
            )

            # Ignoring stderr for now...
            command.stderr.on('data',(data) ->
                output.concat(data)
            )


    # This function will be exposed over HTTP to update a user when tasks are complete
    handleTask: (message,toUser) ->
        comCenter = @
        console.log 'receiving handleTask'

        #get the clientId from connected users
        clientId = comCenter.connectedClients[toUser].clientId
        fromUser = 'SERVER'


        #Send message to the recipient user
        nowjs.getClient clientId, ->
            @now.receiveMessage({message:message,fromUser:fromUser,messageType:'taskMessage'})



    sendProjectUpdates: ->
        # Identifies all projects that have had a change in the number of active users.

        projects = @projects
        updatedProjects = []

        if projects.objects?

            # Identify those projects that have had a change in the number of active users.
            for project_id, project_status of projects.objects
                if project_status.hasChanged == true
                    updatedProject = {id: project_id, activeUsers: project_status.activeUsers}
                    updatedProjects.push(updatedProject)


                    projects.objects[project_id].hasChanged = false

            # For each project that has had a change in the number of active users, send an update to the registered listeners to each project
            for project in updatedProjects
                data = {functionName:'updateProjectStatus',args:updatedProjects}
                nowjs.getGroup("projectSubscribers_#{project.id}").now.receiveMessage({message:data, fromUser:'SERVER', messageType:'groupFunction'})



    initializeProjects: ->
        projects = @projects
        projects.objects = {}

        projects.updateActiveUsers= (projectId,change) ->

            if not projects.objects[projectId]?
                projects.objects[projectId] = {}

            if not projects.objects[projectId].activeUsers?
                projects.objects[projectId].activeUsers = 0

            projects.objects[projectId].activeUsers += change
            projects.objects[projectId].hasChanged = true

        ###
        # Omitting the listeners for now, to keep app simple.
        projects.addListener = (projectId, clientId) ->

            if not projects.objects[projectId]?
                projects.objects[projectId] = {}

            if not projects.objects[projectId].listeners?
                projects.objects[projectId].listeners = []

            projects.objects[projectId].listeners.push(clientId)
        ###

        # Update all users on the dashboard of changes to the number of active users in projects
        setInterval(
            =>
                @sendProjectUpdates()

            3000
        )




        #child.stdout.



# API
comcenter =
    createInstance: (server,io,options) ->
        return new ComCenter(server,io,options)

# Export
module.exports = comcenter

