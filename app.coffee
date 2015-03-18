# First task is to setup environment
if process.env.NODE_ENV != 'production'
  dotenv = require 'dotenv'
  dotenv.load()

express = require('express.io')
CBuffer = require('CBuffer');
slack = require('slack-utils/api')(process.env.API_TOKEN, process.env.INCOMING_HOOK_URL)
online_list = require('./presence.coffee')

app = express().http().io()
# This is a circular buffer of messages, which are stored in memory
messages = new CBuffer(parseInt(process.env.BUFFER_SIZE))

# Setup your sessions, just like normal.
app.use express.cookieParser()
app.use express.bodyParser()
app.use express.session secret: process.env.SESSION_SECRET
app.use express.static __dirname + '/public'

app.io.set 'transports', ['xhr-polling']

# Slack outgoing webhook is caught here
app.post "/webhook", (req, res) ->
  throw "Invalid Token" unless req.body.token == process.env.OUTGOING_TOKEN

  # Send a blank response if the message was by a service
  # Prevents us from falling into a loop
  return res.json {} if req.body.user_id == 'USLACKBOT'

  # Broadcast the message to all clients
  msg =
    message: slack.parseMessage(req.body.text),
    nick: req.body.user_name,
    classes: "admin",
    timestamp: Math.floor(req.body.timestamp*1000)

  app.io.broadcast "chat:msg", msg

  # Also store the message in memory
  messages.push msg

  # Send a blank response, so slack knows we got it.
  res.send ""

# Broadcast the chat message to all connected clients,
# including the one who made the request
# also send it to slack
app.io.route 'chat:msg', (req)->
  req.data.timestamp = (new Date).getTime()

  # If the message is private
  if req.data.message[0] == '!'
    req.data.private = true
    req.io.emit 'chat:msg', req.data
  else
    # Send the message to all jinora users
    app.io.broadcast 'chat:msg', req.data
  # Send message to slack
  slack.postMessage req.data.message, process.env.SLACK_CHANNEL, req.data.nick
  # Store message in memory
  messages.push req.data

# Once a new chat client connects
# Send them back the last 100 messages
app.io.route 'chat:demand', (req)->
  logs = messages.toArray()
  # We filter out non-private messages
  logs = logs.filter (msg)->
    msg.message[0] != '!'
  req.io.emit 'chat:log', logs

app.io.route 'presence:demand', (req)->
  req.io.emit 'presence:list', online_list

# Render the homepage
app.get "/", (req, res) ->
  res.sendfile "index.html"

app.listen process.env.PORT || 3000
