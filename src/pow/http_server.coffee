fs      = require "fs"
{join}  = require "path"
connect = require "connect"
nack    = require "nack"

module.exports = class HttpServer extends connect.Server
  constructor: (@configuration) ->
    @handlers = {}
    super [@handleRequest, connect.errorHandler showStack: true]
    @on "close", @closeApplications

  getHandlerForHost: (host, callback) ->
    @configuration.findApplicationRootForHost host, (err, root) =>
      return callback err if err
      callback null, @getHandlerForRoot root

  getHandlerForRoot: (root) ->
    @handlers[root] ||=
      root: root
      app:  nack.createServer(join(root, "config.ru"), idle: @configuration.timeout)

  handleRequest: (req, res, next) =>
    pause = connect.utils.pause req
    host  = req.headers.host.replace /:.*/, ""
    @getHandlerForHost host, (err, handler) =>
      @restartIfNecessary handler, =>
        pause.end()
        return next err if err
        req.proxyMetaVariables = @configuration.dstPort.toString()
        handler.app.handle req, res, next
        pause.resume()

  closeApplications: =>
    for root, {app} of @handlers
      app.pool.quit()

  restartIfNecessary: ({root, app}, callback) ->
    fs.unlink join(root, "tmp/restart.txt"), (err) ->
      if err
        callback()
      else
        app.pool.onNext "exit", callback
        app.pool.quit()
