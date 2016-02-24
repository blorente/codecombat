ModalView = require 'views/core/ModalView'
template = require 'templates/core/create-account-modal'
{loginUser, createUser, me} = require 'core/auth'
forms = require 'core/forms'
User = require 'models/User'
application  = require 'core/application'
Classroom = require 'models/Classroom'
errors = require 'core/errors'

module.exports = class AuthModal extends ModalView
  id: 'create-account-modal'
  template: template

  events:
    'click #switch-to-login-btn': 'onClickSwitchToLoginButton'
    'submit form': 'onSubmitForm'
    'keyup #name': 'onNameChange'
    'click #gplus-signup-btn': 'onClickGPlusSignupButton'
    'click #gplus-login-btn': 'onClickGPlusLoginButton'
    'click #facebook-signup-btn': 'onClickFacebookSignupButton'
    'click #facebook-login-btn': 'onClickFacebookLoginButton'
    'click #close-modal': 'hide'
    
  subscriptions:
    'auth:facebook-api-loaded': 'onFacebookAPILoaded'
    
    
  # Initialization

  initialize: (options={}) ->
    @onNameChange = _.debounce(_.bind(@checkNameExists, @), 500)
    @previousFormInputs = options.initialValues or {}
    @listenTo application.gplusHandler, 'logged-into-google', @onGPlusHandlerLoggedIntoGoogle
    @listenTo application.gplusHandler, 'person-loaded', @onGPlusPersonLoaded
    @listenTo application.gplusHandler, 'render-login-buttons', @onGPlusRenderLoginButtons
    @listenTo application.facebookHandler, 'logged-into-facebook', @onFacebookHandlerLoggedIntoFacebook
    @listenTo application.facebookHandler, 'person-loaded', @onFacebookPersonLoaded

  afterRender: ->
    super()
    @playSound 'game-menu-open'
    @$('#facebook-signup-btn').attr('disabled', true) if not window.FB?

  afterInsert: ->
    super()
    _.delay (-> application.router.renderLoginButtons()), 500
    _.delay (=> $('input:visible:first', @$el).focus()), 500

  onGPlusRenderLoginButtons: ->
    @$('#gplus-signup-btn').attr('disabled', false)

  onFacebookAPILoaded: ->
    @$('#facebook-signup-btn').attr('disabled', false)

    
  # User creation

  onSubmitForm: (e) ->
    e.preventDefault()
    @playSound 'menu-button-click'

    forms.clearFormAlerts(@$el)
    attrs = forms.formToObject @$el
    attrs.name = @suggestedName if @suggestedName
    _.defaults attrs, me.pick([
      'preferredLanguage', 'testGroupNumber', 'dateCreated', 'wizardColor1',
      'name', 'music', 'volume', 'emails', 'schoolName'
    ])
    attrs.emails ?= {}
    attrs.emails.generalNews ?= {}
    attrs.emails.generalNews.enabled = @$el.find('#subscribe').prop('checked')
    @classCode = attrs.classCode
    delete attrs.classCode
    _.assign attrs, @gplusAttrs if @gplusAttrs
    _.assign attrs, @facebookAttrs if @facebookAttrs
    res = tv4.validateMultiple attrs, User.schema
    if not res.valid
      return forms.applyErrorsToForm(@$el, res.errors)
    if not _.any([attrs.password, @gplusAttrs, @facebookAttrs])
      return forms.setErrorToProperty @$el, 'password', 'Required', true
    if not forms.validateEmail(attrs.email)
      return forms.setErrorToProperty @$el, 'email', 'Please enter a valid email address', true
    
    @$('#signup-button').text($.i18n.t('signup.creating')).attr('disabled', true)
    @newUser = new User(attrs)
    if @classCode
      @signupClassroomPrecheck()
    else
      @createUser()

  signupClassroomPrecheck: ->
    classroom = new Classroom()
    classroom.fetch({ data: { code: @classCode } })
    classroom.once 'sync', @createUser, @
    classroom.once 'error', @onClassroomFetchError, @
    @enableModalInProgress(@$el)

  onClassroomFetchError: ->
    @$('#signup-button').text($.i18n.t('signup.sign_up')).attr('disabled', false)
    forms.setErrorToProperty(@$('form'), 'classCode', 'Classroom code could not be found')
      
  createUser: ->
    options = {}
    if @gplusAttrs
      @newUser.set('_id', me.id)
      options.url = "/db/user?gplusID=#{@gplusAttrs.gplusID}&gplusAccessToken=#{application.gplusHandler.accessToken.access_token}"
      options.type = 'PUT'
    if @facebookAttrs
      @newUser.set('_id', me.id)
      options.url = "/db/user?facebookID=#{@facebookAttrs.facebookID}&facebookAccessToken=#{application.facebookHandler.authResponse.accessToken}"
      options.type = 'PUT'
    @newUser.save(null, options)
    @newUser.once 'sync', @onUserCreated, @
    @newUser.once 'error', @onUserSaveError, @

  onUserSaveError: (user, jqxhr) ->
    @$('#signup-button').text($.i18n.t('signup.sign_up')).attr('disabled', false)
    if _.isObject(jqxhr.responseJSON) and jqxhr.responseJSON.property
      error = jqxhr.responseJSON
      if jqxhr.status is 409 and error.property is 'name'
        @newUser.unset 'name'
        return @createUser()
      return forms.applyErrorsToForm(@$el, [jqxhr.responseJSON])
    errors.showNotyNetworkError(jqxhr)

  onUserCreated: ->
    Backbone.Mediator.publish "auth:signed-up", {}
    window.tracker?.trackEvent 'Finished Signup', label: 'CodeCombat'

    if @classCode
      url = "/courses?_cc="+@classCode
      application.router.navigate(url)
    window.location.reload()
    
  
  # Google Plus

  onClickGPlusSignupButton: ->
    @clickedGPlusLogin = true
    # the button has been set up to trigger the log in, so we'll hear back when the user has logged into google

  onGPlusHandlerLoggedIntoGoogle: ->
    return unless @clickedGPlusLogin
    application.gplusHandler.loadPerson()
    @$('#gplus-signup-btn').attr('disabled', true).find('.sign-in-blurb').text($.i18n.t('signup.creating'))

  onGPlusPersonLoaded: (@gplusAttrs) ->
    # TODO: Handle GPlus person loading errors
    existingUser = new User()
    existingUser.fetchGPlusUser(@gplusAttrs.gplusID, application.gplusHandler.accessToken.access_token)
    existingUser.once 'sync', @onceExistingGPlusUserSync, @
    existingUser.once 'error', @onceExistingGPlusUserError, @

  onceExistingGPlusUserSync: ->
    @$('#email-password-row').remove()
    @$('#gplus-account-exists-row').removeClass('hide')

  onceExistingGPlusUserError: (user, jqxhr) ->
    if jqxhr.status is 404
      @$('#email-password-row').remove()
      @$('#gplus-logged-in-row').toggleClass('hide')
    else
      @$('#gplus-signup-btn').attr('disabled', false).find('.sign-in-blurb').text($.i18n.t('login.sign_in_with_gplus'))
      errors.showNotyNetworkError(jqxhr)

  onClickGPlusLoginButton: ->
    user = new User()
    user.loginByGPlus(@gplusAttrs.gplusID, application.gplusHandler.accessToken.access_token)
    user.once 'sync', -> window.location.reload()
    user.once 'error', @onceLoginGPlusError, @
    @$('#gplus-login-btn').text($.i18n.t('login.logging_in')).attr('disabled', true)

  onceLoginGPlusError: (user, jqxhr) ->
    @$('#gplus-login-btn').text($.i18n.t('login.logging_in')).attr('disabled', false)
    errors.showNotyNetworkError(jqxhr)

    
  # Facebook

  onClickFacebookSignupButton: ->
    @clickedFacebookLogin = true
    if application.facebookHandler.loggedIn
      @onFacebookHandlerLoggedIntoFacebook()
    else
      application.facebookHandler.loginThroughFacebook()

  onFacebookHandlerLoggedIntoFacebook: ->
    return unless @clickedFacebookLogin
    application.facebookHandler.loadPerson()
    @$('#facebook-signup-btn').attr('disabled', true).find('.sign-in-blurb').text($.i18n.t('signup.creating'))
    
  onFacebookPersonLoaded: (@facebookAttrs) ->
    # TODO: Handle Facebook person loading errors
    existingUser = new User()
    existingUser.fetchFacebookUser(@facebookAttrs.facebookID, application.facebookHandler.authResponse.accessToken)
    existingUser.once 'sync', @onceExistingFacebookUserSync, @
    existingUser.once 'error', @onceExistingFacebookUserError, @

  onceExistingFacebookUserSync: ->
    @$('#email-password-row').remove()
    @$('#facebook-account-exists-row').removeClass('hide')

  onceExistingFacebookUserError: (user, jqxhr) ->
    if jqxhr.status is 404
      @$('#facebook-logged-in-row').toggleClass('hide')
      @$('#email-password-row').remove()
    else
      @$('#facebook-signup-btn').attr('disabled', false).find('.sign-in-blurb').text($.i18n.t('login.sign_in_with_facebook'))
      errors.showNotyNetworkError(jqxhr)

  onClickFacebookLoginButton: ->
    user = new User()
    user.loginByFacebook(@facebookAttrs.facebookID, application.facebookHandler.authResponse.accessToken)
    user.once 'sync', -> window.location.reload()
    user.once 'error', @onceLoginFacebookError, @
    @$('#facebook-login-btn').text('Logging In').attr('disabled', true)

  onceLoginFacebookError: (user, jqxhr) ->
    @$('#facebook-login-btn').text('Log in now.').attr('disabled', false)
    errors.showNotyNetworkError(jqxhr)
  
    
  # Misc
  
  onHidden: ->
    super()
    @playSound 'game-menu-close'

  checkNameExists: ->
    name = $('#name', @$el).val()
    return forms.clearFormAlerts(@$el) if name is ''
    User.getUnconflictedName name, (newName) =>
      forms.clearFormAlerts(@$el)
      if name is newName
        @suggestedName = undefined
      else
        @suggestedName = newName
        forms.setErrorToProperty @$el, 'name', "That name is taken! How about #{newName}?", true

  onClickSwitchToLoginButton: (e) ->
    AuthModal = require 'views/core/AuthModal'
    modal = new AuthModal({ 
      mode: 'login'
      initialValues: forms.formToObject @$('form')
    })
    currentView.openModalView(modal)
    
