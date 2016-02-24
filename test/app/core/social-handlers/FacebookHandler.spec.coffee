FacebookHandler = require 'core/social-handlers/FacebookHandler'

mockAuthEvent =
  response:
    authResponse:
      accessToken: 'aksdhjflkqjrj245234b52k345q344le4j4k5l45j45s4dkljvdaskl'
      userID: '4301938'
      expiresIn: 5138
      signedRequest: 'akjsdhfjkhea.3423nkfkdsejnfkd'
    status: 'connected'

window.FB ?= {
  api: ->
  login: ->
}

describe 'lib/FacebookHandler.coffee', ->
  it 'on facebook-logged-in, gets data from FB and marks self as logged in', ->
    spyOn FB, 'api'
    facebookHandler = new FacebookHandler()
    facebookHandler.loginThroughFacebook()
    expect(facebookHandler.loggedIn).toBe(false)
    Backbone.Mediator.publish 'auth:logged-in-with-facebook', mockAuthEvent
    expect(facebookHandler.loggedIn).toBe(true)
    expect(facebookHandler.authResponse).toBe(mockAuthEvent.response.authResponse)
