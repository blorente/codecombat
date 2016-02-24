errorModalTemplate = require 'templates/core/error'
{applyErrorsToForm} = require 'core/forms'

module.exports =
  parseServerError: (text) ->
    try
      error = JSON.parse(text) or {message: 'Unknown error.'}
    catch SyntaxError
      error = {message: text or 'Unknown error.'}
    error = error[0] if _.isArray(error)
    error

  genericFailure: (jqxhr) ->
    Backbone.Mediator.publish('errors:server-error', {response: jqxhr})
    return @connectionFailure() if not jqxhr.status
  
    error = module.exports.parseServerError(jqxhr.responseText)
    message = error.message
    message = error.property + ' ' + message if error.property
    console.warn(jqxhr.status, jqxhr.statusText, error)
    existingForm = $('.form:visible:first')
    if existingForm[0]
      missingErrors = applyErrorsToForm(existingForm, [error])
      for error in missingErrors
        existingForm.append($('<div class="alert alert-danger"></div>').text(error.message))
    else
      res = errorModalTemplate(
        status: jqxhr.status
        statusText: jqxhr.statusText
        message: message
      )
      showErrorModal(res)

  backboneFailure: (model, jqxhr, options) ->
    module.exports.genericFailure(jqxhr)

  connectionFailure: ->
    html = errorModalTemplate(
      status: 0
      statusText: 'Connection Gone'
      message: 'No response from the CoCo servers, captain.'
    )
    showErrorModal(html)
    
  showNotyNetworkError: (jqxhr) ->
    noty({
      text: jqxhr.responseJSON?.message or jqxhr.responseJSON?.errorName or jqxhr.responseText or 'Unknown error'
      layout: 'topCenter'
      type: 'error'
      killer: false,
      dismissQueue: true
    })

showErrorModal = (html) ->
  # TODO: make a views/modal/error_modal view for this to use so the template can reuse templates/core/modal-base?
  $('#modal-wrapper').html(html)
  $('.modal:visible').modal('hide')
  $('#modal-error').modal('show')
