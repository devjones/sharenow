var connect = require('connect'),
    coffee = require('coffee-script'),
	sys = require('sys'),
    comcenter = require('./comCenter'),
	sharejs,
	server;

try {
	sharejs = require('../lib/server');
} catch(e) {
	console.error("\nCould not include server library. Build using:\n % cake build");
	throw e;
}

server = connect(
    connect.bodyParser(),
    connect.logger()
);


options = require('./options') || {};
var port = options.port || 8080;
server.listen(port);

// Attach the sharejs REST and Socket.io interfaces to the server
io = sharejs.attach(server, options);

//Attach the comCenter to the server.  createInstance function analagous to attach
comcenter.createInstance(server,io,options);

//Add routes to handle task responses via http
server.use(connect.router(require('./tasks')));

sys.puts('Server now running. Port: ' + port);


/*
  app.get('/taskupdate/:username',function(req,res) {
    cc.sendTaskMessage('done',req.params.username);
    return send200(res);
  });
*/
